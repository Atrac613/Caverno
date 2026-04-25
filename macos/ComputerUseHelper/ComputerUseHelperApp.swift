import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

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

private struct ComputerUseHelperRequest {
  static let protocolVersion = 1
  static let mainAppBundleIdentifier = "com.noguwo.apps.caverno"

  let protocolVersion: Int
  let requestId: String
  let command: ComputerUseHelperCommand
  let senderBundleIdentifier: String
  let senderProcessIdentifier: Int
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
    self.senderBundleIdentifier = userInfo["senderBundleIdentifier"] as? String ?? ""
    self.senderProcessIdentifier = intValue(userInfo["senderProcessIdentifier"]) ?? 0
    self.arguments = userInfo["arguments"] as? [String: Any] ?? [:]
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

private final class ComputerUseHelperIpc: NSObject {
  private let mainAppBundleIdentifier = "com.noguwo.apps.caverno"
  private let helperBundleIdentifier = "com.noguwo.apps.caverno.computer-use"
  private let requestName = Notification.Name("com.caverno.computer_use.helper.request")
  private let responseName = Notification.Name("com.caverno.computer_use.helper.response")
  private let center = DistributedNotificationCenter.default()
  private var audioRecorder: Any?

  func start() {
    center.addObserver(
      self,
      selector: #selector(handleRequest(_:)),
      name: requestName,
      object: mainAppBundleIdentifier,
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
      self?.postResponse(
        requestId: requestId,
        command: request.command,
        response: response
      )
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

  private func postResponse(
    requestId: String,
    command: ComputerUseHelperCommand? = nil,
    response: [String: Any]
  ) {
    var userInfo: [String: Any] = [
      "protocolVersion": ComputerUseHelperRequest.protocolVersion,
      "requestId": requestId,
      "response": response,
    ]
    if let command {
      userInfo["command"] = command.rawValue
    }

    center.postNotificationName(
      responseName,
      object: helperBundleIdentifier,
      userInfo: userInfo,
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
