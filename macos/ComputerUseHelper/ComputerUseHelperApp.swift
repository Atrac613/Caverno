import AppKit
import ApplicationServices
import CoreGraphics

@main
final class ComputerUseHelperApp: NSObject, NSApplicationDelegate {
  private let ipc = ComputerUseHelperIpc()
  private var window: NSWindow?
  private var accessibilityRow: PermissionRowView?
  private var screenRecordingRow: PermissionRowView?

  func applicationDidFinishLaunching(_ notification: Notification) {
    ipc.start()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
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
    refreshPermissionRows()
  }

  private func makeContentView() -> NSView {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 22
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)

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

    let rows = NSStackView()
    rows.orientation = .vertical
    rows.alignment = .width
    rows.spacing = 12
    rows.translatesAutoresizingMaskIntoConstraints = false

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
    self.accessibilityRow = accessibilityRow
    self.screenRecordingRow = screenRecordingRow

    rows.addArrangedSubview(accessibilityRow)
    rows.addArrangedSubview(screenRecordingRow)

    let footer = NSTextField(
      wrappingLabelWithString:
        "Permissions must be granted manually in System Settings. You can revoke them at any time without removing Caverno."
    )
    footer.font = .systemFont(ofSize: 12, weight: .regular)
    footer.textColor = .tertiaryLabelColor
    footer.alignment = .center
    footer.maximumNumberOfLines = 2

    stack.addArrangedSubview(title)
    stack.addArrangedSubview(subtitle)
    stack.addArrangedSubview(rows)
    stack.addArrangedSubview(footer)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 64),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -64),
      stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      rows.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])

    refreshPermissionRows()
    return root
  }

  private func refreshPermissionRows() {
    let permissions = computerUsePermissionSnapshot()
    accessibilityRow?.setGranted(permissions.accessibilityGranted)
    screenRecordingRow?.setGranted(permissions.screenCaptureGranted)
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

private func computerUsePermissionSnapshot() -> PermissionSnapshot {
  let screenCaptureGranted: Bool
  if #available(macOS 10.15, *) {
    screenCaptureGranted = CGPreflightScreenCaptureAccess()
  } else {
    screenCaptureGranted = true
  }

  let systemAudioRecordingSupported: Bool
  if #available(macOS 13.0, *) {
    systemAudioRecordingSupported = true
  } else {
    systemAudioRecordingSupported = false
  }

  return PermissionSnapshot(
    accessibilityGranted: AXIsProcessTrusted(),
    screenCaptureGranted: screenCaptureGranted,
    systemAudioRecordingSupported: systemAudioRecordingSupported
  )
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
}

private struct ComputerUseHelperRequest {
  static let protocolVersion = 1

  let protocolVersion: Int
  let requestId: String
  let command: ComputerUseHelperCommand
  let arguments: [String: Any]

  init?(userInfo: [AnyHashable: Any]) {
    guard
      let requestId = userInfo["requestId"] as? String,
      let commandName = userInfo["command"] as? String,
      let command = ComputerUseHelperCommand(rawValue: commandName)
    else {
      return nil
    }

    self.protocolVersion = userInfo["protocolVersion"] as? Int ?? 0
    self.requestId = requestId
    self.command = command
    self.arguments = userInfo["arguments"] as? [String: Any] ?? [:]
  }

  var isSupportedProtocolVersion: Bool {
    protocolVersion == Self.protocolVersion
  }
}

private final class ComputerUseHelperIpc: NSObject {
  private let requestName = Notification.Name("com.caverno.computer_use.helper.request")
  private let responseName = Notification.Name("com.caverno.computer_use.helper.response")
  private let center = DistributedNotificationCenter.default()

  func start() {
    center.addObserver(
      self,
      selector: #selector(handleRequest(_:)),
      name: requestName,
      object: nil,
      suspensionBehavior: .deliverImmediately
    )
  }

  @objc private func handleRequest(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let requestId = userInfo["requestId"] as? String
    else {
      return
    }

    guard let request = ComputerUseHelperRequest(userInfo: userInfo) else {
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

    guard request.isSupportedProtocolVersion else {
      postResponse(
        requestId: request.requestId,
        response: errorResponse(
          code: "unsupported_protocol",
          error: "Unsupported computer-use helper protocol version.",
          details: request.protocolVersion
        )
      )
      return
    }

    let response = handle(request: request)
    postResponse(requestId: requestId, response: response)
  }

  private func handle(request: ComputerUseHelperRequest) -> [String: Any] {
    switch request.command {
    case .ping:
      return baseResponse(extra: ["message": "pong"])
    case .permissionStatus:
      return permissionStatus()
    case .openSettings:
      return openSettings(arguments: request.arguments)
    case .stopAll:
      return baseResponse(
        extra: [
          "stoppedAudioRecording": false,
          "cancelledInputEvents": true,
        ]
      )
    case .screenshot:
      return screenshot(arguments: request.arguments)
    case .listWindows:
      return listWindows(arguments: request.arguments)
    case .focusWindow:
      return focusWindow(arguments: request.arguments)
    case .screenshotWindow:
      return screenshotWindow(arguments: request.arguments)
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

  private func baseResponse(ok: Bool = true, extra: [String: Any] = [:]) -> [String: Any] {
    var response: [String: Any] = [
      "ok": ok,
      "backend": "helper",
      "protocolVersion": 1,
      "helperDisplayName": "Caverno Computer Use",
      "helperBundleIdentifier": "com.noguwo.apps.caverno.computer-use",
    ]
    for (key, value) in extra {
      response[key] = value
    }
    return response
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

  private func postResponse(requestId: String, response: [String: Any]) {
    center.postNotificationName(
      responseName,
      object: nil,
      userInfo: [
        "protocolVersion": ComputerUseHelperRequest.protocolVersion,
        "requestId": requestId,
        "response": response,
      ],
      deliverImmediately: true
    )
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

private func rectMap(_ rect: CGRect) -> [String: Double] {
  [
    "x": Double(rect.origin.x),
    "y": Double(rect.origin.y),
    "width": Double(rect.width),
    "height": Double(rect.height),
  ]
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
