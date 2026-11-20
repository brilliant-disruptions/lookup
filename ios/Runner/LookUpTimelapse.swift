// Timelapse on iPhone: the frames Dart keeps (one every few seconds) encoded
// as the next frames of an H.264 .mp4 at a fixed frame rate. Same channel
// protocol as android/.../LookUpTimelapse.kt (documented there); Dart side in
// lib/services/capture/.
//
// NOT YET IN THE RUNNER TARGET: written on Linux, never compiled (CLAUDE.md:
// no uncompiled Swift in a target from Linux; see docs/mac-checklist.md).
// On a Mac: add this file to the Runner target, then register it in
// AppDelegate's didInitializeImplicitFlutterEngine next to LookUpCapture:
//
//   if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LookUpTimelapse") {
//     LookUpTimelapse.register(with: registrar)
//   }
//
// Until then Dart gets MissingPluginException on "lookup/timelapse".

import AVFoundation
import CoreVideo
import Flutter
import UIKit

final class LookUpTimelapse: NSObject {
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = LookUpTimelapse()
    let methods = FlutterMethodChannel(name: "lookup/timelapse", binaryMessenger: registrar.messenger())
    methods.setMethodCallHandler { call, result in instance.handle(call, result: result) }
    keep = instance
  }

  private static var keep: LookUpTimelapse?

  /// Every recording's work, in order, so a begin after an end or cancel
  /// waits for that file to be done with.
  private let queue = DispatchQueue(label: "lookup.timelapse")

  /// The recording taking frames; main thread only.
  private var open: TimelapseRecording?

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "begin": begin(args, result: result)
    case "add": add(args, result: result)
    case "end": end(result: result)
    case "cancel": cancel(result: result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private static func failure(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  private func begin(_ args: [String: Any], result: @escaping FlutterResult) {
    guard open == nil else {
      result(Self.failure("busy", "A timelapse is already recording"))
      return
    }
    let path = args["path"] as? String ?? ""
    let width = (args["width"] as? NSNumber)?.intValue ?? 0
    let height = (args["height"] as? NSNumber)?.intValue ?? 0
    let fps = (args["fps"] as? NSNumber)?.intValue ?? 30
    let rotation = (((args["rotation"] as? NSNumber)?.intValue ?? 0) % 360 + 360) % 360
    let bitrate = (args["bitrate"] as? NSNumber)?.intValue ?? 12_000_000
    guard !path.isEmpty, width > 0, height > 0, width % 2 == 0, height % 2 == 0,
          fps > 0, rotation % 90 == 0, bitrate > 0 else {
      result(Self.failure("failed", "Bad timelapse settings"))
      return
    }
    let r = TimelapseRecording(path: path, width: width, height: height, fps: fps)
    open = r
    queue.async {
      do {
        try r.start(rotation: rotation, bitrate: bitrate)
        DispatchQueue.main.async { result(nil) }
      } catch {
        r.discard()
        DispatchQueue.main.async {
          if self.open === r { self.open = nil }
          result(Self.failure("failed", error.localizedDescription))
        }
      }
    }
  }

  private func add(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let r = open else {
      result(Self.failure("not_started", "No timelapse is recording"))
      return
    }
    let chroma = (r.width / 2) * (r.height / 2)
    guard let y = (args["y"] as? FlutterStandardTypedData)?.data,
          let u = (args["u"] as? FlutterStandardTypedData)?.data,
          let v = (args["v"] as? FlutterStandardTypedData)?.data,
          y.count >= r.width * r.height, u.count >= chroma, v.count >= chroma else {
      result(Self.failure("bad_frame", "Frame planes don't match \(r.width)×\(r.height)"))
      return
    }
    queue.async {
      if r.failed {
        DispatchQueue.main.async { result(Self.failure("failed", "The timelapse stopped")) }
        return
      }
      do {
        let frames = try r.append(y: y, u: u, v: v)
        DispatchQueue.main.async { result(frames) }
      } catch {
        r.discard()
        DispatchQueue.main.async {
          if self.open === r { self.open = nil }
          result(Self.failure("failed", error.localizedDescription))
        }
      }
    }
  }

  private func end(result: @escaping FlutterResult) {
    guard let r = open else {
      result(Self.failure("not_started", "No timelapse is recording"))
      return
    }
    open = nil
    queue.async {
      if r.failed {
        DispatchQueue.main.async { result(Self.failure("failed", "The timelapse stopped")) }
        return
      }
      // Hold the queue until the file is closed, so a following begin waits.
      let done = DispatchSemaphore(value: 0)
      r.finish { outcome in
        switch outcome {
        case .success(let frames):
          let seconds = Double(frames) / Double(r.fps)
          DispatchQueue.main.async { result(["path": r.path, "frames": frames, "seconds": seconds]) }
        case .failure(let error):
          r.discard()
          DispatchQueue.main.async { result(Self.failure("failed", error.localizedDescription)) }
        }
        done.signal()
      }
      done.wait()
    }
  }

  private func cancel(result: @escaping FlutterResult) {
    guard let r = open else {
      result(nil)
      return
    }
    open = nil
    queue.async {
      r.discard()
      DispatchQueue.main.async { result(nil) }
    }
  }
}

private struct TimelapseError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// One .mp4 being written. Everything but init runs on LookUpTimelapse's queue.
private final class TimelapseRecording {
  let path: String
  let width: Int
  let height: Int
  let fps: Int
  private(set) var failed = false
  private var frames = 0
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

  init(path: String, width: Int, height: Int, fps: Int) {
    self.path = path
    self.width = width
    self.height = height
    self.fps = fps
  }

  private var url: URL { URL(fileURLWithPath: path) }

  func start(rotation: Int, bitrate: Int) throws {
    try? FileManager.default.removeItem(at: url)
    let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: bitrate,
        AVVideoExpectedSourceFrameRateKey: fps,
        // A key frame every second.
        AVVideoMaxKeyFrameIntervalKey: fps,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
      ] as [String: Any],
    ]
    guard w.canApply(outputSettings: settings, forMediaType: .video) else {
      throw TimelapseError("This phone can't encode \(width)×\(height) H.264")
    }
    let i = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    i.expectsMediaDataInRealTime = false
    i.transform = Self.transform(rotation: rotation, width: width, height: height)
    let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ])
    guard w.canAdd(i) else { throw TimelapseError("Couldn't add the video track") }
    w.add(i)
    guard w.startWriting() else {
      throw w.error ?? TimelapseError("Couldn't start writing")
    }
    w.startSession(atSourceTime: .zero)
    writer = w
    input = i
    adaptor = a
  }

  /// The clockwise turn as the track's display matrix: what
  /// CGAffineTransform(rotationAngle:) gives, with exact zeros and ones, plus
  /// the translation the camera writes so the picture stays in view.
  private static func transform(rotation: Int, width: Int, height: Int) -> CGAffineTransform {
    let w = CGFloat(width), h = CGFloat(height)
    switch rotation {
    case 90: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
    case 180: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
    case 270: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
    default: return .identity
    }
  }

  /// Writes one frame; returns how many have gone in.
  func append(y: Data, u: Data, v: Data) throws -> Int {
    guard let w = writer, let i = input, let a = adaptor, w.status == .writing else {
      throw writer?.error ?? TimelapseError("The writer isn't running")
    }
    // Not real time: wait (briefly) for the encoder rather than drop a frame.
    let deadline = Date().addingTimeInterval(5)
    while !i.isReadyForMoreMediaData {
      if w.status != .writing { throw w.error ?? TimelapseError("The writer stopped") }
      if Date() > deadline { throw TimelapseError("The encoder stopped taking frames") }
      Thread.sleep(forTimeInterval: 0.01)
    }
    guard let pool = a.pixelBufferPool else {
      throw w.error ?? TimelapseError("No pixel buffer pool")
    }
    var made: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &made) == kCVReturnSuccess,
          let buffer = made else {
      throw TimelapseError("Couldn't make a pixel buffer")
    }
    try fill(buffer, y: y, u: u, v: v)
    let time = CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps))
    guard a.append(buffer, withPresentationTime: time) else {
      throw w.error ?? TimelapseError("Couldn't append the frame")
    }
    frames += 1
    return frames
  }

  /// Planar I420 into the buffer's Y plane and interleaved CbCr plane,
  /// whatever their row lengths.
  private func fill(_ b: CVPixelBuffer, y: Data, u: Data, v: Data) throws {
    CVPixelBufferLockBaseAddress(b, [])
    defer { CVPixelBufferUnlockBaseAddress(b, []) }
    guard CVPixelBufferGetPlaneCount(b) >= 2,
          let yBase = CVPixelBufferGetBaseAddressOfPlane(b, 0),
          let cBase = CVPixelBufferGetBaseAddressOfPlane(b, 1) else {
      throw TimelapseError("Unexpected pixel buffer layout")
    }
    let yStride = CVPixelBufferGetBytesPerRowOfPlane(b, 0)
    let cStride = CVPixelBufferGetBytesPerRowOfPlane(b, 1)
    let yDst = yBase.assumingMemoryBound(to: UInt8.self)
    let cDst = cBase.assumingMemoryBound(to: UInt8.self)
    let w = width, h = height, cw = width / 2, ch = height / 2
    y.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
      guard let s = src.baseAddress else { return }
      for row in 0..<h {
        memcpy(yDst + row * yStride, s + row * w, w)
      }
    }
    u.withUnsafeBytes { (ub: UnsafeRawBufferPointer) in
      v.withUnsafeBytes { (vb: UnsafeRawBufferPointer) in
        let us = ub.bindMemory(to: UInt8.self)
        let vs = vb.bindMemory(to: UInt8.self)
        for row in 0..<ch {
          let d = cDst + row * cStride
          let from = row * cw
          for col in 0..<cw {
            d[col * 2] = us[from + col]
            d[col * 2 + 1] = vs[from + col]
          }
        }
      }
    }
  }

  /// Closes the file; calls back with the frame count once it's written.
  func finish(_ done: @escaping (Result<Int, Error>) -> Void) {
    guard let w = writer, let i = input, w.status == .writing else {
      done(.failure(writer?.error ?? TimelapseError("The writer isn't running")))
      return
    }
    if frames == 0 {
      // An .mp4 with nothing in it isn't a video.
      w.cancelWriting()
      release()
      try? FileManager.default.removeItem(at: url)
      done(.success(0))
      return
    }
    i.markAsFinished()
    // The last frame shows for 1/fps too.
    w.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps)))
    let count = frames
    w.finishWriting {
      let ok = w.status == .completed
      let error = w.error
      self.release()
      if ok {
        done(.success(count))
      } else {
        done(.failure(error ?? TimelapseError("Couldn't finish the video")))
      }
    }
  }

  /// Stops and deletes the file. Safe to call twice.
  func discard() {
    failed = true
    if let w = writer, w.status == .writing { w.cancelWriting() }
    release()
    try? FileManager.default.removeItem(at: url)
  }

  private func release() {
    writer = nil
    input = nil
    adaptor = nil
  }
}
