import Flutter
import UIKit
import WatchConnectivity
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
    WatchBridgePlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "WatchBridgePlugin")!)
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

/// FlutterPlugin that bridges the Flutter app and the paired Apple Watch app.
///
/// Flutter does not run on watchOS, so the companion is a native SwiftUI target
/// and every frame crosses a `WCSession` here. Two channels, matching
/// `lib/core/services/watch_bridge_service.dart`:
///
/// - a MethodChannel for Dart -> watch (snapshots, stream chunks, command
///   results) and for capability queries;
/// - an EventChannel for watch -> Dart commands.
///
/// Payloads are JSON strings rather than structured dictionaries so the wire
/// format is owned by one Dart file instead of being split across a
/// hand-maintained Swift mirror.
class WatchBridgePlugin: NSObject, FlutterPlugin {
  private static let methodChannelName = "com.caverno/watch_bridge"
  private static let commandChannelName = "com.caverno/watch_bridge/commands"

  /// Key under which every payload travels, in both directions.
  private static let payloadKey = "payload"

  private var commandSink: FlutterEventSink?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = WatchBridgePlugin()

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let commandChannel = FlutterEventChannel(
      name: commandChannelName,
      binaryMessenger: registrar.messenger()
    )
    commandChannel.setStreamHandler(instance)

    instance.activateSession()
  }

  private func activateSession() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(isAvailable())
    case "pushSnapshot":
      guard let payload = call.arguments as? String else {
        result(invalidArguments())
        return
      }
      pushSnapshot(payload)
      result(nil)
    case "pushStreamChunk":
      guard let payload = call.arguments as? String else {
        result(invalidArguments())
        return
      }
      // Stream chunks are only meaningful while the watch app is on screen.
      // Queuing a stale sentence for later delivery would have the watch read
      // out text from a turn that already finished, so this drops instead.
      sendIfReachable(payload)
      result(nil)
    case "sendCommandResult":
      guard let payload = call.arguments as? String else {
        result(invalidArguments())
        return
      }
      sendIfReachable(payload)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func invalidArguments() -> FlutterError {
    FlutterError(
      code: "invalid_arguments",
      message: "A JSON payload string is required.",
      details: nil
    )
  }

  private func isAvailable() -> Bool {
    guard WCSession.isSupported() else { return false }
    let session = WCSession.default
    return session.activationState == .activated
      && session.isPaired
      && session.isWatchAppInstalled
  }

  /// Delivers the latest state twice, on purpose.
  ///
  /// `updateApplicationContext` coalesces: the OS keeps only the newest
  /// dictionary, which is exactly right for state and means a watch that wakes
  /// up later still sees the current frame. `sendMessage` is added when the
  /// watch app is foreground-reachable so an approval appears immediately
  /// rather than at the system's next opportunistic sync.
  private func pushSnapshot(_ payload: String) {
    guard isAvailable() else { return }
    let session = WCSession.default
    do {
      try session.updateApplicationContext([Self.payloadKey: payload])
    } catch {
      // A rejected context is not actionable here: the next snapshot supersedes
      // it, and the reachable path below may still have delivered this one.
      NSLog("WatchBridgePlugin: updateApplicationContext failed: \(error)")
    }
    sendIfReachable(payload)
  }

  private func sendIfReachable(_ payload: String) {
    guard isAvailable() else { return }
    let session = WCSession.default
    guard session.isReachable else { return }
    session.sendMessage(
      [Self.payloadKey: payload],
      replyHandler: nil,
      errorHandler: { error in
        NSLog("WatchBridgePlugin: sendMessage failed: \(error)")
      }
    )
  }

  /// Forwards a watch payload to Dart on the main thread.
  ///
  /// WatchConnectivity delivers on a background queue, and Flutter platform
  /// channels must be touched from the platform thread.
  private func emitCommand(_ message: [String: Any]) {
    guard let payload = message[Self.payloadKey] as? String else { return }
    DispatchQueue.main.async { [weak self] in
      self?.commandSink?(payload)
    }
  }
}

extension WatchBridgePlugin: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    commandSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    commandSink = nil
    return nil
  }
}

extension WatchBridgePlugin: WCSessionDelegate {
  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      NSLog("WatchBridgePlugin: activation failed: \(error)")
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  /// Re-activates after the user switches to a different paired watch.
  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    emitCommand(message)
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    emitCommand(message)
    // The command result comes back asynchronously over `sendCommandResult`
    // once Dart has acted, so acknowledge receipt immediately instead of
    // holding the watch's reply handler open past its timeout.
    replyHandler(["received": true])
  }

  func session(
    _ session: WCSession,
    didReceiveUserInfo userInfo: [String: Any] = [:]
  ) {
    emitCommand(userInfo)
  }
}
