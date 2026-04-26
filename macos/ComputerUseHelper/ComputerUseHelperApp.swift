import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

@objc(CavernoComputerUseXpcProtocol)
protocol CavernoComputerUseXpcProtocol: NSObjectProtocol {
  func handleRequest(_ request: NSDictionary, withReply reply: @escaping (NSDictionary) -> Void)
}

@main
final class ComputerUseHelperApp: NSObject, NSApplicationDelegate {
  private static var delegateInstance: ComputerUseHelperApp?

  static func main() {
    let application = NSApplication.shared
    let delegate = ComputerUseHelperApp()
    delegateInstance = delegate
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
  }

  private let ipc = ComputerUseHelperIpc()
  private var window: NSWindow?
  private var statusSummaryLabel: NSTextField?
  private var helperReachableRow: PermissionRowView?
  private var accessibilityRow: PermissionRowView?
  private var screenRecordingRow: PermissionRowView?
  private var permissionSmokeRow: SmokeStepRowView?
  private var displayScreenshotSmokeRow: SmokeStepRowView?
  private var windowCaptureSmokeRow: SmokeStepRowView?

  func applicationDidFinishLaunching(_ notification: Notification) {
    ipc.start()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Caverno Computer Use"
    window.center()
    window.contentView = makeContentView()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    ipc.start()
    refreshPermissionRows()
  }

  private func makeContentView() -> NSView {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)

    let icon = NSImageView()
    icon.symbolConfiguration = .init(pointSize: 52, weight: .medium)
    icon.image = NSImage(
      systemSymbolName: "cursorarrow.click.2",
      accessibilityDescription: "Caverno Computer Use"
    )
    icon.contentTintColor = .controlAccentColor
    icon.translatesAutoresizingMaskIntoConstraints = false

    let title = NSTextField(labelWithString: "Enable Caverno Computer Use")
    title.font = .systemFont(ofSize: 32, weight: .bold)
    title.alignment = .center
    title.maximumNumberOfLines = 2

    let subtitle = NSTextField(
      wrappingLabelWithString:
        "Caverno Computer Use owns the macOS permissions needed to observe screens and control apps. These permissions are used only after Caverno asks you to run a desktop task."
    )
    subtitle.font = .systemFont(ofSize: 15, weight: .regular)
    subtitle.textColor = .secondaryLabelColor
    subtitle.alignment = .center
    subtitle.maximumNumberOfLines = 3

    let statusSummaryLabel = NSTextField(
      wrappingLabelWithString: "Refresh permissions to verify readiness."
    )
    statusSummaryLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    statusSummaryLabel.textColor = .secondaryLabelColor
    statusSummaryLabel.alignment = .center
    statusSummaryLabel.maximumNumberOfLines = 2
    self.statusSummaryLabel = statusSummaryLabel

    let rows = NSStackView()
    rows.orientation = .vertical
    rows.alignment = .width
    rows.spacing = 12
    rows.translatesAutoresizingMaskIntoConstraints = false

    let helperReachableRow = PermissionRowView(
      symbolName: "bolt.horizontal.circle",
      title: "Helper Reachable",
      subtitle: "Confirms Caverno can reach this helper over the current IPC bridge.",
      buttonTitle: "Refresh",
      action: { [weak self] in self?.refreshPermissionRows() }
    )
    let accessibilityRow = PermissionRowView(
      symbolName: "figure.stand",
      title: "Accessibility",
      subtitle: "Allows Caverno Computer Use to access app interfaces.",
      buttonTitle: "Open",
      action: { openSettingsPane(.accessibility) }
    )
    let screenRecordingRow = PermissionRowView(
      symbolName: "camera.viewfinder",
      title: "Screen & System Audio Recording",
      subtitle: "Allows screenshots and system audio capture after approval.",
      buttonTitle: "Open",
      action: { openSettingsPane(.screenRecording) }
    )
    self.helperReachableRow = helperReachableRow
    self.accessibilityRow = accessibilityRow
    self.screenRecordingRow = screenRecordingRow

    rows.addArrangedSubview(helperReachableRow)
    rows.addArrangedSubview(accessibilityRow)
    rows.addArrangedSubview(screenRecordingRow)

    let smokeTitle = NSTextField(labelWithString: "Verification")
    smokeTitle.font = .systemFont(ofSize: 15, weight: .semibold)
    smokeTitle.textColor = .secondaryLabelColor
    smokeTitle.alignment = .left

    let smokeRows = NSStackView()
    smokeRows.orientation = .vertical
    smokeRows.alignment = .width
    smokeRows.spacing = 8
    smokeRows.translatesAutoresizingMaskIntoConstraints = false

    let permissionSmokeRow = SmokeStepRowView(
      title: "Permissions",
      subtitle: "Accessibility and Screen & System Audio Recording are granted."
    )
    let displayScreenshotSmokeRow = SmokeStepRowView(
      title: "Display Screenshot",
      subtitle: "A display image can be captured after Screen Recording is granted."
    )
    let windowCaptureSmokeRow = SmokeStepRowView(
      title: "Window Capture",
      subtitle: "A visible window can be located and captured for visual grounding."
    )
    self.permissionSmokeRow = permissionSmokeRow
    self.displayScreenshotSmokeRow = displayScreenshotSmokeRow
    self.windowCaptureSmokeRow = windowCaptureSmokeRow
    smokeRows.addArrangedSubview(permissionSmokeRow)
    smokeRows.addArrangedSubview(displayScreenshotSmokeRow)
    smokeRows.addArrangedSubview(windowCaptureSmokeRow)

    let refreshButton = NSButton(
      title: "Refresh",
      target: self,
      action: #selector(refreshFromButton)
    )
    refreshButton.bezelStyle = .rounded
    let verifyButton = NSButton(
      title: "Verify",
      target: self,
      action: #selector(runOnboardingVerification)
    )
    verifyButton.bezelStyle = .rounded
    verifyButton.keyEquivalent = "\r"

    let buttonStack = NSStackView(views: [refreshButton, verifyButton])
    buttonStack.orientation = .horizontal
    buttonStack.alignment = .centerY
    buttonStack.spacing = 10

    let footer = NSTextField(
      wrappingLabelWithString:
        "Grant permissions to Caverno Computer Use, not Caverno. You can revoke them at any time in System Settings."
    )
    footer.font = .systemFont(ofSize: 12, weight: .regular)
    footer.textColor = .tertiaryLabelColor
    footer.alignment = .center
    footer.maximumNumberOfLines = 2

    stack.addArrangedSubview(icon)
    stack.addArrangedSubview(title)
    stack.addArrangedSubview(subtitle)
    stack.addArrangedSubview(statusSummaryLabel)
    stack.addArrangedSubview(rows)
    stack.addArrangedSubview(smokeTitle)
    stack.addArrangedSubview(smokeRows)
    stack.addArrangedSubview(buttonStack)
    stack.addArrangedSubview(footer)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 64),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -64),
      stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      icon.heightAnchor.constraint(equalToConstant: 68),
      icon.widthAnchor.constraint(equalToConstant: 68),
      rows.widthAnchor.constraint(equalTo: stack.widthAnchor),
      smokeTitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
      smokeRows.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])

    refreshPermissionRows()
    return root
  }

  private func refreshPermissionRows() {
    let permissions = computerUsePermissionSnapshot()
    helperReachableRow?.setGranted(true)
    accessibilityRow?.setGranted(permissions.accessibilityGranted)
    screenRecordingRow?.setGranted(permissions.screenCaptureGranted)
    permissionSmokeRow?.setStatus(
      permissions.accessibilityGranted && permissions.screenCaptureGranted ? .done : .waiting,
      detail: permissions.accessibilityGranted && permissions.screenCaptureGranted
        ? "Ready"
        : "Grant missing permissions"
    )
    let ready = permissions.accessibilityGranted && permissions.screenCaptureGranted
    statusSummaryLabel?.stringValue = ready
      ? "Ready for visual checks. Caverno will still ask before input or audio actions."
      : "Action required: grant the missing permissions below, then verify again."
    statusSummaryLabel?.textColor = ready ? .systemGreen : .secondaryLabelColor
  }

  @objc private func refreshFromButton() {
    refreshPermissionRows()
  }

  @objc private func runOnboardingVerification() {
    let verification = performOnboardingVerification()
    let permissionStep = verification.permissionStep
    let displayStep = verification.displayScreenshotStep
    let windowStep = verification.windowCaptureStep

    refreshPermissionRows()
    permissionSmokeRow?.setStatus(
      permissionStep.ok ? .done : .failed,
      detail: permissionStep.detail
    )

    displayScreenshotSmokeRow?.setStatus(
      displayStep.ok ? .done : .failed,
      detail: displayStep.detail
    )

    windowCaptureSmokeRow?.setStatus(
      windowStep.ok ? .done : .failed,
      detail: windowStep.detail
    )

    ipc.recordOnboardingVerification(verification.toMap())

    statusSummaryLabel?.stringValue = verification.ok
      ? "Verification complete. Caverno can observe displays and windows through this helper."
      : "Verification incomplete. Fix the failed step, then run Verify again."
    statusSummaryLabel?.textColor = verification.ok ? .systemGreen : .secondaryLabelColor
  }
}

private enum SettingsPane {
  case privacy
  case accessibility
  case screenRecording

  init?(section: String) {
    switch section.lowercased() {
    case "accessibility":
      self = .accessibility
    case "screen_capture", "screencapture", "screen_recording", "screenrecording":
      self = .screenRecording
    case "privacy":
      self = .privacy
    default:
      return nil
    }
  }

  var responseSection: String {
    switch self {
    case .privacy:
      return "privacy"
    case .accessibility:
      return "accessibility"
    case .screenRecording:
      return "screenRecording"
    }
  }

  var url: URL? {
    switch self {
    case .privacy:
      return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
    case .accessibility:
      return URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    case .screenRecording:
      return URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
      )
    }
  }
}

private func openSettingsPane(_ pane: SettingsPane) {
  guard let url = pane.url else {
    return
  }
  NSWorkspace.shared.open(url)
}

private struct PermissionSnapshot {
  let accessibilityGranted: Bool
  let screenCaptureGranted: Bool
  let systemAudioRecordingSupported: Bool

  func toMap() -> [String: Any] {
    [
      "accessibilityGranted": accessibilityGranted,
      "screenCaptureGranted": screenCaptureGranted,
      "systemAudioRecordingSupported": systemAudioRecordingSupported,
    ]
  }
}

private struct OnboardingVerificationStep {
  let id: String
  let label: String
  let ok: Bool
  let detail: String

  var status: String {
    ok ? "done" : "failed"
  }

  func toMap() -> [String: Any] {
    [
      "id": id,
      "label": label,
      "ok": ok,
      "status": status,
      "detail": detail,
    ]
  }
}

private struct OnboardingVerificationResult {
  let generatedAt: Date
  let permissions: [String: Any]
  let permissionStep: OnboardingVerificationStep
  let displayScreenshotStep: OnboardingVerificationStep
  let windowCaptureStep: OnboardingVerificationStep

  var ok: Bool {
    permissionStep.ok && displayScreenshotStep.ok && windowCaptureStep.ok
  }

  func toMap() -> [String: Any] {
    let formatter = ISO8601DateFormatter()
    let steps = [
      permissionStep,
      displayScreenshotStep,
      windowCaptureStep,
    ]
    let summary = ok ? "Verification complete" : "Verification incomplete"
    return [
      "ok": ok,
      "generatedAt": formatter.string(from: generatedAt),
      "summary": summary,
      "permissions": permissions,
      "steps": steps.map { $0.toMap() },
      "displayScreenshot": displayScreenshotStep.toMap(),
      "windowCapture": windowCaptureStep.toMap(),
    ]
  }
}

private func computerUsePermissionSnapshot() -> PermissionSnapshot {
  let screenCaptureGranted: Bool
  if #available(macOS 10.15, *) {
    screenCaptureGranted = CGPreflightScreenCaptureAccess()
  } else {
    screenCaptureGranted = true
  }

  return PermissionSnapshot(
    accessibilityGranted: AXIsProcessTrusted(),
    screenCaptureGranted: screenCaptureGranted,
    systemAudioRecordingSupported: systemAudioRecordingSupported()
  )
}

private func systemAudioRecordingSupported() -> Bool {
  if #available(macOS 13.0, *) {
    return true
  }
  return false
}

private enum ComputerUseHelperCommand: String {
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

private enum ComputerUseHelperIpcSchema {
  static let protocolVersion = 1
  static let mainAppBundleIdentifier = "com.noguwo.apps.caverno"
  static let helperBundleIdentifier = "com.noguwo.apps.caverno.computer-use"
  static let activeTransport = "distributed_notification_center"
  static let preferredTransport = "xpc_service"
  static let fallbackTransport = activeTransport
  static let xpcServiceName = "com.noguwo.apps.caverno.computer-use.xpc"
  static let xpcSupportedCommands = [
    "ping",
    "permissionStatus",
    "openSettings",
    "stopAll",
    "screenshot",
    "listWindows",
    "focusWindow",
    "screenshotWindow",
  ]
  static let xpcReady = true
  static let xpcProductionReady = false
  static let xpcStatus = "experimental_fallback"
  static let mainAppUnsafeOsActionsAllowed = false
  static let helperOwnsUnsafeOsActions = true
  static let helperOwnedActionCategories = [
    "accessibility",
    "screen_capture",
    "input_events",
    "system_audio_recording",
    "emergency_stop",
  ]
  static let xpcNextParityCommands = ["moveMouse", "click"]
  static let xpcProductionReadinessCriteria = [
    "named_service_connects_from_signed_main_app",
    "ping_permission_status_open_settings_stop_all_screenshot_list_windows_focus_window_screenshot_window_match_dnc",
    "capture_input_audio_commands_have_parity_smoke_coverage",
    "fallback_path_is_observable_and_non_destructive",
  ]
  static let requestName = Notification.Name("com.caverno.computer_use.helper.request")
  static let responseName = Notification.Name("com.caverno.computer_use.helper.response")
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

private enum ComputerUseHelperSharedDiagnostics {
  static let path = "/tmp/caverno-computer-use-helper-diagnostics.json"

  static func write(_ diagnostics: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(diagnostics) else {
      return
    }
    do {
      let data = try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
      try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
    } catch {
      NSLog("CavernoComputerUseHelperIPC shared diagnostics write failed: %@", error.localizedDescription)
    }
  }
}

private final class ComputerUseHelperXpcHandler: NSObject, CavernoComputerUseXpcProtocol {
  weak var ipc: ComputerUseHelperIpc?

  init(ipc: ComputerUseHelperIpc) {
    self.ipc = ipc
  }

  func handleRequest(_ request: NSDictionary, withReply reply: @escaping (NSDictionary) -> Void) {
    let payload = request as? [String: Any] ?? [:]
    ipc?.handleXpcRequest(payload) { response in
      reply(response as NSDictionary)
    }
  }
}

private final class ComputerUseHelperXpcListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let handler: ComputerUseHelperXpcHandler

  init(ipc: ComputerUseHelperIpc) {
    self.handler = ComputerUseHelperXpcHandler(ipc: ipc)
  }

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    newConnection.exportedInterface = NSXPCInterface(with: CavernoComputerUseXpcProtocol.self)
    newConnection.exportedObject = handler
    newConnection.resume()
    return true
  }
}

private struct ComputerUseHelperRequest {
  static let protocolVersion = ComputerUseHelperIpcSchema.protocolVersion
  static let mainAppBundleIdentifier = ComputerUseHelperIpcSchema.mainAppBundleIdentifier

  let protocolVersion: Int
  let requestId: String
  let command: ComputerUseHelperCommand
  let senderBundleIdentifier: String
  let senderProcessIdentifier: Int
  let arguments: [String: Any]

  init?(userInfo: [AnyHashable: Any]) {
    guard
      let requestId = userInfo[ComputerUseHelperIpcSchema.Field.requestId] as? String,
      let commandName = userInfo[ComputerUseHelperIpcSchema.Field.command] as? String,
      let command = ComputerUseHelperCommand(rawValue: commandName)
    else {
      return nil
    }

    self.protocolVersion = userInfo[ComputerUseHelperIpcSchema.Field.protocolVersion] as? Int ?? 0
    self.requestId = requestId
    self.command = command
    self.senderBundleIdentifier =
      userInfo[ComputerUseHelperIpcSchema.Field.senderBundleIdentifier] as? String ?? ""
    self.senderProcessIdentifier =
      intValue(userInfo[ComputerUseHelperIpcSchema.Field.senderProcessIdentifier]) ?? 0
    self.arguments = userInfo[ComputerUseHelperIpcSchema.Field.arguments] as? [String: Any] ?? [:]
  }

  var isSupportedProtocolVersion: Bool {
    protocolVersion == Self.protocolVersion
  }

  var hasTrustedSender: Bool {
    guard senderBundleIdentifier == Self.mainAppBundleIdentifier else {
      return false
    }
    guard senderProcessIdentifier > 0 else {
      return false
    }
    let application = NSRunningApplication(
      processIdentifier: pid_t(senderProcessIdentifier)
    )
    return application?.bundleIdentifier == Self.mainAppBundleIdentifier
  }
}

private final class ComputerUseHelperStatusStore {
  private let verificationKey = "lastOnboardingVerification"
  private let statusKey = "lastHelperStatus"
  private let defaults = UserDefaults.standard

  func loadVerification() -> [String: Any]? {
    defaults.dictionary(forKey: verificationKey)
  }

  func saveVerification(_ verification: [String: Any]) {
    defaults.set(verification, forKey: verificationKey)
  }

  func saveStatus(_ status: [String: Any]) {
    defaults.set(status, forKey: statusKey)
  }
}

private final class ComputerUseHelperIpc: NSObject {
  private let mainAppBundleIdentifier = ComputerUseHelperIpcSchema.mainAppBundleIdentifier
  private let helperBundleIdentifier = ComputerUseHelperIpcSchema.helperBundleIdentifier
  private let requestName = ComputerUseHelperIpcSchema.requestName
  private let responseName = ComputerUseHelperIpcSchema.responseName
  private let center = DistributedNotificationCenter.default()
  private let statusStore = ComputerUseHelperStatusStore()
  private var audioRecorder: Any?
  private var lastOnboardingVerification: [String: Any]?
  private var helperIpcEventCount = 0
  private var lastHelperIpcRequest: [String: Any]?
  private var started = false
  private var xpcListener: NSXPCListener?
  private var xpcListenerDelegate: ComputerUseHelperXpcListenerDelegate?
  private var xpcListenerStarted = false

  override init() {
    super.init()
    lastOnboardingVerification = statusStore.loadVerification()
  }

  func start() {
    guard !started else {
      writeSharedDiagnostics(event: "listener_already_started")
      return
    }
    started = true
    center.addObserver(
      self,
      selector: #selector(handleRequest(_:)),
      name: requestName,
      object: nil,
      suspensionBehavior: .deliverImmediately
    )
    center.suspended = false
    startXpcListener()
    writeSharedDiagnostics(event: "listener_started")
  }

  private func startXpcListener() {
    guard xpcListener == nil else {
      return
    }
    let listener = NSXPCListener(machServiceName: ComputerUseHelperIpcSchema.xpcServiceName)
    let delegate = ComputerUseHelperXpcListenerDelegate(ipc: self)
    listener.delegate = delegate
    listener.resume()
    xpcListener = listener
    xpcListenerDelegate = delegate
    xpcListenerStarted = true
    NSLog(
      "CavernoComputerUseHelperIPC xpc listener started service=%@",
      ComputerUseHelperIpcSchema.xpcServiceName
    )
  }

  func recordOnboardingVerification(_ verification: [String: Any]) {
    lastOnboardingVerification = verification
    statusStore.saveVerification(verification)
    writeSharedDiagnostics(event: "onboarding_verification_saved")
  }

  @objc private func handleRequest(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let requestId = userInfo[ComputerUseHelperIpcSchema.Field.requestId] as? String
    else {
      recordRequestDiagnostic(
        requestId: nil,
        commandName: nil,
        senderBundleIdentifier: nil,
        senderProcessIdentifier: nil,
        status: "invalid_notification"
      )
      return
    }

    guard let request = ComputerUseHelperRequest(userInfo: userInfo) else {
      recordRequestDiagnostic(
        requestId: requestId,
        commandName: userInfo[ComputerUseHelperIpcSchema.Field.command] as? String,
        senderBundleIdentifier: userInfo[ComputerUseHelperIpcSchema.Field.senderBundleIdentifier] as? String,
        senderProcessIdentifier: intValue(userInfo[ComputerUseHelperIpcSchema.Field.senderProcessIdentifier]),
        status: "invalid_request"
      )
      postResponse(
        requestId: requestId,
        response: errorResponse(
          code: "invalid_request",
          error: "Caverno Computer Use received an invalid helper request.",
          details: nil
        )
      )
      return
    }

    recordRequestDiagnostic(request: request, status: "received")
    NSLog(
      "CavernoComputerUseHelperIPC request received requestId=%@ command=%@ sender=%@ pid=%d",
      request.requestId,
      request.command.rawValue,
      request.senderBundleIdentifier,
      request.senderProcessIdentifier
    )

    guard request.isSupportedProtocolVersion else {
      recordRequestDiagnostic(request: request, status: "unsupported_protocol")
      postResponse(
        requestId: request.requestId,
        command: request.command,
        response: errorResponse(
          code: "unsupported_protocol",
          error: "Unsupported computer-use helper protocol version.",
          details: request.protocolVersion
        )
      )
      return
    }

    guard request.hasTrustedSender else {
      recordRequestDiagnostic(request: request, status: "untrusted_sender")
      postResponse(
        requestId: request.requestId,
        command: request.command,
        response: errorResponse(
          code: "untrusted_sender",
          error: "Caverno Computer Use only accepts commands from Caverno.",
          details: [
            "senderBundleIdentifier": request.senderBundleIdentifier,
            "senderProcessIdentifier": request.senderProcessIdentifier,
          ]
        )
      )
      return
    }

    handle(request: request) { [weak self] response in
      guard let self else {
        return
      }
      let diagnostic = self.recordRequestDiagnostic(
        request: request,
        status: response["ok"] as? Bool == false ? "response_error" : "response",
        errorCode: response["code"] as? String
      )
      var responseWithDiagnostics = response
      responseWithDiagnostics["helperIpcEventCount"] = self.helperIpcEventCount
      responseWithDiagnostics["lastHelperIpcRequest"] = diagnostic
      self.postResponse(
        requestId: requestId,
        command: request.command,
        response: responseWithDiagnostics
      )
    }
  }

  func handleXpcRequest(_ payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
    let userInfo = payload.reduce(into: [AnyHashable: Any]()) { partial, entry in
      partial[AnyHashable(entry.key)] = entry.value
    }
    guard let request = ComputerUseHelperRequest(userInfo: userInfo) else {
      recordRequestDiagnostic(
        requestId: payload[ComputerUseHelperIpcSchema.Field.requestId] as? String,
        commandName: payload[ComputerUseHelperIpcSchema.Field.command] as? String,
        senderBundleIdentifier: payload[ComputerUseHelperIpcSchema.Field.senderBundleIdentifier] as? String,
        senderProcessIdentifier: intValue(payload[ComputerUseHelperIpcSchema.Field.senderProcessIdentifier]),
        status: "xpc_invalid_request"
      )
      completion(
        errorResponse(
          code: "invalid_request",
          error: "Caverno Computer Use received an invalid XPC helper request.",
          details: nil
        )
      )
      return
    }

    recordRequestDiagnostic(request: request, status: "xpc_received")
    NSLog(
      "CavernoComputerUseHelperIPC xpc request received requestId=%@ command=%@ sender=%@ pid=%d",
      request.requestId,
      request.command.rawValue,
      request.senderBundleIdentifier,
      request.senderProcessIdentifier
    )

    guard request.isSupportedProtocolVersion else {
      recordRequestDiagnostic(request: request, status: "xpc_unsupported_protocol")
      completion(
        errorResponse(
          code: "unsupported_protocol",
          error: "Unsupported computer-use helper protocol version.",
          details: request.protocolVersion
        )
      )
      return
    }

    guard request.hasTrustedSender else {
      recordRequestDiagnostic(request: request, status: "xpc_untrusted_sender")
      completion(
        errorResponse(
          code: "untrusted_sender",
          error: "Caverno Computer Use only accepts commands from Caverno.",
          details: [
            "senderBundleIdentifier": request.senderBundleIdentifier,
            "senderProcessIdentifier": request.senderProcessIdentifier,
          ]
        )
      )
      return
    }

    guard ComputerUseHelperIpcSchema.xpcSupportedCommands.contains(request.command.rawValue) else {
      recordRequestDiagnostic(request: request, status: "xpc_unsupported_command")
      completion(
        errorResponse(
          code: "unsupported_command",
          error: "This command is not available over XPC.",
          details: request.command.rawValue
        )
      )
      return
    }

    handle(request: request) { [weak self] response in
      guard let self else {
        completion(response)
        return
      }
      let diagnostic = self.recordRequestDiagnostic(
        request: request,
        status: response["ok"] as? Bool == false ? "xpc_response_error" : "xpc_response",
        errorCode: response["code"] as? String
      )
      var responseWithDiagnostics = response
      responseWithDiagnostics["helperIpcEventCount"] = self.helperIpcEventCount
      responseWithDiagnostics["lastHelperIpcRequest"] = diagnostic
      responseWithDiagnostics["selectedIpcTransport"] = ComputerUseHelperIpcSchema.preferredTransport
      completion(responseWithDiagnostics)
    }
  }

  private func handle(
    request: ComputerUseHelperRequest,
    completion: @escaping ([String: Any]) -> Void
  ) {
    switch request.command {
    case .ping:
      completion(baseResponse(extra: ["message": "pong"]))
    case .permissionStatus:
      completion(permissionStatus())
    case .openSettings:
      completion(openSettings(arguments: request.arguments))
    case .stopAll:
      stopAll(completion: completion)
    case .screenshot:
      completion(screenshot(arguments: request.arguments))
    case .listWindows:
      completion(listWindows(arguments: request.arguments))
    case .focusWindow:
      completion(focusWindow(arguments: request.arguments))
    case .screenshotWindow:
      completion(screenshotWindow(arguments: request.arguments))
    case .moveMouse:
      completion(moveMouse(arguments: request.arguments))
    case .click:
      completion(click(arguments: request.arguments))
    case .drag:
      completion(drag(arguments: request.arguments))
    case .scroll:
      completion(scroll(arguments: request.arguments))
    case .typeText:
      completion(typeText(arguments: request.arguments))
    case .pressKey:
      completion(pressKey(arguments: request.arguments))
    case .startSystemAudioRecording:
      startSystemAudioRecording(arguments: request.arguments, completion: completion)
    case .stopSystemAudioRecording:
      stopSystemAudioRecording(completion: completion)
    }
  }

  private func permissionStatus() -> [String: Any] {
    var response = baseResponse()
    for (key, value) in computerUsePermissionSnapshot().toMap() {
      response[key] = value
    }
    return response
  }

  private func openSettings(arguments: [String: Any]) -> [String: Any] {
    let section = arguments["section"] as? String ?? "privacy"
    guard let pane = SettingsPane(section: section), let url = pane.url else {
      return errorResponse(
        code: "invalid_args",
        error: "section must be accessibility, screen_recording, or privacy",
        details: section
      )
    }

    let opened = NSWorkspace.shared.open(url)
    return baseResponse(
      ok: opened,
      extra: [
        "section": pane.responseSection,
        "url": url.absoluteString,
      ]
    )
  }

  private func stopAll(completion: @escaping ([String: Any]) -> Void) {
    guard audioRecorder != nil else {
      completion(
        baseResponse(
          extra: [
            "stoppedAudioRecording": false,
            "cancelledInputEvents": true,
          ]
        )
      )
      return
    }

    stopSystemAudioRecording { response in
      var merged = response
      merged["stoppedAudioRecording"] = response["ok"] as? Bool == true
      merged["cancelledInputEvents"] = true
      completion(merged)
    }
  }

  private func screenshot(arguments: [String: Any]) -> [String: Any] {
    guard let screen = resolveScreen(arguments: arguments) else {
      return errorResponse(code: "display_not_found", error: "No display is available")
    }

    guard let image = CGDisplayCreateImage(screen.displayID) else {
      return errorResponse(
        code: "screenshot_failed",
        error: "Failed to capture the display. Grant Screen Recording permission in System Settings."
      )
    }

    do {
      let encodedImage = try encodePng(
        image: image,
        maxWidth: intValue(arguments["max_width"] ?? arguments["maxWidth"])
      )
      return baseResponse(
        extra: [
          "imageBase64": encodedImage.base64,
          "imageMimeType": "image/png",
          "width": encodedImage.width,
          "height": encodedImage.height,
          "displayId": screen.displayID,
          "displayBounds": rectMap(screen.bounds),
          "coordinateSpace": "screenshot_pixels",
          "inputOrigin": "top_left",
          "xScaleToDisplay": screen.bounds.width / CGFloat(encodedImage.width),
          "yScaleToDisplay": screen.bounds.height / CGFloat(encodedImage.height),
        ]
      )
    } catch {
      return errorResponse(
        code: "image_encode_failed",
        error: "Failed to encode the screenshot.",
        details: error.localizedDescription
      )
    }
  }

  private func listWindows(arguments: [String: Any]) -> [String: Any] {
    let includeCurrentApp =
      boolValue(arguments["include_current_app"] ?? arguments["includeCurrentApp"]) ?? false
    let maxWindows = max(1, min(intValue(arguments["max_windows"] ?? arguments["maxWindows"]) ?? 80, 200))
    let helperPid = Int(ProcessInfo.processInfo.processIdentifier)
    let mainAppPid = intValue(arguments["main_app_pid"] ?? arguments["mainAppPid"])
    let windows = visibleWindows()
      .filter { window in
        includeCurrentApp ||
          (window.ownerPID != helperPid && window.ownerPID != mainAppPid)
      }
      .prefix(maxWindows)
      .map { $0.toMap() }

    return baseResponse(
      extra: [
        "windows": Array(windows),
        "count": windows.count,
        "coordinateSpace": "window_pixels",
        "inputOrigin": "top_left",
      ]
    )
  }

  private func focusWindow(arguments: [String: Any]) -> [String: Any] {
    guard let windowID = windowID(arguments: arguments) else {
      return errorResponse(code: "invalid_args", error: "window_id is required")
    }
    guard let window = findWindow(windowID: windowID) else {
      return errorResponse(
        code: "window_not_found",
        error: "No matching window is available.",
        details: windowID
      )
    }
    guard AXIsProcessTrusted() else {
      return accessibilityDeniedResponse()
    }

    let app = NSRunningApplication(processIdentifier: pid_t(window.ownerPID))
    app?.activate(options: [.activateIgnoringOtherApps])

    let appElement = AXUIElementCreateApplication(pid_t(window.ownerPID))
    var focused = false
    if let axWindow = findAccessibilityWindow(appElement: appElement, windowID: windowID) {
      AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
      let setResult = AXUIElementSetAttributeValue(
        appElement,
        kAXFocusedWindowAttribute as CFString,
        axWindow
      )
      focused = setResult == .success
    }

    return baseResponse(
      extra: [
        "ok": focused || app != nil,
        "windowId": window.windowID,
        "ownerPid": window.ownerPID,
        "appName": window.ownerName,
        "title": window.title,
        "focusedWindow": focused,
      ]
    )
  }

  private func screenshotWindow(arguments: [String: Any]) -> [String: Any] {
    guard let windowID = windowID(arguments: arguments) else {
      return errorResponse(code: "invalid_args", error: "window_id is required")
    }
    guard let window = findWindow(windowID: windowID) else {
      return errorResponse(
        code: "window_not_found",
        error: "No matching window is available.",
        details: windowID
      )
    }

    guard let image = CGWindowListCreateImage(
      .null,
      .optionIncludingWindow,
      CGWindowID(windowID),
      [.boundsIgnoreFraming, .bestResolution]
    ) else {
      return errorResponse(
        code: "screenshot_failed",
        error: "Failed to capture the window. Grant Screen Recording permission in System Settings.",
        details: windowID
      )
    }

    do {
      let encodedImage = try encodePng(
        image: image,
        maxWidth: intValue(arguments["max_width"] ?? arguments["maxWidth"])
      )
      return baseResponse(
        extra: [
          "imageBase64": encodedImage.base64,
          "imageMimeType": "image/png",
          "width": encodedImage.width,
          "height": encodedImage.height,
          "windowId": window.windowID,
          "ownerPid": window.ownerPID,
          "appName": window.ownerName,
          "title": window.title,
          "windowBounds": rectMap(window.bounds),
          "coordinateSpace": "window_pixels",
          "inputOrigin": "top_left",
          "xScaleToWindow": window.bounds.width / CGFloat(encodedImage.width),
          "yScaleToWindow": window.bounds.height / CGFloat(encodedImage.height),
        ]
      )
    } catch {
      return errorResponse(
        code: "image_encode_failed",
        error: "Failed to encode the window screenshot.",
        details: error.localizedDescription
      )
    }
  }

  private func click(arguments: [String: Any]) -> [String: Any] {
    guard AXIsProcessTrusted() else {
      return accessibilityDeniedResponse()
    }
    guard let point = resolvePoint(arguments: arguments) else {
      return errorResponse(code: "invalid_args", error: "x and y are required")
    }

    let buttonName = (arguments["button"] as? String ?? "left").lowercased()
    let clickCount = max(1, min(intValue(arguments["click_count"] ?? arguments["clickCount"]) ?? 1, 3))
    let button = mouseButton(buttonName)
    let downType = mouseDownType(buttonName)
    let upType = mouseUpType(buttonName)

    for _ in 0..<clickCount {
      postMouseEvent(type: downType, point: point, button: button)
      postMouseEvent(type: upType, point: point, button: button)
      usleep(60_000)
    }

    return baseResponse(
      extra: [
        "x": Double(point.x),
        "y": Double(point.y),
        "button": buttonName,
        "clickCount": clickCount,
      ]
    )
  }

  private func moveMouse(arguments: [String: Any]) -> [String: Any] {
    guard AXIsProcessTrusted() else {
      return accessibilityDeniedResponse()
    }
    guard let point = resolvePoint(arguments: arguments) else {
      return errorResponse(code: "invalid_args", error: "x and y are required")
    }

    postMouseEvent(type: .mouseMoved, point: point, button: .left)
    return baseResponse(extra: ["x": Double(point.x), "y": Double(point.y)])
  }

  private func drag(arguments: [String: Any]) -> [String: Any] {
    guard AXIsProcessTrusted() else {
      return accessibilityDeniedResponse()
    }
    guard
      let fromX = number(arguments["from_x"] ?? arguments["fromX"]),
      let fromY = number(arguments["from_y"] ?? arguments["fromY"]),
      let toX = number(arguments["to_x"] ?? arguments["toX"]),
      let toY = number(arguments["to_y"] ?? arguments["toY"])
    else {
      return errorResponse(
        code: "invalid_args",
        error: "from_x, from_y, to_x, and to_y are required"
      )
    }

    var fromArguments = arguments
    fromArguments["x"] = fromX
    fromArguments["y"] = fromY
    var toArguments = arguments
    toArguments["x"] = toX
    toArguments["y"] = toY

    guard
      let fromPoint = resolvePoint(arguments: fromArguments),
      let toPoint = resolvePoint(arguments: toArguments)
    else {
      return errorResponse(
        code: "invalid_args",
        error: "Unable to resolve drag coordinates"
      )
    }

    let durationMs = max(
      50,
      min(intValue(arguments["duration_ms"] ?? arguments["durationMs"]) ?? 300, 3000)
    )
    let steps = max(4, min(durationMs / 16, 120))
    postMouseEvent(type: .leftMouseDown, point: fromPoint, button: .left)
    for step in 1...steps {
      let t = CGFloat(step) / CGFloat(steps)
      let point = CGPoint(
        x: fromPoint.x + (toPoint.x - fromPoint.x) * t,
        y: fromPoint.y + (toPoint.y - fromPoint.y) * t
      )
      postMouseEvent(type: .leftMouseDragged, point: point, button: .left)
      usleep(useconds_t(durationMs * 1000 / steps))
    }
    postMouseEvent(type: .leftMouseUp, point: toPoint, button: .left)

    return baseResponse(
      extra: [
        "from": pointMap(fromPoint),
        "to": pointMap(toPoint),
        "durationMs": durationMs,
      ]
    )
  }

  private func scroll(arguments: [String: Any]) -> [String: Any] {
    guard AXIsProcessTrusted() else {
      return accessibilityDeniedResponse()
    }
    if let point = resolvePoint(arguments: arguments) {
      postMouseEvent(type: .mouseMoved, point: point, button: .left)
    }

    let deltaX = Int(number(arguments["delta_x"] ?? arguments["deltaX"]) ?? 0)
    let deltaY = Int(number(arguments["delta_y"] ?? arguments["deltaY"]) ?? -5)
    guard let event = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .line,
      wheelCount: 2,
      wheel1: Int32(deltaY),
      wheel2: Int32(deltaX),
      wheel3: 0
    ) else {
      return errorResponse(code: "event_failed", error: "Failed to create scroll event")
    }
    event.post(tap: .cghidEventTap)
    return baseResponse(extra: ["deltaX": deltaX, "deltaY": deltaY])
  }

  private func typeText(arguments: [String: Any]) -> [String: Any] {
    guard AXIsProcessTrusted() else {
      return accessibilityDeniedResponse()
    }
    guard let text = arguments["text"] as? String, !text.isEmpty else {
      return errorResponse(code: "invalid_args", error: "text is required")
    }

    for character in text {
      var units = Array(String(character).utf16)
      guard !units.isEmpty else {
        continue
      }
      guard
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
      else {
        continue
      }
      units.withUnsafeMutableBufferPointer { buffer in
        down.keyboardSetUnicodeString(
          stringLength: buffer.count,
          unicodeString: buffer.baseAddress
        )
        up.keyboardSetUnicodeString(
          stringLength: buffer.count,
          unicodeString: buffer.baseAddress
        )
      }
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
      usleep(10_000)
    }

    return baseResponse(extra: ["characters": text.count])
  }

  private func pressKey(arguments: [String: Any]) -> [String: Any] {
    guard AXIsProcessTrusted() else {
      return accessibilityDeniedResponse()
    }
    guard
      let rawKey = arguments["key"] as? String,
      let keyCode = keyCodes[rawKey.lowercased()]
    else {
      return errorResponse(
        code: "invalid_args",
        error: "Unsupported key",
        details: arguments["key"]
      )
    }

    let flags = eventFlags(arguments["modifiers"] as? [String] ?? [])
    guard
      let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else {
      return errorResponse(code: "event_failed", error: "Failed to create key event")
    }

    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return baseResponse(
      extra: [
        "key": rawKey,
        "modifiers": arguments["modifiers"] as? [String] ?? [],
      ]
    )
  }

  private func startSystemAudioRecording(
    arguments: [String: Any],
    completion: @escaping ([String: Any]) -> Void
  ) {
    guard systemAudioRecordingSupported() else {
      completion(
        errorResponse(
          code: "unsupported",
          error: "System audio recording requires macOS 13 or later."
        )
      )
      return
    }
    guard audioRecorder == nil else {
      completion(
        errorResponse(
          code: "already_recording",
          error: "System audio recording is already active."
        )
      )
      return
    }

    let outputPath = arguments["output_path"] as? String
      ?? arguments["outputPath"] as? String
    let excludeCurrentProcessAudio =
      boolValue(
        arguments["exclude_current_process_audio"]
          ?? arguments["excludeCurrentProcessAudio"]
      ) ?? true

    if #available(macOS 13.0, *) {
      let recorder = SystemAudioRecorder()
      audioRecorder = recorder
      recorder.start(
        outputPath: outputPath,
        excludeCurrentProcessAudio: excludeCurrentProcessAudio
      ) { [weak self] response in
        if response["ok"] as? Bool != true {
          self?.audioRecorder = nil
        }
        completion(self?.audioResponse(response) ?? response)
      }
    }
  }

  private func stopSystemAudioRecording(
    completion: @escaping ([String: Any]) -> Void
  ) {
    guard let recorder = audioRecorder else {
      completion(
        errorResponse(
          code: "not_recording",
          error: "System audio recording is not active."
        )
      )
      return
    }

    if #available(macOS 13.0, *), let typedRecorder = recorder as? SystemAudioRecorder {
      typedRecorder.stop { [weak self] response in
        guard let self else {
          completion(response)
          return
        }
        self.audioRecorder = nil
        completion(self.audioResponse(response))
      }
    } else {
      audioRecorder = nil
      completion(
        errorResponse(
          code: "unsupported",
          error: "System audio recording requires macOS 13 or later."
        )
      )
    }
  }

  private func audioResponse(_ response: [String: Any]) -> [String: Any] {
    var merged = baseResponse(ok: response["ok"] as? Bool ?? false)
    for (key, value) in response {
      merged[key] = value
    }
    return merged
  }

  private func baseResponse(ok: Bool = true, extra: [String: Any] = [:]) -> [String: Any] {
    let audioRecordingActive = audioRecorder != nil
    let activeWork = [
      "systemAudioRecording": audioRecordingActive,
    ]
    let persistedStatus = persistedStatusSnapshot(activeWork: activeWork)
    statusStore.saveStatus(persistedStatus)
    var response: [String: Any] = [
      "ok": ok,
      "backend": "helper",
      "protocolVersion": ComputerUseHelperIpcSchema.protocolVersion,
      "helperDisplayName": "Caverno Computer Use",
      "helperBundleIdentifier": ComputerUseHelperIpcSchema.helperBundleIdentifier,
      "ipcTransport": ComputerUseHelperIpcSchema.activeTransport,
      "selectedIpcTransport": ComputerUseHelperIpcSchema.activeTransport,
      "preferredIpcTransport": ComputerUseHelperIpcSchema.preferredTransport,
      "fallbackIpcTransport": ComputerUseHelperIpcSchema.fallbackTransport,
      "requestObject": ComputerUseHelperIpcSchema.mainAppBundleIdentifier,
      "responseObject": ComputerUseHelperIpcSchema.helperBundleIdentifier,
      "requestNotificationName": ComputerUseHelperIpcSchema.requestName.rawValue,
      "responseNotificationName": ComputerUseHelperIpcSchema.responseName.rawValue,
      "requestEnvelope": ComputerUseHelperIpcSchema.requestEnvelope,
      "responseEnvelope": ComputerUseHelperIpcSchema.responseEnvelope,
      "xpcServiceName": ComputerUseHelperIpcSchema.xpcServiceName,
      "xpcSupportedCommands": ComputerUseHelperIpcSchema.xpcSupportedCommands,
      "xpcReady": ComputerUseHelperIpcSchema.xpcReady,
      "xpcProductionReady": ComputerUseHelperIpcSchema.xpcProductionReady,
      "xpcStatus": ComputerUseHelperIpcSchema.xpcStatus,
      "mainAppUnsafeOsActionsAllowed": ComputerUseHelperIpcSchema.mainAppUnsafeOsActionsAllowed,
      "helperOwnsUnsafeOsActions": ComputerUseHelperIpcSchema.helperOwnsUnsafeOsActions,
      "helperOwnedActionCategories": ComputerUseHelperIpcSchema.helperOwnedActionCategories,
      "xpcNextParityCommands": ComputerUseHelperIpcSchema.xpcNextParityCommands,
      "xpcProductionReadinessCriteria": ComputerUseHelperIpcSchema.xpcProductionReadinessCriteria,
      "xpcListenerStarted": xpcListenerStarted,
      "audioRecordingActive": audioRecordingActive,
      "activeWork": activeWork,
      "helperStatusPersistence": persistedStatus,
      "helperIpcEventCount": helperIpcEventCount,
      "helperSharedDiagnosticsPath": ComputerUseHelperSharedDiagnostics.path,
    ]
    if let lastHelperIpcRequest {
      response["lastHelperIpcRequest"] = lastHelperIpcRequest
    }
    if let lastOnboardingVerification {
      response["onboardingVerification"] = lastOnboardingVerification
    }
    for (key, value) in extra {
      response[key] = value
    }
    return response
  }

  private func persistedStatusSnapshot(activeWork: [String: Bool]) -> [String: Any] {
    let formatter = ISO8601DateFormatter()
    var status: [String: Any] = [
      "updatedAt": formatter.string(from: Date()),
      "activeWork": activeWork,
    ]
    if let lastOnboardingVerification {
      status["onboardingVerification"] = lastOnboardingVerification
    }
    return status
  }

  private func errorResponse(
    code: String,
    error: String,
    details: Any? = nil
  ) -> [String: Any] {
    var response = baseResponse(ok: false)
    response["code"] = code
    response["error"] = error
    if let details {
      response["details"] = details
    }
    return response
  }

  private func accessibilityDeniedResponse() -> [String: Any] {
    errorResponse(
      code: "accessibility_denied",
      error: "Accessibility permission is required. Grant Caverno Computer Use in System Settings > Privacy & Security > Accessibility."
    )
  }

  private func postResponse(
    requestId: String,
    command: ComputerUseHelperCommand? = nil,
    response: [String: Any]
  ) {
    var userInfo: [String: Any] = [
      ComputerUseHelperIpcSchema.Field.protocolVersion: ComputerUseHelperRequest.protocolVersion,
      ComputerUseHelperIpcSchema.Field.requestId: requestId,
      ComputerUseHelperIpcSchema.Field.response: response,
    ]
    if let command {
      userInfo[ComputerUseHelperIpcSchema.Field.command] = command.rawValue
    }

    center.postNotificationName(
      responseName,
      object: helperBundleIdentifier,
      userInfo: userInfo,
      deliverImmediately: true
    )
    NSLog(
      "CavernoComputerUseHelperIPC response posted requestId=%@ command=%@",
      requestId,
      command?.rawValue ?? "unknown"
    )
  }

  @discardableResult
  private func recordRequestDiagnostic(
    request: ComputerUseHelperRequest,
    status: String,
    errorCode: String? = nil
  ) -> [String: Any] {
    return recordRequestDiagnostic(
      requestId: request.requestId,
      commandName: request.command.rawValue,
      senderBundleIdentifier: request.senderBundleIdentifier,
      senderProcessIdentifier: request.senderProcessIdentifier,
      status: status,
      errorCode: errorCode
    )
  }

  @discardableResult
  private func recordRequestDiagnostic(
    requestId: String?,
    commandName: String?,
    senderBundleIdentifier: String?,
    senderProcessIdentifier: Int?,
    status: String,
    errorCode: String? = nil
  ) -> [String: Any] {
    helperIpcEventCount += 1
    var diagnostic: [String: Any] = [
      "sequence": helperIpcEventCount,
      "status": status,
      "receivedAt": ISO8601DateFormatter().string(from: Date()),
      "expectedSenderBundleIdentifier": mainAppBundleIdentifier,
      "helperBundleIdentifier": helperBundleIdentifier,
      "ipcTransport": ComputerUseHelperIpcSchema.activeTransport,
    ]
    if let requestId {
      diagnostic["requestId"] = requestId
    }
    if let commandName {
      diagnostic["command"] = commandName
    }
    if let senderBundleIdentifier {
      diagnostic["senderBundleIdentifier"] = senderBundleIdentifier
    }
    if let senderProcessIdentifier {
      diagnostic["senderProcessIdentifier"] = senderProcessIdentifier
    }
    if let errorCode {
      diagnostic["errorCode"] = errorCode
    }
    lastHelperIpcRequest = diagnostic
    writeSharedDiagnostics(event: "ipc_event")
    return diagnostic
  }

  private func writeSharedDiagnostics(event: String) {
    var diagnostics: [String: Any] = [
      "schemaName": "caverno_computer_use_helper_diagnostics",
      "schemaVersion": 1,
      "event": event,
      "generatedAt": ISO8601DateFormatter().string(from: Date()),
      "helperBundleIdentifier": helperBundleIdentifier,
      "helperProcessIdentifier": Int(ProcessInfo.processInfo.processIdentifier),
      "listenerStarted": true,
      "requestNotificationName": requestName.rawValue,
      "responseNotificationName": responseName.rawValue,
      "ipcTransport": ComputerUseHelperIpcSchema.activeTransport,
      "preferredIpcTransport": ComputerUseHelperIpcSchema.preferredTransport,
      "fallbackIpcTransport": ComputerUseHelperIpcSchema.fallbackTransport,
      "xpcReady": ComputerUseHelperIpcSchema.xpcReady,
      "xpcProductionReady": ComputerUseHelperIpcSchema.xpcProductionReady,
      "xpcStatus": ComputerUseHelperIpcSchema.xpcStatus,
      "mainAppUnsafeOsActionsAllowed": ComputerUseHelperIpcSchema.mainAppUnsafeOsActionsAllowed,
      "helperOwnsUnsafeOsActions": ComputerUseHelperIpcSchema.helperOwnsUnsafeOsActions,
      "helperOwnedActionCategories": ComputerUseHelperIpcSchema.helperOwnedActionCategories,
      "xpcNextParityCommands": ComputerUseHelperIpcSchema.xpcNextParityCommands,
      "xpcProductionReadinessCriteria": ComputerUseHelperIpcSchema.xpcProductionReadinessCriteria,
      "xpcListenerStarted": xpcListenerStarted,
      "helperIpcEventCount": helperIpcEventCount,
    ]
    if let lastHelperIpcRequest {
      diagnostics["lastHelperIpcRequest"] = lastHelperIpcRequest
    }
    if let lastOnboardingVerification {
      diagnostics["onboardingVerification"] = lastOnboardingVerification
    }
    ComputerUseHelperSharedDiagnostics.write(diagnostics)
  }
}

private func resolveScreen(arguments: [String: Any]) -> ScreenDescriptor? {
  let requestedDisplayId = directDisplayIdValue(arguments["display_id"] ?? arguments["displayId"])
  let screens = NSScreen.screens
  if let requestedDisplayId {
    for screen in screens {
      if screen.displayID == requestedDisplayId {
        return ScreenDescriptor(screen: screen)
      }
    }
    return nil
  }
  return NSScreen.main.map(ScreenDescriptor.init(screen:))
}

private func visibleWindows() -> [WindowDescriptor] {
  guard
    let windowInfoList = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]]
  else {
    return []
  }

  return windowInfoList.compactMap { info in
    guard
      let windowID = intValue(info[kCGWindowNumber as String]),
      let ownerPID = intValue(info[kCGWindowOwnerPID as String]),
      let ownerName = info[kCGWindowOwnerName as String] as? String,
      let layer = intValue(info[kCGWindowLayer as String]),
      layer == 0,
      let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
      let bounds = CGRect(dictionaryRepresentation: boundsInfo),
      bounds.width >= 32,
      bounds.height >= 32
    else {
      return nil
    }

    let alpha = number(info[kCGWindowAlpha as String]) ?? 1
    if alpha <= 0 {
      return nil
    }

    return WindowDescriptor(
      windowID: windowID,
      ownerPID: ownerPID,
      ownerName: ownerName,
      title: info[kCGWindowName as String] as? String ?? "",
      bounds: bounds,
      layer: layer,
      alpha: Double(alpha),
      isOnScreen: (info[kCGWindowIsOnscreen as String] as? Bool) ?? true
    )
  }
}

private func performOnboardingVerification() -> OnboardingVerificationResult {
  let permissions = computerUsePermissionSnapshot()
  let permissionsReady = permissions.accessibilityGranted && permissions.screenCaptureGranted
  let permissionStep = OnboardingVerificationStep(
    id: "permissions",
    label: "Permissions",
    ok: permissionsReady,
    detail: permissionsReady ? "Ready" : "Missing permissions"
  )
  return OnboardingVerificationResult(
    generatedAt: Date(),
    permissions: permissions.toMap(),
    permissionStep: permissionStep,
    displayScreenshotStep: verifyOnboardingDisplayScreenshot(),
    windowCaptureStep: verifyOnboardingWindowCapture()
  )
}

private func verifyOnboardingDisplayScreenshot() -> OnboardingVerificationStep {
  guard let screen = NSScreen.main else {
    return OnboardingVerificationStep(
      id: "display_screenshot",
      label: "Display Screenshot",
      ok: false,
      detail: "No display"
    )
  }
  guard let image = CGDisplayCreateImage(screen.displayID) else {
    return OnboardingVerificationStep(
      id: "display_screenshot",
      label: "Display Screenshot",
      ok: false,
      detail: "Screen Recording required"
    )
  }
  if image.width <= 0 || image.height <= 0 {
    return OnboardingVerificationStep(
      id: "display_screenshot",
      label: "Display Screenshot",
      ok: false,
      detail: "Empty image"
    )
  }
  return OnboardingVerificationStep(
    id: "display_screenshot",
    label: "Display Screenshot",
    ok: true,
    detail: "\(image.width) x \(image.height) px"
  )
}

private func verifyOnboardingWindowCapture() -> OnboardingVerificationStep {
  let helperPid = Int(ProcessInfo.processInfo.processIdentifier)
  let candidates = visibleWindows()
  guard let window = candidates.first(where: { $0.ownerPID != helperPid }) ?? candidates.first else {
    return OnboardingVerificationStep(
      id: "window_capture",
      label: "Window Capture",
      ok: false,
      detail: "No visible window"
    )
  }
  guard let image = CGWindowListCreateImage(
    .null,
    .optionIncludingWindow,
    CGWindowID(window.windowID),
    [.boundsIgnoreFraming, .bestResolution]
  ) else {
    return OnboardingVerificationStep(
      id: "window_capture",
      label: "Window Capture",
      ok: false,
      detail: "Window capture failed"
    )
  }
  if image.width <= 0 || image.height <= 0 {
    return OnboardingVerificationStep(
      id: "window_capture",
      label: "Window Capture",
      ok: false,
      detail: "Empty image"
    )
  }
  return OnboardingVerificationStep(
    id: "window_capture",
    label: "Window Capture",
    ok: true,
    detail: "\(window.ownerName) #\(window.windowID)"
  )
}

private func findWindow(windowID: Int) -> WindowDescriptor? {
  visibleWindows().first { $0.windowID == windowID }
}

private func findAccessibilityWindow(
  appElement: AXUIElement,
  windowID: Int
) -> AXUIElement? {
  var value: CFTypeRef?
  let copyResult = AXUIElementCopyAttributeValue(
    appElement,
    kAXWindowsAttribute as CFString,
    &value
  )
  guard copyResult == .success, let windows = value as? [AXUIElement] else {
    return nil
  }

  for window in windows {
    var rawWindowID: CFTypeRef?
    let idResult = AXUIElementCopyAttributeValue(
      window,
      "AXWindowNumber" as CFString,
      &rawWindowID
    )
    if idResult == .success,
       let number = rawWindowID as? NSNumber,
       number.intValue == windowID {
      return window
    }
  }
  return nil
}

private func windowID(arguments: [String: Any]) -> Int? {
  intValue(arguments["window_id"] ?? arguments["windowId"])
}

private func resolvePoint(arguments: [String: Any]) -> CGPoint? {
  guard
    let x = number(arguments["x"]),
    let y = number(arguments["y"])
  else {
    return nil
  }

  if let windowID = windowID(arguments: arguments),
     let window = findWindow(windowID: windowID) {
    let sourceWidth = number(arguments["source_width"] ?? arguments["sourceWidth"])
    let sourceHeight = number(arguments["source_height"] ?? arguments["sourceHeight"])
    let xScale = sourceWidth == nil || sourceWidth == 0
      ? 1
      : window.bounds.width / sourceWidth!
    let yScale = sourceHeight == nil || sourceHeight == 0
      ? 1
      : window.bounds.height / sourceHeight!
    return CGPoint(
      x: window.bounds.origin.x + x * xScale,
      y: window.bounds.origin.y + y * yScale
    )
  }

  guard let screen = resolveScreen(arguments: arguments) else {
    return nil
  }

  let sourceWidth = number(arguments["source_width"] ?? arguments["sourceWidth"])
  let sourceHeight = number(arguments["source_height"] ?? arguments["sourceHeight"])
  let xScale = sourceWidth == nil || sourceWidth == 0
    ? screen.bounds.width / CGFloat(CGDisplayPixelsWide(screen.displayID))
    : screen.bounds.width / sourceWidth!
  let yScale = sourceHeight == nil || sourceHeight == 0
    ? screen.bounds.height / CGFloat(CGDisplayPixelsHigh(screen.displayID))
    : screen.bounds.height / sourceHeight!

  return CGPoint(
    x: screen.bounds.origin.x + x * xScale,
    y: screen.bounds.origin.y + y * yScale
  )
}

private func encodePng(image: CGImage, maxWidth: Int?) throws -> EncodedImage {
  let targetImage: CGImage
  if let maxWidth, maxWidth > 0, image.width > maxWidth {
    let scale = CGFloat(maxWidth) / CGFloat(image.width)
    let targetWidth = maxWidth
    let targetHeight = max(1, Int(CGFloat(image.height) * scale))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw ComputerUseError.imageResizeFailed
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    guard let resized = context.makeImage() else {
      throw ComputerUseError.imageResizeFailed
    }
    targetImage = resized
  } else {
    targetImage = image
  }

  let bitmap = NSBitmapImageRep(cgImage: targetImage)
  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    throw ComputerUseError.imageEncodeFailed
  }
  return EncodedImage(
    base64: data.base64EncodedString(),
    width: targetImage.width,
    height: targetImage.height
  )
}

private func intValue(_ value: Any?) -> Int? {
  if let value = value as? Int {
    return value
  }
  if let value = value as? UInt32 {
    return Int(value)
  }
  if let value = value as? Double {
    return Int(value)
  }
  if let value = value as? NSNumber {
    return value.intValue
  }
  return nil
}

private func directDisplayIdValue(_ value: Any?) -> CGDirectDisplayID? {
  guard let intValue = intValue(value), intValue >= 0 else {
    return nil
  }
  return CGDirectDisplayID(intValue)
}

private func boolValue(_ value: Any?) -> Bool? {
  if let value = value as? Bool {
    return value
  }
  if let value = value as? NSNumber {
    return value.boolValue
  }
  return nil
}

private func number(_ value: Any?) -> CGFloat? {
  if let value = value as? CGFloat {
    return value
  }
  if let value = value as? Double {
    return CGFloat(value)
  }
  if let value = value as? Int {
    return CGFloat(value)
  }
  if let value = value as? NSNumber {
    return CGFloat(truncating: value)
  }
  return nil
}

private func postMouseEvent(type: CGEventType, point: CGPoint, button: CGMouseButton) {
  let event = CGEvent(
    mouseEventSource: nil,
    mouseType: type,
    mouseCursorPosition: point,
    mouseButton: button
  )
  event?.post(tap: .cghidEventTap)
}

private func mouseButton(_ value: String) -> CGMouseButton {
  switch value {
  case "right":
    return .right
  case "middle":
    return .center
  default:
    return .left
  }
}

private func mouseDownType(_ value: String) -> CGEventType {
  switch value {
  case "right":
    return .rightMouseDown
  case "middle":
    return .otherMouseDown
  default:
    return .leftMouseDown
  }
}

private func mouseUpType(_ value: String) -> CGEventType {
  switch value {
  case "right":
    return .rightMouseUp
  case "middle":
    return .otherMouseUp
  default:
    return .leftMouseUp
  }
}

private func eventFlags(_ modifiers: [String]) -> CGEventFlags {
  var flags = CGEventFlags()
  for modifier in modifiers.map({ $0.lowercased() }) {
    switch modifier {
    case "cmd", "command", "meta":
      flags.insert(.maskCommand)
    case "shift":
      flags.insert(.maskShift)
    case "option", "alt":
      flags.insert(.maskAlternate)
    case "ctrl", "control":
      flags.insert(.maskControl)
    default:
      continue
    }
  }
  return flags
}

private func rectMap(_ rect: CGRect) -> [String: Double] {
  [
    "x": Double(rect.origin.x),
    "y": Double(rect.origin.y),
    "width": Double(rect.width),
    "height": Double(rect.height),
  ]
}

private func pointMap(_ point: CGPoint) -> [String: Double] {
  ["x": Double(point.x), "y": Double(point.y)]
}

private struct EncodedImage {
  let base64: String
  let width: Int
  let height: Int
}

private enum ComputerUseError: Error {
  case imageResizeFailed
  case imageEncodeFailed
}

private struct ScreenDescriptor {
  let screen: NSScreen
  let displayID: CGDirectDisplayID
  let bounds: CGRect

  init(screen: NSScreen) {
    self.screen = screen
    self.displayID = screen.displayID
    self.bounds = CGDisplayBounds(screen.displayID)
  }
}

private struct WindowDescriptor {
  let windowID: Int
  let ownerPID: Int
  let ownerName: String
  let title: String
  let bounds: CGRect
  let layer: Int
  let alpha: Double
  let isOnScreen: Bool

  func toMap() -> [String: Any] {
    [
      "windowId": windowID,
      "ownerPid": ownerPID,
      "appName": ownerName,
      "title": title,
      "bounds": [
        "x": Double(bounds.origin.x),
        "y": Double(bounds.origin.y),
        "width": Double(bounds.width),
        "height": Double(bounds.height),
      ],
      "layer": layer,
      "alpha": alpha,
      "isOnScreen": isOnScreen,
    ]
  }
}

private extension NSScreen {
  var displayID: CGDirectDisplayID {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
      ?? CGMainDisplayID()
  }
}

private let keyCodes: [String: CGKeyCode] = [
  "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
  "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
  "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
  "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
  "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
  "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
  "n": 45, "m": 46, ".": 47, "`": 50,
  "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
  "escape": 53, "esc": 53, "command": 55, "shift": 56, "caps_lock": 57,
  "option": 58, "control": 59, "right_shift": 60, "right_option": 61,
  "right_control": 62, "function": 63, "f17": 64, "volume_up": 72,
  "volume_down": 73, "mute": 74, "f18": 79, "f19": 80, "f20": 90,
  "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101,
  "f11": 103, "f13": 105, "f16": 106, "f14": 107, "f10": 109,
  "f12": 111, "f15": 113, "help": 114, "home": 115, "page_up": 116,
  "forward_delete": 117, "f4": 118, "end": 119, "f2": 120,
  "page_down": 121, "f1": 122, "left": 123, "right": 124, "down": 125,
  "up": 126,
]

@available(macOS 13.0, *)
private final class SystemAudioRecorder: NSObject, SCStreamOutput {
  private var stream: SCStream?
  private var audioFile: AVAudioFile?
  private var outputURL: URL?
  private var startedAt: Date?
  private let queue = DispatchQueue(label: "com.caverno.computer-use.system-audio-recorder")

  func start(
    outputPath: String?,
    excludeCurrentProcessAudio: Bool,
    completion: @escaping ([String: Any]) -> Void
  ) {
    let url = outputPath.map(URL.init(fileURLWithPath:)) ?? defaultOutputURL()
    outputURL = url
    startedAt = Date()

    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
      guard let self else { return }
      if let error {
        completion([
          "ok": false,
          "code": "screen_capture_unavailable",
          "error": error.localizedDescription,
        ])
        return
      }
      guard let display = content?.displays.first else {
        completion([
          "ok": false,
          "code": "display_not_found",
          "error": "No display is available",
        ])
        return
      }

      let filter = SCContentFilter(display: display, excludingWindows: [])
      let configuration = SCStreamConfiguration()
      configuration.width = 2
      configuration.height = 2
      configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
      configuration.queueDepth = 3
      configuration.capturesAudio = true
      configuration.excludesCurrentProcessAudio = excludeCurrentProcessAudio
      configuration.sampleRate = 48_000
      configuration.channelCount = 2

      let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
      do {
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
      } catch {
        completion([
          "ok": false,
          "code": "audio_output_failed",
          "error": error.localizedDescription,
        ])
        return
      }

      self.stream = stream
      stream.startCapture { error in
        if let error {
          completion([
            "ok": false,
            "code": "recording_start_failed",
            "error": error.localizedDescription,
          ])
          return
        }
        completion([
          "ok": true,
          "path": url.path,
          "format": "caf",
          "excludeCurrentProcessAudio": excludeCurrentProcessAudio,
        ])
      }
    }
  }

  func stop(completion: @escaping ([String: Any]) -> Void) {
    guard let stream else {
      completion([
        "ok": false,
        "code": "not_recording",
        "error": "System audio recording is not active",
      ])
      return
    }

    stream.stopCapture { [weak self] error in
      guard let self else { return }
      let url = self.outputURL
      let startedAt = self.startedAt
      self.stream = nil
      self.audioFile = nil
      self.outputURL = nil
      self.startedAt = nil

      if let error {
        completion([
          "ok": false,
          "code": "recording_stop_failed",
          "error": error.localizedDescription,
        ])
        return
      }

      var response: [String: Any] = ["ok": true]
      if let url {
        response["path"] = url.path
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
          response["bytes"] = size.intValue
        }
      }
      if let startedAt {
        response["durationMs"] = Int(Date().timeIntervalSince(startedAt) * 1000)
      }
      completion(response)
    }
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .audio, sampleBuffer.isValid else {
      return
    }

    try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
      guard
        let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
        let format = AVAudioFormat(
          standardFormatWithSampleRate: description.mSampleRate,
          channels: description.mChannelsPerFrame
        ),
        let buffer = AVAudioPCMBuffer(
          pcmFormat: format,
          bufferListNoCopy: audioBufferList.unsafePointer
        )
      else {
        return
      }

      if audioFile == nil, let outputURL {
        try? FileManager.default.createDirectory(
          at: outputURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        audioFile = try? AVAudioFile(forWriting: outputURL, settings: format.settings)
      }

      try? audioFile?.write(from: buffer)
    }
  }

  private func defaultOutputURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CavernoComputerUse", isDirectory: true)
    let formatter = ISO8601DateFormatter()
    let fileName = "system-audio-\(formatter.string(from: Date())).caf"
      .replacingOccurrences(of: ":", with: "-")
    return directory.appendingPathComponent(fileName)
  }
}

private final class PermissionRowView: NSView {
  private let statusLabel = NSTextField(labelWithString: "Unknown")
  private let actionButton: NSButton
  private let action: () -> Void

  init(
    symbolName: String,
    title: String,
    subtitle: String,
    buttonTitle: String,
    action: @escaping () -> Void
  ) {
    self.action = action
    self.actionButton = NSButton(title: buttonTitle, target: nil, action: nil)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

    let icon = NSImageView()
    icon.symbolConfiguration = .init(pointSize: 26, weight: .medium)
    icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
    icon.contentTintColor = .controlAccentColor
    icon.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

    let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
    subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.maximumNumberOfLines = 2

    let textStack = NSStackView(views: [titleLabel, subtitleLabel])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 4

    statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    actionButton.target = self
    actionButton.action = #selector(runAction)
    actionButton.bezelStyle = .rounded

    let trailingStack = NSStackView(views: [statusLabel, actionButton])
    trailingStack.orientation = .horizontal
    trailingStack.alignment = .centerY
    trailingStack.spacing = 10

    let rowStack = NSStackView(views: [icon, textStack, trailingStack])
    rowStack.orientation = .horizontal
    rowStack.alignment = .centerY
    rowStack.spacing = 14
    rowStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(rowStack)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(greaterThanOrEqualToConstant: 78),
      icon.widthAnchor.constraint(equalToConstant: 36),
      rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  func setGranted(_ granted: Bool) {
    statusLabel.stringValue = granted ? "Done" : "Missing"
    statusLabel.textColor = granted ? .systemGreen : .secondaryLabelColor
    actionButton.isHidden = granted
  }

  @objc private func runAction() {
    action()
  }
}

private enum SmokeStepStatus {
  case waiting
  case done
  case failed

  var label: String {
    switch self {
    case .waiting:
      return "Waiting"
    case .done:
      return "Done"
    case .failed:
      return "Needs attention"
    }
  }

  var color: NSColor {
    switch self {
    case .waiting:
      return .secondaryLabelColor
    case .done:
      return .systemGreen
    case .failed:
      return .systemOrange
    }
  }

  var symbolName: String {
    switch self {
    case .waiting:
      return "circle"
    case .done:
      return "checkmark.circle.fill"
    case .failed:
      return "exclamationmark.triangle.fill"
    }
  }
}

private final class SmokeStepRowView: NSView {
  private let icon = NSImageView()
  private let statusLabel = NSTextField(labelWithString: "Waiting")
  private let detailLabel: NSTextField

  init(title: String, subtitle: String) {
    self.detailLabel = NSTextField(wrappingLabelWithString: subtitle)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 8
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65).cgColor

    icon.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
    icon.translatesAutoresizingMaskIntoConstraints = false

    let titleLabel = NSTextField(labelWithString: title)
    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

    detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.maximumNumberOfLines = 2

    let textStack = NSStackView(views: [titleLabel, detailLabel])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 3

    statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)

    let rowStack = NSStackView(views: [icon, textStack, statusLabel])
    rowStack.orientation = .horizontal
    rowStack.alignment = .centerY
    rowStack.spacing = 12
    rowStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(rowStack)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
      icon.widthAnchor.constraint(equalToConstant: 24),
      rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
    ])

    setStatus(.waiting, detail: subtitle)
  }

  required init?(coder: NSCoder) {
    nil
  }

  func setStatus(_ status: SmokeStepStatus, detail: String) {
    icon.image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: status.label)
    icon.contentTintColor = status.color
    statusLabel.stringValue = status.label
    statusLabel.textColor = status.color
    detailLabel.stringValue = detail
  }
}
