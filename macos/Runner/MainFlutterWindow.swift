import Cocoa
import CoreGraphics
import Darwin
import FlutterMacOS
import ServiceManagement
import Sparkle

@objc(CavernoComputerUseXpcProtocol)
protocol CavernoComputerUseXpcProtocol: NSObjectProtocol {
  func handleRequest(_ request: NSDictionary, withReply reply: @escaping (NSDictionary) -> Void)
}

class MainFlutterWindow: NSWindow {
  private var securityScopedBookmarkChannel: SecurityScopedBookmarkChannel?
  private var computerUseChannel: MacosComputerUseChannel?
  private var sparkleUpdateChannel: MacosSparkleUpdateChannel?
  private var appMenuChannel: MacosAppMenuChannel?

  /// Asks the Flutter side to present the in-app settings modal. Invoked from the
  /// native application menu (Caverno > Settings…) via the AppDelegate.
  func requestOpenSettings() {
    appMenuChannel?.requestOpenSettings()
  }

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
    sparkleUpdateChannel = MacosSparkleUpdateChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )
    appMenuChannel = MacosAppMenuChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}

/// Sends one-way application-menu commands from native macOS to Flutter. Unlike the
/// other channels here it only invokes Dart methods (native is the caller), so it does
/// not register a method-call handler.
final class MacosAppMenuChannel {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.caverno/app_menu",
      binaryMessenger: messenger
    )
  }

  func requestOpenSettings() {
    channel.invokeMethod("openSettings", arguments: nil)
  }
}

final class MacosSparkleUpdateChannel {
  private let channel: FlutterMethodChannel
  private let updateController = MacosSparkleUpdateController.shared

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.caverno/sparkle_updates",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStatus":
      result(updateController.statusPayload())
    case "checkForUpdates":
      updateController.checkForUpdates(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

final class MacosSparkleUpdateController {
  static let shared = MacosSparkleUpdateController()

  private let updaterController: SPUStandardUpdaterController?
  private let configuredFeedURL: String?
  private let publicKeyConfigured: Bool

  private init() {
    configuredFeedURL = Self.validConfiguredFeedURL()
    publicKeyConfigured = Self.hasConfiguredPublicKey()
    if configuredFeedURL != nil && publicKeyConfigured {
      updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
      )
    } else {
      updaterController = nil
    }
  }

  func checkForUpdates(result: @escaping FlutterResult) {
    guard let updaterController = updaterController else {
      result(
        FlutterError(
          code: "sparkle_not_configured",
          message: "Sparkle updates are not configured for this build.",
          details: statusPayload()
        )
      )
      return
    }

    DispatchQueue.main.async {
      updaterController.checkForUpdates(nil)
      result(self.statusPayload())
    }
  }

  func checkForUpdatesFromMenu(_ sender: Any?) {
    guard let updaterController = updaterController else {
      presentNotConfiguredAlert()
      return
    }

    DispatchQueue.main.async {
      updaterController.checkForUpdates(sender)
    }
  }

  func statusPayload() -> [String: Any] {
    var payload: [String: Any] = [
      "available": true,
      "configured": updaterController != nil,
      "feedURL": configuredFeedURL ?? "",
      "publicKeyConfigured": publicKeyConfigured,
      "scheduledCheckIntervalSeconds": 3600,
      "bundleVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
      "bundleShortVersion": Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "",
    ]

    if let updater = updaterController?.updater {
      payload["automaticallyChecksForUpdates"] = updater.automaticallyChecksForUpdates
      payload["automaticallyDownloadsUpdates"] = updater.automaticallyDownloadsUpdates
      payload["updateCheckIntervalSeconds"] = updater.updateCheckInterval
    } else {
      payload["automaticallyChecksForUpdates"] = false
      payload["automaticallyDownloadsUpdates"] = false
      payload["updateCheckIntervalSeconds"] = 3600
      payload["nextAction"] =
        "Set SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY for release builds."
    }

    return payload
  }

  private func presentNotConfiguredAlert() {
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = "Updates are not configured for this build."
      alert.informativeText =
        "Build a release with SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY to enable Sparkle updates."
      alert.alertStyle = .informational
      alert.runModal()
    }
  }

  private static func validConfiguredFeedURL() -> String? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
      return nil
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty && !trimmed.contains("$(") else {
      return nil
    }
    guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
      return nil
    }
    return trimmed
  }

  private static func hasConfiguredPublicKey() -> Bool {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
      return false
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && !trimmed.contains("$(")
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
  case showMainWindow
  case permissionStatus
  case openSettings
  case showPermissionOverlay
  case startOnboardingPermissionFlow
  case stopAll
  case screenshot
  case listDisplays
  case listWindows
  case accessibilitySnapshot
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

  var blocksOnHelperPathMismatch: Bool {
    switch self {
    case .ping, .showMainWindow, .permissionStatus, .openSettings,
         .showPermissionOverlay, .startOnboardingPermissionFlow, .stopAll:
      return false
    case .screenshot, .listDisplays, .listWindows, .accessibilitySnapshot,
         .focusWindow, .screenshotWindow, .moveMouse, .click, .drag, .scroll,
         .typeText, .pressKey, .startSystemAudioRecording,
         .stopSystemAudioRecording:
      return true
    }
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
    "showMainWindow",
    "permissionStatus",
    "openSettings",
    "showPermissionOverlay",
    "startOnboardingPermissionFlow",
    "stopAll",
    "screenshot",
    "listDisplays",
    "listWindows",
    "accessibilitySnapshot",
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
  static let mainAppOwnsTccPermissions = false
  static let tccPermissionOwnerBundleIdentifier = "com.noguwo.apps.caverno.computer-use"
  static let tccPermissionOwnerDisplayName = "Caverno Computer Use"
  static let helperActsAsOsActionExecutor = true
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
    "ping_show_main_window_permission_status_open_settings_show_permission_overlay_start_onboarding_permission_flow_stop_all_screenshot_list_displays_list_windows_accessibility_snapshot_focus_window_screenshot_window_move_mouse_click_drag_scroll_type_text_press_key_system_audio_match_dnc",
    "capture_input_audio_commands_have_parity_smoke_coverage",
    "fallback_path_is_observable_and_non_destructive",
  ]
  static let xpcFallbackTimeout = 3.0
  static let xpcWarmupTimeout = 1.0
  static let xpcWarmupReuseInterval = 30.0
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
  private var lastSuccessfulXpcWarmupAt: Date?

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
    let lockOwner = activeExpectedLockOwner(expectedHelperPath: helperPath)
    let runningHelperPath = runningApplication?.bundleURL?.standardizedFileURL.path
    let helperRunningViaLockOwner = runningApplication == nil && lockOwner != nil
    let mismatchedApplications = runningApplications.filter {
      $0.bundleURL?.standardizedFileURL.path != helperPath
    }
    let helperPathMatchesRunningHelper =
      mismatchedApplications.isEmpty &&
      (helperRunningViaLockOwner || runningHelperPath == nil || runningHelperPath == helperPath)
    var response: [String: Any] = [
      "ok": true,
      "helperDisplayName": helperDisplayName,
      "helperBundleIdentifier": helperBundleIdentifier,
      "helperInstalled": FileManager.default.fileExists(atPath: helperURL.path),
      "helperRunning": runningApplication != nil || helperRunningViaLockOwner,
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
      "mainAppOwnsTccPermissions": MacosComputerUseIpcSchema.mainAppOwnsTccPermissions,
      "tccPermissionOwnerBundleIdentifier": MacosComputerUseIpcSchema.tccPermissionOwnerBundleIdentifier,
      "tccPermissionOwnerDisplayName": MacosComputerUseIpcSchema.tccPermissionOwnerDisplayName,
      "helperActsAsOsActionExecutor": MacosComputerUseIpcSchema.helperActsAsOsActionExecutor,
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
    if let lockOwner {
      response["helperRunningViaLockOwner"] = helperRunningViaLockOwner
      response["helperLockOwnerProcessIdentifier"] =
        lockOwner["activeLockOwnerProcessIdentifier"]
      response["helperLockOwnerBundlePath"] = lockOwner["activeLockOwnerBundlePath"]
      response["helperLockOwnerDiagnosticsEvent"] =
        lockOwner["activeLockOwnerDiagnosticsEvent"]
      if runningHelperPath == nil {
        response["runningHelperPath"] = helperPath
        response["helperProcessIdentifier"] = lockOwner["activeLockOwnerProcessIdentifier"]
      }
    }
    if runningApplications.count > 1 {
      response["helperDuplicateProcessIdentifiers"] = runningApplications
        .map { Int($0.processIdentifier) }
      response["helperDuplicateProcessCount"] = runningApplications.count
    }
    if !mismatchedApplications.isEmpty {
      response["mismatchedHelperProcessIdentifiers"] =
        mismatchedApplications.map { Int($0.processIdentifier) }
      response["mismatchedHelperPaths"] = mismatchedApplications.map {
        $0.bundleURL?.standardizedFileURL.path ?? ""
      }
    }
    if !helperPathMatchesRunningHelper {
      response["helperPathMismatch"] = true
      response["helperPathMismatchDetails"] = [
        "expectedHelperPath": helperPath,
        "runningHelperPath": runningHelperPath ?? mismatchedApplications.first?.bundleURL?.standardizedFileURL.path ?? "",
        "nextAction": "Restart Caverno Computer Use from Caverno before validating granted permissions.",
      ]
    }
    response["oldHelperActionRequestsBlocked"] = true
    response["installMigrationGuardrails"] = installMigrationGuardrails(
      helperPath: helperPath,
      runningHelperPath: runningHelperPath,
      helperPathMatchesRunningHelper: helperPathMatchesRunningHelper,
      mismatchedApplications: mismatchedApplications,
      staleReasons: []
    )
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
      runningApplication: runningApplication,
      lockOwnerProcessIdentifier: lockOwner?["activeLockOwnerProcessIdentifier"] as? Int
    )
    if let processIdentifier = runningApplication?.processIdentifier {
      response["helperProcessIdentifier"] = Int(processIdentifier)
    }
    return response
  }

  private func addSharedDiagnostics(
    to response: inout [String: Any],
    helperURL: URL,
    runningApplication: NSRunningApplication?,
    lockOwnerProcessIdentifier: Int?
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
    } else if let lockOwnerProcessIdentifier {
      let diagnosticProcessIdentifiers = [
        helperSharedDiagnostics["helperProcessIdentifier"] as? Int,
        helperSharedDiagnostics["singleInstanceLockOwnerProcessIdentifier"] as? Int,
        helperSharedDiagnostics["existingHelperProcessIdentifier"] as? Int,
      ].compactMap { $0 }
      let pidMatches = diagnosticProcessIdentifiers.contains(lockOwnerProcessIdentifier)
      response["helperSharedDiagnosticsMatchesRunningHelper"] = pidMatches
      response["helperSharedDiagnosticsProcessIdentifier"] = lockOwnerProcessIdentifier
      response["helperSharedDiagnosticsMatchedViaLockOwner"] = true
      if !pidMatches {
        staleReasons.append("process_identifier_mismatch")
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
    response["installMigrationGuardrails"] = installMigrationGuardrails(
      helperPath: helperURL.standardizedFileURL.path,
      runningHelperPath: runningApplication?.bundleURL?.standardizedFileURL.path,
      helperPathMatchesRunningHelper: response["helperPathMatchesRunningHelper"] as? Bool ?? false,
      mismatchedApplications: [],
      staleReasons: staleReasons
    )
  }

  private func installMigrationGuardrails(
    helperPath: String,
    runningHelperPath: String?,
    helperPathMatchesRunningHelper: Bool,
    mismatchedApplications: [NSRunningApplication],
    staleReasons: [String]
  ) -> [String: Any] {
    let helperPathMismatch = !helperPathMatchesRunningHelper || !mismatchedApplications.isEmpty
    let diagnosticsStale = !staleReasons.isEmpty
    var blockers: [String] = []
    if helperPathMismatch {
      blockers.append("helper_path_mismatch")
    }
    if diagnosticsStale {
      blockers.append("stale_helper_diagnostics")
    }
    let tccRegrantRequired =
      helperPathMismatch ||
      staleReasons.contains("helper_bundle_path_mismatch") ||
      staleReasons.contains("helper_executable_path_mismatch")
    return [
      "schemaName": "macos_computer_use_install_migration_guardrails",
      "schemaVersion": 1,
      "milestone": "M38",
      "status": blockers.isEmpty ? "ready" : "blocked",
      "ready": blockers.isEmpty,
      "m38InstallMigrationGate": [
        "status": blockers.isEmpty ? "ready" : "blocked",
        "ready": blockers.isEmpty,
        "blockers": blockers,
      ],
      "helperIdentityPreservedWhenPossible": true,
      "expectedHelperPath": helperPath,
      "runningHelperPath": runningHelperPath ?? "",
      "helperPathMatchesRunningHelper": helperPathMatchesRunningHelper,
      "helperPathMismatch": helperPathMismatch,
      "helperDiagnosticsStale": diagnosticsStale,
      "helperDiagnosticsStaleReasons": staleReasons,
      "tccRegrantRequired": tccRegrantRequired,
      "tccRegrantReason": tccRegrantRequired
        ? "Helper Accessibility grants are tied to the helper app identity. Regrant may be required after the helper path, executable, or signing identity changes."
        : "The current helper identity matches the expected embedded helper path.",
      "oldHelperActionRequestsBlocked": true,
      "allowedDuringMigration": [
        "status",
        "open_helper_ui",
        "permission_recovery",
        "emergency_stop",
      ],
      "blockedDuringMigration": [
        "screenshot",
        "window_capture",
        "focus",
        "pointer_input",
        "keyboard_input",
        "system_audio_recording",
      ],
      "nextAction": blockers.isEmpty
        ? "Install and migration guardrails are ready."
        : "Restart Caverno Computer Use from the installed Caverno bundle, recheck helper identity, and ask the user to regrant TCC only if macOS reports the new helper as missing permissions.",
    ]
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
      finishLaunchForRunningHelper(
        extra: extra,
        runningHelperPath: helperPath,
        helperPathMatchesRunningHelper: true,
        lockOwner: nil,
        result: result
      )
      return
    }

    let mismatchedApplications = runningApplications.filter {
      $0.bundleURL?.standardizedFileURL.path != helperPath
    }
    if let mismatchedApplication = mismatchedApplications.first {
      let runningHelperPath = mismatchedApplication.bundleURL?.standardizedFileURL.path ?? ""
      mismatchedApplication.activate(options: [.activateIgnoringOtherApps])
      var launchExtra = extra
      launchExtra["preservedMismatchedHelperPath"] = true
      launchExtra["mismatchedHelperProcessIdentifier"] =
        Int(mismatchedApplication.processIdentifier)
      launchExtra["mismatchedHelperPath"] = runningHelperPath
      launchExtra["expectedHelperPath"] = helperPath
      if mismatchedApplications.count > 1 {
        launchExtra["mismatchedHelperProcessIdentifiers"] =
          mismatchedApplications.map { Int($0.processIdentifier) }
        launchExtra["mismatchedHelperPaths"] = mismatchedApplications.map {
          $0.bundleURL?.standardizedFileURL.path ?? ""
        }
      }
      finishLaunchForRunningHelper(
        extra: launchExtra,
        runningHelperPath: runningHelperPath,
        helperPathMatchesRunningHelper: false,
        lockOwner: nil,
        result: result
      )
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

    if let lockOwner = activeExpectedLockOwner(expectedHelperPath: helperPath) {
      if let processIdentifier = lockOwner["activeLockOwnerProcessIdentifier"] as? Int,
         let application = NSRunningApplication(processIdentifier: pid_t(processIdentifier)) {
        application.activate(options: [.activateIgnoringOtherApps])
      }
      finishLaunchForRunningHelper(
        extra: extra,
        runningHelperPath: helperPath,
        helperPathMatchesRunningHelper: true,
        lockOwner: lockOwner,
        result: result
      )
      return
    }

    openEmbeddedHelper(helperURL: helperURL, extra: extra, result: result)
  }

  private func finishLaunchForRunningHelper(
    extra: [String: Any],
    runningHelperPath: String,
    helperPathMatchesRunningHelper: Bool,
    lockOwner: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    sendPreferred(
      command: .showMainWindow,
      arguments: ["reason": "open_computer_use"],
      timeout: 1.5
    ) { [weak self] mainWindowResult in
      guard let self else {
        return
      }
      var response = self.status()
      response["alreadyRunning"] = true
      response["runningHelperPath"] = runningHelperPath
      response["helperPathMatchesRunningHelper"] = helperPathMatchesRunningHelper
      if !helperPathMatchesRunningHelper {
        response["helperPathMismatch"] = true
        response["helperPathMismatchDetails"] = [
          "expectedHelperPath": self.embeddedHelperURL().standardizedFileURL.path,
          "runningHelperPath": runningHelperPath,
          "nextAction":
            "Keep using the currently granted helper for this session, then restart from the installed Caverno bundle before release sign-off.",
        ]
      }
      if let mainWindowResponse = mainWindowResult as? [String: Any] {
        response["mainWindowRequest"] = mainWindowResponse
      } else if let error = mainWindowResult as? FlutterError {
        response["mainWindowRequest"] = [
          "ok": false,
          "code": error.code,
          "error": error.message ?? "Caverno Computer Use did not respond to showMainWindow.",
          "details": error.details ?? [:],
        ]
      }
      if let lockOwner {
        response["alreadyRunningViaLockOwner"] = true
        response["helperRunning"] = true
        response["helperProcessIdentifier"] =
          lockOwner["activeLockOwnerProcessIdentifier"]
        response["helperLockOwnerBundlePath"] = lockOwner["activeLockOwnerBundlePath"]
        response["helperLockOwnerDiagnosticsEvent"] =
          lockOwner["activeLockOwnerDiagnosticsEvent"]
      }
      for (key, value) in extra {
        response[key] = value
      }
      result(response)
    }
  }

  private func activeExpectedLockOwner(expectedHelperPath: String) -> [String: Any]? {
    guard
      let diagnostics = MacosComputerUseHelperSharedDiagnostics.read(),
      diagnostics["helperBundleIdentifier"] as? String == helperBundleIdentifier
    else {
      return nil
    }

    let candidatePaths = [
      diagnostics["existingHelperBundlePath"] as? String,
      diagnostics["helperBundlePath"] as? String,
    ].compactMap { value -> String? in
      guard let value, !value.isEmpty else {
        return nil
      }
      return URL(fileURLWithPath: value).standardizedFileURL.path
    }
    guard candidatePaths.contains(expectedHelperPath) else {
      return nil
    }

    let ownerProcessIdentifier =
      diagnostics["existingHelperProcessIdentifier"] as? Int ??
      diagnostics["singleInstanceLockOwnerProcessIdentifier"] as? Int ??
      diagnostics["helperProcessIdentifier"] as? Int
    guard
      let ownerProcessIdentifier,
      ownerProcessIdentifier > 0,
      processIsRunning(ownerProcessIdentifier)
    else {
      return nil
    }

    return [
      "activeLockOwnerProcessIdentifier": ownerProcessIdentifier,
      "activeLockOwnerBundlePath": expectedHelperPath,
      "activeLockOwnerDiagnosticsEvent": diagnostics["event"] as? String ?? "",
      "activeLockOwnerDiagnostics": diagnostics,
    ]
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
    configuration.environment = ProcessInfo.processInfo.environment.merging([
      "CAVERNO_COMPUTER_USE_PRESENT_MAIN_WINDOW": "1",
    ]) { _, new in new }
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
        "mainAppOwnsTccPermissions": MacosComputerUseIpcSchema.mainAppOwnsTccPermissions,
        "tccPermissionOwnerBundleIdentifier": MacosComputerUseIpcSchema.tccPermissionOwnerBundleIdentifier,
        "tccPermissionOwnerDisplayName": MacosComputerUseIpcSchema.tccPermissionOwnerDisplayName,
        "helperActsAsOsActionExecutor": MacosComputerUseIpcSchema.helperActsAsOsActionExecutor,
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
      let helperPath = self.embeddedHelperURL().standardizedFileURL.path
      let lockOwner = self.activeExpectedLockOwner(expectedHelperPath: helperPath)
      if let runningProcessIdentifier = runningApplication?.processIdentifier {
        details["helperProcessIdentifier"] = Int(runningProcessIdentifier)
      } else if let lockOwnerProcessIdentifier =
        lockOwner?["activeLockOwnerProcessIdentifier"] as? Int {
        details["helperProcessIdentifier"] = lockOwnerProcessIdentifier
        details["helperRunning"] = true
        details["helperRunningViaLockOwner"] = true
      }
      self.addSharedDiagnostics(
        to: &details,
        helperURL: self.embeddedHelperURL(),
        runningApplication: runningApplication,
        lockOwnerProcessIdentifier: lockOwner?["activeLockOwnerProcessIdentifier"] as? Int
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
    if let blocker = helperPathMismatchActionBlocker(for: command) {
      result(
        FlutterError(
          code: "old_helper_process_blocked",
          message: "Caverno Computer Use action blocked because a different helper app is running.",
          details: blocker
        )
      )
      return
    }

    if shouldWarmupXpc(for: command) {
      sendXpcWarmup(for: command) { [weak self] warmupDiagnostic in
        guard let self else {
          return
        }
        if self.sendXpc(
          command: command,
          arguments: arguments,
          timeout: timeout,
          warmupDiagnostic: warmupDiagnostic,
          result: result
        ) {
          return
        }
        self.sendFallback(
          command: command,
          arguments: arguments,
          timeout: timeout,
          warmupDiagnostic: warmupDiagnostic,
          result: result
        )
      }
      return
    }

    if sendXpc(command: command, arguments: arguments, timeout: timeout, result: result) {
      return
    }

    sendFallback(command: command, arguments: arguments, timeout: timeout, result: result)
  }

  private func helperPathMismatchActionBlocker(
    for command: MacosComputerUseHelperCommand
  ) -> [String: Any]? {
    guard command.blocksOnHelperPathMismatch else {
      return nil
    }
    let currentStatus = status()
    guard currentStatus["helperPathMismatch"] as? Bool == true else {
      return nil
    }
    return [
      "schemaName": "macos_computer_use_install_migration_guardrails",
      "schemaVersion": 1,
      "milestone": "M38",
      "command": command.rawValue,
      "status": "blocked",
      "oldHelperActionRequestsBlocked": true,
      "expectedHelperPath": currentStatus["embeddedHelperPath"] ?? currentStatus["helperPath"] ?? "",
      "runningHelperPath": currentStatus["runningHelperPath"] ?? "",
      "mismatchedHelperPath": currentStatus["mismatchedHelperPath"] ?? "",
      "mismatchedHelperPaths": currentStatus["mismatchedHelperPaths"] ?? [],
      "blockers": ["helper_path_mismatch"],
      "nextAction": "Restart Caverno Computer Use from the installed Caverno bundle, then recheck helper identity before running desktop actions.",
    ]
  }

  private func sendFallback(
    command: MacosComputerUseHelperCommand,
    arguments: [String: Any],
    timeout: TimeInterval,
    warmupDiagnostic: [String: Any]? = nil,
    result: @escaping FlutterResult
  ) {
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
      preferredAttemptDiagnostic: warmupDiagnostic.map {
        ["warmupAttempt": $0, "status": "xpc_skipped_after_warmup"]
      },
      result: result
    )
  }

  private func shouldWarmupXpc(for command: MacosComputerUseHelperCommand) -> Bool {
    guard MacosComputerUseIpcSchema.xpcReady else {
      return false
    }
    guard command.supportsPreferredXpcTransport, command != .ping else {
      return false
    }
    guard let lastSuccessfulXpcWarmupAt else {
      return true
    }
    return Date().timeIntervalSince(lastSuccessfulXpcWarmupAt) >
      MacosComputerUseIpcSchema.xpcWarmupReuseInterval
  }

  private func sendXpcWarmup(
    for command: MacosComputerUseHelperCommand,
    completion: @escaping ([String: Any]) -> Void
  ) {
    let requestId = UUID().uuidString
    let sentAt = Date()
    helperIpcSequence += 1
    let sequence = helperIpcSequence
    let request = MacosComputerUseHelperRequest(
      requestId: requestId,
      command: .ping,
      arguments: ["warmupForCommand": command.rawValue]
    )
    var completed = false
    let connection = NSXPCConnection(
      machServiceName: MacosComputerUseIpcSchema.xpcServiceName,
      options: []
    )
    connection.remoteObjectInterface = NSXPCInterface(with: CavernoComputerUseXpcProtocol.self)

    func finish(
      status: String,
      completedAt: Date = Date(),
      errorCode: String? = nil,
      errorDescription: String? = nil
    ) {
      guard !completed else {
        return
      }
      completed = true
      connection.invalidate()
      var diagnostic = helperIpcDiagnostic(
        sequence: sequence,
        requestId: requestId,
        command: .ping,
        selectedTransport: MacosComputerUseIpcSchema.preferredTransport,
        attemptedTransport: nil,
        sentAt: sentAt,
        timeout: MacosComputerUseIpcSchema.xpcWarmupTimeout,
        status: status,
        completedAt: completedAt,
        errorCode: errorCode,
        errorDescription: errorDescription
      )
      diagnostic["warmupForCommand"] = command.rawValue
      diagnostic["xpcWarmup"] = true
      if status == "xpc_response" {
        diagnostic["responseReceivedBeforeTimeout"] = true
        lastSuccessfulXpcWarmupAt = completedAt
      } else if status == "xpc_timeout" {
        diagnostic["responseReceivedBeforeTimeout"] = false
      }
      lastHelperIpcAttempt = diagnostic
      completion(diagnostic)
    }

    connection.invalidationHandler = { [weak self] in
      DispatchQueue.main.async {
        guard let self, !completed else {
          return
        }
        self.lastHelperIpcAttempt = self.helperIpcDiagnostic(
          sequence: sequence,
          requestId: requestId,
          command: .ping,
          selectedTransport: MacosComputerUseIpcSchema.preferredTransport,
          attemptedTransport: nil,
          sentAt: sentAt,
          timeout: MacosComputerUseIpcSchema.xpcWarmupTimeout,
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
          "CavernoComputerUseIPC xpc warmup error requestId=%@ command=%@ error=%@",
          requestId,
          command.rawValue,
          error.localizedDescription
        )
        finish(
          status: "xpc_error",
          errorCode: MacosComputerUseIpcSchema.xpcUnavailable,
          errorDescription: error.localizedDescription
        )
      }
    } as? CavernoComputerUseXpcProtocol

    guard let proxy else {
      finish(status: "xpc_proxy_unavailable", errorCode: MacosComputerUseIpcSchema.xpcUnavailable)
      return
    }

    NSLog(
      "CavernoComputerUseIPC xpc warmup sent requestId=%@ command=%@",
      requestId,
      command.rawValue
    )
    proxy.handleRequest(request.userInfo as NSDictionary) { response in
      DispatchQueue.main.async {
        let responseMap = response as? [String: Any] ?? [:]
        finish(
          status: responseMap["ok"] as? Bool == false ? "xpc_response_error" : "xpc_response",
          completedAt: Date(),
          errorCode: responseMap["code"] as? String
        )
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + MacosComputerUseIpcSchema.xpcWarmupTimeout) {
      finish(status: "xpc_timeout", errorCode: MacosComputerUseIpcSchema.xpcTimeout)
    }
  }

  private func sendXpc(
    command: MacosComputerUseHelperCommand,
    arguments: [String: Any],
    timeout: TimeInterval,
    warmupDiagnostic: [String: Any]? = nil,
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

    func fallback(
      status: String,
      errorCode: String,
      errorDescription: String? = nil,
      extraDiagnostics: [String: Any] = [:]
    ) {
      guard !completed else {
        return
      }
      completed = true
      connection.invalidate()
      var diagnostic = helperIpcDiagnostic(
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
      diagnostic.merge(extraDiagnostics) { _, new in new }
      if let warmupDiagnostic {
        diagnostic["warmupAttempt"] = warmupDiagnostic
      }
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
        guard let self else {
          return
        }
        let responseReceivedAt = Date()
        let responseMap = response as? [String: Any] ?? [:]
        if completed {
          if var diagnostic = self.lastPreferredIpcAttempt,
             diagnostic["requestId"] as? String == requestId,
             diagnostic["status"] as? String == "xpc_timeout" {
            diagnostic["responseReceivedAfterTimeout"] = true
            diagnostic["lateResponseCompletedAt"] = self.isoString(responseReceivedAt)
            diagnostic["lateResponseElapsedMs"] = Int(
              responseReceivedAt.timeIntervalSince(sentAt) * 1000
            )
            diagnostic["lateResponseOk"] = responseMap["ok"] as? Bool ?? true
            if let responseCode = responseMap["code"] as? String {
              diagnostic["lateResponseCode"] = responseCode
            }
            if let warmupDiagnostic {
              diagnostic["warmupAttempt"] = warmupDiagnostic
            }
            self.lastPreferredIpcAttempt = diagnostic
            self.lastHelperIpcAttempt = diagnostic
            NSLog(
              "CavernoComputerUseIPC xpc late response received requestId=%@ command=%@ elapsedMs=%d",
              requestId,
              command.rawValue,
              diagnostic["lateResponseElapsedMs"] as? Int ?? -1
            )
          }
          return
        }
        completed = true
        connection.invalidate()
        var responseWithTransport = responseMap
        responseWithTransport["selectedIpcTransport"] = MacosComputerUseIpcSchema.preferredTransport
        responseWithTransport["fallbackIpcTransport"] = MacosComputerUseIpcSchema.fallbackTransport
        var diagnostic = self.helperIpcDiagnostic(
          sequence: sequence,
          requestId: requestId,
          command: command,
          selectedTransport: MacosComputerUseIpcSchema.preferredTransport,
          attemptedTransport: nil,
          sentAt: sentAt,
          timeout: MacosComputerUseIpcSchema.xpcFallbackTimeout,
          status: responseMap["ok"] as? Bool == false ? "xpc_response_error" : "xpc_response",
          completedAt: responseReceivedAt,
          errorCode: responseMap["code"] as? String
        )
        diagnostic["responseReceivedBeforeTimeout"] = true
        if let warmupDiagnostic {
          diagnostic["warmupAttempt"] = warmupDiagnostic
          responseWithTransport["preferredIpcWarmupAttempt"] = warmupDiagnostic
        }
        responseWithTransport["preferredIpcAttempt"] = diagnostic
        self.lastHelperIpcAttempt = diagnostic
        self.lastPreferredIpcAttempt = diagnostic
        NSLog(
          "CavernoComputerUseIPC xpc response received requestId=%@ command=%@",
          requestId,
          command.rawValue
        )
        result(responseWithTransport)
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + MacosComputerUseIpcSchema.xpcFallbackTimeout) {
      fallback(
        status: "xpc_timeout",
        errorCode: MacosComputerUseIpcSchema.xpcTimeout,
        extraDiagnostics: ["responseReceivedBeforeTimeout": false]
      )
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
      "mainAppOwnsTccPermissions": MacosComputerUseIpcSchema.mainAppOwnsTccPermissions,
      "tccPermissionOwnerBundleIdentifier": MacosComputerUseIpcSchema.tccPermissionOwnerBundleIdentifier,
      "tccPermissionOwnerDisplayName": MacosComputerUseIpcSchema.tccPermissionOwnerDisplayName,
      "helperActsAsOsActionExecutor": MacosComputerUseIpcSchema.helperActsAsOsActionExecutor,
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
    case "mainAppScreenCapturePreflight":
      result(mainAppScreenCapturePreflight())
    case "openSystemSettings":
      openSystemSettings(call, result: result)
    case "listWindows":
      helperClient.sendPreferred(
        command: .listWindows,
        arguments: helperArguments(call),
        timeout: 3,
        result: result
      )
    case "accessibilitySnapshot":
      helperClient.sendPreferred(
        command: .accessibilitySnapshot,
        arguments: helperArguments(call),
        timeout: 4,
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
    case "listDisplays":
      helperClient.sendPreferred(
        command: .listDisplays,
        arguments: helperArguments(call),
        timeout: 3,
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
    // Screen & System Audio Recording is owned by Caverno Computer Use (the helper).
    // The main app must not call CGPreflightScreenCaptureAccess, because that API
    // registers the calling process with TCC and causes a misleading "Caverno would
    // like to record" prompt for users who only need to grant the helper.
    return [
      "accessibilityGranted": AXIsProcessTrusted(),
      "screenCaptureGranted": false,
      "systemAudioRecordingSupported": isSystemAudioRecordingSupported(),
      "screenCaptureOwner": MacosComputerUseIpcSchema.tccPermissionOwnerDisplayName,
      "screenCaptureOwnerBundleIdentifier": MacosComputerUseIpcSchema.tccPermissionOwnerBundleIdentifier,
      "mainAppScreenCaptureRequestBlocked": true,
      "nextAction": "Query helperPermissionStatus to read Screen & System Audio Recording owned by Caverno Computer Use.",
    ]
  }

  private func requestAccessibility(result: @escaping FlutterResult) {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)
    result(["accessibilityGranted": trusted])
  }

  // Query-only preflight for the MAIN APP's Screen Recording grant. Used by
  // chat clipboard / drag flows that depend on super_clipboard /
  // super_native_extensions, which call CGWindowListCreate* and therefore
  // need the main app to hold Screen Recording. Returns the current state
  // without prompting the user; super_clipboard's own calls handle the
  // initial prompt registration when needed.
  private func mainAppScreenCapturePreflight() -> [String: Any] {
    let granted: Bool
    if #available(macOS 10.15, *) {
      granted = CGPreflightScreenCaptureAccess()
    } else {
      granted = true
    }
    return [
      "ok": true,
      "screenCaptureGranted": granted,
      "ownerBundleIdentifier": Bundle.main.bundleIdentifier ?? "",
      "purpose": "main_app_clipboard_drag",
    ]
  }

  private func requestScreenCapture(result: @escaping FlutterResult) {
    // Refuse to call CGRequestScreenCaptureAccess from the main app. The helper
    // owns Screen & System Audio Recording; prompting the main app would register
    // Caverno with TCC and grant the wrong process.
    result([
      "ok": false,
      "screenCaptureGranted": false,
      "screenCaptureOwner": MacosComputerUseIpcSchema.tccPermissionOwnerDisplayName,
      "screenCaptureOwnerBundleIdentifier": MacosComputerUseIpcSchema.tccPermissionOwnerBundleIdentifier,
      "mainAppScreenCaptureRequestBlocked": true,
      "code": "main_app_screen_capture_request_blocked",
      "error":
        "Caverno does not own Screen & System Audio Recording. Drive the helper onboarding flow so the user grants Caverno Computer Use instead.",
      "nextAction":
        "Call showPermissionOverlay or startOnboardingPermissionFlow on the helper backend to direct the user to grant Caverno Computer Use.",
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
