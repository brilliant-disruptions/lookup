package com.brilliantdisruptions.lookup

import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

/**
 * Timelapse: the frames Dart keeps (one every few seconds) encoded as the
 * next frames of an H.264 .mp4 at a fixed frame rate. Dart side:
 * lib/services/capture/.
 *
 * Methods on "lookup/timelapse":
 *  - begin {path, width, height, fps, rotation, bitrate}: errors "busy" if a
 *    recording is open, "failed" if the encoder can't be set up (e.g. a size
 *    this phone's encoder can't take)
 *  - add {y, u, v} → frames written so far; planar I420, y is width×height,
 *    u and v are (width/2)×(height/2). Frame i shows at i/fps seconds.
 *    Errors "not_started" with no recording, "bad_frame" for short planes.
 *  - end → {path, frames, seconds} once the file is written and closed
 *  - cancel: stops and deletes the partial file; fine with nothing open
 * Rotation (clockwise degrees to upright) goes in the file's orientation
 * hint; the pixels aren't turned. Any "failed" error ends the recording and
 * deletes its file, so the next call can be a begin.
 *
 * All encoding runs in order on one background thread, recordings included,
 * so a begin after an end or cancel waits for that file to be done with.
 */
class LookUpTimelapse(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

  private val main = Handler(Looper.getMainLooper())
  private var worker: Handler? = null

  /** The recording taking frames; main thread only. */
  private var open: Recording? = null

  init {
    MethodChannel(messenger, "lookup/timelapse").setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "begin" -> begin(call, result)
      "add" -> add(call, result)
      "end" -> end(result)
      "cancel" -> cancel(result)
      else -> result.notImplemented()
    }
  }

  private fun worker(): Handler = worker ?: run {
    val t = HandlerThread("LookUpTimelapse").also { it.start() }
    Handler(t.looper).also { worker = it }
  }

  private fun begin(call: MethodCall, result: MethodChannel.Result) {
    if (open != null) {
      result.error("busy", "A timelapse is already recording", null)
      return
    }
    val path = call.argument<String>("path")
    val width = call.argument<Number>("width")?.toInt() ?: 0
    val height = call.argument<Number>("height")?.toInt() ?: 0
    val fps = call.argument<Number>("fps")?.toInt() ?: 30
    val rotation = (((call.argument<Number>("rotation")?.toInt() ?: 0) % 360) + 360) % 360
    val bitrate = call.argument<Number>("bitrate")?.toInt() ?: 12_000_000
    if (path.isNullOrEmpty() || width <= 0 || height <= 0 || width % 2 != 0 || height % 2 != 0 ||
      fps <= 0 || rotation % 90 != 0 || bitrate <= 0) {
      result.error("failed", "Bad timelapse settings", null)
      return
    }
    val r = Recording(path, width, height, fps, rotation, bitrate)
    open = r
    worker().post {
      try {
        r.start()
        main.post { result.success(null) }
      } catch (e: Exception) {
        r.discard()
        main.post {
          if (open === r) open = null
          result.error("failed", e.message ?: e.javaClass.simpleName, null)
        }
      }
    }
  }

  private fun add(call: MethodCall, result: MethodChannel.Result) {
    val r = open
    if (r == null) {
      result.error("not_started", "No timelapse is recording", null)
      return
    }
    val y = call.argument<ByteArray>("y")
    val u = call.argument<ByteArray>("u")
    val v = call.argument<ByteArray>("v")
    val chroma = (r.width / 2) * (r.height / 2)
    if (y == null || u == null || v == null || y.size < r.width * r.height || u.size < chroma || v.size < chroma) {
      result.error("bad_frame", "Frame planes don't match ${r.width}×${r.height}", null)
      return
    }
    worker().post {
      if (r.failed) {
        main.post { result.error("failed", "The timelapse stopped", null) }
        return@post
      }
      try {
        val frames = r.encode(y, u, v)
        main.post { result.success(frames) }
      } catch (e: Exception) {
        r.discard()
        main.post {
          if (open === r) open = null
          result.error("failed", e.message ?: e.javaClass.simpleName, null)
        }
      }
    }
  }

  private fun end(result: MethodChannel.Result) {
    val r = open
    if (r == null) {
      result.error("not_started", "No timelapse is recording", null)
      return
    }
    open = null
    worker().post {
      if (r.failed) {
        main.post { result.error("failed", "The timelapse stopped", null) }
        return@post
      }
      try {
        val frames = r.finish()
        main.post {
          result.success(mapOf("path" to r.path, "frames" to frames, "seconds" to frames.toDouble() / r.fps))
        }
      } catch (e: Exception) {
        r.discard()
        main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
      }
    }
  }

  private fun cancel(result: MethodChannel.Result) {
    val r = open
    open = null
    if (r == null) {
      result.success(null)
      return
    }
    worker().post {
      r.discard()
      main.post { result.success(null) }
    }
  }
}

/** One .mp4 being written. Everything but the constructor runs on the worker thread. */
private class Recording(
  val path: String,
  val width: Int,
  val height: Int,
  val fps: Int,
  val rotation: Int,
  val bitrate: Int,
) {
  companion object {
    const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
    const val TIMEOUT_US = 10_000L
    const val INPUT_WAIT_NS = 5_000_000_000L
    const val DRAIN_WAIT_NS = 10_000_000_000L
  }

  private var codec: MediaCodec? = null
  private var muxer: MediaMuxer? = null
  private var colorFormat = MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible
  private var track = -1
  private var muxing = false
  private var samples = 0
  private var frames = 0
  var failed = false
    private set

  fun start() {
    val (name, color) = pickEncoder()
      ?: throw IllegalStateException("This phone can't encode ${width}×$height H.264")
    colorFormat = color
    val c = MediaCodec.createByCodecName(name)
    codec = c
    val rate = c.codecInfo.getCapabilitiesForType(MIME).videoCapabilities?.bitrateRange?.clamp(bitrate) ?: bitrate
    fun format(fullRange: Boolean) = MediaFormat.createVideoFormat(MIME, width, height).apply {
      setInteger(MediaFormat.KEY_COLOR_FORMAT, color)
      setInteger(MediaFormat.KEY_BIT_RATE, rate)
      setInteger(MediaFormat.KEY_FRAME_RATE, fps)
      setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
      // Camera YUV is full range; tagged limited, the faintest sky would crush to black.
      if (fullRange) setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_FULL)
    }
    try {
      c.configure(format(fullRange = true), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
    } catch (_: Exception) {
      // An encoder that won't take the range hint still encodes, slightly contrasty.
      c.reset()
      c.configure(format(fullRange = false), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
    }
    File(path).delete()
    val m = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    muxer = m
    m.setOrientationHint(rotation)
    c.start()
  }

  /**
   * An H.264 encoder that takes this size, the platform's default first
   * (usually the hardware one), with the input colour format to use.
   */
  @Suppress("DEPRECATION") // The byte-buffer colour formats, for encoders without Flexible.
  private fun pickEncoder(): Pair<String, Int>? {
    val preferred = try {
      MediaCodec.createEncoderByType(MIME).let { val n = it.name; it.release(); n }
    } catch (_: Exception) {
      null
    }
    val encoders = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
      .filter { it.isEncoder && it.supportedTypes.any { t -> t.equals(MIME, ignoreCase = true) } }
      .sortedBy { if (it.name == preferred) 0 else 1 }
    for (info in encoders) {
      val caps = try { info.getCapabilitiesForType(MIME) } catch (_: Exception) { continue }
      if (caps.videoCapabilities?.isSizeSupported(width, height) != true) continue
      val colors = caps.colorFormats
      val color = listOf(
        MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible,
        MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar,
        MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar,
      ).firstOrNull { colors.contains(it) } ?: continue
      return info.name to color
    }
    return null
  }

  /** Feeds one frame to the encoder; returns how many have gone in. */
  fun encode(y: ByteArray, u: ByteArray, v: ByteArray): Int {
    val c = codec ?: throw IllegalStateException("The encoder isn't running")
    val index = inputIndex(c)
    val capacity = c.getInputBuffer(index)?.capacity() ?: 0
    val image = c.getInputImage(index)
    val size = if (image != null) {
      fill(image, y, u, v)
      if (capacity > 0) capacity else width * height * 3 / 2
    } else {
      val buf = c.getInputBuffer(index) ?: throw IllegalStateException("No encoder input buffer")
      fill(buf, c.inputFormat, y, u, v)
    }
    c.queueInputBuffer(index, 0, size, frameUs(frames), 0)
    frames++
    drain(c, endOfStream = false)
    return frames
  }

  /** Ends the stream, waits for the encoder to empty and closes the file. */
  fun finish(): Int {
    val c = codec ?: throw IllegalStateException("The encoder isn't running")
    val index = inputIndex(c)
    c.queueInputBuffer(index, 0, 0, frameUs(frames), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
    drain(c, endOfStream = true)
    val written = samples > 0
    release(stopMuxer = written)
    // A muxer with nothing in it leaves a broken file.
    if (!written) File(path).delete()
    return if (written) frames else 0
  }

  /** Stops, frees the encoder and deletes the file. Safe to call twice. */
  fun discard() {
    failed = true
    release(stopMuxer = false)
    File(path).delete()
  }

  private fun frameUs(i: Int): Long = i * 1_000_000L / fps

  private fun inputIndex(c: MediaCodec): Int {
    val deadline = System.nanoTime() + INPUT_WAIT_NS
    while (true) {
      val i = c.dequeueInputBuffer(TIMEOUT_US)
      if (i >= 0) return i
      // Some encoders only free an input once their output is taken.
      drain(c, endOfStream = false)
      if (System.nanoTime() > deadline) throw IllegalStateException("The encoder stopped taking frames")
    }
  }

  private fun drain(c: MediaCodec, endOfStream: Boolean) {
    val info = MediaCodec.BufferInfo()
    val deadline = System.nanoTime() + DRAIN_WAIT_NS
    while (true) {
      val i = c.dequeueOutputBuffer(info, if (endOfStream) TIMEOUT_US else 0L)
      when {
        i == MediaCodec.INFO_TRY_AGAIN_LATER -> {
          if (!endOfStream) return
          if (System.nanoTime() > deadline) throw IllegalStateException("The encoder didn't finish")
        }
        i == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
          if (muxing) throw IllegalStateException("The encoder changed format twice")
          startMuxer(c.outputFormat)
        }
        i >= 0 -> {
          val buf = c.getOutputBuffer(i)
          val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
          if (!config && info.size > 0 && buf != null) {
            // The format normally comes first; if not, it's known by now.
            if (!muxing) startMuxer(c.outputFormat)
            buf.position(info.offset)
            buf.limit(info.offset + info.size)
            muxer!!.writeSampleData(track, buf, info)
            samples++
          }
          c.releaseOutputBuffer(i, false)
          if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
        }
        // INFO_OUTPUT_BUFFERS_CHANGED (deprecated; getOutputBuffer covers it).
        else -> {}
      }
    }
  }

  private fun startMuxer(format: MediaFormat) {
    val m = muxer ?: throw IllegalStateException("No muxer")
    track = m.addTrack(format)
    m.start()
    muxing = true
  }

  /** Planar I420 into the encoder's own layout, whatever its strides. */
  private fun fill(image: Image, y: ByteArray, u: ByteArray, v: ByteArray) {
    val planes = image.planes
    copyIn(planes[0], y, width, height)
    copyIn(planes[1], u, width / 2, height / 2)
    copyIn(planes[2], v, width / 2, height / 2)
  }

  private fun copyIn(plane: Image.Plane, src: ByteArray, w: Int, h: Int) {
    val buf = plane.buffer
    val rs = plane.rowStride
    val ps = plane.pixelStride
    for (row in 0 until h) {
      val base = row * rs
      val from = row * w
      if (ps == 1) {
        buf.position(base)
        buf.put(src, from, w)
      } else {
        for (col in 0 until w) buf.put(base + col * ps, src[from + col])
      }
    }
  }

  /**
   * For an encoder that gives no Image: write the configured byte layout
   * (planar or semi-planar) at the input format's stride. Returns the size.
   */
  @Suppress("DEPRECATION")
  private fun fill(buf: ByteBuffer, format: MediaFormat, y: ByteArray, u: ByteArray, v: ByteArray): Int {
    val stride = format.intOr("stride", width).coerceAtLeast(width)
    val slice = format.intOr("slice-height", height).coerceAtLeast(height)
    val cw = width / 2
    val ch = height / 2
    buf.clear()
    for (row in 0 until height) {
      buf.position(row * stride)
      buf.put(y, row * width, width)
    }
    val chromaStart = stride * slice
    if (colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar) {
      val cStride = stride / 2
      val vStart = chromaStart + cStride * (slice / 2)
      for (row in 0 until ch) {
        buf.position(chromaStart + row * cStride)
        buf.put(u, row * cw, cw)
        buf.position(vStart + row * cStride)
        buf.put(v, row * cw, cw)
      }
      return vStart + cStride * (slice / 2)
    }
    // Semi-planar: Cb and Cr interleaved, NV12 order.
    val line = ByteArray(width)
    for (row in 0 until ch) {
      for (col in 0 until cw) {
        line[col * 2] = u[row * cw + col]
        line[col * 2 + 1] = v[row * cw + col]
      }
      buf.position(chromaStart + row * stride)
      buf.put(line, 0, cw * 2)
    }
    return chromaStart + stride * (slice / 2)
  }

  private fun MediaFormat.intOr(key: String, fallback: Int): Int =
    try { if (containsKey(key)) getInteger(key).takeIf { it > 0 } ?: fallback else fallback } catch (_: Exception) { fallback }

  private fun release(stopMuxer: Boolean) {
    codec?.let { c ->
      try { c.stop() } catch (_: Exception) {}
      try { c.release() } catch (_: Exception) {}
    }
    codec = null
    muxer?.let { m ->
      if (stopMuxer && muxing) {
        try { m.stop() } catch (_: Exception) {}
      }
      try { m.release() } catch (_: Exception) {}
    }
    muxer = null
    muxing = false
  }
}
