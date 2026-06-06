import Flutter
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    BackgroundTaskPlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundTaskPlugin")!)
    AppleFoundationModelsPlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "AppleFoundationModelsPlugin")!)
  }
}

/// FlutterPlugin that exposes iOS background task API via MethodChannel.
class BackgroundTaskPlugin: NSObject, FlutterPlugin {
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.caverno/background_task",
      binaryMessenger: registrar.messenger()
    )
    let instance = BackgroundTaskPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "beginBackgroundTask":
      beginBackgroundTask()
      result(nil)
    case "endBackgroundTask":
      endBackgroundTask()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginBackgroundTask() {
    if backgroundTaskId != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTaskId)
    }
    backgroundTaskId = UIApplication.shared.beginBackgroundTask { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    if backgroundTaskId != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTaskId)
      backgroundTaskId = .invalid
    }
  }
}

/// FlutterPlugin that exposes Apple's on-device Foundation Models framework.
class AppleFoundationModelsPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.caverno/apple_foundation_models",
      binaryMessenger: registrar.messenger()
    )
    let instance = AppleFoundationModelsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkAvailability":
      checkAvailability(result: result)
    case "respond":
      respond(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func checkAvailability(result: @escaping FlutterResult) {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      result(Self.availabilityPayload())
      return
    }
#endif
    result([
      "isAvailable": false,
      "status": "unavailable",
      "reason": "ios_26_required",
    ])
  }

  private func respond(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let prompt = arguments["prompt"] as? String else {
      result(FlutterError(
        code: "invalid_arguments",
        message: "A prompt string is required.",
        details: nil
      ))
      return
    }

    let instructions = arguments["instructions"] as? String ?? ""
    let temperature = (arguments["temperature"] as? NSNumber)?.doubleValue
    let maxTokens = (arguments["maxTokens"] as? NSNumber)?.intValue

#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      Task {
        do {
          let content = try await Self.generateResponse(
            instructions: instructions,
            prompt: prompt,
            temperature: temperature,
            maxTokens: maxTokens
          )
          await MainActor.run {
            result(["content": content])
          }
        } catch {
          await MainActor.run {
            result(FlutterError(
              code: "foundation_models_error",
              message: error.localizedDescription,
              details: String(describing: error)
            ))
          }
        }
      }
      return
    }
#endif

    result(FlutterError(
      code: "foundation_models_unavailable",
      message: "Apple Foundation Models requires iOS 26 or newer.",
      details: "ios_26_required"
    ))
  }

#if canImport(FoundationModels)
  @available(iOS 26.0, *)
  private static func availabilityPayload() -> [String: Any] {
    switch SystemLanguageModel.default.availability {
    case .available:
      return [
        "isAvailable": true,
        "status": "available",
      ]
    case .unavailable(let reason):
      return [
        "isAvailable": false,
        "status": "unavailable",
        "reason": String(describing: reason),
      ]
    }
  }

  @available(iOS 26.0, *)
  private static func generateResponse(
    instructions: String,
    prompt: String,
    temperature: Double?,
    maxTokens: Int?
  ) async throws -> String {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
      throw NSError(
        domain: "CavernoAppleFoundationModels",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Apple Foundation Models is unavailable.",
          "availability": String(describing: model.availability),
        ]
      )
    }

    let normalizedTemperature = temperature.map { min(max($0, 0.0), 1.0) }
    let normalizedMaxTokens = maxTokens.flatMap { $0 > 0 ? $0 : nil }
    let options = GenerationOptions(
      temperature: normalizedTemperature,
      maximumResponseTokens: normalizedMaxTokens
    )
    let session = LanguageModelSession(model: model, instructions: instructions)
    let response = try await session.respond(to: prompt, options: options)
    return response.content
  }
#endif
}
