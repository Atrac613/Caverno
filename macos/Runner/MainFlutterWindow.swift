import Cocoa
import CoreGraphics
import Darwin
import FlutterMacOS
import ServiceManagement

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
  case showPermissionOverlay
  case startOnboardingPermissionFlow
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
    true
  }
}

fileprivate enum MacosComputerUseIpcSchema {
  static let protocolVersion = 1
  static let activeTransport = "xpc_service"
  static let preferredTransport = activeTransport
  static let fallbackTransport = "distributed_notification_center"
  static let xpcServiceName = "com.noguwo.apps.caverno.computer-use.xpc"
  static let xpcSupportedCommands = [
    "ping",
    "permissionStatus",
    "openSettings",
    "showPermissionOverlay",
    "startOnboardingPermissionFlow",
    "stopAll",
    "screenshot",
    "listWindows",
    "focusWindow",
    "screenshotWindow",
    "moveMouse",
    "click",
    "drag",
    "scroll",
    "typeText",
    "pressKey",
    "startSystemAudioRecording",
    "stopSystemAudioRecording",
  ]
  static let xpcReady = true
  static let xpcProductionReady = true
  static let xpcStatus = "production"
  static let xpcConnectionMode = "external_helper_mach_service"
  static let xpcLaunchAgentPlistName = "com.noguwo.apps.caverno.computer-use.plist"
  static let xpcLaunchAgentRelativePath = "Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist"
  static let xpcRegistrationRequirement = "launchd_mach_service_registration"
  static let xpcProductionBlockers: [String] = []
  static let xpcProductionNextAction = "XPC is production ready."
  static let mainAppUnsafeOsActionsAllowed = false
  static let helperOwnsUnsafeOsActions = true
  static let helperOwnedActionCategories = [
    "accessibility",
    "screen_capture",
    "input_events",
    "system_audio_recording",
    "emergency_stop",
  ]
  static let xpcNextParityCommands: [String] = []
  static let xpcProductionReadinessCriteria = [
    "named_service_connects_from_signed_main_app",
    "ping_permission_status_open_settings_show_permission_overlay_start_onboarding_permission_flow_stop_all_screenshot_list_windows_focus_window_screenshot_window_move_mouse_click_drag_scroll_type_text_press_key_system_audio_match_dnc",
    "capture_input_audio_commands_have_parity_smoke_coverage",
    "fallback_path_is_observable_and_non_destructive",
  ]
  static let xpcFallbackTimeout = 2.0
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
    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: helperBundleIdentifier
    ).filter { !$0.isTerminated }
    let runningApplication = runningApplications.first
    let helperPath = helperURL.standardizedFileURL.path
    let runningHelperPath = runningApplication?.bundleURL?.standardizedFileURL.path
    let helperPathMatchesRunningHelper =
      runningHelperPath == nil || runningHelperPath == helperPath
    var response: [String: Any] = [
      "ok": true,
      "helperDisplayName": helperDisplayName,
      "helperBundleIdentifier": helperBundleIdentifier,
      "helperInstalled": FileManager.default.fileExists(atPath: helperURL.path),
      "helperRunning": runningApplication != nil,
      "helperRunningProcessCount": runningApplications.count,
      "singleInstanceExpected": true,
      "singleInstanceLockExpected": true,
      "singleInstanceLockPath": "/tmp/caverno-computer-use-helper.lock",
      "helperDockPolicy": "agent_hidden_from_dock",
      "helperPath": helperPath,
      "embeddedHelperPath": helperPath,
      "helperLaunchPath": helperPath,
      "helperPathMatchesRunningHelper": helperPathMatchesRunningHelper,
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
      "xpcProductionReady": MacosComputerUseIpcSchema.xpcProductionReady,
      "xpcStatus": MacosComputerUseIpcSchema.xpcStatus,
      "xpcConnectionMode": MacosComputerUseIpcSchema.xpcConnectionMode,
      "xpcLaunchAgentPlistName": MacosComputerUseIpcSchema.xpcLaunchAgentPlistName,
      "xpcLaunchAgentRelativePath": MacosComputerUseIpcSchema.xpcLaunchAgentRelativePath,
      "xpcRegistrationRequirement": MacosComputerUseIpcSchema.xpcRegistrationRequirement,
      "xpcProductionBlockers": MacosComputerUseIpcSchema.xpcProductionBlockers,
      "xpcProductionNextAction": MacosComputerUseIpcSchema.xpcProductionNextAction,
      "mainAppUnsafeOsActionsAllowed": MacosComputerUseIpcSchema.mainAppUnsafeOsActionsAllowed,
      "helperOwnsUnsafeOsActions": MacosComputerUseIpcSchema.helperOwnsUnsafeOsActions,
      "helperOwnedActionCategories": MacosComputerUseIpcSchema.helperOwnedActionCategories,
      "xpcNextParityCommands": MacosComputerUseIpcSchema.xpcNextParityCommands,
      "xpcProductionReadinessCriteria": MacosComputerUseIpcSchema.xpcProductionReadinessCriteria,
      "pendingHelperIpcRequestCount": pendingRequests.count,
    ]
    if let runningHelperPath {
      response["runningHelperPath"] = runningHelperPath
    }
    if runningApplications.count > 1 {
      response["helperDuplicateProcessIdentifiers"] = runningApplications
        .map { Int($0.processIdentifier) }
      response["helperDuplicateProcessCount"] = runningApplications.count
    }
    if !helperPathMatchesRunningHelper {
      response["helperPathMismatch"] = true
      response["helperPathMismatchDetails"] = [
        "expectedHelperPath": helperPath,
        "runningHelperPath": runningHelperPath ?? "",
        "nextAction": "Restart Caverno Computer Use from Caverno before validating granted permissions.",
      ]
    }
    response.merge(xpcLaunchAgentStatus()) { _, new in new }
    if let lastHelperIpcAttempt {
      response["lastHelperIpcAttempt"] = lastHelperIpcAttempt
    }
    if let lastPreferredIpcAttempt {
      response["lastPreferredIpcAttempt"] = lastPreferredIpcAttempt
    }
    addSharedDiagnostics(
      to: &response,
      helperURL: helperURL,
      runningApplication: runningApplication
    )
    if let processIdentifier = runningApplication?.processIdentifier {
      response["helperProcessIdentifier"] = Int(processIdentifier)
    }
    return response
  }

  private func addSharedDiagnostics(
    to response: inout [String: Any],
    helperURL: URL,
    runningApplication: NSRunningApplication?
  ) {
    response["helperSharedDiagnosticsPath"] = MacosComputerUseHelperSharedDiagnostics.path
    guard let helperSharedDiagnostics = MacosComputerUseHelperSharedDiagnostics.read() else {
      return
    }

    response["helperSharedDiagnostics"] = helperSharedDiagnostics
    let expectedBundlePath = helperURL.standardizedFileURL.path
    let expectedExecutablePath = helperURL
      .appendingPathComponent("Contents/MacOS/Caverno Computer Use")
      .standardizedFileURL.path
    var staleReasons: [String] = []

    if let runningProcessIdentifier = runningApplication?.processIdentifier {
      let runningPid = Int(runningProcessIdentifier)
      let diagnosticPid = helperSharedDiagnostics["helperProcessIdentifier"] as? Int
      let pidMatches = diagnosticPid == runningPid
      response["helperSharedDiagnosticsMatchesRunningHelper"] = pidMatches
      if !pidMatches {
        staleReasons.append("process_identifier_mismatch")
      }
      if let diagnosticPid {
        response["helperSharedDiagnosticsProcessIdentifier"] = diagnosticPid
      }
    } else {
      response["helperSharedDiagnosticsMatchesRunningHelper"] = false
      staleReasons.append("no_running_helper_process")
    }

    if let diagnosticBundlePath = helperSharedDiagnostics["helperBundlePath"] as? String {
      let bundleMatches =
        URL(fileURLWithPath: diagnosticBundlePath).standardizedFileURL.path == expectedBundlePath
      response["helperSharedDiagnosticsMatchesExpectedBundle"] = bundleMatches
      if !bundleMatches {
        staleReasons.append("helper_bundle_path_mismatch")
      }
    }
    if let diagnosticExecutablePath = helperSharedDiagnostics["helperExecutablePath"] as? String {
      let executableMatches =
        URL(fileURLWithPath: diagnosticExecutablePath).standardizedFileURL.path == expectedExecutablePath
      response["helperSharedDiagnosticsMatchesExpectedExecutable"] = executableMatches
      if !executableMatches {
        staleReasons.append("helper_executable_path_mismatch")
      }
    }
    if let generatedAt = helperSharedDiagnostics["generatedAt"] as? String,
       let generatedDate = parseSharedDiagnosticsDate(generatedAt) {
      let ageMs = max(0, Int(Date().timeIntervalSince(generatedDate) * 1000))
      response["helperSharedDiagnosticsAgeMs"] = ageMs
    }

    response["helperSharedDiagnosticsStale"] = !staleReasons.isEmpty
    response["helperSharedDiagnosticsStaleReasons"] = staleReasons
  }

  private func parseSharedDiagnosticsDate(_ value: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: value) {
      return date
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  func registerXpcLaunchAgent(result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(xpcLaunchAgentUnsupportedResponse(action: "register"))
      return
    }

    do {
      try SMAppService.agent(plistName: MacosComputerUseIpcSchema.xpcLaunchAgentPlistName).register()
      var response = status()
      response["ok"] = true
      response["xpcLaunchAgentRegistrationAction"] = "register"
      result(response)
    } catch {
      var response = status()
      response["ok"] = false
      response["code"] = "xpc_launch_agent_register_failed"
      response["error"] = error.localizedDescription
      response["xpcLaunchAgentRegistrationAction"] = "register"
      result(response)
    }
  }

  func unregisterXpcLaunchAgent(result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result(xpcLaunchAgentUnsupportedResponse(action: "unregister"))
      return
    }

    do {
      try SMAppService.agent(plistName: MacosComputerUseIpcSchema.xpcLaunchAgentPlistName).unregister()
      var response = status()
      response["ok"] = true
      response["xpcLaunchAgentRegistrationAction"] = "unregister"
      result(response)
    } catch {
      var response = status()
      response["ok"] = false
      response["code"] = "xpc_launch_agent_unregister_failed"
      response["error"] = error.localizedDescription
      response["xpcLaunchAgentRegistrationAction"] = "unregister"
      result(response)
    }
  }

  private func xpcLaunchAgentStatus() -> [String: Any] {
    let plistURL = Bundle.main.bundleURL
      .appendingPathComponent(MacosComputerUseIpcSchema.xpcLaunchAgentRelativePath)
    var response: [String: Any] = [
      "xpcLaunchAgentPlistName": MacosComputerUseIpcSchema.xpcLaunchAgentPlistName,
      "xpcLaunchAgentRelativePath": MacosComputerUseIpcSchema.xpcLaunchAgentRelativePath,
      "xpcLaunchAgentPlistPath": plistURL.path,
      "xpcLaunchAgentPlistInstalled": FileManager.default.fileExists(atPath: plistURL.path),
    ]

    guard #available(macOS 13.0, *) else {
      response["xpcLaunchAgentSupported"] = false
      response["xpcLaunchAgentStatus"] = "unsupported_macos"
      return response
    }

    let service = SMAppService.agent(plistName: MacosComputerUseIpcSchema.xpcLaunchAgentPlistName)
    let status = service.status
    response["xpcLaunchAgentSupported"] = true
    response["xpcLaunchAgentStatus"] = xpcLaunchAgentStatusName(status)
    response["xpcLaunchAgentEnabled"] = status == .enabled
    response["xpcLaunchAgentRequiresApproval"] = status == .requiresApproval
    response["xpcLaunchAgentRegistered"] = status == .enabled || status == .requiresApproval
    return response
  }

  @available(macOS 13.0, *)
  private func xpcLaunchAgentStatusName(_ status: SMAppService.Status) -> String {
    switch status {
    case .notRegistered:
      return "not_registered"
    case .enabled:
      return "enabled"
    case .requiresApproval:
      return "requires_approval"
    case .notFound:
      return "not_found"
    @unknown default:
      return "unknown"
    }
  }

  private func xpcLaunchAgentUnsupportedResponse(action: String) -> [String: Any] {
    var response = status()
    response["ok"] = false
    response["code"] = "xpc_launch_agent_unsupported"
    response["error"] = "SMAppService LaunchAgent registration requires macOS 13.0 or later."
    response["xpcLaunchAgentRegistrationAction"] = action
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

  func terminateForXpcLaunchAgent(result: @escaping FlutterResult) {
    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: helperBundleIdentifier
    ).filter { !$0.isTerminated }
    let processIdentifiers = runningApplications.map { Int($0.processIdentifier) }
    for application in runningApplications {
      application.terminate()
    }

    func finish(timedOut: Bool = false) {
      MacosComputerUseHelperSharedDiagnostics.remove()
      var response = status()
      response["ok"] = true
      response["terminatedHelperProcessIdentifiers"] = processIdentifiers
      response["terminatedForXpcLaunchAgent"] = true
      if processIdentifiers.isEmpty {
        response["noExistingHelperProcess"] = true
      }
      if timedOut {
        response["helperTerminationTimedOut"] = true
      }
      result(response)
    }

    guard !runningApplications.isEmpty else {
      finish()
      return
    }

    let startedAt = Date()
    func waitForTermination() {
      let stillRunning = NSRunningApplication.runningApplications(
        withBundleIdentifier: helperBundleIdentifier
      ).contains { !$0.isTerminated }
      if !stillRunning {
        finish()
        return
      }
      if Date().timeIntervalSince(startedAt) >= 2 {
        finish(timedOut: true)
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

    let helperPath = helperURL.standardizedFileURL.path
    let runningApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: helperBundleIdentifier
    ).filter { !$0.isTerminated }

    if let runningApplication = runningApplications.first(where: {
      $0.bundleURL?.standardizedFileURL.path == helperPath
    }) {
      runningApplication.activate(options: [.activateIgnoringOtherApps])
      var response = status()
      response["alreadyRunning"] = true
      for (key, value) in extra {
        response[key] = value
      }
      result(response)
      return
    }

    let mismatchedApplications = runningApplications.filter {
      $0.bundleURL?.standardizedFileURL.path != helperPath
    }
    if !mismatchedApplications.isEmpty {
      let processIdentifiers = mismatchedApplications.map { Int($0.processIdentifier) }
      let paths = mismatchedApplications.map { $0.bundleURL?.standardizedFileURL.path ?? "" }
      for application in mismatchedApplications {
        application.terminate()
      }
      let startedAt = Date()
      func waitForMismatchedTermination() {
        let stillRunning = NSRunningApplication.runningApplications(
          withBundleIdentifier: helperBundleIdentifier
        ).contains { application in
          !application.isTerminated &&
            application.bundleURL?.standardizedFileURL.path != helperPath
        }
        if !stillRunning || Date().timeIntervalSince(startedAt) >= 2 {
          var launchExtra = extra
          launchExtra["terminatedMismatchedHelperProcessIdentifiers"] = processIdentifiers
          launchExtra["terminatedMismatchedHelperPaths"] = paths
          launchExtra["replacedMismatchedHelperPath"] = true
          if stillRunning {
            launchExtra["helperPathMismatchTerminationTimedOut"] = true
          }
          openEmbeddedHelper(helperURL: helperURL, extra: launchExtra, result: result)
          return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
          waitForMismatchedTermination()
        }
      }
      waitForMismatchedTermination()
      return
    }

    if let staleLock = staleMismatchedLockOwner(expectedHelperPath: helperPath) {
      terminateStaleLockOwner(staleLock) { [weak self] repair in
        guard let self else {
          return
        }
        var launchExtra = extra
        for (key, value) in repair {
          launchExtra[key] = value
        }
        self.openEmbeddedHelper(helperURL: helperURL, extra: launchExtra, result: result)
      }
      return
    }

    openEmbeddedHelper(helperURL: helperURL, extra: extra, result: result)
  }

  private func staleMismatchedLockOwner(expectedHelperPath: String) -> [String: Any]? {
    guard
      let diagnostics = MacosComputerUseHelperSharedDiagnostics.read(),
      diagnostics["event"] as? String == "duplicate_instance_lock_held",
      diagnostics["helperBundleIdentifier"] as? String == helperBundleIdentifier,
      let existingPath = diagnostics["existingHelperBundlePath"] as? String,
      !existingPath.isEmpty,
      URL(fileURLWithPath: existingPath).standardizedFileURL.path != expectedHelperPath
    else {
      return nil
    }

    let ownerProcessIdentifier =
      diagnostics["existingHelperProcessIdentifier"] as? Int ??
      diagnostics["singleInstanceLockOwnerProcessIdentifier"] as? Int
    guard let ownerProcessIdentifier, ownerProcessIdentifier > 0 else {
      return nil
    }

    return [
      "staleLockOwnerProcessIdentifier": ownerProcessIdentifier,
      "staleLockOwnerBundlePath": existingPath,
      "staleLockDiagnostics": diagnostics,
    ]
  }

  private func terminateStaleLockOwner(
    _ staleLock: [String: Any],
    completion: @escaping ([String: Any]) -> Void
  ) {
    let processIdentifier = staleLock["staleLockOwnerProcessIdentifier"] as? Int ?? 0
    let bundlePath = staleLock["staleLockOwnerBundlePath"] as? String ?? ""
    terminateProcess(processIdentifier)

    let startedAt = Date()
    var forceTerminateAttempted = false
    func finish(timedOut: Bool = false, forceTimedOut: Bool = false) {
      MacosComputerUseHelperSharedDiagnostics.remove()
      var response: [String: Any] = [
        "replacedStaleHelperLockOwner": true,
        "terminatedStaleHelperProcessIdentifier": processIdentifier,
        "terminatedStaleHelperPath": bundlePath,
        "forceTerminatedStaleHelperProcess": forceTerminateAttempted,
      ]
      if timedOut {
        response["staleHelperLockOwnerTerminationTimedOut"] = true
      }
      if forceTimedOut {
        response["staleHelperLockOwnerForceTerminationTimedOut"] = true
      }
      completion(response)
    }

    func waitForTermination() {
      let stillRunning = processIsRunning(processIdentifier)
      if !stillRunning {
        finish()
        return
      }
      let elapsed = Date().timeIntervalSince(startedAt)
      if elapsed >= 1 && !forceTerminateAttempted {
        forceTerminateAttempted = true
        forceTerminateProcess(processIdentifier)
      }
      if elapsed >= 3 {
        finish(timedOut: true, forceTimedOut: forceTerminateAttempted)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        waitForTermination()
      }
    }

    waitForTermination()
  }

  private func terminateProcess(_ processIdentifier: Int) {
    guard processIdentifier > 0 else {
      return
    }
    if let application = NSRunningApplication(processIdentifier: pid_t(processIdentifier)) {
      _ = application.terminate()
    } else {
      _ = Darwin.kill(pid_t(processIdentifier), SIGTERM)
    }
  }

  private func forceTerminateProcess(_ processIdentifier: Int) {
    guard processIdentifier > 0 else {
      return
    }
    if let application = NSRunningApplication(processIdentifier: pid_t(processIdentifier)) {
      _ = application.forceTerminate()
    } else {
      _ = Darwin.kill(pid_t(processIdentifier), SIGKILL)
    }
  }

  private func processIsRunning(_ processIdentifier: Int) -> Bool {
    guard processIdentifier > 0 else {
      return false
    }
    if let application = NSRunningApplication(processIdentifier: pid_t(processIdentifier)),
       !application.isTerminated {
      return true
    }
    return Darwin.kill(pid_t(processIdentifier), 0) == 0
  }

  private func openEmbeddedHelper(
    helperURL: URL,
    extra: [String: Any],
    result: @escaping FlutterResult
  ) {
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
        "xpcProductionReady": MacosComputerUseIpcSchema.xpcProductionReady,
        "xpcStatus": MacosComputerUseIpcSchema.xpcStatus,
        "xpcConnectionMode": MacosComputerUseIpcSchema.xpcConnectionMode,
        "xpcRegistrationRequirement": MacosComputerUseIpcSchema.xpcRegistrationRequirement,
        "xpcProductionBlockers": MacosComputerUseIpcSchema.xpcProductionBlockers,
        "xpcProductionNextAction": MacosComputerUseIpcSchema.xpcProductionNextAction,
        "mainAppUnsafeOsActionsAllowed": MacosComputerUseIpcSchema.mainAppUnsafeOsActionsAllowed,
        "helperOwnsUnsafeOsActions": MacosComputerUseIpcSchema.helperOwnsUnsafeOsActions,
        "helperOwnedActionCategories": MacosComputerUseIpcSchema.helperOwnedActionCategories,
        "xpcNextParityCommands": MacosComputerUseIpcSchema.xpcNextParityCommands,
        "xpcProductionReadinessCriteria": MacosComputerUseIpcSchema.xpcProductionReadinessCriteria,
      ]
      if let attemptedTransport = pendingRequest.attemptedTransport {
        details["attemptedIpcTransport"] = attemptedTransport
      }
      if let preferredAttemptDiagnostic = pendingRequest.preferredAttemptDiagnostic {
        details["preferredIpcAttempt"] = preferredAttemptDiagnostic
      }
      let runningApplication = self.runningHelperApplication()
      if let runningProcessIdentifier = runningApplication?.processIdentifier {
        details["helperProcessIdentifier"] = Int(runningProcessIdentifier)
      }
      self.addSharedDiagnostics(
        to: &details,
        helperURL: self.embeddedHelperURL(),
        runningApplication: runningApplication
      )
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

    func fallback(status: String, errorCode: String, errorDescription: String? = nil) {
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
        errorCode: errorCode,
        errorDescription: errorDescription
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
        fallback(
          status: "xpc_error",
          errorCode: MacosComputerUseIpcSchema.xpcUnavailable,
          errorDescription: error.localizedDescription
        )
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
    errorCode: String? = nil,
    errorDescription: String? = nil
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
      "xpcProductionReady": MacosComputerUseIpcSchema.xpcProductionReady,
      "xpcStatus": MacosComputerUseIpcSchema.xpcStatus,
      "xpcConnectionMode": MacosComputerUseIpcSchema.xpcConnectionMode,
      "xpcRegistrationRequirement": MacosComputerUseIpcSchema.xpcRegistrationRequirement,
      "xpcProductionBlockers": MacosComputerUseIpcSchema.xpcProductionBlockers,
      "xpcProductionNextAction": MacosComputerUseIpcSchema.xpcProductionNextAction,
      "mainAppUnsafeOsActionsAllowed": MacosComputerUseIpcSchema.mainAppUnsafeOsActionsAllowed,
      "helperOwnsUnsafeOsActions": MacosComputerUseIpcSchema.helperOwnsUnsafeOsActions,
      "helperOwnedActionCategories": MacosComputerUseIpcSchema.helperOwnedActionCategories,
      "xpcNextParityCommands": MacosComputerUseIpcSchema.xpcNextParityCommands,
      "xpcProductionReadinessCriteria": MacosComputerUseIpcSchema.xpcProductionReadinessCriteria,
    ]
    diagnostic.merge(xpcLaunchAgentStatus()) { _, new in new }
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
    if let errorDescription {
      diagnostic["errorDescription"] = errorDescription
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
  private let helperDisplayName = "Caverno Computer Use"
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
    case "terminateHelperForXpcLaunchAgent":
      helperClient.terminateForXpcLaunchAgent(result: result)
    case "registerXpcLaunchAgent":
      helperClient.registerXpcLaunchAgent(result: result)
    case "unregisterXpcLaunchAgent":
      helperClient.unregisterXpcLaunchAgent(result: result)
    case "helperPing":
      helperClient.sendPreferred(command: .ping, result: result)
    case "helperPermissionStatus":
      helperClient.sendPreferred(command: .permissionStatus, result: result)
    case "helperOpenSystemSettings":
      helperClient.sendPreferred(
        command: .openSettings,
        arguments: call.arguments as? [String: Any] ?? [:],
        result: result
      )
    case "helperShowPermissionOverlay":
      helperClient.sendPreferred(
        command: .showPermissionOverlay,
        arguments: call.arguments as? [String: Any] ?? [:],
        result: result
      )
    case "helperStartOnboardingPermissionFlow":
      helperClient.sendPreferred(
        command: .startOnboardingPermissionFlow,
        arguments: call.arguments as? [String: Any] ?? [:],
        result: result
      )
    case "helperStopAll":
      helperClient.sendPreferred(command: .stopAll, timeout: 8, result: result)
    case "getPermissions":
      result(permissionSnapshot())
    case "requestAccessibility":
      requestAccessibility(result: result)
    case "requestScreenCapture":
      requestScreenCapture(result: result)
    case "openSystemSettings":
      openSystemSettings(call, result: result)
    case "listWindows":
      helperClient.sendPreferred(
        command: .listWindows,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "focusWindow":
      helperClient.sendPreferred(
        command: .focusWindow,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "screenshot":
      helperClient.sendPreferred(
        command: .screenshot,
        arguments: helperArguments(call),
        timeout: 8,
        result: result
      )
    case "screenshotWindow":
      helperClient.sendPreferred(
        command: .screenshotWindow,
        arguments: helperArguments(call),
        timeout: 8,
        result: result
      )
    case "click":
      helperClient.sendPreferred(
        command: .click,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "moveMouse":
      helperClient.sendPreferred(
        command: .moveMouse,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "drag":
      helperClient.sendPreferred(
        command: .drag,
        arguments: helperArguments(call),
        timeout: 6,
        result: result
      )
    case "scroll":
      helperClient.sendPreferred(
        command: .scroll,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "typeText":
      helperClient.sendPreferred(
        command: .typeText,
        arguments: helperArguments(call),
        timeout: 5,
        result: result
      )
    case "pressKey":
      helperClient.sendPreferred(
        command: .pressKey,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "startSystemAudioRecording":
      helperClient.sendPreferred(
        command: .startSystemAudioRecording,
        arguments: helperArguments(call),
        timeout: 8,
        result: result
      )
    case "stopSystemAudioRecording":
      helperClient.sendPreferred(
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
    return [
      "accessibilityGranted": AXIsProcessTrusted(),
      "screenCaptureGranted": false,
      "systemAudioRecordingSupported": isSystemAudioRecordingSupported(),
      "screenCaptureOwner": helperDisplayName,
      "mainAppScreenCaptureRequestBlocked": true,
      "nextAction": "Launch Caverno Computer Use and grant Screen & System Audio Recording to the helper.",
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
    result([
      "ok": false,
      "code": "main_app_screen_capture_blocked",
      "screenCaptureGranted": false,
      "screenCaptureOwner": helperDisplayName,
      "error": "Caverno.app does not request Screen & System Audio Recording. Computer Use permissions belong to Caverno Computer Use.",
      "nextAction": "Open the helper-owned permission overlay and grant Screen & System Audio Recording to Caverno Computer Use.",
    ])
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
