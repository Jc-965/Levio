import Flutter
import MediaPipeTasksVision
import UIKit

final class MotionPoseBridge: NSObject, FlutterPlugin {
  private static let channelName = "com.parkiwell.app/motion_pose"

  private let worker = DispatchQueue(
    label: "com.parkiwell.app.motion-pose",
    qos: .userInitiated
  )
  private var poseLandmarker: PoseLandmarker?
  private var disposed = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = MotionPoseBridge()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.publish(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      initialize(call, result: result)
    case "detect":
      detect(call, result: result)
    case "dispose":
      dispose(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    worker.sync {
      poseLandmarker = nil
      disposed = true
    }
  }

  private func initialize(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let modelPath = arguments["modelPath"] as? String,
      !modelPath.isEmpty
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "A pose model path is required.",
          details: nil
        )
      )
      return
    }

    worker.async { [weak self] in
      do {
        self?.poseLandmarker = try Self.createLandmarker(
          modelPath: modelPath,
          delegate: .GPU
        )
        self?.disposed = false
        Self.succeed(result, value: nil)
      } catch {
        do {
          self?.poseLandmarker = try Self.createLandmarker(
            modelPath: modelPath,
            delegate: .CPU
          )
          self?.disposed = false
          Self.succeed(result, value: nil)
        } catch {
          Self.fail(result, code: "INITIALIZATION_FAILED", error: error)
        }
      }
    }
  }

  private static func createLandmarker(
    modelPath: String,
    delegate: Delegate
  ) throws -> PoseLandmarker {
    let options = PoseLandmarkerOptions()
    options.baseOptions.modelAssetPath = modelPath
    options.baseOptions.delegate = delegate
    options.runningMode = .image
    options.numPoses = 2
    options.minPoseDetectionConfidence = 0.5
    options.minPosePresenceConfidence = 0.5
    options.minTrackingConfidence = 0.5
    return try PoseLandmarker(options: options)
  }

  private func detect(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let planeData = arguments["planes"] as? [FlutterStandardTypedData],
      let rowStrides = arguments["rowStrides"] as? [Int],
      let width = arguments["width"] as? Int,
      let height = arguments["height"] as? Int,
      let format = arguments["format"] as? String,
      let rotationDegrees = arguments["rotationDegrees"] as? Int,
      let timestampMs = arguments["timestampMs"] as? Int,
      !planeData.isEmpty,
      !rowStrides.isEmpty
    else {
      result(
        FlutterError(
          code: "INVALID_ARGUMENTS",
          message: "Incomplete camera frame metadata.",
          details: nil
        )
      )
      return
    }

    worker.async { [weak self] in
      do {
        guard let landmarker = self?.poseLandmarker, self?.disposed == false
        else {
          throw MotionPoseError.notInitialized
        }
        guard format == "bgra8888" else {
          throw MotionPoseError.unsupportedFormat(format)
        }
        let image = try Self.makeImage(
          data: planeData[0].data,
          width: width,
          height: height,
          bytesPerRow: rowStrides[0]
        )
        let mpImage = try MPImage(
          uiImage: image,
          orientation: Self.orientation(for: rotationDegrees)
        )
        let started = ProcessInfo.processInfo.systemUptime
        let detection = try landmarker.detect(image: mpImage)
        let inferenceMs =
          (ProcessInfo.processInfo.systemUptime - started) * 1_000
        var response: [String: Any?] = [
          "timestampMs": timestampMs,
          "inferenceMs": inferenceMs,
          "poseCount": detection.landmarks.count,
          "landmarks": nil,
          "worldLandmarks": nil,
        ]
        if let landmarks = detection.landmarks.first {
          response["landmarks"] = landmarks.map { landmark in
            [
              "x": Double(landmark.x),
              "y": Double(landmark.y),
              "z": Double(landmark.z),
              "visibility": landmark.visibility?.doubleValue ?? 0,
              "presence": landmark.presence?.doubleValue ?? 0,
            ]
          }
          if let world = detection.worldLandmarks.first {
            response["worldLandmarks"] = world.enumerated().map {
              index, landmark in
              [
                "x": Double(landmark.x),
                "y": Double(landmark.y),
                "z": Double(landmark.z),
                "visibility":
                  landmarks[index].visibility?.doubleValue ?? 0,
                "presence": landmarks[index].presence?.doubleValue ?? 0,
              ]
            }
          }
        }
        Self.succeed(result, value: response)
      } catch {
        Self.fail(result, code: "DETECTION_FAILED", error: error)
      }
    }
  }

  private func dispose(result: @escaping FlutterResult) {
    worker.async { [weak self] in
      self?.poseLandmarker = nil
      self?.disposed = true
      Self.succeed(result, value: nil)
    }
  }

  private static func makeImage(
    data: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int
  ) throws -> UIImage {
    guard width > 0, height > 0, bytesPerRow >= width * 4 else {
      throw MotionPoseError.invalidFrame
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(
      rawValue:
        CGBitmapInfo.byteOrder32Little.rawValue
        | CGImageAlphaInfo.premultipliedFirst.rawValue
    )
    guard
      let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    else {
      throw MotionPoseError.invalidFrame
    }
    return UIImage(cgImage: image)
  }

  private static func orientation(
    for degrees: Int
  ) -> UIImage.Orientation {
    switch ((degrees % 360) + 360) % 360 {
    case 90:
      return .right
    case 180:
      return .down
    case 270:
      return .left
    default:
      return .up
    }
  }

  private static func succeed(
    _ result: @escaping FlutterResult,
    value: Any?
  ) {
    DispatchQueue.main.async {
      result(value)
    }
  }

  private static func fail(
    _ result: @escaping FlutterResult,
    code: String,
    error: Error
  ) {
    DispatchQueue.main.async {
      result(
        FlutterError(
          code: code,
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }
}

private enum MotionPoseError: LocalizedError {
  case invalidFrame
  case notInitialized
  case unsupportedFormat(String)

  var errorDescription: String? {
    switch self {
    case .invalidFrame:
      return "The camera frame could not be decoded."
    case .notInitialized:
      return "The motion pose runtime is not initialized."
    case .unsupportedFormat(let format):
      return "Unsupported iOS camera format: \(format)"
    }
  }
}
