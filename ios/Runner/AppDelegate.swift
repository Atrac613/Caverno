import Flutter
import UIKit

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
