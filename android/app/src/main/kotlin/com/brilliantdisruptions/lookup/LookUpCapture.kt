package com.brilliantdisruptions.lookup

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Size
import android.view.Surface
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.max
import kotlin.math.min

/**
 * "Catch it": long, back-to-back exposures with the shutter and ISO LookUp
 * chose (lib/domain/photo/exposure.dart), focus at infinity and white balance
 * locked, streamed to Dart as YUV frames for stacking
 * (lib/domain/photo/streak_stacker.dart). Dart side: lib/services/capture/.
 *
 * Methods on "lookup/capture":
 *  - capabilities → {manual, minShutterS, maxShutterS, minIso, maxIso, lenses: [{id, longFov, shortFov, f}]}
 *  - open {lensId} → {textureId, width, height, sensorOrientation}: preview on, auto exposure
 *  - start {shutterS?, iso?, longPx}: frames start flowing on "lookup/capture/frames"
 *  - stop: back to the preview
 *  - close
 *  - keepAwake {on}
 * Frames: {w, h, y, u, v, rotation, t}; y is w×h, u and v are (w/2)×(h/2).
 *
 * Only the back cameras listed in CameraManager.cameraIdList are offered;
 * phones that hide the ultra-wide behind a logical camera show just one.
 */
class LookUpCapture(
  private val activity: Activity,
  messenger: BinaryMessenger,
  private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

  companion object {
    const val PERMISSION_REQUEST = 4217
  }

  private val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
  private val main = Handler(Looper.getMainLooper())
  private var thread: HandlerThread? = null
  private var handler: Handler? = null

  private var device: CameraDevice? = null
  private var session: CameraCaptureSession? = null
  private var reader: ImageReader? = null
  private var producer: TextureRegistry.SurfaceProducer? = null
  private var previewSurface: Surface? = null
  private var sensorOrientation = 90
  private var manualFocus = false
  private var sink: EventChannel.EventSink? = null
  private var pendingPermission: ((Boolean) -> Unit)? = null
  @Volatile private var streaming = false
  @Volatile private var lastSent = 0L
  private var minFrameGapMs = 0L

  init {
    MethodChannel(messenger, "lookup/capture").setMethodCallHandler(this)
    EventChannel(messenger, "lookup/capture/frames").setStreamHandler(this)
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
    sink = events
  }

  override fun onCancel(arguments: Any?) {
    sink = null
  }

  /** Forwarded from MainActivity.onRequestPermissionsResult. */
  fun onPermissionResult(granted: Boolean) {
    val p = pendingPermission
    pendingPermission = null
    p?.invoke(granted)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      when (call.method) {
        "capabilities" -> result.success(capabilities())
        "open" -> withPermission(result) { open(call.argument<String>("lensId"), result) }
        "start" -> {
          start(call.argument<Double>("shutterS"), call.argument<Int>("iso"), call.argument<Int>("longPx") ?: 1920, result)
        }
        "stop" -> {
          streaming = false
          preview()
          result.success(null)
        }
        "close" -> {
          close()
          result.success(null)
        }
        "keepAwake" -> {
          val on = call.argument<Boolean>("on") == true
          if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
          else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
          result.success(null)
        }
        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      result.error("capture", e.message ?: e.javaClass.simpleName, null)
    }
  }

  private fun withPermission(result: MethodChannel.Result, then: () -> Unit) {
    if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
      then()
      return
    }
    pendingPermission = { granted ->
      if (granted) then() else result.error("CameraAccessDenied", "Camera access is off", null)
    }
    activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
  }

  private fun backIds(): List<String> = manager.cameraIdList.filter {
    manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
  }

  private fun fov(sensorMm: Float, focalMm: Float): Double =
    2 * atan(sensorMm / (2.0 * focalMm)) * 180 / Math.PI

  private fun capabilities(): Map<String, Any?> {
    val ids = backIds()
    val lenses = ids.mapNotNull { id ->
      val c = manager.getCameraCharacteristics(id)
      val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.firstOrNull() ?: return@mapNotNull null
      val size = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE) ?: return@mapNotNull null
      mapOf(
        "id" to id,
        "longFov" to fov(max(size.width, size.height), focal),
        "shortFov" to fov(min(size.width, size.height), focal),
        "f" to (c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_APERTURES)?.firstOrNull()?.toDouble() ?: 1.8),
      )
    }
    // Exposure limits from the first back camera, which is the main one.
    val first = ids.firstOrNull()?.let { manager.getCameraCharacteristics(it) }
    val caps = first?.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)
    val manual = caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)
    val exposure = first?.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE)
    val maxFrame = first?.get(CameraCharacteristics.SENSOR_INFO_MAX_FRAME_DURATION)
    val iso = first?.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
    val longestNs = listOfNotNull(exposure?.upper, maxFrame).minOrNull()
    return mapOf(
      "manual" to (manual && exposure != null && iso != null),
      "minShutterS" to (exposure?.lower?.div(1e9) ?: (1.0 / 8000)),
      "maxShutterS" to (longestNs?.div(1e9) ?: (1.0 / 30)),
      "minIso" to (iso?.lower ?: 50),
      "maxIso" to (iso?.upper ?: 3200),
      "lenses" to lenses,
    )
  }

  /** Largest size up to [longPx] on its long side, 4:3 if there is one. */
  private fun pick(sizes: Array<Size>, longPx: Int): Size {
    val fits = sizes.filter { max(it.width, it.height) <= longPx }
    val fourThree = fits.filter { abs(max(it.width, it.height).toDouble() / min(it.width, it.height) - 4.0 / 3) < 0.02 }
    return (fourThree.ifEmpty { fits }).maxByOrNull { it.width * it.height }
      ?: sizes.minByOrNull { it.width * it.height }!!
  }

  @SuppressLint("MissingPermission")
  private fun open(lensId: String?, result: MethodChannel.Result) {
    close()
    val id = lensId?.takeIf { it.isNotEmpty() && backIds().contains(it) } ?: backIds().firstOrNull()
    if (id == null) {
      result.error("capture", "No back camera", null)
      return
    }
    val t = HandlerThread("LookUpCapture").also { it.start() }
    thread = t
    val h = Handler(t.looper)
    handler = h
    val chars = manager.getCameraCharacteristics(id)
    sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
    manualFocus = (chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f) > 0f
    val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)!!
    val frameSize = pick(map.getOutputSizes(ImageFormat.YUV_420_888), 1920)
    val previewSize = pick(map.getOutputSizes(SurfaceTexture::class.java), 1440)

    val p = textures.createSurfaceProducer()
    p.setSize(previewSize.width, previewSize.height)
    producer = p
    previewSurface = p.surface
    val r = ImageReader.newInstance(frameSize.width, frameSize.height, ImageFormat.YUV_420_888, 4)
    r.setOnImageAvailableListener({ onImage(it) }, h)
    reader = r

    manager.openCamera(id, object : CameraDevice.StateCallback() {
      override fun onOpened(camera: CameraDevice) {
        device = camera
        @Suppress("DEPRECATION")
        camera.createCaptureSession(listOf(previewSurface!!, r.surface), object : CameraCaptureSession.StateCallback() {
          override fun onConfigured(s: CameraCaptureSession) {
            session = s
            preview()
            main.post {
              result.success(mapOf(
                "textureId" to p.id(),
                "width" to previewSize.width,
                "height" to previewSize.height,
                "sensorOrientation" to sensorOrientation,
              ))
            }
          }

          override fun onConfigureFailed(s: CameraCaptureSession) {
            main.post { result.error("capture", "Camera session failed", null) }
          }
        }, h)
      }

      override fun onDisconnected(camera: CameraDevice) {
        camera.close()
        device = null
      }

      override fun onError(camera: CameraDevice, error: Int) {
        camera.close()
        device = null
        main.post { result.error("capture", "Camera error $error", null) }
      }
    }, h)
  }

  /** Preview only: auto exposure so you can see to aim, focus at infinity. */
  private fun preview() {
    val d = device ?: return
    val s = session ?: return
    val b = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
    b.addTarget(previewSurface!!)
    focusAtInfinity(b)
    s.setRepeatingRequest(b.build(), null, handler)
  }

  private fun focusAtInfinity(b: CaptureRequest.Builder) {
    if (!manualFocus) return
    b.set(CaptureRequest.CONTROL_AF_MODE, CameraMetadata.CONTROL_AF_MODE_OFF)
    b.set(CaptureRequest.LENS_FOCUS_DISTANCE, 0f)
  }

  private fun start(shutterS: Double?, iso: Int?, longPx: Int, result: MethodChannel.Result) {
    val d = device
    val s = session
    if (d == null || s == null) {
      result.error("capture", "Camera not open", null)
      return
    }
    val manual = shutterS != null && iso != null
    val b = d.createCaptureRequest(if (manual) CameraDevice.TEMPLATE_MANUAL else CameraDevice.TEMPLATE_PREVIEW)
    b.addTarget(previewSurface!!)
    b.addTarget(reader!!.surface)
    focusAtInfinity(b)
    if (manual) {
      val ns = (shutterS!! * 1e9).toLong()
      b.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
      b.set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_OFF)
      b.set(CaptureRequest.SENSOR_EXPOSURE_TIME, ns)
      b.set(CaptureRequest.SENSOR_SENSITIVITY, iso!!)
      b.set(CaptureRequest.SENSOR_FRAME_DURATION, ns)
      b.set(CaptureRequest.CONTROL_AWB_LOCK, true)
      minFrameGapMs = 0
    } else {
      // Auto exposure frames come fast; ten a second is plenty to stack.
      minFrameGapMs = 100
    }
    streaming = true
    s.setRepeatingRequest(b.build(), null, handler)
    result.success(null)
  }

  private fun onImage(r: ImageReader) {
    val img = r.acquireNextImage() ?: return
    try {
      val now = System.currentTimeMillis()
      if (!streaming || sink == null || now - lastSent < minFrameGapMs) return
      lastSent = now
      val w = img.width
      val h = img.height
      val y = copyPlane(img.planes[0], w, h)
      val u = copyPlane(img.planes[1], w / 2, h / 2)
      val v = copyPlane(img.planes[2], w / 2, h / 2)
      val frame = mapOf("w" to w, "h" to h, "y" to y, "u" to u, "v" to v, "rotation" to sensorOrientation, "t" to now)
      main.post { sink?.success(frame) }
    } finally {
      img.close()
    }
  }

  /** A plane copied into a tight w×h array, whatever its strides. */
  private fun copyPlane(p: Image.Plane, w: Int, h: Int): ByteArray {
    val out = ByteArray(w * h)
    val buf = p.buffer
    val rs = p.rowStride
    val ps = p.pixelStride
    for (row in 0 until h) {
      val base = row * rs
      if (ps == 1) {
        buf.position(base)
        buf.get(out, row * w, min(w, buf.remaining()))
      } else {
        for (col in 0 until w) {
          val i = base + col * ps
          if (i < buf.limit()) out[row * w + col] = buf.get(i)
        }
      }
    }
    return out
  }

  private fun close() {
    streaming = false
    try { session?.close() } catch (_: Exception) {}
    session = null
    try { device?.close() } catch (_: Exception) {}
    device = null
    reader?.close()
    reader = null
    producer?.release()
    producer = null
    previewSurface = null
    thread?.quitSafely()
    thread = null
    handler = null
  }
}
