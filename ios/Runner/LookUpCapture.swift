// "Catch it" on iPhone: back-to-back custom exposures (shutter and ISO from
// lib/domain/photo/exposure.dart), focus at infinity, white balance locked,
// streamed to Dart as YUV frames for stacking (lib/domain/photo/streak_stacker.dart).
// Same channel protocol as android/.../LookUpCapture.kt; Dart side in
// lib/services/capture/native_capture.dart. Registered in AppDelegate's
// didInitializeImplicitFlutterEngine.

import AVFoundation
import Flutter
import UIKit

final class LookUpCapture: NSObject, FlutterStreamHandler, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = LookUpCapture(textures: registrar.textures())
    let methods = FlutterMethodChannel(name: "lookup/capture", binaryMessenger: registrar.messenger())
    methods.setMethodCallHandler { call, result in instance.handle(call, result: result) }
    FlutterEventChannel(name: "lookup/capture/frames", binaryMessenger: registrar.messenger())
      .setStreamHandler(instance)
    keep = instance
  }

  private static var keep: LookUpCapture?

  private let textures: FlutterTextureRegistry
  private let queue = DispatchQueue(label: "lookup.capture")
  private var session: AVCaptureSession?
  private var device: AVCaptureDevice?
  private var textureId: Int64 = 0
  private var latest: CVPixelBuffer?
  private let latestLock = NSLock()
  private var sink: FlutterEventSink?
  private var streaming = false
  private var lastSent = Date.distantPast
  private var minGap: TimeInterval = 0
  private var longPx = 1920

  init(textures: FlutterTextureRegistry) {
    self.textures = textures
  }

  // MARK: Channel

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "capabilities":
      result(capabilities())
    case "open":
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          guard granted else {
            result(FlutterError(code: "CameraAccessDenied", message: "Camera access is off", details: nil))
            return
          }
          self.open(lensId: args["lensId"] as? String, result: result)
        }
      }
    case "start":
      start(shutterS: args["shutterS"] as? Double, iso: (args["iso"] as? NSNumber)?.floatValue,
            longPx: args["longPx"] as? Int ?? 1920, result: result)
    case "stop":
      streaming = false
      preview()
      result(nil)
    case "close":
      close()
      result(nil)
    case "keepAwake":
      UIApplication.shared.isIdleTimerDisabled = (args["on"] as? Bool) == true
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Cameras

  private func backCameras() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
      mediaType: .video,
      position: .back
    ).devices
  }

  /// Field of view along the format's long and short sides.
  private func fov(_ d: AVCaptureDevice) -> (Double, Double) {
    let long = Double(d.activeFormat.videoFieldOfView)
    let dims = CMVideoFormatDescriptionGetDimensions(d.activeFormat.formatDescription)
    let ratio = Double(min(dims.width, dims.height)) / Double(max(dims.width, dims.height))
    let short = 2 * atan(tan(long / 2 * .pi / 180) * ratio) * 180 / .pi
    return (long, short)
  }

  /// The longest frame (and so exposure) the active format allows:
  /// asking AVFoundation for more raises an exception.
  private func longestFrameS(_ d: AVCaptureDevice) -> Double {
    let f = d.activeFormat
    let frame = f.videoSupportedFrameRateRanges.map { CMTimeGetSeconds($0.maxFrameDuration) }.max() ?? (1.0 / 30)
    return min(frame, CMTimeGetSeconds(f.maxExposureDuration))
  }

  private func capabilities() -> [String: Any] {
    let cams = backCameras()
    let lenses: [[String: Any]] = cams.map { d in
      let (long, short) = fov(d)
      return ["id": d.uniqueID, "longFov": long, "shortFov": short, "f": Double(d.lensAperture)]
    }
    guard let main = cams.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? cams.first else {
      return ["manual": false, "lenses": lenses]
    }
    let f = main.activeFormat
    return [
      "manual": main.isExposureModeSupported(.custom),
      "minShutterS": CMTimeGetSeconds(f.minExposureDuration),
      "maxShutterS": longestFrameS(main),
      "minIso": Int(f.minISO),
      "maxIso": Int(f.maxISO),
      "lenses": lenses,
    ]
  }

  private func open(lensId: String?, result: @escaping FlutterResult) {
    close()
    let cams = backCameras()
    guard let d = cams.first(where: { $0.uniqueID == lensId })
      ?? cams.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? cams.first else {
      result(FlutterError(code: "capture", message: "No back camera", details: nil))
      return
    }
    let s = AVCaptureSession()
    s.sessionPreset = .high
    do {
      let input = try AVCaptureDeviceInput(device: d)
      guard s.canAddInput(input) else { throw NSError(domain: "capture", code: 1) }
      s.addInput(input)
    } catch {
      result(FlutterError(code: "capture", message: "Camera didn't start", details: nil))
      return
    }
    let out = AVCaptureVideoDataOutput()
    out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
    out.alwaysDiscardsLateVideoFrames = false
    out.setSampleBufferDelegate(self, queue: queue)
    if s.canAddOutput(out) { s.addOutput(out) }
    session = s
    device = d
    textureId = textures.register(self)
    autoFocus()
    queue.async {
      s.startRunning()
      let dims = CMVideoFormatDescriptionGetDimensions(d.activeFormat.formatDescription)
      DispatchQueue.main.async {
        // Frames arrive in the sensor's landscape orientation: a quarter turn
        // clockwise makes them upright with the phone held upright.
        result(["textureId": self.textureId, "width": Int(dims.width), "height": Int(dims.height), "sensorOrientation": 90])
      }
    }
  }

  /// Aiming: ordinary autofocus, so the preview is sharp indoors too.
  private func autoFocus() {
    guard let d = device, (try? d.lockForConfiguration()) != nil else { return }
    if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
    d.unlockForConfiguration()
  }

  /// Capturing: stars are at infinity, and autofocus can't find them in the dark.
  private func focusAtInfinity() {
    guard let d = device, (try? d.lockForConfiguration()) != nil else { return }
    if d.isFocusModeSupported(.locked) { d.setFocusModeLocked(lensPosition: 1.0, completionHandler: nil) }
    d.unlockForConfiguration()
  }

  /// Back to auto exposure for aiming.
  private func preview() {
    guard let d = device, (try? d.lockForConfiguration()) != nil else { return }
    if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
    if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
    d.activeVideoMaxFrameDuration = .invalid
    d.activeVideoMinFrameDuration = .invalid
    if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
    d.unlockForConfiguration()
  }

  private func start(shutterS: Double?, iso: Float?, longPx: Int, result: @escaping FlutterResult) {
    guard let d = device else {
      result(FlutterError(code: "capture", message: "Camera not open", details: nil))
      return
    }
    self.longPx = longPx
    focusAtInfinity()
    if let shutterS = shutterS, let iso = iso, d.isExposureModeSupported(.custom) {
      do {
        try d.lockForConfiguration()
        let f = d.activeFormat
        let seconds = min(max(shutterS, CMTimeGetSeconds(f.minExposureDuration)), longestFrameS(d))
        let duration = CMTime(seconds: seconds, preferredTimescale: 1_000_000)
        // Frames as long as the exposure, back to back.
        d.activeVideoMaxFrameDuration = duration
        d.activeVideoMinFrameDuration = duration
        d.setExposureModeCustom(duration: duration, iso: min(max(iso, f.minISO), f.maxISO), completionHandler: nil)
        if d.isWhiteBalanceModeSupported(.locked) { d.whiteBalanceMode = .locked }
        d.unlockForConfiguration()
      } catch {
        result(FlutterError(code: "capture", message: "Couldn't set the exposure", details: nil))
        return
      }
      minGap = 0
    } else {
      minGap = 0.1
    }
    streaming = true
    result(nil)
  }

  private func close() {
    streaming = false
    session?.stopRunning()
    session = nil
    device = nil
    if textureId != 0 {
      textures.unregisterTexture(textureId)
      textureId = 0
    }
  }

  // MARK: Frames

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    latestLock.lock()
    defer { latestLock.unlock() }
    guard let b = latest else { return nil }
    return Unmanaged.passRetained(b)
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    latestLock.lock()
    latest = buffer
    latestLock.unlock()
    let id = textureId
    DispatchQueue.main.async { if id != 0 { self.textures.textureFrameAvailable(id) } }

    let now = Date()
    guard streaming, sink != nil, now.timeIntervalSince(lastSent) >= minGap else { return }
    lastSent = now
    guard let frame = yuv(buffer) else { return }
    DispatchQueue.main.async { self.sink?(frame) }
  }

  /// Y at up to [longPx] on the long side (every nth pixel), Cb and Cr at
  /// half that, tightly packed.
  private func yuv(_ b: CVPixelBuffer) -> [String: Any]? {
    CVPixelBufferLockBaseAddress(b, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(b, .readOnly) }
    guard CVPixelBufferGetPlaneCount(b) >= 2,
          let yBase = CVPixelBufferGetBaseAddressOfPlane(b, 0),
          let cBase = CVPixelBufferGetBaseAddressOfPlane(b, 1) else { return nil }
    let srcW = CVPixelBufferGetWidthOfPlane(b, 0), srcH = CVPixelBufferGetHeightOfPlane(b, 0)
    let step = max(1, Int((Double(max(srcW, srcH)) / Double(longPx)).rounded(.up)))
    let w = (srcW / step) & ~1, h = (srcH / step) & ~1
    let yStride = CVPixelBufferGetBytesPerRowOfPlane(b, 0)
    let cStride = CVPixelBufferGetBytesPerRowOfPlane(b, 1)
    let yp = yBase.assumingMemoryBound(to: UInt8.self)
    let cp = cBase.assumingMemoryBound(to: UInt8.self)
    var y = [UInt8](repeating: 0, count: w * h)
    var u = [UInt8](repeating: 0, count: (w / 2) * (h / 2))
    var v = [UInt8](repeating: 0, count: (w / 2) * (h / 2))
    for row in 0..<h {
      let src = row * step * yStride
      for col in 0..<w { y[row * w + col] = yp[src + col * step] }
    }
    for row in 0..<(h / 2) {
      let src = row * step * cStride
      for col in 0..<(w / 2) {
        let i = src + col * step * 2
        u[row * (w / 2) + col] = cp[i]
        v[row * (w / 2) + col] = cp[i + 1]
      }
    }
    return [
      "w": w, "h": h,
      "y": FlutterStandardTypedData(bytes: Data(y)),
      "u": FlutterStandardTypedData(bytes: Data(u)),
      "v": FlutterStandardTypedData(bytes: Data(v)),
      "rotation": 90,
      "t": Int(Date().timeIntervalSince1970 * 1000),
    ]
  }
}
