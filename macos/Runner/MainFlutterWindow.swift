import Cocoa
import CoreGraphics
import FlutterMacOS

@objc(CavernoComputerUseXpcProtocol)
protocol CavernoComputerUseXpcProtocol: NSObjectProtocol {
  func handleRequest(_ request: NSDictionary, withReply reply: @escaping (NSDictionary) -> Void)
}

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

  var supportsPreferredXpcTransport: Bool {
    switch self {
    case .ping, .permissionStatus:
      return true
    default:
      return false
    }
  }
}

fileprivate enum MacosComputerUseIpcSchema {
  static let protocolVersion = 1
  static let activeTransport = "distributed_notification_center"
  static let preferredTransport = "xpc_service"
  static let fallbackTransport = activeTransport
  static let xpcServiceName = "com.noguwo.apps.caverno.computer-use.xpc"
  static let xpcSupportedCommands = ["ping", "permissionStatus"]
  static let xpcReady = true
  static let xpcFallbackTimeout = 0.7
  static let requestName = Notification.Name("com.caverno.computer_use.helper.request")
  static let responseName = Notification.Name("com.caverno.computer_use.helper.response")
  static let helperUnreachable = "helper_unreachable"
  static let xpcUnavailable = "helper_xpc_unavailable"
  static let xpcTimeout = "helper_xpc_timeout"
  static let unsupportedProtocol = "helper_unsupported_protocol"
  static let responseMismatch = "helper_response_mismatch"
  static let invalidResponse = "helper_invalid_response"
  static let requestEnvelope = [
    Field.protocolVersion,
    Field.requestId,
    Field.command,
    Field.senderBundleIdentifier,
    Field.senderProcessIdentifier,
    Field.arguments,
  ]
  static let responseEnvelope = [
    Field.protocolVersion,
    Field.requestId,
    Field.command,
    Field.response,
  ]

  enum Field {
    static let protocolVersion = "protocolVersion"
    static let requestId = "requestId"
    static let command = "command"
    static let senderBundleIdentifier = "senderBundleIdentifier"
    static let senderProcessIdentifier = "senderProcessIdentifier"
    static let arguments = "arguments"
    static let response = "response"
  }
}

fileprivate enum MacosComputerUseHelperSharedDiagnostics {
  static let path = "/tmp/caverno-computer-use-helper-diagnostics.json"

  static func read() -> [String: Any]? {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    return decoded
  }

  static func remove() {
    try? FileManager.default.removeItem(atPath: path)
  }
}

fileprivate struct MacosComputerUseHelperRequest {
  static let protocolVersion = MacosComputerUseIpcSchema.protocolVersion

  let requestId: String
  let command: MacosComputerUseHelperCommand
  let arguments: [String: Any]

  var userInfo: [String: Any] {
    [
      MacosComputerUseIpcSchema.Field.protocolVersion: Self.protocolVersion,
      MacosComputerUseIpcSchema.Field.requestId: requestId,
      MacosComputerUseIpcSchema.Field.command: command.rawValue,
      MacosComputerUseIpcSchema.Field.senderBundleIdentifier: Bundle.main.bundleIdentifier ?? "",
      MacosComputerUseIpcSchema.Field.senderProcessIdentifier: Int(ProcessInfo.processInfo.processIdentifier),
      MacosComputerUseIpcSchema.Field.arguments: arguments,
    ]
  }
}

fileprivate struct PendingMacosComputerUseHelperRequest {
  let sequence: Int
  let requestId: String
  let command: MacosComputerUseHelperCommand
  let selectedTransport: String
  let attemptedTransport: String?
  let preferredAttemptDiagnostic: [String: Any]?
  let sentAt: Date
  let timeout: TimeInterval
  let result: FlutterResult
}

final class MacosComputerUseHelperClient: NSObject {
  private let helperBundleIdentifier = "com.noguwo.apps.caverno.computer-use"
  private let helperDisplayName = "Caverno Computer Use"
  private let requestName = MacosComputerUseIpcSchema.requestName
  private let responseName = MacosComputerUseIpcSchema.responseName
  private let center = DistributedNotificationCenter.default()
  private var pendingRequests: [String: PendingMacosComputerUseHelperRequest] = [:]
  private var helperIpcSequence = 0
  private var lastHelperIpcAttempt: [String: Any]?
  private var lastPreferredIpcAttempt: [String: Any]?

  override init() {
    super.init()
    center.addObserver(
      self,
      selector: #selector(handleResponse(_:)),
      name: responseName,
      object: nil,
      suspensionBehavior: .deliverImmediately
    )
    center.suspended = false
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
      "protocolVersion": MacosComputerUseHelperRequest.protocolVersion,
      "ipcTransport": MacosComputerUseIpcSchema.activeTransport,
      "preferredIpcTransport": MacosComputerUseIpcSchema.preferredTransport,
      "fallbackIpcTransport": MacosComputerUseIpcSchema.fallbackTransport,
      "requestObject": Bundle.main.bundleIdentifier ?? "",
      "responseObject": helperBundleIdentifier,
      "requestNotificationName": MacosComputerUseIpcSchema.requestName.rawValue,
      "responseNotificationName": MacosComputerUseIpcSchema.responseName.rawValue,
      "requestEnvelope": MacosComputerUseIpcSchema.requestEnvelope,
      "responseEnvelope": MacosComputerUseIpcSchema.responseEnvelope,
      "xpcServiceName": MacosComputerUseIpcSchema.xpcServiceName,
      "xpcSupportedCommands": MacosComputerUseIpcSchema.xpcSupportedCommands,
      "xpcReady": MacosComputerUseIpcSchema.xpcReady,
      "pendingHelperIpcRequestCount": pendingRequests.count,
    ]
    if let lastHelperIpcAttempt {
      response["lastHelperIpcAttempt"] = lastHelperIpcAttempt
    }
    if let lastPreferredIpcAttempt {
      response["lastPreferredIpcAttempt"] = lastPreferredIpcAttempt
    }
    response["helperSharedDiagnosticsPath"] = MacosComputerUseHelperSharedDiagnostics.path
    if let helperSharedDiagnostics = MacosComputerUseHelperSharedDiagnostics.read() {
      response["helperSharedDiagnostics"] = helperSharedDiagnostics
      if let diagnosticProcessIdentifier =
        helperSharedDiagnostics["helperProcessIdentifier"] as? Int,
        let runningProcessIdentifier = runningApplication?.processIdentifier {
        let diagnosticsMatchesRunningHelper =
          diagnosticProcessIdentifier == Int(runningProcessIdentifier)
        response["helperSharedDiagnosticsMatchesRunningHelper"] =
          diagnosticsMatchesRunningHelper
        response["helperSharedDiagnosticsStale"] = !diagnosticsMatchesRunningHelper
      } else if runningApplication == nil {
        response["helperSharedDiagnosticsStale"] = true
      }
    }
    if let processIdentifier = runningApplication?.processIdentifier {
      response["helperProcessIdentifier"] = Int(processIdentifier)
    }
    return response
  }

  func launch(result: @escaping FlutterResult) {
    launch(extra: [:], result: result)
  }

  func restart(result: @escaping FlutterResult) {
    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: helperBundleIdentifier
    ).filter { !$0.isTerminated }
    let processIdentifiers = runningApplications.map { Int($0.processIdentifier) }
    for application in runningApplications {
      application.terminate()
    }

    func launchAfterTermination(timedOut: Bool = false) {
      MacosComputerUseHelperSharedDiagnostics.remove()
      var extra: [String: Any] = [
        "restarted": true,
        "terminatedHelperProcessIdentifiers": processIdentifiers,
      ]
      if timedOut {
        extra["helperTerminationTimedOut"] = true
      }
      if processIdentifiers.isEmpty {
        extra["noExistingHelperProcess"] = true
      }
      launch(extra: extra, result: result)
    }

    guard !runningApplications.isEmpty else {
      launchAfterTermination()
      return
    }

    let startedAt = Date()
    func waitForTermination() {
      let stillRunning = NSRunningApplication.runningApplications(
        withBundleIdentifier: helperBundleIdentifier
      ).contains { !$0.isTerminated }
      if !stillRunning {
        launchAfterTermination()
        return
      }
      if Date().timeIntervalSince(startedAt) >= 2 {
        launchAfterTermination(timedOut: true)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        waitForTermination()
      }
    }

    waitForTermination()
  }

  private func launch(extra: [String: Any], result: @escaping FlutterResult) {
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
      for (key, value) in extra {
        response[key] = value
      }
      result(response)
      return
    }

    MacosComputerUseHelperSharedDiagnostics.remove()
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
      for (key, value) in extra {
        response[key] = value
      }
      result(response)
    }
  }

  fileprivate func send(
    command: MacosComputerUseHelperCommand,
    arguments: [String: Any] = [:],
    timeout: TimeInterval = 1.5,
    selectedTransport: String = MacosComputerUseIpcSchema.activeTransport,
    attemptedTransport: String? = nil,
    preferredAttemptDiagnostic: [String: Any]? = nil,
    result: @escaping FlutterResult
  ) {
    let requestId = UUID().uuidString
    let sentAt = Date()
    helperIpcSequence += 1
    let sequence = helperIpcSequence
    let request = MacosComputerUseHelperRequest(
      requestId: requestId,
      command: command,
      arguments: arguments
    )
    pendingRequests[requestId] = PendingMacosComputerUseHelperRequest(
      sequence: sequence,
      requestId: requestId,
      command: command,
      selectedTransport: selectedTransport,
      attemptedTransport: attemptedTransport,
      preferredAttemptDiagnostic: preferredAttemptDiagnostic,
      sentAt: sentAt,
      timeout: timeout,
      result: result
    )
    lastHelperIpcAttempt = helperIpcDiagnostic(
      sequence: sequence,
      requestId: requestId,
      command: command,
      selectedTransport: selectedTransport,
      attemptedTransport: attemptedTransport,
      sentAt: sentAt,
      timeout: timeout,
      status: "sent"
    )
    NSLog(
      "CavernoComputerUseIPC request sent requestId=%@ command=%@ transport=%@",
      requestId,
      command.rawValue,
      selectedTransport
    )
    center.postNotificationName(
      requestName,
      object: Bundle.main.bundleIdentifier,
      userInfo: request.userInfo,
      deliverImmediately: true
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self, let pendingRequest = self.pendingRequests.removeValue(forKey: requestId) else {
        return
      }
      self.lastHelperIpcAttempt = self.helperIpcDiagnostic(
        pendingRequest: pendingRequest,
        status: "timeout",
        completedAt: Date(),
        errorCode: MacosComputerUseIpcSchema.helperUnreachable
      )
      NSLog(
        "CavernoComputerUseIPC request timeout requestId=%@ command=%@",
        pendingRequest.requestId,
        pendingRequest.command.rawValue
      )
      var details: [String: Any] = [
        "command": pendingRequest.command.rawValue,
        "helperBundleIdentifier": "com.noguwo.apps.caverno.computer-use",
        "helperRunning": self.runningHelperApplication() != nil,
        "ipcTransport": pendingRequest.selectedTransport,
        "selectedIpcTransport": pendingRequest.selectedTransport,
        "preferredIpcTransport": MacosComputerUseIpcSchema.preferredTransport,
        "fallbackIpcTransport": MacosComputerUseIpcSchema.fallbackTransport,
        "xpcReady": MacosComputerUseIpcSchema.xpcReady,
      ]
      if let attemptedTransport = pendingRequest.attemptedTransport {
        details["attemptedIpcTransport"] = attemptedTransport
      }
      if let preferredAttemptDiagnostic = pendingRequest.preferredAttemptDiagnostic {
        details["preferredIpcAttempt"] = preferredAttemptDiagnostic
      }
      if let runningProcessIdentifier = self.runningHelperApplication()?.processIdentifier {
        details["helperProcessIdentifier"] = Int(runningProcessIdentifier)
      }
      details["helperSharedDiagnosticsPath"] = MacosComputerUseHelperSharedDiagnostics.path
      if let helperSharedDiagnostics = MacosComputerUseHelperSharedDiagnostics.read() {
        details["helperSharedDiagnostics"] = helperSharedDiagnostics
      }
      if let lastHelperIpcAttempt = self.lastHelperIpcAttempt {
        details["lastHelperIpcAttempt"] = lastHelperIpcAttempt
      }
      pendingRequest.result(
        FlutterError(
          code: MacosComputerUseIpcSchema.helperUnreachable,
          message: "Caverno Computer Use did not respond to \(pendingRequest.command.rawValue).",
          details: details
        )
      )
    }
  }

  fileprivate func sendPreferred(
    command: MacosComputerUseHelperCommand,
    arguments: [String: Any] = [:],
    timeout: TimeInterval = 1.5,
    result: @escaping FlutterResult
  ) {
    if sendXpc(command: command, arguments: arguments, timeout: timeout, result: result) {
      return
    }

    let attemptedTransport: String?
    if command.supportsPreferredXpcTransport {
      attemptedTransport = MacosComputerUseIpcSchema.preferredTransport
    } else {
      attemptedTransport = nil
    }
    send(
      command: command,
      arguments: arguments,
      timeout: timeout,
      selectedTransport: MacosComputerUseIpcSchema.fallbackTransport,
      attemptedTransport: attemptedTransport,
      result: result
    )
  }

  private func sendXpc(
    command: MacosComputerUseHelperCommand,
    arguments: [String: Any],
    timeout: TimeInterval,
    result: @escaping FlutterResult
  ) -> Bool {
    guard MacosComputerUseIpcSchema.xpcReady else {
      return false
    }
    guard command.supportsPreferredXpcTransport else {
      return false
    }

    let requestId = UUID().uuidString
    let sentAt = Date()
    helperIpcSequence += 1
    let sequence = helperIpcSequence
    let request = MacosComputerUseHelperRequest(
      requestId: requestId,
      command: command,
      arguments: arguments
    )
    lastHelperIpcAttempt = helperIpcDiagnostic(
      sequence: sequence,
      requestId: requestId,
      command: command,
      selectedTransport: MacosComputerUseIpcSchema.preferredTransport,
      attemptedTransport: nil,
      sentAt: sentAt,
      timeout: MacosComputerUseIpcSchema.xpcFallbackTimeout,
      status: "sent"
    )

    let connection = NSXPCConnection(
      machServiceName: MacosComputerUseIpcSchema.xpcServiceName,
      options: []
    )
    connection.remoteObjectInterface = NSXPCInterface(with: CavernoComputerUseXpcProtocol.self)
    var completed = false

    func fallback(status: String, errorCode: String) {
      guard !completed else {
        return
      }
      completed = true
      connection.invalidate()
      let diagnostic = helperIpcDiagnostic(
        sequence: sequence,
        requestId: requestId,
        command: command,
        selectedTransport: MacosComputerUseIpcSchema.preferredTransport,
        attemptedTransport: nil,
        sentAt: sentAt,
        timeout: MacosComputerUseIpcSchema.xpcFallbackTimeout,
        status: status,
        completedAt: Date(),
        errorCode: errorCode
      )
      lastHelperIpcAttempt = diagnostic
      lastPreferredIpcAttempt = diagnostic
      send(
        command: command,
        arguments: arguments,
        timeout: timeout,
        selectedTransport: MacosComputerUseIpcSchema.fallbackTransport,
        attemptedTransport: MacosComputerUseIpcSchema.preferredTransport,
        preferredAttemptDiagnostic: diagnostic,
        result: result
      )
    }

    connection.invalidationHandler = { [weak self] in
      DispatchQueue.main.async {
        guard let self, !completed else {
          return
        }
        self.lastHelperIpcAttempt = self.helperIpcDiagnostic(
          sequence: sequence,
          requestId: requestId,
          command: command,
          selectedTransport: MacosComputerUseIpcSchema.preferredTransport,
          attemptedTransport: nil,
          sentAt: sentAt,
          timeout: MacosComputerUseIpcSchema.xpcFallbackTimeout,
          status: "xpc_invalidated",
          completedAt: Date(),
          errorCode: MacosComputerUseIpcSchema.xpcUnavailable
        )
      }
    }
    connection.resume()

    let proxy = connection.remoteObjectProxyWithErrorHandler { error in
      DispatchQueue.main.async {
        NSLog(
          "CavernoComputerUseIPC xpc error requestId=%@ command=%@ error=%@",
          requestId,
          command.rawValue,
          error.localizedDescription
        )
        fallback(status: "xpc_error", errorCode: MacosComputerUseIpcSchema.xpcUnavailable)
      }
    } as? CavernoComputerUseXpcProtocol

    guard let proxy else {
      fallback(status: "xpc_proxy_unavailable", errorCode: MacosComputerUseIpcSchema.xpcUnavailable)
      return true
    }

    NSLog(
      "CavernoComputerUseIPC xpc request sent requestId=%@ command=%@",
      requestId,
      command.rawValue
    )
    proxy.handleRequest(request.userInfo as NSDictionary) { [weak self] response in
      DispatchQueue.main.async {
        guard let self, !completed else {
          return
        }
        completed = true
        connection.invalidate()
        let responseMap = response as? [String: Any] ?? [:]
        var responseWithTransport = responseMap
        responseWithTransport["selectedIpcTransport"] = MacosComputerUseIpcSchema.preferredTransport
        responseWithTransport["fallbackIpcTransport"] = MacosComputerUseIpcSchema.fallbackTransport
        self.lastHelperIpcAttempt = self.helperIpcDiagnostic(
          sequence: sequence,
          requestId: requestId,
          command: command,
          selectedTransport: MacosComputerUseIpcSchema.preferredTransport,
          attemptedTransport: nil,
          sentAt: sentAt,
          timeout: MacosComputerUseIpcSchema.xpcFallbackTimeout,
          status: responseMap["ok"] as? Bool == false ? "xpc_response_error" : "xpc_response",
          completedAt: Date(),
          errorCode: responseMap["code"] as? String
        )
        NSLog(
          "CavernoComputerUseIPC xpc response received requestId=%@ command=%@",
          requestId,
          command.rawValue
        )
        result(responseWithTransport)
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + MacosComputerUseIpcSchema.xpcFallbackTimeout) {
      fallback(status: "xpc_timeout", errorCode: MacosComputerUseIpcSchema.xpcTimeout)
    }
    return true
  }

  @objc private func handleResponse(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let requestId = userInfo[MacosComputerUseIpcSchema.Field.requestId] as? String,
      let pendingRequest = pendingRequests.removeValue(forKey: requestId)
    else {
      return
    }

    let protocolVersion = userInfo[MacosComputerUseIpcSchema.Field.protocolVersion] as? Int ?? 0
    guard protocolVersion == MacosComputerUseHelperRequest.protocolVersion else {
      lastHelperIpcAttempt = helperIpcDiagnostic(
        pendingRequest: pendingRequest,
        status: "unsupported_protocol",
        completedAt: Date(),
        errorCode: MacosComputerUseIpcSchema.unsupportedProtocol
      )
      pendingRequest.result(
        FlutterError(
          code: MacosComputerUseIpcSchema.unsupportedProtocol,
          message: "Caverno Computer Use returned an unsupported protocol version.",
          details: [
            "protocolVersion": protocolVersion,
            "command": pendingRequest.command.rawValue,
          ]
        )
      )
      return
    }

    let commandName = userInfo[MacosComputerUseIpcSchema.Field.command] as? String ?? ""
    guard commandName == pendingRequest.command.rawValue else {
      lastHelperIpcAttempt = helperIpcDiagnostic(
        pendingRequest: pendingRequest,
        status: "response_mismatch",
        completedAt: Date(),
        errorCode: MacosComputerUseIpcSchema.responseMismatch
      )
      pendingRequest.result(
        FlutterError(
          code: MacosComputerUseIpcSchema.responseMismatch,
          message: "Caverno Computer Use returned a response for a different command.",
          details: [
            "expectedCommand": pendingRequest.command.rawValue,
            "actualCommand": commandName,
          ]
        )
      )
      return
    }

    guard let response = userInfo[MacosComputerUseIpcSchema.Field.response] as? [String: Any] else {
      lastHelperIpcAttempt = helperIpcDiagnostic(
        pendingRequest: pendingRequest,
        status: "invalid_response",
        completedAt: Date(),
        errorCode: MacosComputerUseIpcSchema.invalidResponse
      )
      pendingRequest.result(
        FlutterError(
          code: MacosComputerUseIpcSchema.invalidResponse,
          message: "Caverno Computer Use returned an invalid response.",
          details: nil
        )
      )
      return
    }

    var responseWithTransport = response
    responseWithTransport["selectedIpcTransport"] = pendingRequest.selectedTransport
    responseWithTransport["fallbackIpcTransport"] = MacosComputerUseIpcSchema.fallbackTransport
    if let attemptedTransport = pendingRequest.attemptedTransport {
      responseWithTransport["attemptedIpcTransport"] = attemptedTransport
    }
    if let preferredAttemptDiagnostic = pendingRequest.preferredAttemptDiagnostic {
      responseWithTransport["preferredIpcAttempt"] = preferredAttemptDiagnostic
    }
    lastHelperIpcAttempt = helperIpcDiagnostic(
      pendingRequest: pendingRequest,
      status: response["ok"] as? Bool == false ? "response_error" : "response",
      completedAt: Date(),
      errorCode: response["code"] as? String
    )
    NSLog(
      "CavernoComputerUseIPC response received requestId=%@ command=%@",
      pendingRequest.requestId,
      pendingRequest.command.rawValue
    )
    pendingRequest.result(responseWithTransport)
  }

  private func helperIpcDiagnostic(
    pendingRequest: PendingMacosComputerUseHelperRequest,
    status: String,
    completedAt: Date? = nil,
    errorCode: String? = nil
  ) -> [String: Any] {
    helperIpcDiagnostic(
      sequence: pendingRequest.sequence,
      requestId: pendingRequest.requestId,
      command: pendingRequest.command,
      selectedTransport: pendingRequest.selectedTransport,
      attemptedTransport: pendingRequest.attemptedTransport,
      sentAt: pendingRequest.sentAt,
      timeout: pendingRequest.timeout,
      status: status,
      completedAt: completedAt,
      errorCode: errorCode
    )
  }

  private func helperIpcDiagnostic(
    sequence: Int,
    requestId: String,
    command: MacosComputerUseHelperCommand,
    selectedTransport: String,
    attemptedTransport: String?,
    sentAt: Date,
    timeout: TimeInterval,
    status: String,
    completedAt: Date? = nil,
    errorCode: String? = nil
  ) -> [String: Any] {
    var diagnostic: [String: Any] = [
      "sequence": sequence,
      "requestId": requestId,
      "command": command.rawValue,
      "status": status,
      "sentAt": isoString(sentAt),
      "timeoutMs": Int(timeout * 1000),
      "senderBundleIdentifier": Bundle.main.bundleIdentifier ?? "",
      "senderProcessIdentifier": Int(ProcessInfo.processInfo.processIdentifier),
      "selectedIpcTransport": selectedTransport,
      "preferredIpcTransport": MacosComputerUseIpcSchema.preferredTransport,
      "fallbackIpcTransport": MacosComputerUseIpcSchema.fallbackTransport,
      "xpcReady": MacosComputerUseIpcSchema.xpcReady,
    ]
    if let attemptedTransport {
      diagnostic["attemptedIpcTransport"] = attemptedTransport
    }
    if let completedAt {
      diagnostic["completedAt"] = isoString(completedAt)
      diagnostic["elapsedMs"] = Int(completedAt.timeIntervalSince(sentAt) * 1000)
    }
    if let errorCode {
      diagnostic["errorCode"] = errorCode
    }
    return diagnostic
  }

  private func isoString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }

  private func embeddedHelperURL() -> URL {
    Bundle.main.bundleURL
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Helpers", isDirectory: true)
      .appendingPathComponent("\(helperDisplayName).app", isDirectory: true)
  }

  private func runningHelperApplication() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(
      withBundleIdentifier: helperBundleIdentifier
    ).first { !$0.isTerminated }
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
    case "restartHelper":
      helperClient.restart(result: result)
    case "helperPing":
      helperClient.sendPreferred(command: .ping, result: result)
    case "helperPermissionStatus":
      helperClient.sendPreferred(command: .permissionStatus, result: result)
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
