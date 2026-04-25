import Cocoa
import CoreGraphics
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var securityScopedBookmarkChannel: SecurityScopedBookmarkChannel?
  private var computerUseChannel: MacosComputerUseChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let windowWidth: CGFloat = 1280
    let windowHeight: CGFloat = 800
    let originX = screenFrame.origin.x + (screenFrame.width - windowWidth) / 2
    let originY = screenFrame.origin.y + (screenFrame.height - windowHeight) / 2
    let windowFrame = NSRect(x: originX, y: originY, width: windowWidth, height: windowHeight)
    self.setFrame(windowFrame, display: true)

    self.minSize = NSSize(width: 480, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)
    securityScopedBookmarkChannel = SecurityScopedBookmarkChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )
    computerUseChannel = MacosComputerUseChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}

final class SecurityScopedBookmarkChannel {
  private let channel: FlutterMethodChannel
  private var activeUrls: [String: URL] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.caverno/security_scoped_bookmarks",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  deinit {
    for url in activeUrls.values {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createBookmark":
      handleCreateBookmark(call, result: result)
    case "startAccessingBookmark":
      handleStartAccessingBookmark(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleCreateBookmark(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      !path.isEmpty
    else {
      result(
        FlutterError(code: "invalid_args", message: "path is required", details: nil)
      )
      return
    }

    do {
      let url = URL(fileURLWithPath: path)
      let bookmarkData = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      result(bookmarkData.base64EncodedString())
    } catch {
      result(
        FlutterError(
          code: "bookmark_create_failed",
          message: "Failed to create security-scoped bookmark",
          details: error.localizedDescription
        )
      )
    }
  }

  private func handleStartAccessingBookmark(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let bookmark = arguments["bookmark"] as? String,
      let bookmarkData = Data(base64Encoded: bookmark)
    else {
      result(
        FlutterError(code: "invalid_args", message: "bookmark is required", details: nil)
      )
      return
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      let path = url.path
      let accessStarted: Bool
      if activeUrls[path] != nil {
        accessStarted = true
      } else {
        accessStarted = url.startAccessingSecurityScopedResource()
        if accessStarted {
          activeUrls[path] = url
        }
      }

      var response: [String: Any] = [
        "accessStarted": accessStarted,
        "path": path,
      ]

      if isStale {
        let refreshedData = try url.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        response["bookmark"] = refreshedData.base64EncodedString()
      }

      if !accessStarted {
        response["error"] = "macOS denied access to the bookmarked folder."
      }

      result(response)
    } catch {
      result(
        FlutterError(
          code: "bookmark_restore_failed",
          message: "Failed to restore security-scoped bookmark",
          details: error.localizedDescription
        )
      )
    }
  }
}

fileprivate enum MacosComputerUseHelperCommand: String {
  case ping
  case permissionStatus
  case openSettings
  case stopAll
  case screenshot
  case listWindows
  case focusWindow
  case screenshotWindow
  case moveMouse
  case click
  case drag
  case scroll
  case typeText
  case pressKey
  case startSystemAudioRecording
  case stopSystemAudioRecording
}

fileprivate struct MacosComputerUseHelperRequest {
  static let protocolVersion = 1

  let requestId: String
  let command: MacosComputerUseHelperCommand
  let arguments: [String: Any]

  var userInfo: [String: Any] {
    [
      "protocolVersion": Self.protocolVersion,
      "requestId": requestId,
      "command": command.rawValue,
      "senderBundleIdentifier": Bundle.main.bundleIdentifier ?? "",
      "senderProcessIdentifier": Int(ProcessInfo.processInfo.processIdentifier),
      "arguments": arguments,
    ]
  }
}

fileprivate struct PendingMacosComputerUseHelperRequest {
  let command: MacosComputerUseHelperCommand
  let result: FlutterResult
}

final class MacosComputerUseHelperClient: NSObject {
  private let helperBundleIdentifier = "com.noguwo.apps.caverno.computer-use"
  private let helperDisplayName = "Caverno Computer Use"
  private let requestName = Notification.Name("com.caverno.computer_use.helper.request")
  private let responseName = Notification.Name("com.caverno.computer_use.helper.response")
  private let center = DistributedNotificationCenter.default()
  private var pendingRequests: [String: PendingMacosComputerUseHelperRequest] = [:]

  override init() {
    super.init()
    center.addObserver(
      self,
      selector: #selector(handleResponse(_:)),
      name: responseName,
      object: helperBundleIdentifier,
      suspensionBehavior: .deliverImmediately
    )
  }

  deinit {
    center.removeObserver(self)
  }

  func status() -> [String: Any] {
    let helperURL = embeddedHelperURL()
    let runningApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: helperBundleIdentifier
    ).first { !$0.isTerminated }
    var response: [String: Any] = [
      "ok": true,
      "helperDisplayName": helperDisplayName,
      "helperBundleIdentifier": helperBundleIdentifier,
      "helperInstalled": FileManager.default.fileExists(atPath: helperURL.path),
      "helperRunning": runningApplication != nil,
      "helperPath": helperURL.path,
    ]
    if let processIdentifier = runningApplication?.processIdentifier {
      response["helperProcessIdentifier"] = Int(processIdentifier)
    }
    return response
  }

  func launch(result: @escaping FlutterResult) {
    let helperURL = embeddedHelperURL()
    guard FileManager.default.fileExists(atPath: helperURL.path) else {
      result(
        FlutterError(
          code: "helper_not_installed",
          message: "Caverno Computer Use is not bundled with this Caverno build.",
          details: ["helperPath": helperURL.path]
        )
      )
      return
    }

    if let runningApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: helperBundleIdentifier
    ).first(where: { !$0.isTerminated }) {
      runningApplication.activate(options: [.activateIgnoringOtherApps])
      var response = status()
      response["alreadyRunning"] = true
      result(response)
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) {
      [weak self] application, error in
      guard let self else {
        return
      }
      if let error {
        result(
          FlutterError(
            code: "helper_launch_failed",
            message: "Failed to launch Caverno Computer Use.",
            details: error.localizedDescription
          )
        )
        return
      }

      var response = self.status()
      response["launched"] = true
      if let processIdentifier = application?.processIdentifier {
        response["helperProcessIdentifier"] = Int(processIdentifier)
      }
      result(response)
    }
  }

  fileprivate func send(
    command: MacosComputerUseHelperCommand,
    arguments: [String: Any] = [:],
    timeout: TimeInterval = 1.5,
    result: @escaping FlutterResult
  ) {
    let requestId = UUID().uuidString
    let request = MacosComputerUseHelperRequest(
      requestId: requestId,
      command: command,
      arguments: arguments
    )
    pendingRequests[requestId] = PendingMacosComputerUseHelperRequest(
      command: command,
      result: result
    )
    center.postNotificationName(
      requestName,
      object: Bundle.main.bundleIdentifier,
      userInfo: request.userInfo,
      deliverImmediately: true
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let pendingRequest = self?.pendingRequests.removeValue(forKey: requestId) else {
        return
      }
      pendingRequest.result(
        FlutterError(
          code: "helper_unreachable",
          message: "Caverno Computer Use did not respond to \(pendingRequest.command.rawValue).",
          details: [
            "command": pendingRequest.command.rawValue,
            "helperBundleIdentifier": "com.noguwo.apps.caverno.computer-use",
          ]
        )
      )
    }
  }

  @objc private func handleResponse(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let requestId = userInfo["requestId"] as? String,
      let pendingRequest = pendingRequests.removeValue(forKey: requestId)
    else {
      return
    }

    let protocolVersion = userInfo["protocolVersion"] as? Int ?? 0
    guard protocolVersion == MacosComputerUseHelperRequest.protocolVersion else {
      pendingRequest.result(
        FlutterError(
          code: "helper_unsupported_protocol",
          message: "Caverno Computer Use returned an unsupported protocol version.",
          details: [
            "protocolVersion": protocolVersion,
            "command": pendingRequest.command.rawValue,
          ]
        )
      )
      return
    }

    let commandName = userInfo["command"] as? String ?? ""
    guard commandName == pendingRequest.command.rawValue else {
      pendingRequest.result(
        FlutterError(
          code: "helper_response_mismatch",
          message: "Caverno Computer Use returned a response for a different command.",
          details: [
            "expectedCommand": pendingRequest.command.rawValue,
            "actualCommand": commandName,
          ]
        )
      )
      return
    }

    guard let response = userInfo["response"] as? [String: Any] else {
      pendingRequest.result(
        FlutterError(
          code: "helper_invalid_response",
          message: "Caverno Computer Use returned an invalid response.",
          details: nil
        )
      )
      return
    }

    pendingRequest.result(response)
  }

  private func embeddedHelperURL() -> URL {
    Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Helpers", isDirectory: true)
      .appendingPathComponent("\(helperDisplayName).app", isDirectory: true)
  }
}

final class MacosComputerUseChannel {
  private let channel: FlutterMethodChannel
  private let helperClient = MacosComputerUseHelperClient()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.caverno/macos_computer_use",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "helperStatus":
      result(helperClient.status())
    case "launchHelper":
      helperClient.launch(result: result)
    case "helperPing":
      helperClient.send(command: .ping, result: result)
    case "helperPermissionStatus":
      helperClient.send(command: .permissionStatus, result: result)
    case "helperOpenSystemSettings":
      helperClient.send(
        command: .openSettings,
        arguments: call.arguments as? [String: Any] ?? [:],
        result: result
      )
    case "helperStopAll":
      helperClient.send(command: .stopAll, timeout: 8, result: result)
    case "getPermissions":
      result(permissionSnapshot())
    case "requestAccessibility":
      requestAccessibility(result: result)
    case "requestScreenCapture":
      requestScreenCapture(result: result)
    case "openSystemSettings":
      openSystemSettings(call, result: result)
    case "listWindows":
      helperClient.send(
        command: .listWindows,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "focusWindow":
      helperClient.send(
        command: .focusWindow,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "screenshot":
      helperClient.send(
        command: .screenshot,
        arguments: helperArguments(call),
        timeout: 8,
        result: result
      )
    case "screenshotWindow":
      helperClient.send(
        command: .screenshotWindow,
        arguments: helperArguments(call),
        timeout: 8,
        result: result
      )
    case "click":
      helperClient.send(
        command: .click,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "moveMouse":
      helperClient.send(
        command: .moveMouse,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "drag":
      helperClient.send(
        command: .drag,
        arguments: helperArguments(call),
        timeout: 6,
        result: result
      )
    case "scroll":
      helperClient.send(
        command: .scroll,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "typeText":
      helperClient.send(
        command: .typeText,
        arguments: helperArguments(call),
        timeout: 5,
        result: result
      )
    case "pressKey":
      helperClient.send(
        command: .pressKey,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "startSystemAudioRecording":
      helperClient.send(
        command: .startSystemAudioRecording,
        arguments: helperArguments(call),
        timeout: 8,
        result: result
      )
    case "stopSystemAudioRecording":
      helperClient.send(
        command: .stopSystemAudioRecording,
        arguments: helperArguments(call),
        timeout: 8,
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func helperArguments(_ call: FlutterMethodCall) -> [String: Any] {
    var arguments = call.arguments as? [String: Any] ?? [:]
    arguments["mainAppPid"] = Int(ProcessInfo.processInfo.processIdentifier)
    return arguments
  }

  private func permissionSnapshot() -> [String: Any] {
    var screenCaptureGranted = true
    if #available(macOS 10.15, *) {
      screenCaptureGranted = CGPreflightScreenCaptureAccess()
    }

    return [
      "accessibilityGranted": AXIsProcessTrusted(),
      "screenCaptureGranted": screenCaptureGranted,
      "systemAudioRecordingSupported": isSystemAudioRecordingSupported(),
    ]
  }

  private func requestAccessibility(result: @escaping FlutterResult) {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)
    result(["accessibilityGranted": trusted])
  }

  private func requestScreenCapture(result: @escaping FlutterResult) {
    if #available(macOS 10.15, *) {
      let granted = CGRequestScreenCaptureAccess()
      result(["screenCaptureGranted": granted])
      return
    }
    result(["screenCaptureGranted": true])
  }

  private func openSystemSettings(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let section = (arguments["section"] as? String ?? "").lowercased()
    let target: (section: String, url: String)?
    switch section {
    case "accessibility":
      target = (
        "accessibility",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    case "screen_capture", "screencapture", "screen_recording", "screenrecording":
      target = (
        "screenRecording",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
      )
    case "privacy":
      target = (
        "privacy",
        "x-apple.systempreferences:com.apple.preference.security?Privacy"
      )
    default:
      target = nil
    }

    guard let target else {
      result(
        FlutterError(
          code: "invalid_args",
          message: "section must be accessibility, screen_recording, or privacy",
          details: section
        )
      )
      return
    }
    guard let url = URL(string: target.url) else {
      result(FlutterError(code: "invalid_url", message: "Failed to build System Settings URL", details: target.url))
      return
    }

    let opened = NSWorkspace.shared.open(url)
    result([
      "ok": opened,
      "section": target.section,
      "url": url.absoluteString,
    ])
  }

  private func isSystemAudioRecordingSupported() -> Bool {
    if #available(macOS 13.0, *) {
      return true
    }
    return false
  }
}
