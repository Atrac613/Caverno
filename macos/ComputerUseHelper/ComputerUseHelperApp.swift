import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreMedia
import Darwin
import QuartzCore
import ScreenCaptureKit

@objc(CavernoComputerUseXpcProtocol)
protocol CavernoComputerUseXpcProtocol: NSObjectProtocol {
  func handleRequest(_ request: NSDictionary, withReply reply: @escaping (NSDictionary) -> Void)
}

@main
final class ComputerUseHelperApp: NSObject, NSApplicationDelegate {
  private static var delegateInstance: ComputerUseHelperApp?
  private static var singleInstanceLock: ComputerUseHelperSingleInstanceLock?
  private static let presentMainWindowEnvironmentKey = "CAVERNO_COMPUTER_USE_PRESENT_MAIN_WINDOW"

  private static var shouldPresentMainWindowAtLaunch: Bool {
    ProcessInfo.processInfo.environment[presentMainWindowEnvironmentKey] == "1"
  }

  static func main() {
    switch ComputerUseHelperSingleInstanceLock.acquire() {
    case .acquired(let lock):
      singleInstanceLock = lock
      var bootstrapExtra = lock.diagnostics
      bootstrapExtra["launchMode"] = shouldPresentMainWindowAtLaunch
        ? "foreground_ui"
        : "background"
      bootstrapExtra["mainWindowRequestedAtLaunch"] = shouldPresentMainWindowAtLaunch
      ComputerUseHelperSharedDiagnostics.setBootstrapExtra(bootstrapExtra)
      ComputerUseHelperSharedDiagnostics.writeBootstrap(event: "single_instance_lock_acquired")
    case .alreadyRunning(let diagnostics):
      var extra = diagnostics
      if let existingApplication = existingInstanceDiagnostics(
        activate: shouldPresentMainWindowAtLaunch
      ) {
        extra.merge(existingApplication) { _, new in new }
      }
      if duplicateInstanceShouldPreserveExistingDiagnostics(extra) {
        return
      }
      ComputerUseHelperSharedDiagnostics.writeBootstrap(
        event: "duplicate_instance_lock_held",
        extra: extra
      )
      return
    case .failed(let diagnostics):
      var extra = diagnostics
      if let existingApplication = existingInstanceDiagnostics(
        activate: shouldPresentMainWindowAtLaunch
      ) {
        extra.merge(existingApplication) { _, new in new }
      }
      ComputerUseHelperSharedDiagnostics.writeBootstrap(
        event: "single_instance_lock_failed",
        extra: extra
      )
      return
    }
    guard !exitForExistingInstanceIfNeeded() else {
      return
    }
    let application = NSApplication.shared
    let delegate = ComputerUseHelperApp()
    delegateInstance = delegate
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
  }

  private static func existingInstanceDiagnostics(activate: Bool) -> [String: Any]? {
    let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    let existingApplications = NSRunningApplication.runningApplications(
      withBundleIdentifier: ComputerUseHelperIpcSchema.helperBundleIdentifier
    ).filter { application in
      !application.isTerminated &&
        application.processIdentifier != currentProcessIdentifier
    }
    guard let existingApplication = existingApplications.first else {
      return nil
    }
    if activate {
      existingApplication.activate(options: [.activateIgnoringOtherApps])
    }
    return [
      "existingHelperProcessIdentifier": Int(existingApplication.processIdentifier),
      "existingHelperBundlePath": existingApplication.bundleURL?.path ?? "",
      "duplicateHelperProcessCount": existingApplications.count,
      "existingHelperActivated": activate,
      "singleInstancePolicy": activate
        ? "activate_existing_and_exit"
        : "reuse_existing_and_exit",
    ]
  }

  private static func duplicateInstanceShouldPreserveExistingDiagnostics(
    _ duplicateDiagnostics: [String: Any]
  ) -> Bool {
    if existingHelperMatchesCurrentBundle(duplicateDiagnostics) {
      return true
    }
    guard
      let sharedDiagnostics = ComputerUseHelperSharedDiagnostics.read(),
      sharedDiagnosticsMatchCurrentBundle(sharedDiagnostics),
      sharedDiagnosticsMatchLockOwner(
        sharedDiagnostics,
        duplicateDiagnostics: duplicateDiagnostics
      )
    else {
      return false
    }
    return true
  }

  private static func existingHelperMatchesCurrentBundle(_ diagnostics: [String: Any]) -> Bool {
    guard let existingBundlePath = diagnostics["existingHelperBundlePath"] as? String else {
      return false
    }
    let existingPath = URL(fileURLWithPath: existingBundlePath).standardizedFileURL.path
    let currentPath = Bundle.main.bundleURL.standardizedFileURL.path
    return existingPath == currentPath
  }

  private static func sharedDiagnosticsMatchCurrentBundle(_ diagnostics: [String: Any]) -> Bool {
    guard
      diagnostics["helperBundleIdentifier"] as? String == ComputerUseHelperIpcSchema.helperBundleIdentifier,
      let helperBundlePath = diagnostics["helperBundlePath"] as? String
    else {
      return false
    }
    let diagnosticPath = URL(fileURLWithPath: helperBundlePath).standardizedFileURL.path
    let currentPath = Bundle.main.bundleURL.standardizedFileURL.path
    return diagnosticPath == currentPath
  }

  private static func sharedDiagnosticsMatchLockOwner(
    _ sharedDiagnostics: [String: Any],
    duplicateDiagnostics: [String: Any]
  ) -> Bool {
    guard
      let lockOwnerProcessIdentifier =
        duplicateDiagnostics["singleInstanceLockOwnerProcessIdentifier"] as? Int,
      lockOwnerProcessIdentifier > 0
    else {
      return false
    }
    let sharedProcessIdentifiers = [
      sharedDiagnostics["helperProcessIdentifier"] as? Int,
      sharedDiagnostics["singleInstanceLockOwnerProcessIdentifier"] as? Int,
      sharedDiagnostics["existingHelperProcessIdentifier"] as? Int,
    ].compactMap { $0 }
    return sharedProcessIdentifiers.contains(lockOwnerProcessIdentifier)
  }

  private static func exitForExistingInstanceIfNeeded() -> Bool {
    guard let existingApplication = existingInstanceDiagnostics(
      activate: shouldPresentMainWindowAtLaunch
    ) else {
      return false
    }

    ComputerUseHelperSharedDiagnostics.writeBootstrap(
      event: "duplicate_instance_exiting",
      extra: existingApplication
    )
    return true
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
  private var permissionOverlayWindowController: PermissionOverlayWindowController?
  private var lastOnboardingTransition: OnboardingTransitionDiagnostic?

  func applicationDidFinishLaunching(_ notification: Notification) {
    ComputerUseHelperSharedDiagnostics.writeBootstrap(event: "application_did_finish_launching")
    ipc.start()
    guard Self.shouldPresentMainWindowAtLaunch else {
      return
    }
    _ = presentMainWindow(reason: "launch")
  }

  private func makeMainWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Caverno Computer Use"
    window.isReleasedWhenClosed = false
    window.center()
    window.contentView = makeContentView()
    return window
  }

  private func presentMainWindow(reason: String) -> [String: Any] {
    let createdWindow = window == nil
    let window = window ?? makeMainWindow()
    window.makeKeyAndOrderFront(nil)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    refreshPermissionRows()
    return [
      "ok": true,
      "mainWindowPresented": true,
      "mainWindowCreated": createdWindow,
      "mainWindowReason": reason,
      "launchMode": "foreground_ui",
    ]
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    ipc.start()
    refreshPermissionRows()
  }

  fileprivate static func showMainWindow(reason: String) -> [String: Any] {
    if Thread.isMainThread {
      return delegateInstance?.presentMainWindow(reason: reason)
        ?? [
          "ok": false,
          "code": "missing_delegate",
          "error": "Caverno Computer Use main window is not available.",
        ]
    }

    var response: [String: Any] = [:]
    DispatchQueue.main.sync {
      response = delegateInstance?.presentMainWindow(reason: reason)
        ?? [
          "ok": false,
          "code": "missing_delegate",
          "error": "Caverno Computer Use main window is not available.",
        ]
    }
    return response
  }

  fileprivate static func showPermissionOverlay(pane: SettingsPane) -> PermissionOverlayPresentation {
    if Thread.isMainThread {
      return delegateInstance?.presentPermissionOverlay(pane: pane)
        ?? PermissionOverlayPresentation.missingDelegate()
    }

    var presentation = PermissionOverlayPresentation.missingDelegate()
    DispatchQueue.main.sync {
      presentation = delegateInstance?.presentPermissionOverlay(pane: pane)
        ?? PermissionOverlayPresentation.missingDelegate()
    }
    return presentation
  }

  fileprivate static func startOnboardingPermissionFlow(pane: SettingsPane) -> [String: Any] {
    if Thread.isMainThread {
      return delegateInstance?.startOnboardingPermissionFlow(pane: pane)
        ?? [
          "ok": false,
          "code": "delegate_unavailable",
          "error": "Caverno Computer Use onboarding is not available.",
        ]
    }

    var response: [String: Any] = [
      "ok": false,
      "code": "delegate_unavailable",
      "error": "Caverno Computer Use onboarding is not available.",
    ]
    DispatchQueue.main.sync {
      response = delegateInstance?.startOnboardingPermissionFlow(pane: pane)
        ?? response
    }
    return response
  }

  fileprivate static func currentOnboardingTransitionMap() -> [String: Any]? {
    if Thread.isMainThread {
      return delegateInstance?.lastOnboardingTransition?.toMap()
    }

    var transition: [String: Any]?
    DispatchQueue.main.sync {
      transition = delegateInstance?.lastOnboardingTransition?.toMap()
    }
    return transition
  }

  private func presentPermissionOverlay(pane: SettingsPane) -> PermissionOverlayPresentation {
    let helperBundleURL = Bundle.main.bundleURL
    let controller = PermissionOverlayWindowController(
      pane: pane,
      helperBundleURL: helperBundleURL,
      returnWindow: window,
      onReturnToOnboarding: { [weak self] in
        self?.refreshPermissionRows()
      }
    )
    permissionOverlayWindowController = controller
    controller.showOverlay()
    return PermissionOverlayPresentation(
      overlayShown: controller.window?.isVisible == true,
      overlayWindowTitle: controller.window?.title ?? "Caverno Computer Use Permission Overlay",
      overlayWindowLevel: controller.window?.level.rawValue,
      overlayWindowLevelName: controller.overlayWindowLevelName,
      overlayPlacement: controller.overlayPlacement,
      overlayForegroundPolicy: controller.overlayForegroundPolicy,
      overlayCollectionBehavior: controller.overlayCollectionBehaviorNames,
      overlayHidesOnDeactivate: controller.window?.hidesOnDeactivate == true,
      overlayIsFloatingPanel: (controller.window as? NSPanel)?.isFloatingPanel == true,
      helperBundlePath: helperBundleURL.path,
      draggableTileReady: FileManager.default.fileExists(atPath: helperBundleURL.path),
      dragPasteboardTypes: HelperBundleDragTileView.dragPasteboardTypeNames
    )
  }

  private func startOnboardingPermissionFlow(pane: SettingsPane) -> [String: Any] {
    let row: PermissionRowView?
    switch pane {
    case .accessibility:
      row = accessibilityRow
    case .screenRecording:
      row = screenRecordingRow
    case .privacy:
      row = nil
    }
    guard let row else {
      return [
        "ok": false,
        "code": "unsupported_onboarding_permission",
        "error": "Onboarding permission flow supports accessibility or screenRecording.",
        "permission": pane.overlayPermission,
      ]
    }

    let result = startPermissionFlow(pane: pane, row: row)
    return [
      "ok": true,
      "permission": pane.overlayPermission,
      "section": pane.responseSection,
      "settingsOpened": result.settingsOpened,
      "onboardingFlowRequested": true,
      "overlayRequested": true,
      "overlayMode": "floating_helper_panel",
      "lastOnboardingTransition": result.transition.toMap(),
      "nextAction": "Drag Caverno Computer Use into the permission list, then recheck.",
    ]
  }

  @discardableResult
  private func startPermissionFlow(
    pane: SettingsPane,
    row: PermissionRowView
  ) -> (settingsOpened: Bool, transition: OnboardingTransitionDiagnostic) {
    let snapshot = row.snapshotImage()
    let sourceFrame = row.screenFrame()
    row.setPendingSystemSettings(true)
    let settingsOpened = openSettingsPane(pane)
    _ = presentPermissionOverlay(pane: pane)
    let animationResult = animatePermissionRowOverflow(
      snapshot: snapshot,
      sourceFrame: sourceFrame,
      targetWindow: permissionOverlayWindowController?.window,
      targetFrame: permissionOverlayWindowController?.animationTargetFrame(
        matching: sourceFrame?.size
      )
    )
    let transition = OnboardingTransitionDiagnostic(
      permission: pane.overlayPermission,
      placeholderShown: row.pendingSystemSettingsShown,
      animationTarget: animationResult.target,
      sourceFrame: sourceFrame,
      targetFrame: animationResult.frame,
      overlayPlacement: permissionOverlayWindowController?.overlayPlacement
    )
    lastOnboardingTransition = transition
    return (settingsOpened, transition)
  }

  @discardableResult
  private func animatePermissionRowOverflow(
    snapshot: NSImage?,
    sourceFrame: NSRect?,
    targetWindow: NSWindow?,
    targetFrame explicitTargetFrame: NSRect?
  ) -> (target: String, frame: NSRect?) {
    guard
      let snapshot,
      let sourceFrame,
      let screen = NSScreen.screens.first(where: { $0.frame.intersects(sourceFrame) }) ?? NSScreen.main
    else {
      return ("not_available", nil)
    }

    let imageView = NSImageView(frame: NSRect(origin: .zero, size: sourceFrame.size))
    imageView.image = snapshot
    imageView.imageScaling = .scaleAxesIndependently
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 18
    imageView.layer?.masksToBounds = true

    let panel = NSPanel(
      contentRect: sourceFrame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = imageView
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.orderFrontRegardless()

    let fallbackTarget = NSRect(
      x: screen.visibleFrame.midX - sourceFrame.width / 2,
      y: screen.visibleFrame.minY + min(132, screen.visibleFrame.height * 0.16),
      width: sourceFrame.width,
      height: sourceFrame.height
    )
    let targetFrame: NSRect
    let targetName: String
    if let explicitTargetFrame {
      targetFrame = explicitTargetFrame
      targetName = "permission_overlay_window"
    } else if let targetWindow {
      let windowFrame = targetWindow.frame
      targetFrame = NSRect(
        x: windowFrame.minX + 36,
        y: windowFrame.midY - sourceFrame.height / 2,
        width: min(sourceFrame.width, windowFrame.width - 72),
        height: sourceFrame.height
      )
      targetName = "permission_overlay_window"
    } else {
      targetFrame = fallbackTarget
      targetName = "screen_fallback"
    }

    panel.alphaValue = 0.98
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.34
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      panel.animator().setFrame(targetFrame, display: true)
      panel.animator().alphaValue = 0.18
    } completionHandler: {
      panel.close()
    }
    return (targetName, targetFrame)
  }

  private func makeContentView() -> NSView {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(scrollView)

    let documentView = NSView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = documentView

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
    title.translatesAutoresizingMaskIntoConstraints = false

    let subtitle = NSTextField(
      wrappingLabelWithString:
        "Caverno Computer Use owns the macOS permissions needed to observe screens and control apps. These permissions are used only after Caverno asks you to run a desktop task."
    )
    subtitle.font = .systemFont(ofSize: 15, weight: .regular)
    subtitle.textColor = .secondaryLabelColor
    subtitle.alignment = .center
    subtitle.maximumNumberOfLines = 3
    subtitle.translatesAutoresizingMaskIntoConstraints = false

    let statusSummaryLabel = NSTextField(
      wrappingLabelWithString: "Refresh permissions to verify readiness."
    )
    statusSummaryLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    statusSummaryLabel.textColor = .secondaryLabelColor
    statusSummaryLabel.alignment = .center
    statusSummaryLabel.maximumNumberOfLines = 2
    statusSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
    self.statusSummaryLabel = statusSummaryLabel

    let accessibilityRow = PermissionRowView(
      symbolName: "figure.stand",
      title: "Accessibility",
      subtitle: "Allows Caverno Computer Use to access app interfaces.",
      buttonTitle: "Allow",
      action: { [weak self] row in
        self?.startPermissionFlow(pane: .accessibility, row: row)
      }
    )
    let screenRecordingRow = PermissionRowView(
      symbolName: "camera.viewfinder",
      title: "Screenshots",
      subtitle: "Caverno uses screenshots to know where to click.",
      buttonTitle: "Allow",
      action: { [weak self] row in
        self?.startPermissionFlow(pane: .screenRecording, row: row)
      }
    )
    self.accessibilityRow = accessibilityRow
    self.screenRecordingRow = screenRecordingRow
    accessibilityRow.translatesAutoresizingMaskIntoConstraints = false
    screenRecordingRow.translatesAutoresizingMaskIntoConstraints = false

    let smokeTitle = NSTextField(labelWithString: "Verification")
    smokeTitle.font = .systemFont(ofSize: 15, weight: .semibold)
    smokeTitle.textColor = .secondaryLabelColor
    smokeTitle.alignment = .left
    smokeTitle.translatesAutoresizingMaskIntoConstraints = false

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
    permissionSmokeRow.translatesAutoresizingMaskIntoConstraints = false
    displayScreenshotSmokeRow.translatesAutoresizingMaskIntoConstraints = false
    windowCaptureSmokeRow.translatesAutoresizingMaskIntoConstraints = false

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
    buttonStack.translatesAutoresizingMaskIntoConstraints = false

    let footer = NSTextField(
      wrappingLabelWithString:
        "Grant permissions to Caverno Computer Use, not Caverno. You can revoke them at any time in System Settings."
    )
    footer.font = .systemFont(ofSize: 12, weight: .regular)
    footer.textColor = .tertiaryLabelColor
    footer.alignment = .center
    footer.maximumNumberOfLines = 2
    footer.translatesAutoresizingMaskIntoConstraints = false

    [
      icon,
      title,
      subtitle,
      statusSummaryLabel,
      accessibilityRow,
      screenRecordingRow,
      smokeTitle,
      permissionSmokeRow,
      displayScreenshotSmokeRow,
      windowCaptureSmokeRow,
      buttonStack,
      footer,
    ].forEach(documentView.addSubview)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
      documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
      documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
      documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
      documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
      icon.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
      icon.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 58),
      icon.heightAnchor.constraint(equalToConstant: 68),
      icon.widthAnchor.constraint(equalToConstant: 68),
      title.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 64),
      title.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -64),
      title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 28),
      subtitle.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      subtitle.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
      statusSummaryLabel.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      statusSummaryLabel.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      statusSummaryLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 28),
      accessibilityRow.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      accessibilityRow.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      accessibilityRow.topAnchor.constraint(equalTo: statusSummaryLabel.bottomAnchor, constant: 44),
      screenRecordingRow.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      screenRecordingRow.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      screenRecordingRow.topAnchor.constraint(equalTo: accessibilityRow.bottomAnchor, constant: 12),
      smokeTitle.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      smokeTitle.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      smokeTitle.topAnchor.constraint(equalTo: screenRecordingRow.bottomAnchor, constant: 44),
      permissionSmokeRow.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      permissionSmokeRow.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      permissionSmokeRow.topAnchor.constraint(equalTo: smokeTitle.bottomAnchor, constant: 14),
      displayScreenshotSmokeRow.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      displayScreenshotSmokeRow.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      displayScreenshotSmokeRow.topAnchor.constraint(equalTo: permissionSmokeRow.bottomAnchor, constant: 8),
      windowCaptureSmokeRow.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      windowCaptureSmokeRow.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      windowCaptureSmokeRow.topAnchor.constraint(equalTo: displayScreenshotSmokeRow.bottomAnchor, constant: 8),
      buttonStack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
      buttonStack.topAnchor.constraint(equalTo: windowCaptureSmokeRow.bottomAnchor, constant: 28),
      footer.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 96),
      footer.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -96),
      footer.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 14),
      footer.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -28),
    ])

    refreshPermissionRows()
    return root
  }

  private func refreshPermissionRows() {
    let permissions = computerUsePermissionSnapshot()
    helperReachableRow?.setGranted(true)
    accessibilityRow?.setGranted(permissions.accessibilityGranted)
    screenRecordingRow?.setGranted(permissions.screenCaptureGranted)
    if permissions.accessibilityGranted {
      accessibilityRow?.setPendingSystemSettings(false)
    }
    if permissions.screenCaptureGranted {
      screenRecordingRow?.setPendingSystemSettings(false)
    }
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

private final class ComputerUseHelperSingleInstanceLock {
  enum AcquireResult {
    case acquired(ComputerUseHelperSingleInstanceLock)
    case alreadyRunning([String: Any])
    case failed([String: Any])
  }

  static let lockPath = "/tmp/caverno-computer-use-helper.lock"

  let diagnostics: [String: Any]
  private let fileDescriptor: Int32

  private init(fileDescriptor: Int32, diagnostics: [String: Any]) {
    self.fileDescriptor = fileDescriptor
    self.diagnostics = diagnostics
  }

  deinit {
    flock(fileDescriptor, LOCK_UN)
    close(fileDescriptor)
  }

  static func acquire() -> AcquireResult {
    let processIdentifier = Int(ProcessInfo.processInfo.processIdentifier)
    let fileDescriptor = open(lockPath, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
    guard fileDescriptor >= 0 else {
      return .failed(lockDiagnostics(
        status: "open_failed",
        processIdentifier: processIdentifier,
        errorNumber: errno
      ))
    }

    if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
      _ = ftruncate(fileDescriptor, 0)
      let ownerText = "\(processIdentifier)\n"
      ownerText.withCString { pointer in
        _ = write(fileDescriptor, pointer, strlen(pointer))
      }
      let diagnostics = lockDiagnostics(
        status: "acquired",
        processIdentifier: processIdentifier
      )
      return .acquired(
        ComputerUseHelperSingleInstanceLock(
          fileDescriptor: fileDescriptor,
          diagnostics: diagnostics
        )
      )
    }

    let lockError = errno
    close(fileDescriptor)
    if lockError == EWOULDBLOCK || lockError == EAGAIN {
      return .alreadyRunning(lockDiagnostics(
        status: "held_by_existing_process",
        processIdentifier: processIdentifier,
        ownerProcessIdentifier: readLockOwnerProcessIdentifier(),
        errorNumber: lockError
      ))
    }
    return .failed(lockDiagnostics(
      status: "lock_failed",
      processIdentifier: processIdentifier,
      errorNumber: lockError
    ))
  }

  private static func lockDiagnostics(
    status: String,
    processIdentifier: Int,
    ownerProcessIdentifier: Int? = nil,
    errorNumber: Int32? = nil
  ) -> [String: Any] {
    var diagnostics: [String: Any] = [
      "singleInstanceLockStatus": status,
      "singleInstanceLockPath": lockPath,
      "singleInstanceLockOwnerProcessIdentifier": ownerProcessIdentifier ?? processIdentifier,
      "singleInstanceLockRequesterProcessIdentifier": processIdentifier,
      "singleInstanceLockRequired": true,
    ]
    if let errorNumber {
      diagnostics["singleInstanceLockErrorNumber"] = Int(errorNumber)
      diagnostics["singleInstanceLockErrorDescription"] = String(cString: strerror(errorNumber))
    }
    return diagnostics
  }

  private static func readLockOwnerProcessIdentifier() -> Int? {
    guard
      let text = try? String(contentsOfFile: lockPath, encoding: .utf8),
      let firstLine = text.split(separator: "\n").first,
      let processIdentifier = Int(firstLine.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      return nil
    }
    return processIdentifier
  }
}

fileprivate enum SettingsPane {
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

  init?(permissionOverlayPermission permission: String) {
    switch permission.lowercased() {
    case "accessibility":
      self = .accessibility
    case "screen_capture", "screencapture", "screen_recording", "screenrecording":
      self = .screenRecording
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

  var overlayPermission: String {
    switch self {
    case .privacy:
      return "privacy"
    case .accessibility:
      return "accessibility"
    case .screenRecording:
      return "screenRecording"
    }
  }

  var permissionLabel: String {
    switch self {
    case .privacy:
      return "Privacy"
    case .accessibility:
      return "Accessibility"
    case .screenRecording:
      return "Screen & System Audio Recording"
    }
  }

  var overlayInstructionLabel: String {
    switch self {
    case .privacy:
      return "Privacy"
    case .accessibility:
      return "Accessibility"
    case .screenRecording:
      return "Screenshots"
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

@discardableResult
private func openSettingsPane(_ pane: SettingsPane) -> Bool {
  guard let url = pane.url else {
    return false
  }
  return NSWorkspace.shared.open(url)
}

fileprivate struct PermissionOverlayPresentation {
  let overlayShown: Bool
  let overlayWindowTitle: String
  let overlayWindowLevel: Int?
  let overlayWindowLevelName: String
  let overlayPlacement: String
  let overlayForegroundPolicy: String
  let overlayCollectionBehavior: [String]
  let overlayHidesOnDeactivate: Bool
  let overlayIsFloatingPanel: Bool
  let helperBundlePath: String
  let draggableTileReady: Bool
  let dragPasteboardTypes: [String]

  static func missingDelegate() -> PermissionOverlayPresentation {
    let helperBundleURL = Bundle.main.bundleURL
    return PermissionOverlayPresentation(
      overlayShown: false,
      overlayWindowTitle: "Caverno Computer Use Permission Overlay",
      overlayWindowLevel: nil,
      overlayWindowLevelName: "missing",
      overlayPlacement: "delegate_unavailable",
      overlayForegroundPolicy: "delegate_unavailable",
      overlayCollectionBehavior: [],
      overlayHidesOnDeactivate: false,
      overlayIsFloatingPanel: false,
      helperBundlePath: helperBundleURL.path,
      draggableTileReady: FileManager.default.fileExists(atPath: helperBundleURL.path),
      dragPasteboardTypes: HelperBundleDragTileView.dragPasteboardTypeNames
    )
  }

  func toMap() -> [String: Any] {
    var map: [String: Any] = [
      "overlayShown": overlayShown,
      "overlayWindowTitle": overlayWindowTitle,
      "overlayWindowLevelName": overlayWindowLevelName,
      "overlayPlacement": overlayPlacement,
      "overlayForegroundPolicy": overlayForegroundPolicy,
      "overlayCollectionBehavior": overlayCollectionBehavior,
      "overlayHidesOnDeactivate": overlayHidesOnDeactivate,
      "overlayIsFloatingPanel": overlayIsFloatingPanel,
      "helperBundlePath": helperBundlePath,
      "draggableTileReady": draggableTileReady,
      "dragPasteboardTypes": dragPasteboardTypes,
    ]
    if let overlayWindowLevel {
      map["overlayWindowLevel"] = overlayWindowLevel
    }
    return map
  }
}

fileprivate struct OnboardingTransitionDiagnostic {
  let permission: String
  let placeholderShown: Bool
  let animationTarget: String
  let sourceFrame: NSRect?
  let targetFrame: NSRect?
  let overlayPlacement: String?
  let startedAt = ISO8601DateFormatter().string(from: Date())

  func toMap() -> [String: Any] {
    var map: [String: Any] = [
      "onboardingTransitionStarted": true,
      "transitionSourcePermission": permission,
      "transitionPlaceholderShown": placeholderShown,
      "transitionAnimationTarget": animationTarget,
      "transitionStartedAt": startedAt,
    ]
    if let sourceFrame {
      map["transitionSourceFrame"] = frameMap(sourceFrame)
    }
    if let targetFrame {
      map["transitionTargetFrame"] = frameMap(targetFrame)
    }
    if let overlayPlacement {
      map["transitionOverlayPlacement"] = overlayPlacement
    }
    return map
  }

  private func frameMap(_ frame: NSRect) -> [String: Double] {
    [
      "x": Double(frame.minX),
      "y": Double(frame.minY),
      "width": Double(frame.width),
      "height": Double(frame.height),
    ]
  }
}

private final class PermissionOverlayWindowController: NSWindowController {
  private let pane: SettingsPane
  private let helperBundleURL: URL
  private weak var returnWindow: NSWindow?
  private let onReturnToOnboarding: () -> Void
  private var dragCueArrow: NSImageView?
  private var dragTile: HelperBundleDragTileView?
  private(set) var overlayPlacement = "screen_fallback"
  private(set) var overlayForegroundPolicy = "not_shown"

  init(
    pane: SettingsPane,
    helperBundleURL: URL,
    returnWindow: NSWindow?,
    onReturnToOnboarding: @escaping () -> Void
  ) {
    self.pane = pane
    self.helperBundleURL = helperBundleURL
    self.returnWindow = returnWindow
    self.onReturnToOnboarding = onReturnToOnboarding

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 96),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.title = "Caverno Computer Use Permission Overlay"
    panel.isMovableByWindowBackground = true
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true

    super.init(window: panel)
    panel.contentView = makeContentView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func showOverlay() {
    guard let window else {
      return
    }
    positionNearSettings(window)
    window.orderFrontRegardless()
    overlayForegroundPolicy = "accessory_overlay_front"
    startDragCueAnimation()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak window] in
      guard let self, let window else {
        return
      }
      self.positionNearSettings(window)
    }
  }

  var overlayWindowLevelName: String {
    guard let window else {
      return "missing"
    }
    switch window.level {
    case .floating:
      return "floating"
    case .statusBar:
      return "statusBar"
    case .modalPanel:
      return "modalPanel"
    default:
      return "\(window.level.rawValue)"
    }
  }

  var overlayCollectionBehaviorNames: [String] {
    guard let window else {
      return []
    }
    let behavior = window.collectionBehavior
    var names: [String] = []
    if behavior.contains(.canJoinAllSpaces) {
      names.append("canJoinAllSpaces")
    }
    if behavior.contains(.fullScreenAuxiliary) {
      names.append("fullScreenAuxiliary")
    }
    if behavior.contains(.transient) {
      names.append("transient")
    }
    return names
  }

  private func makeContentView() -> NSView {
    let root = NSVisualEffectView()
    root.material = .hudWindow
    root.blendingMode = .behindWindow
    root.state = .active
    root.wantsLayer = true
    root.layer?.cornerRadius = 18
    root.layer?.borderWidth = 1
    root.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor

    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)

    let backButton = NSButton(
      image: NSImage(
        systemSymbolName: "chevron.left",
        accessibilityDescription: "Return to onboarding"
      ) ?? NSImage(),
      target: self,
      action: #selector(returnToOnboarding)
    )
    backButton.bezelStyle = .circular
    backButton.translatesAutoresizingMaskIntoConstraints = false
    backButton.widthAnchor.constraint(equalToConstant: 42).isActive = true
    backButton.heightAnchor.constraint(equalToConstant: 42).isActive = true

    let content = NSStackView()
    content.orientation = .vertical
    content.alignment = .width
    content.spacing = 4

    let arrow = NSImageView()
    arrow.symbolConfiguration = .init(pointSize: 28, weight: .bold)
    arrow.image = NSImage(
      systemSymbolName: "arrow.up",
      accessibilityDescription: "Drag up"
    )
    arrow.contentTintColor = .controlAccentColor
    arrow.translatesAutoresizingMaskIntoConstraints = false
    arrow.wantsLayer = true
    arrow.widthAnchor.constraint(equalToConstant: 32).isActive = true
    arrow.heightAnchor.constraint(equalToConstant: 28).isActive = true
    dragCueArrow = arrow

    let instruction = NSTextField(wrappingLabelWithString: instructionText)
    instruction.font = .systemFont(ofSize: 13, weight: .semibold)
    instruction.textColor = .labelColor
    instruction.maximumNumberOfLines = 1
    instruction.lineBreakMode = .byTruncatingTail

    let instructionRow = NSStackView(views: [arrow, instruction])
    instructionRow.orientation = .horizontal
    instructionRow.alignment = .centerY
    instructionRow.spacing = 8

    let tile = HelperBundleDragTileView(helperBundleURL: helperBundleURL)
    tile.translatesAutoresizingMaskIntoConstraints = false
    tile.heightAnchor.constraint(equalToConstant: 36).isActive = true
    dragTile = tile

    content.addArrangedSubview(instructionRow)
    content.addArrangedSubview(tile)

    stack.addArrangedSubview(backButton)
    stack.addArrangedSubview(content)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
    ])

    return root
  }

  private var instructionText: String {
    "Drag Caverno Computer Use to the list above to allow \(pane.overlayInstructionLabel)"
  }

  func animationTargetFrame(matching sourceSize: NSSize?) -> NSRect? {
    guard
      let sourceSize,
      let tileFrame = dragTileScreenFrame()
    else {
      return nil
    }
    return NSRect(
      x: tileFrame.minX,
      y: tileFrame.midY - sourceSize.height / 2,
      width: min(sourceSize.width, tileFrame.width),
      height: sourceSize.height
    )
  }

  private func positionNearSettings(_ window: NSWindow) {
    guard let screen = NSScreen.main else {
      window.center()
      return
    }
    if
      let settingsFrame = systemSettingsWindowFrame(),
      let targetScreen = screenContaining(settingsFrame)
    {
      overlayPlacement = position(window, near: settingsFrame, on: targetScreen)
      return
    }

    overlayPlacement = "screen_fallback"
    let frame = screen.visibleFrame
    let size = window.frame.size
    let origin = NSPoint(
      x: frame.midX - size.width / 2,
      y: frame.minY + min(96, frame.height * 0.12)
    )
    window.setFrameOrigin(origin)
  }

  private func position(
    _ window: NSWindow,
    near settingsFrame: NSRect,
    on screen: NSScreen
  ) -> String {
    let frame = screen.visibleFrame
    let size = window.frame.size
    let x = clamped(
      settingsFrame.midX - size.width / 2,
      min: frame.minX + 16,
      max: frame.maxX - size.width - 16
    )
    let lowerListY = clamped(
      settingsFrame.minY + 18,
      min: frame.minY + 16,
      max: frame.maxY - size.height - 16
    )
    let belowY = settingsFrame.minY - size.height - 16
    let y: CGFloat
    let placement: String
    if settingsFrame.height >= size.height + 120 {
      y = lowerListY
      placement = "system_settings_permission_list"
    } else if belowY >= frame.minY + 16 {
      y = belowY
      placement = "system_settings_window"
    } else {
      y = frame.minY + min(96, frame.height * 0.12)
      placement = "screen_fallback"
    }
    window.setFrameOrigin(NSPoint(x: x, y: y))
    return placement
  }

  private func systemSettingsWindowFrame() -> NSRect? {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return nil
    }

    let candidates = windows.compactMap { window -> NSRect? in
      guard
        let owner = window[kCGWindowOwnerName as String] as? String,
        owner == "System Settings" || owner == "System Preferences",
        let layer = window[kCGWindowLayer as String] as? Int,
        layer == 0,
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
        let x = bounds["X"],
        let y = bounds["Y"],
        let width = bounds["Width"],
        let height = bounds["Height"],
        width > 200,
        height > 200
      else {
        return nil
      }
      return appKitWindowFrame(from: CGRect(x: x, y: y, width: width, height: height))
    }

    return candidates.max { lhs, rhs in
      lhs.width * lhs.height < rhs.width * rhs.height
    }
  }

  private func appKitWindowFrame(from cgFrame: CGRect) -> NSRect {
    let displayMaxY = NSScreen.screens.map { $0.frame.maxY }.max()
      ?? NSScreen.main?.frame.maxY
      ?? cgFrame.maxY
    return NSRect(
      x: cgFrame.minX,
      y: displayMaxY - cgFrame.minY - cgFrame.height,
      width: cgFrame.width,
      height: cgFrame.height
    )
  }

  private func screenContaining(_ frame: NSRect) -> NSScreen? {
    let center = NSPoint(x: frame.midX, y: frame.midY)
    return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? NSScreen.main
  }

  private func startDragCueAnimation() {
    guard let layer = dragCueArrow?.layer else {
      return
    }
    layer.removeAnimation(forKey: "pullCue")

    let pull = CAKeyframeAnimation(keyPath: "transform.translation.y")
    pull.values = [0, -10, -4, -14, 0]
    pull.keyTimes = [0, 0.22, 0.42, 0.62, 1]
    pull.duration = 1.15
    pull.timingFunctions = [
      CAMediaTimingFunction(name: .easeOut),
      CAMediaTimingFunction(name: .easeInEaseOut),
      CAMediaTimingFunction(name: .easeOut),
      CAMediaTimingFunction(name: .easeIn),
    ]
    pull.repeatCount = .infinity

    let scale = CAKeyframeAnimation(keyPath: "transform.scale")
    scale.values = [1, 1.08, 1.02, 1.12, 1]
    scale.keyTimes = pull.keyTimes
    scale.duration = pull.duration
    scale.timingFunctions = pull.timingFunctions
    scale.repeatCount = .infinity

    let group = CAAnimationGroup()
    group.animations = [pull, scale]
    group.duration = pull.duration
    group.repeatCount = .infinity
    group.isRemovedOnCompletion = false
    layer.add(group, forKey: "pullCue")
  }

  private func dragTileScreenFrame() -> NSRect? {
    guard
      let dragTile,
      let window = dragTile.window
    else {
      return nil
    }
    dragTile.superview?.layoutSubtreeIfNeeded()
    return window.convertToScreen(dragTile.convert(dragTile.bounds, to: nil))
  }

  private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
    Swift.max(minimum, Swift.min(value, maximum))
  }

  @objc private func returnToOnboarding() {
    guard let window else {
      showReturnWindow()
      return
    }
    let targetFrame = returnAnimationFrame(from: window.frame)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.24
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      window.animator().setFrame(targetFrame, display: true)
      window.animator().alphaValue = 0.08
    } completionHandler: { [weak self] in
      window.close()
      self?.showReturnWindow()
    }
  }

  private func returnAnimationFrame(from overlayFrame: NSRect) -> NSRect {
    guard let returnWindow else {
      return overlayFrame.insetBy(dx: overlayFrame.width * 0.28, dy: overlayFrame.height * 0.28)
    }
    let targetSize = NSSize(
      width: max(220, overlayFrame.width * 0.42),
      height: max(72, overlayFrame.height * 0.42)
    )
    return NSRect(
      x: returnWindow.frame.midX - targetSize.width / 2,
      y: returnWindow.frame.midY - targetSize.height / 2,
      width: targetSize.width,
      height: targetSize.height
    )
  }

  private func showReturnWindow() {
    close()
    onReturnToOnboarding()
    returnWindow?.deminiaturize(nil)
    returnWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

private final class HelperBundleDragTileView: NSView, NSDraggingSource {
  static let dragPasteboardTypes: [NSPasteboard.PasteboardType] = [
    .fileURL,
    .URL,
    .string,
    NSPasteboard.PasteboardType("NSURLPboardType"),
  ]
  static let dragPasteboardTypeNames = dragPasteboardTypes.map(\.rawValue)

  private let helperBundleURL: URL

  init(helperBundleURL: URL) {
    self.helperBundleURL = helperBundleURL
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
    buildSubviews()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func mouseDragged(with event: NSEvent) {
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setString(helperBundleURL.absoluteString, forType: .fileURL)
    pasteboardItem.setString(helperBundleURL.absoluteString, forType: .URL)
    pasteboardItem.setString(helperBundleURL.path, forType: .string)
    pasteboardItem.setString(
      helperBundleURL.absoluteString,
      forType: NSPasteboard.PasteboardType("NSURLPboardType")
    )
    let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
    draggingItem.setDraggingFrame(bounds, contents: draggingImage())
    beginDraggingSession(with: [draggingItem], event: event, source: self)
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .copy
  }

  func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
    true
  }

  private func buildSubviews() {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    let icon = NSImageView()
    icon.image = NSWorkspace.shared.icon(forFile: helperBundleURL.path)
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 24).isActive = true

    let label = NSTextField(labelWithString: "Caverno Computer Use")
    label.font = .systemFont(ofSize: 13, weight: .semibold)
    label.textColor = .labelColor

    stack.addArrangedSubview(icon)
    stack.addArrangedSubview(label)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  private func draggingImage() -> NSImage {
    let image = NSWorkspace.shared.icon(forFile: helperBundleURL.path)
    image.size = NSSize(width: 48, height: 48)
    return image
  }
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
}

private enum ComputerUseHelperIpcSchema {
  static let protocolVersion = 1
  static let mainAppBundleIdentifier = "com.noguwo.apps.caverno"
  static let helperBundleIdentifier = "com.noguwo.apps.caverno.computer-use"
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
    "ping_show_main_window_permission_status_open_settings_show_permission_overlay_start_onboarding_permission_flow_stop_all_screenshot_list_displays_list_windows_accessibility_snapshot_focus_window_screenshot_window_move_mouse_click_drag_scroll_type_text_press_key_system_audio_match_dnc",
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
  private static var bootstrapExtra: [String: Any] = [:]

  static func setBootstrapExtra(_ extra: [String: Any]) {
    bootstrapExtra = extra
  }

  static func addBootstrapExtra(to diagnostics: inout [String: Any]) {
    for (key, value) in bootstrapExtra {
      diagnostics[key] = value
    }
  }

  static func read() -> [String: Any]? {
    let url = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  static func writeBootstrap(event: String, extra: [String: Any] = [:]) {
    let bundle = Bundle.main
    let processInfo = ProcessInfo.processInfo
    var diagnostics: [String: Any] = [
      "schemaName": "caverno_computer_use_helper_diagnostics",
      "schemaVersion": 1,
      "event": event,
      "generatedAt": ISO8601DateFormatter().string(from: Date()),
      "helperBundleIdentifier": bundle.bundleIdentifier ?? "",
      "helperBundlePath": bundle.bundlePath,
      "helperExecutablePath": bundle.executablePath ?? "",
      "helperProcessIdentifier": Int(processInfo.processIdentifier),
      "processName": processInfo.processName,
      "arguments": processInfo.arguments,
      "environmentKeys": processInfo.environment.keys.sorted(),
      "listenerStarted": false,
      "xpcListenerStarted": false,
      "xpcListenerStartAttempted": false,
      "launchMode": "unknown",
    ]
    addBootstrapExtra(to: &diagnostics)
    for (key, value) in extra {
      diagnostics[key] = value
    }
    write(diagnostics)
  }

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
  private var xpcListenerStartAttempted = false

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
    xpcListenerStartAttempted = true
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
    case .showMainWindow:
      completion(showMainWindow(arguments: request.arguments))
    case .permissionStatus:
      completion(permissionStatus())
    case .openSettings:
      completion(openSettings(arguments: request.arguments))
    case .showPermissionOverlay:
      completion(showPermissionOverlay(arguments: request.arguments))
    case .startOnboardingPermissionFlow:
      completion(startOnboardingPermissionFlow(arguments: request.arguments))
    case .stopAll:
      stopAll(completion: completion)
    case .screenshot:
      completion(screenshot(arguments: request.arguments))
    case .listDisplays:
      completion(listDisplays(arguments: request.arguments))
    case .listWindows:
      completion(listWindows(arguments: request.arguments))
    case .accessibilitySnapshot:
      completion(accessibilitySnapshot(arguments: request.arguments))
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

  private func showMainWindow(arguments: [String: Any]) -> [String: Any] {
    let reason = arguments["reason"] as? String ?? "ipc"
    var response = ComputerUseHelperApp.showMainWindow(reason: reason)
    let ok = response["ok"] as? Bool ?? true
    response.removeValue(forKey: "ok")
    return baseResponse(ok: ok, extra: response)
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

  private func showPermissionOverlay(arguments: [String: Any]) -> [String: Any] {
    let permission = (arguments["permission"] as? String)
      ?? (arguments["section"] as? String)
      ?? "accessibility"
    guard
      let pane = SettingsPane(permissionOverlayPermission: permission),
      let url = pane.url
    else {
      return errorResponse(
        code: "invalid_args",
        error: "permission must be accessibility or screenRecording",
        details: permission
      )
    }

    let opened = NSWorkspace.shared.open(url)
    let presentation = ComputerUseHelperApp.showPermissionOverlay(pane: pane)
    var overlay = presentation.toMap()
    overlay["permission"] = pane.overlayPermission
    overlay["section"] = pane.responseSection
    overlay["url"] = url.absoluteString
    overlay["settingsOpened"] = opened
    overlay["overlayRequested"] = true
    overlay["overlayMode"] = "floating_helper_panel"
    overlay["nextAction"] =
      "Drag Caverno Computer Use into the permission list, then recheck."
    return baseResponse(
      ok: opened,
      extra: overlay
    )
  }

  private func startOnboardingPermissionFlow(arguments: [String: Any]) -> [String: Any] {
    let permission = (arguments["permission"] as? String)
      ?? (arguments["section"] as? String)
      ?? "screenRecording"
    guard let pane = SettingsPane(permissionOverlayPermission: permission) else {
      return errorResponse(
        code: "invalid_args",
        error: "permission must be accessibility or screenRecording",
        details: permission
      )
    }

    var flow = ComputerUseHelperApp.startOnboardingPermissionFlow(pane: pane)
    let ok = flow["ok"] as? Bool ?? true
    flow.removeValue(forKey: "ok")
    return baseResponse(ok: ok, extra: flow)
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
    guard computerUsePermissionSnapshot().screenCaptureGranted else {
      return screenCaptureDeniedResponse()
    }

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
          "displayIndex": screen.index,
          "displayName": screen.name,
          "displayIsMain": screen.isMain,
          "displayCount": displayDescriptors().count,
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

  private func listDisplays(arguments: [String: Any]) -> [String: Any] {
    let displays = displayDescriptors().map { $0.toMap() }
    return baseResponse(
      extra: [
        "schemaName": "macos_computer_use_display_inventory",
        "schemaVersion": 1,
        "displays": displays,
        "count": displays.count,
        "coordinateSpace": "screen_points",
        "inputOrigin": "top_left",
        "nextAction": displays.count > 1
          ? "Use displayId from this result when observing, screenshotting, or acting on a non-main display."
          : "Use the main display unless the user attaches another target context.",
      ]
    )
  }

  private func listWindows(arguments: [String: Any]) -> [String: Any] {
    let includeCurrentApp =
      boolValue(arguments["include_current_app"] ?? arguments["includeCurrentApp"]) ?? false
    let maxWindows = max(1, min(intValue(arguments["max_windows"] ?? arguments["maxWindows"]) ?? 80, 200))
    let spaceScope = WindowSpaceScope(arguments: arguments)
    let includeHidden =
      boolValue(arguments["include_hidden"] ?? arguments["includeHidden"])
        ?? (spaceScope == .allSpaces)
    let helperPid = Int(ProcessInfo.processInfo.processIdentifier)
    let mainAppPid = intValue(arguments["main_app_pid"] ?? arguments["mainAppPid"])
    let windows = windowDescriptors(spaceScope: spaceScope, includeHidden: includeHidden)
      .filter { window in
        includeCurrentApp ||
          (window.ownerPID != helperPid && window.ownerPID != mainAppPid)
      }
      .prefix(maxWindows)
      .map { $0.toMap() }
    let windowList = Array(windows)

    return baseResponse(
      extra: [
        "schemaName": "macos_computer_use_window_inventory",
        "schemaVersion": 1,
        "windows": windowList,
        "count": windowList.count,
        "spaceScope": spaceScope.rawValue,
        "includeHidden": includeHidden,
        "spaceSupport": windowSpaceSupportMetadata(spaceScope: spaceScope),
        "coordinateSpace": "window_pixels",
        "inputOrigin": "top_left",
        "nextAction": windowSpaceNextAction(spaceScope: spaceScope),
      ]
    )
  }

  private func accessibilitySnapshot(arguments: [String: Any]) -> [String: Any] {
    guard AXIsProcessTrusted() else {
      return accessibilityDeniedResponse()
    }

    let rawTarget = (arguments["target"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard rawTarget.isEmpty || rawTarget == "front_window" || rawTarget == "window" else {
      return errorResponse(
        code: "invalid_args",
        error: "target must be front_window or window"
      )
    }

    let requestedWindowID = windowID(arguments: arguments)
    let target = rawTarget.isEmpty
      ? (requestedWindowID == nil ? "front_window" : "window")
      : rawTarget
    let maxElements = clampedInt(
      arguments["max_elements"] ?? arguments["maxElements"],
      defaultValue: 80,
      minimum: 1,
      maximum: 200
    )
    let maxDepth = clampedInt(
      arguments["max_depth"] ?? arguments["maxDepth"],
      defaultValue: 4,
      minimum: 0,
      maximum: 8
    )
    let labelMaxCharacters = clampedInt(
      arguments["label_max_characters"] ?? arguments["labelMaxCharacters"],
      defaultValue: 120,
      minimum: 20,
      maximum: 240
    )

    let includeCurrentApp =
      boolValue(arguments["include_current_app"] ?? arguments["includeCurrentApp"]) ?? false
    let helperPid = Int(ProcessInfo.processInfo.processIdentifier)
    let mainAppPid = intValue(arguments["main_app_pid"] ?? arguments["mainAppPid"])

    let window: WindowDescriptor
    if target == "window" {
      guard let requestedWindowID else {
        return errorResponse(code: "invalid_args", error: "window_id is required")
      }
      guard
        let selectedWindow = findWindow(
          windowID: requestedWindowID,
          spaceScope: .allSpaces,
          includeHidden: true
        )
      else {
        return errorResponse(
          code: "window_not_found",
          error: "No matching window is available.",
          details: requestedWindowID
        )
      }
      window = selectedWindow
    } else {
      guard
        let selectedWindow = visibleWindows().first(where: { candidate in
          includeCurrentApp ||
            (candidate.ownerPID != helperPid && candidate.ownerPID != mainAppPid)
        })
      else {
        return errorResponse(
          code: "window_not_found",
          error: "No visible front window is available."
        )
      }
      window = selectedWindow
    }

    let appElement = AXUIElementCreateApplication(pid_t(window.ownerPID))
    let matchedWindow = findAccessibilityWindow(
      appElement: appElement,
      windowID: window.windowID
    )
    let axWindow = matchedWindow
      ?? (target == "front_window"
        ? focusedAccessibilityWindow(appElement: appElement) ?? firstAccessibilityWindow(appElement: appElement)
        : nil)
    guard let axWindow else {
      return errorResponse(
        code: "accessibility_window_not_found",
        error: "No matching accessibility window is available.",
        details: window.windowID
      )
    }

    let traversal = accessibilitySnapshotElements(
      root: axWindow,
      maxDepth: maxDepth,
      maxElements: maxElements,
      labelMaxCharacters: labelMaxCharacters
    )
    let observationId = "ax-\(Int(Date().timeIntervalSince1970 * 1_000_000))"
    return baseResponse(
      extra: [
        "schemaName": "macos_computer_use_accessibility_snapshot",
        "schemaVersion": 1,
        "observationId": observationId,
        "snapshotId": observationId,
        "readOnly": true,
        "target": [
          "requested": target,
          "resolved": "window",
          "windowId": window.windowID,
          "accessibilityWindowMatchedBy": matchedWindow == nil
            ? "front_window_fallback"
            : "window_id",
        ],
        "window": window.toMap(),
        "permissions": computerUsePermissionSnapshot().toMap(),
        "coordinateSpace": "screen_points",
        "inputOrigin": "top_left",
        "bounds": [
          "maxElements": maxElements,
          "maxDepth": maxDepth,
          "labelMaxCharacters": labelMaxCharacters,
        ],
        "elementCount": traversal.elements.count,
        "truncated": traversal.truncatedByElementLimit || traversal.truncatedByDepthLimit,
        "truncation": [
          "byElementLimit": traversal.truncatedByElementLimit,
          "byDepthLimit": traversal.truncatedByDepthLimit,
          "labelTruncatedCount": traversal.labelTruncatedCount,
        ],
        "redaction": [
          "policy": "metadata_only",
          "labels": "AXTitle, AXDescription, AXHelp, and AXIdentifier only",
          "labelMaxCharacters": labelMaxCharacters,
          "labelTruncatedCount": traversal.labelTruncatedCount,
          "valuesOmitted": true,
          "selectedTextOmitted": true,
          "rawAttributeValuesOmitted": true,
          "secureValueOmitted": true,
          "omittedAttributes": [
            "AXValue",
            "AXSelectedText",
            "AXSelectedTextRange",
            "AXAttributedStringForRange",
          ],
        ],
        "elements": traversal.elements,
        "nextAction": "Use this read-only snapshot to choose target metadata or run computer_vision_observe before requesting an approved desktop action.",
      ]
    )
  }

  private func focusWindow(arguments: [String: Any]) -> [String: Any] {
    guard let windowID = windowID(arguments: arguments) else {
      return errorResponse(code: "invalid_args", error: "window_id is required")
    }
    guard
      let window = findWindow(
        windowID: windowID,
        spaceScope: .allSpaces,
        includeHidden: true
      )
    else {
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

    var elementTargeting: [String: Any]?
    if accessibilityElementTargetID(arguments: arguments) != nil {
      switch resolveAccessibilityElementTarget(arguments: arguments) {
      case .resolved(let target):
        let focusResult = focusAccessibilityElement(target.element, appElement: target.appElement)
        let elementFocused = focusResult == .success
        elementTargeting = target.metadata(
          status: elementFocused ? "resolved" : "failed",
          action: "AXFocus",
          fallbackUsed: false,
          code: elementFocused ? nil : "element_focus_failed",
          error: elementFocused
            ? nil
            : "The target element was found, but it did not accept accessibility focus."
        )
      case .failed(let code, let error, let details):
        elementTargeting = unresolvedElementTargetingMetadata(
          arguments: arguments,
          status: "failed",
          code: code,
          error: error,
          details: details,
          fallbackUsed: false
        )
      }
    }

    var extra: [String: Any] = [
      "ok": focused || app != nil,
      "windowId": window.windowID,
      "ownerPid": window.ownerPID,
      "appName": window.ownerName,
      "title": window.title,
      "focusedWindow": focused,
      "spaceStatus": window.spaceStatus,
      "spaceSupport": windowSpaceSupportMetadata(spaceScope: .allSpaces),
      "nextAction": window.isOnScreen
        ? "Run computer_vision_observe again before the next desktop action."
        : "macOS may switch to the window Space during activation. Run computer_vision_observe again before any input action.",
    ]
    if let elementTargeting {
      extra["elementTargeting"] = elementTargeting
    }

    return baseResponse(
      extra: extra
    )
  }

  private func screenshotWindow(arguments: [String: Any]) -> [String: Any] {
    guard computerUsePermissionSnapshot().screenCaptureGranted else {
      return screenCaptureDeniedResponse()
    }

    guard let windowID = windowID(arguments: arguments) else {
      return errorResponse(code: "invalid_args", error: "window_id is required")
    }
    guard
      let window = findWindow(
        windowID: windowID,
        spaceScope: .allSpaces,
        includeHidden: true
      )
    else {
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
          "spaceStatus": window.spaceStatus,
          "spaceSupport": windowSpaceSupportMetadata(spaceScope: .allSpaces),
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

    let buttonName = (arguments["button"] as? String ?? "left").lowercased()
    let clickCount = max(1, min(intValue(arguments["click_count"] ?? arguments["clickCount"]) ?? 1, 3))
    let button = mouseButton(buttonName)
    let downType = mouseDownType(buttonName)
    let upType = mouseUpType(buttonName)

    if accessibilityElementTargetID(arguments: arguments) != nil {
      switch resolveAccessibilityElementTarget(arguments: arguments) {
      case .resolved(let target):
        let pressResult = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
        if pressResult == .success {
          return baseResponse(
            extra: [
              "button": buttonName,
              "clickCount": clickCount,
              "elementTargeting": target.metadata(
                status: "resolved",
                action: "AXPress",
                fallbackUsed: false
              ),
            ]
          )
        }

        if let point = target.centerPoint {
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
              "elementTargeting": target.metadata(
                status: "fallback",
                action: "element_frame_center_click",
                fallbackUsed: true,
                code: "element_press_failed",
                error: "The target element did not accept AXPress, so the helper clicked the element frame center."
              ),
            ]
          )
        }

        var response = errorResponse(
          code: "element_press_failed",
          error: "The target element did not accept AXPress and has no frame for a safe fallback click."
        )
        response["elementTargeting"] = target.metadata(
          status: "failed",
          action: "AXPress",
          fallbackUsed: false,
          code: "element_frame_unavailable",
          error: "The target element did not expose a usable frame."
        )
        return response
      case .failed(let code, let error, let details):
        if let point = resolvePoint(arguments: arguments) {
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
              "elementTargeting": unresolvedElementTargetingMetadata(
                arguments: arguments,
                status: "fallback",
                code: code,
                error: error,
                details: details,
                fallbackUsed: true
              ),
            ]
          )
        }
        var response = errorResponse(code: code, error: error, details: details)
        response["elementTargeting"] = unresolvedElementTargetingMetadata(
          arguments: arguments,
          status: "failed",
          code: code,
          error: error,
          details: details,
          fallbackUsed: false
        )
        return response
      }
    }

    guard let point = resolvePoint(arguments: arguments) else {
      return errorResponse(code: "invalid_args", error: "x and y are required")
    }

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

    var elementTargeting: [String: Any]?
    if accessibilityElementTargetID(arguments: arguments) != nil {
      switch resolveAccessibilityElementTarget(arguments: arguments) {
      case .resolved(let target):
        let focusResult = focusAccessibilityElement(target.element, appElement: target.appElement)
        if focusResult == .success {
          elementTargeting = target.metadata(
            status: "resolved",
            action: "AXFocus",
            fallbackUsed: false
          )
        } else if let point = target.centerPoint {
          postMouseEvent(type: .leftMouseDown, point: point, button: .left)
          postMouseEvent(type: .leftMouseUp, point: point, button: .left)
          usleep(80_000)
          elementTargeting = target.metadata(
            status: "fallback",
            action: "element_frame_center_click",
            fallbackUsed: true,
            code: "element_focus_failed",
            error: "The target element did not accept accessibility focus, so the helper clicked the element frame center before typing."
          )
        } else {
          var response = errorResponse(
            code: "element_focus_failed",
            error: "The target element did not accept accessibility focus and has no frame for a safe focus fallback."
          )
          response["elementTargeting"] = target.metadata(
            status: "failed",
            action: "AXFocus",
            fallbackUsed: false,
            code: "element_frame_unavailable",
            error: "The target element did not expose a usable frame."
          )
          return response
        }
      case .failed(let code, let error, let details):
        var response = errorResponse(code: code, error: error, details: details)
        response["elementTargeting"] = unresolvedElementTargetingMetadata(
          arguments: arguments,
          status: "failed",
          code: code,
          error: error,
          details: details,
          fallbackUsed: false
        )
        return response
      }
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

    var extra: [String: Any] = ["characters": text.count]
    if let elementTargeting {
      extra["elementTargeting"] = elementTargeting
    }
    return baseResponse(extra: extra)
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
      "xpcConnectionMode": ComputerUseHelperIpcSchema.xpcConnectionMode,
      "xpcRegistrationRequirement": ComputerUseHelperIpcSchema.xpcRegistrationRequirement,
      "xpcProductionBlockers": ComputerUseHelperIpcSchema.xpcProductionBlockers,
      "xpcProductionNextAction": ComputerUseHelperIpcSchema.xpcProductionNextAction,
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
    if let lastOnboardingTransition = ComputerUseHelperApp.currentOnboardingTransitionMap() {
      response["lastOnboardingTransition"] = lastOnboardingTransition
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
    if let lastOnboardingTransition = ComputerUseHelperApp.currentOnboardingTransitionMap() {
      status["lastOnboardingTransition"] = lastOnboardingTransition
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

  private func screenCaptureDeniedResponse() -> [String: Any] {
    errorResponse(
      code: "screen_capture_denied",
      error: "Screen & System Audio Recording permission is required. Grant Caverno Computer Use in System Settings > Privacy & Security > Screen & System Audio Recording."
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
      "helperBundlePath": Bundle.main.bundlePath,
      "helperExecutablePath": Bundle.main.executablePath ?? "",
      "helperProcessIdentifier": Int(ProcessInfo.processInfo.processIdentifier),
      "processName": ProcessInfo.processInfo.processName,
      "arguments": ProcessInfo.processInfo.arguments,
      "listenerStarted": started,
      "requestNotificationName": requestName.rawValue,
      "responseNotificationName": responseName.rawValue,
      "ipcTransport": ComputerUseHelperIpcSchema.activeTransport,
      "preferredIpcTransport": ComputerUseHelperIpcSchema.preferredTransport,
      "fallbackIpcTransport": ComputerUseHelperIpcSchema.fallbackTransport,
      "xpcReady": ComputerUseHelperIpcSchema.xpcReady,
      "xpcProductionReady": ComputerUseHelperIpcSchema.xpcProductionReady,
      "xpcStatus": ComputerUseHelperIpcSchema.xpcStatus,
      "xpcConnectionMode": ComputerUseHelperIpcSchema.xpcConnectionMode,
      "xpcRegistrationRequirement": ComputerUseHelperIpcSchema.xpcRegistrationRequirement,
      "xpcProductionBlockers": ComputerUseHelperIpcSchema.xpcProductionBlockers,
      "xpcProductionNextAction": ComputerUseHelperIpcSchema.xpcProductionNextAction,
      "mainAppUnsafeOsActionsAllowed": ComputerUseHelperIpcSchema.mainAppUnsafeOsActionsAllowed,
      "helperOwnsUnsafeOsActions": ComputerUseHelperIpcSchema.helperOwnsUnsafeOsActions,
      "helperOwnedActionCategories": ComputerUseHelperIpcSchema.helperOwnedActionCategories,
      "xpcNextParityCommands": ComputerUseHelperIpcSchema.xpcNextParityCommands,
      "xpcProductionReadinessCriteria": ComputerUseHelperIpcSchema.xpcProductionReadinessCriteria,
      "xpcListenerStarted": xpcListenerStarted,
      "xpcListenerStartAttempted": xpcListenerStartAttempted,
      "xpcServiceName": ComputerUseHelperIpcSchema.xpcServiceName,
      "helperIpcEventCount": helperIpcEventCount,
    ]
    ComputerUseHelperSharedDiagnostics.addBootstrapExtra(to: &diagnostics)
    if let lastHelperIpcRequest {
      diagnostics["lastHelperIpcRequest"] = lastHelperIpcRequest
    }
    if let lastOnboardingVerification {
      diagnostics["onboardingVerification"] = lastOnboardingVerification
    }
    if let lastOnboardingTransition = ComputerUseHelperApp.currentOnboardingTransitionMap() {
      diagnostics["lastOnboardingTransition"] = lastOnboardingTransition
    }
    ComputerUseHelperSharedDiagnostics.write(diagnostics)
  }
}

private func resolveScreen(arguments: [String: Any]) -> ScreenDescriptor? {
  let requestedDisplayId = directDisplayIdValue(arguments["display_id"] ?? arguments["displayId"])
  let requestedDisplayIndex = intValue(arguments["display_index"] ?? arguments["displayIndex"])
  let screens = displayDescriptors()
  if let requestedDisplayId {
    for screen in screens {
      if screen.displayID == requestedDisplayId {
        return screen
      }
    }
    return nil
  }
  if let requestedDisplayIndex {
    for screen in screens {
      if screen.index == requestedDisplayIndex {
        return screen
      }
    }
    return nil
  }
  return screens.first(where: { $0.isMain }) ?? screens.first
}

private func displayDescriptors() -> [ScreenDescriptor] {
  NSScreen.screens.enumerated().map { index, screen in
    ScreenDescriptor(screen: screen, index: index)
  }
}

private func visibleWindows() -> [WindowDescriptor] {
  windowDescriptors(spaceScope: .activeSpace, includeHidden: false)
}

private func windowDescriptors(
  spaceScope: WindowSpaceScope,
  includeHidden: Bool
) -> [WindowDescriptor] {
  let options: CGWindowListOption = spaceScope == .allSpaces
    ? [.optionAll, .excludeDesktopElements]
    : [.optionOnScreenOnly, .excludeDesktopElements]
  guard
    let windowInfoList = CGWindowListCopyWindowInfo(
      options,
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
    if !includeHidden && alpha <= 0 {
      return nil
    }
    let isOnScreen =
      boolValue(info[kCGWindowIsOnscreen as String]) ?? (spaceScope == .activeSpace)
    if spaceScope == .activeSpace && !includeHidden && !isOnScreen {
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
      isOnScreen: isOnScreen
    )
  }
}

private func windowSpaceSupportMetadata(spaceScope: WindowSpaceScope) -> [String: Any] {
  [
    "desktopModel": "macos_spaces",
    "requestedScope": spaceScope.rawValue,
    "activeSpaceOnly": spaceScope == .activeSpace,
    "allSpacesBestEffort": spaceScope == .allSpaces,
    "spaceIdentifiersAvailable": false,
    "spaceNamesAvailable": false,
    "switchingRequiresApprovedInput": true,
    "switchSpaceKeys": [
      "previous": ["key": "left", "modifiers": ["control"]],
      "next": ["key": "right", "modifiers": ["control"]],
    ],
  ]
}

private func windowSpaceNextAction(spaceScope: WindowSpaceScope) -> String {
  switch spaceScope {
  case .activeSpace:
    return "Use space_scope=all_spaces when the target app may be on another macOS Space."
  case .allSpaces:
    return "Windows marked not_on_active_space_or_hidden may require focusing the window or an approved Control-Left/Right Space switch, followed by computer_vision_observe, before any input action."
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
    displayScreenshotStep: verifyOnboardingDisplayScreenshot(permissions: permissions),
    windowCaptureStep: verifyOnboardingWindowCapture(permissions: permissions)
  )
}

private func verifyOnboardingDisplayScreenshot(
  permissions: PermissionSnapshot
) -> OnboardingVerificationStep {
  guard permissions.screenCaptureGranted else {
    return OnboardingVerificationStep(
      id: "display_screenshot",
      label: "Display Screenshot",
      ok: false,
      detail: "Screen Recording required"
    )
  }
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

private func verifyOnboardingWindowCapture(
  permissions: PermissionSnapshot
) -> OnboardingVerificationStep {
  guard permissions.screenCaptureGranted else {
    return OnboardingVerificationStep(
      id: "window_capture",
      label: "Window Capture",
      ok: false,
      detail: "Screen Recording required"
    )
  }
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

private func findWindow(
  windowID: Int,
  spaceScope: WindowSpaceScope = .activeSpace,
  includeHidden: Bool = false
) -> WindowDescriptor? {
  windowDescriptors(spaceScope: spaceScope, includeHidden: includeHidden)
    .first { $0.windowID == windowID }
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

private func focusedAccessibilityWindow(appElement: AXUIElement) -> AXUIElement? {
  var value: CFTypeRef?
  let copyResult = AXUIElementCopyAttributeValue(
    appElement,
    kAXFocusedWindowAttribute as CFString,
    &value
  )
  guard copyResult == .success else {
    return nil
  }
  guard let value else {
    return nil
  }
  return (value as! AXUIElement)
}

private func firstAccessibilityWindow(appElement: AXUIElement) -> AXUIElement? {
  var value: CFTypeRef?
  let copyResult = AXUIElementCopyAttributeValue(
    appElement,
    kAXWindowsAttribute as CFString,
    &value
  )
  guard copyResult == .success, let windows = value as? [AXUIElement] else {
    return nil
  }
  return windows.first
}

private func accessibilitySnapshotElements(
  root: AXUIElement,
  maxDepth: Int,
  maxElements: Int,
  labelMaxCharacters: Int
) -> AccessibilityTraversalResult {
  var elements: [[String: Any]] = []
  var truncatedByElementLimit = false
  var truncatedByDepthLimit = false
  var labelTruncatedCount = 0

  func visit(_ element: AXUIElement, depth: Int, parentId: String?) {
    guard elements.count < maxElements else {
      truncatedByElementLimit = true
      return
    }

    let children = accessibilityChildren(element)
    let elementId = String(format: "ax-%04d", elements.count + 1)
    let snapshot = accessibilityElementMap(
      element: element,
      elementId: elementId,
      parentId: parentId,
      depth: depth,
      children: children,
      labelMaxCharacters: labelMaxCharacters
    )
    if snapshot.labelTruncated {
      labelTruncatedCount += 1
    }
    elements.append(snapshot.map)

    guard depth < maxDepth else {
      if !children.isEmpty {
        truncatedByDepthLimit = true
      }
      return
    }

    for child in children {
      guard elements.count < maxElements else {
        truncatedByElementLimit = true
        break
      }
      visit(child, depth: depth + 1, parentId: elementId)
    }
  }

  visit(root, depth: 0, parentId: nil)
  return AccessibilityTraversalResult(
    elements: elements,
    truncatedByElementLimit: truncatedByElementLimit,
    truncatedByDepthLimit: truncatedByDepthLimit,
    labelTruncatedCount: labelTruncatedCount
  )
}

private func accessibilityElementMap(
  element: AXUIElement,
  elementId: String,
  parentId: String?,
  depth: Int,
  children: [AXUIElement],
  labelMaxCharacters: Int
) -> (map: [String: Any], labelTruncated: Bool) {
  let role = accessibilityStringAttribute(element, kAXRoleAttribute as String) ?? "unknown"
  let subrole = accessibilityStringAttribute(element, kAXSubroleAttribute as String)
  let label = accessibilityLabel(
    element: element,
    maxCharacters: labelMaxCharacters
  )
  let enabled = accessibilityBoolAttribute(element, kAXEnabledAttribute as String)
  let focused = accessibilityBoolAttribute(element, kAXFocusedAttribute as String)
  let frame = accessibilityFrame(element)
  let secure = isSecureAccessibilityElement(
    element: element,
    role: role,
    subrole: subrole
  )

  var redaction: [String: Any] = [
    "policy": "metadata_only",
    "labelTruncated": label.truncated,
    "labelMaxCharacters": labelMaxCharacters,
    "valueOmitted": true,
    "selectedTextOmitted": true,
    "rawAttributeValuesOmitted": true,
  ]
  if secure {
    redaction["secureValueOmitted"] = true
  }

  var map: [String: Any] = [
    "elementId": elementId,
    "depth": depth,
    "role": role,
    "label": label.value ?? "",
    "labelAvailable": label.value != nil,
    "frame": frame ?? NSNull(),
    "frameKnown": frame != nil,
    "enabled": enabled ?? false,
    "enabledKnown": enabled != nil,
    "focused": focused ?? false,
    "focusedKnown": focused != nil,
    "childCount": children.count,
    "redaction": redaction,
  ]
  if let parentId {
    map["parentId"] = parentId
  }
  if let subrole, !subrole.isEmpty {
    map["subrole"] = subrole
  }
  if let labelSource = label.source {
    map["labelSource"] = labelSource
  }
  return (map, label.truncated)
}

private func accessibilityChildren(_ element: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  let copyResult = AXUIElementCopyAttributeValue(
    element,
    kAXChildrenAttribute as CFString,
    &value
  )
  guard copyResult == .success else {
    return []
  }
  return value as? [AXUIElement] ?? []
}

private func accessibilityLabel(
  element: AXUIElement,
  maxCharacters: Int
) -> AccessibilityLabelSnapshot {
  for candidate in [
    (kAXTitleAttribute as String, "title"),
    (kAXDescriptionAttribute as String, "description"),
    (kAXHelpAttribute as String, "help"),
    ("AXIdentifier", "identifier"),
  ] {
    guard let value = accessibilityStringAttribute(element, candidate.0) else {
      continue
    }
    let bounded = boundedAccessibilityString(
      value,
      maxCharacters: maxCharacters
    )
    return AccessibilityLabelSnapshot(
      value: bounded.value,
      source: candidate.1,
      truncated: bounded.truncated
    )
  }
  return AccessibilityLabelSnapshot(value: nil, source: nil, truncated: false)
}

private func accessibilityStringAttribute(
  _ element: AXUIElement,
  _ attribute: String
) -> String? {
  var value: CFTypeRef?
  let copyResult = AXUIElementCopyAttributeValue(
    element,
    attribute as CFString,
    &value
  )
  guard copyResult == .success else {
    return nil
  }
  let rawValue: String?
  if let stringValue = value as? String {
    rawValue = stringValue
  } else if let attributedValue = value as? NSAttributedString {
    rawValue = attributedValue.string
  } else {
    rawValue = nil
  }
  guard
    let rawValue,
    !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  else {
    return nil
  }
  return rawValue
    .replacingOccurrences(of: "\n", with: " ")
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func accessibilityBoolAttribute(
  _ element: AXUIElement,
  _ attribute: String
) -> Bool? {
  var value: CFTypeRef?
  let copyResult = AXUIElementCopyAttributeValue(
    element,
    attribute as CFString,
    &value
  )
  guard copyResult == .success else {
    return nil
  }
  if let boolValue = value as? Bool {
    return boolValue
  }
  if let numberValue = value as? NSNumber {
    return numberValue.boolValue
  }
  return nil
}

private func accessibilityFrameRect(_ element: AXUIElement) -> CGRect? {
  guard
    let position = accessibilityPointAttribute(element, kAXPositionAttribute as String),
    let size = accessibilitySizeAttribute(element, kAXSizeAttribute as String)
  else {
    return nil
  }
  return CGRect(
    x: position.x,
    y: position.y,
    width: size.width,
    height: size.height
  )
}

private func accessibilityFrame(_ element: AXUIElement) -> [String: Double]? {
  guard let frame = accessibilityFrameRect(element) else {
    return nil
  }
  return rectMap(frame)
}

private func accessibilityPointAttribute(
  _ element: AXUIElement,
  _ attribute: String
) -> CGPoint? {
  var value: CFTypeRef?
  let copyResult = AXUIElementCopyAttributeValue(
    element,
    attribute as CFString,
    &value
  )
  guard
    copyResult == .success,
    let value,
    CFGetTypeID(value) == AXValueGetTypeID()
  else {
    return nil
  }
  let axValue = value as! AXValue
  guard AXValueGetType(axValue) == .cgPoint else {
    return nil
  }
  var point = CGPoint.zero
  guard AXValueGetValue(axValue, .cgPoint, &point) else {
    return nil
  }
  return point
}

private func accessibilitySizeAttribute(
  _ element: AXUIElement,
  _ attribute: String
) -> CGSize? {
  var value: CFTypeRef?
  let copyResult = AXUIElementCopyAttributeValue(
    element,
    attribute as CFString,
    &value
  )
  guard
    copyResult == .success,
    let value,
    CFGetTypeID(value) == AXValueGetTypeID()
  else {
    return nil
  }
  let axValue = value as! AXValue
  guard AXValueGetType(axValue) == .cgSize else {
    return nil
  }
  var size = CGSize.zero
  guard AXValueGetValue(axValue, .cgSize, &size) else {
    return nil
  }
  return size
}

private func boundedAccessibilityString(
  _ value: String,
  maxCharacters: Int
) -> (value: String, truncated: Bool) {
  if value.count <= maxCharacters {
    return (value, false)
  }
  let prefixLength = max(0, maxCharacters - 3)
  return ("\(value.prefix(prefixLength))...", true)
}

private func isSecureAccessibilityElement(
  element: AXUIElement,
  role: String,
  subrole: String?
) -> Bool {
  let roleText = "\(role) \(subrole ?? "")".lowercased()
  if roleText.contains("secure") {
    return true
  }
  return accessibilityBoolAttribute(element, "AXProtectedContent") == true
}

private enum AccessibilityElementTargetLookup {
  case resolved(AccessibilityElementTargetResolution)
  case failed(code: String, error: String, details: Any?)
}

private struct AccessibilityElementTargetResolution {
  let requestedElementId: String
  let elementId: String
  let element: AXUIElement
  let appElement: AXUIElement
  let window: WindowDescriptor
  let role: String
  let subrole: String?
  let label: String?
  let labelSource: String?
  let frame: CGRect?
  let enabled: Bool?
  let focused: Bool?
  let childCount: Int
  let matchedBy: String

  var centerPoint: CGPoint? {
    guard let frame, frame.width > 0, frame.height > 0 else {
      return nil
    }
    return CGPoint(x: frame.midX, y: frame.midY)
  }

  func metadata(
    status: String,
    action: String,
    fallbackUsed: Bool,
    code: String? = nil,
    error: String? = nil
  ) -> [String: Any] {
    var map: [String: Any] = [
      "requested": true,
      "requestedElementId": requestedElementId,
      "elementId": elementId,
      "status": status,
      "action": action,
      "fallbackUsed": fallbackUsed,
      "windowId": window.windowID,
      "appName": window.ownerName,
      "title": window.title,
      "role": role,
      "label": label ?? "",
      "labelAvailable": label != nil,
      "frameKnown": frame != nil,
      "enabledKnown": enabled != nil,
      "focusedKnown": focused != nil,
      "childCount": childCount,
      "matchedBy": matchedBy,
      "coordinateSpace": "screen_points",
    ]
    if let subrole, !subrole.isEmpty {
      map["subrole"] = subrole
    }
    if let labelSource {
      map["labelSource"] = labelSource
    }
    if let frame {
      map["frame"] = rectMap(frame)
      if let centerPoint {
        map["center"] = pointMap(centerPoint)
      }
    }
    if let enabled {
      map["enabled"] = enabled
    }
    if let focused {
      map["focused"] = focused
    }
    if let code {
      map["code"] = code
    }
    if let error {
      map["error"] = error
    }
    return map
  }
}

private func accessibilityElementTargetID(arguments: [String: Any]) -> String? {
  if let value = stringValue(arguments["element_id"] ?? arguments["elementId"]) {
    return value
  }
  guard let target = arguments["target"] else {
    return nil
  }
  if let targetMap = target as? [String: Any] {
    return stringValue(targetMap["element_id"] ?? targetMap["elementId"])
  }
  if let targetMap = target as? NSDictionary {
    return stringValue(targetMap["element_id"] ?? targetMap["elementId"])
  }
  return nil
}

private func resolveAccessibilityElementTarget(
  arguments: [String: Any]
) -> AccessibilityElementTargetLookup {
  guard let elementId = accessibilityElementTargetID(arguments: arguments) else {
    return .failed(
      code: "element_target_not_requested",
      error: "element_id is required for element-targeted execution.",
      details: nil
    )
  }
  guard let windowID = windowID(arguments: arguments) else {
    return .failed(
      code: "element_target_window_required",
      error: "window_id is required with element_id.",
      details: elementId
    )
  }
  guard let window = findWindow(windowID: windowID) else {
    return .failed(
      code: "window_not_found",
      error: "No matching window is available.",
      details: windowID
    )
  }

  let appElement = AXUIElementCreateApplication(pid_t(window.ownerPID))
  guard let axWindow = findAccessibilityWindow(appElement: appElement, windowID: windowID) else {
    return .failed(
      code: "accessibility_window_not_found",
      error: "No matching accessibility window is available.",
      details: windowID
    )
  }

  guard
    let element = findAccessibilityElementTarget(
      root: axWindow,
      appElement: appElement,
      window: window,
      targetElementId: elementId,
      maxDepth: clampedInt(
        arguments["max_accessibility_depth"] ?? arguments["maxAccessibilityDepth"],
        defaultValue: 4,
        minimum: 0,
        maximum: 8
      ),
      maxElements: clampedInt(
        arguments["max_accessibility_elements"] ?? arguments["maxAccessibilityElements"],
        defaultValue: 80,
        minimum: 1,
        maximum: 200
      ),
      labelMaxCharacters: clampedInt(
        arguments["label_max_characters"] ?? arguments["labelMaxCharacters"],
        defaultValue: 120,
        minimum: 20,
        maximum: 240
      )
    )
  else {
    return .failed(
      code: "element_target_not_found",
      error: "The requested accessibility element was not found in the target window.",
      details: [
        "elementId": elementId,
        "windowId": windowID,
      ]
    )
  }
  return .resolved(element)
}

private func findAccessibilityElementTarget(
  root: AXUIElement,
  appElement: AXUIElement,
  window: WindowDescriptor,
  targetElementId: String,
  maxDepth: Int,
  maxElements: Int,
  labelMaxCharacters: Int
) -> AccessibilityElementTargetResolution? {
  var visitedCount = 0

  func visit(_ element: AXUIElement, depth: Int) -> AccessibilityElementTargetResolution? {
    guard visitedCount < maxElements else {
      return nil
    }

    let children = accessibilityChildren(element)
    visitedCount += 1
    let elementId = String(format: "ax-%04d", visitedCount)
    if elementId == targetElementId {
      let role = accessibilityStringAttribute(element, kAXRoleAttribute as String) ?? "unknown"
      let subrole = accessibilityStringAttribute(element, kAXSubroleAttribute as String)
      let label = accessibilityLabel(element: element, maxCharacters: labelMaxCharacters)
      return AccessibilityElementTargetResolution(
        requestedElementId: targetElementId,
        elementId: elementId,
        element: element,
        appElement: appElement,
        window: window,
        role: role,
        subrole: subrole,
        label: label.value,
        labelSource: label.source,
        frame: accessibilityFrameRect(element),
        enabled: accessibilityBoolAttribute(element, kAXEnabledAttribute as String),
        focused: accessibilityBoolAttribute(element, kAXFocusedAttribute as String),
        childCount: children.count,
        matchedBy: "accessibility_snapshot_order"
      )
    }

    guard depth < maxDepth else {
      return nil
    }
    for child in children {
      if let found = visit(child, depth: depth + 1) {
        return found
      }
    }
    return nil
  }

  return visit(root, depth: 0)
}

private func focusAccessibilityElement(
  _ element: AXUIElement,
  appElement: AXUIElement
) -> AXError {
  let appResult = AXUIElementSetAttributeValue(
    appElement,
    kAXFocusedUIElementAttribute as CFString,
    element
  )
  if appResult == .success {
    return appResult
  }
  return AXUIElementSetAttributeValue(
    element,
    kAXFocusedAttribute as CFString,
    kCFBooleanTrue
  )
}

private func unresolvedElementTargetingMetadata(
  arguments: [String: Any],
  status: String,
  code: String,
  error: String,
  details: Any?,
  fallbackUsed: Bool
) -> [String: Any] {
  var map: [String: Any] = [
    "requested": true,
    "requestedElementId": accessibilityElementTargetID(arguments: arguments) ?? "",
    "status": status,
    "code": code,
    "error": error,
    "fallbackUsed": fallbackUsed,
  ]
  if let windowID = windowID(arguments: arguments) {
    map["windowId"] = windowID
  }
  if let details {
    map["details"] = details
  }
  return map
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

  if let requestedWindowID = windowID(arguments: arguments) {
    guard let window = findWindow(windowID: requestedWindowID) else {
      return nil
    }
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

private func stringValue(_ value: Any?) -> String? {
  if let value = value as? String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
  if let value = value as? NSNumber {
    return value.stringValue
  }
  return nil
}

private func clampedInt(
  _ value: Any?,
  defaultValue: Int,
  minimum: Int,
  maximum: Int
) -> Int {
  max(minimum, min(intValue(value) ?? defaultValue, maximum))
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

private struct AccessibilityTraversalResult {
  let elements: [[String: Any]]
  let truncatedByElementLimit: Bool
  let truncatedByDepthLimit: Bool
  let labelTruncatedCount: Int
}

private struct AccessibilityLabelSnapshot {
  let value: String?
  let source: String?
  let truncated: Bool
}

private enum ComputerUseError: Error {
  case imageResizeFailed
  case imageEncodeFailed
}

private enum WindowSpaceScope: String {
  case activeSpace = "active_space"
  case allSpaces = "all_spaces"

  init(arguments: [String: Any]) {
    let rawValue = ((arguments["space_scope"] as? String) ?? (arguments["spaceScope"] as? String) ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    switch rawValue {
    case "all", "all_spaces", "all_desktops", "all_desktop_spaces":
      self = .allSpaces
    default:
      self = .activeSpace
    }
  }
}

private struct ScreenDescriptor {
  let screen: NSScreen
  let index: Int
  let displayID: CGDirectDisplayID
  let bounds: CGRect
  let isMain: Bool
  let name: String

  init(screen: NSScreen, index: Int) {
    self.screen = screen
    self.index = index
    self.displayID = screen.displayID
    self.bounds = CGDisplayBounds(screen.displayID)
    self.isMain = screen.displayID == NSScreen.main?.displayID
    self.name = screen.localizedName
  }

  func toMap() -> [String: Any] {
    [
      "displayId": displayID,
      "displayIndex": index,
      "name": name,
      "isMain": isMain,
      "isActive": CGDisplayIsActive(displayID) != 0,
      "isBuiltin": CGDisplayIsBuiltin(displayID) != 0,
      "bounds": rectMap(bounds),
      "frame": rectMap(screen.frame),
      "visibleFrame": rectMap(screen.visibleFrame),
      "pixelWidth": CGDisplayPixelsWide(displayID),
      "pixelHeight": CGDisplayPixelsHigh(displayID),
      "backingScaleFactor": Double(screen.backingScaleFactor),
    ]
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

  var spaceStatus: String {
    if isOnScreen {
      return "active_space_visible"
    }
    if alpha <= 0 {
      return "hidden_or_minimized"
    }
    return "not_on_active_space_or_hidden"
  }

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
      "spaceStatus": spaceStatus,
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
  private let contentStack: NSStackView
  private let placeholderLabel = NSTextField(labelWithString: "COMPLETE IN SYSTEM SETTINGS")
  private let statusLabel = NSTextField(labelWithString: "Unknown")
  private let actionButton: NSButton
  private let pendingBorderLayer = CAShapeLayer()
  private let action: (PermissionRowView) -> Void
  private var isPendingSystemSettings = false

  init(
    symbolName: String,
    title: String,
    subtitle: String,
    buttonTitle: String,
    action: @escaping (PermissionRowView) -> Void
  ) {
    self.action = action
    self.actionButton = NSButton(title: buttonTitle, target: nil, action: nil)
    self.contentStack = NSStackView()
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    pendingBorderLayer.fillColor = NSColor.clear.cgColor
    pendingBorderLayer.strokeColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
    pendingBorderLayer.lineWidth = 1
    pendingBorderLayer.lineDashPattern = [6, 6]
    pendingBorderLayer.isHidden = true
    layer?.addSublayer(pendingBorderLayer)

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
    textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
    statusLabel.setContentHuggingPriority(.required, for: .horizontal)
    statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    actionButton.target = self
    actionButton.action = #selector(runAction)
    actionButton.bezelStyle = .rounded
    actionButton.setContentHuggingPriority(.required, for: .horizontal)
    actionButton.setContentCompressionResistancePriority(.required, for: .horizontal)

    let trailingStack = NSStackView(views: [statusLabel, actionButton])
    trailingStack.orientation = .horizontal
    trailingStack.alignment = .centerY
    trailingStack.spacing = 10
    trailingStack.setContentHuggingPriority(.required, for: .horizontal)
    trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    contentStack.setViews([icon, textStack, spacer, trailingStack], in: .leading)
    contentStack.orientation = .horizontal
    contentStack.alignment = .centerY
    contentStack.spacing = 14
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentStack)

    placeholderLabel.font = .systemFont(ofSize: 12, weight: .bold)
    placeholderLabel.textColor = .tertiaryLabelColor
    placeholderLabel.alignment = .center
    placeholderLabel.isHidden = true
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(placeholderLabel)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(greaterThanOrEqualToConstant: 78),
      icon.widthAnchor.constraint(equalToConstant: 36),
      icon.heightAnchor.constraint(equalToConstant: 36),
      contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
      contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
      placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
      placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
      placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func layout() {
    super.layout()
    updatePendingBorder()
  }

  func setGranted(_ granted: Bool) {
    statusLabel.stringValue = granted ? "Done" : "Missing"
    statusLabel.textColor = granted ? .systemGreen : .secondaryLabelColor
    actionButton.isHidden = granted
    if granted {
      setPendingSystemSettings(false)
    }
  }

  func setPendingSystemSettings(_ pending: Bool) {
    isPendingSystemSettings = pending
    contentStack.isHidden = pending
    placeholderLabel.isHidden = !pending
    layer?.backgroundColor = pending
      ? NSColor.windowBackgroundColor.withAlphaComponent(0.3).cgColor
      : NSColor.controlBackgroundColor.cgColor
    pendingBorderLayer.isHidden = !pending
    updatePendingBorder()
  }

  var pendingSystemSettingsShown: Bool {
    isPendingSystemSettings && !placeholderLabel.isHidden
  }

  private func updatePendingBorder() {
    pendingBorderLayer.frame = bounds
    pendingBorderLayer.path = CGPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
      cornerWidth: 10,
      cornerHeight: 10,
      transform: nil
    )
  }

  func snapshotImage() -> NSImage? {
    guard bounds.width > 0, bounds.height > 0 else {
      return nil
    }
    guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
      return nil
    }
    cacheDisplay(in: bounds, to: representation)
    let image = NSImage(size: bounds.size)
    image.addRepresentation(representation)
    return image
  }

  func screenFrame() -> NSRect? {
    guard let window else {
      return nil
    }
    return window.convertToScreen(convert(bounds, to: nil))
  }

  @objc private func runAction() {
    action(self)
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
    textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    statusLabel.setContentHuggingPriority(.required, for: .horizontal)
    statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let rowStack = NSStackView(views: [icon, textStack, spacer, statusLabel])
    rowStack.orientation = .horizontal
    rowStack.alignment = .centerY
    rowStack.spacing = 12
    rowStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(rowStack)

    NSLayoutConstraint.activate([
      heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
      icon.widthAnchor.constraint(equalToConstant: 24),
      icon.heightAnchor.constraint(equalToConstant: 24),
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
