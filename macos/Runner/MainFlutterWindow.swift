import Cocoa
import AVFoundation
import CoreGraphics
import CoreMedia
import FlutterMacOS
import ScreenCaptureKit

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

final class MacosComputerUseChannel {
  private let channel: FlutterMethodChannel
  private var audioRecorder: Any?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.caverno/macos_computer_use",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPermissions":
      result(permissionSnapshot())
    case "requestAccessibility":
      requestAccessibility(result: result)
    case "requestScreenCapture":
      requestScreenCapture(result: result)
    case "openSystemSettings":
      openSystemSettings(call, result: result)
    case "listWindows":
      listWindows(call, result: result)
    case "focusWindow":
      focusWindow(call, result: result)
    case "screenshot":
      takeScreenshot(call, result: result)
    case "screenshotWindow":
      takeWindowScreenshot(call, result: result)
    case "click":
      click(call, result: result)
    case "moveMouse":
      moveMouse(call, result: result)
    case "drag":
      drag(call, result: result)
    case "scroll":
      scroll(call, result: result)
    case "typeText":
      typeText(call, result: result)
    case "pressKey":
      pressKey(call, result: result)
    case "startSystemAudioRecording":
      startSystemAudioRecording(call, result: result)
    case "stopSystemAudioRecording":
      stopSystemAudioRecording(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
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

  private func takeScreenshot(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let screen = resolveScreen(arguments: call.arguments as? [String: Any]) else {
      result(FlutterError(code: "display_not_found", message: "No display is available", details: nil))
      return
    }

    guard let image = CGDisplayCreateImage(screen.displayID) else {
      result(
        FlutterError(
          code: "screenshot_failed",
          message: "Failed to capture the display. Grant Screen Recording permission in System Settings.",
          details: nil
        )
      )
      return
    }

    let arguments = call.arguments as? [String: Any] ?? [:]
    let maxWidth = arguments["max_width"] as? Int ?? arguments["maxWidth"] as? Int
    let encodedImage: EncodedImage
    do {
      encodedImage = try encodePng(image: image, maxWidth: maxWidth)
    } catch {
      result(
        FlutterError(
          code: "image_encode_failed",
          message: "Failed to encode the screenshot",
          details: error.localizedDescription
        )
      )
      return
    }

    result([
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
    ])
  }

  private func listWindows(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    let includeCurrentApp = arguments["include_current_app"] as? Bool
      ?? arguments["includeCurrentApp"] as? Bool
      ?? false
    let maxWindows = max(1, min(arguments["max_windows"] as? Int ?? arguments["maxWindows"] as? Int ?? 80, 200))
    let currentPid = Int(ProcessInfo.processInfo.processIdentifier)
    let windows = visibleWindows()
      .filter { includeCurrentApp || $0.ownerPID != currentPid }
      .prefix(maxWindows)
      .map { $0.toMap() }

    result([
      "windows": Array(windows),
      "count": windows.count,
      "coordinateSpace": "window_pixels",
      "inputOrigin": "top_left",
    ])
  }

  private func focusWindow(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let windowID = windowID(arguments: arguments) else {
      result(FlutterError(code: "invalid_args", message: "window_id is required", details: nil))
      return
    }
    guard let window = findWindow(windowID: windowID) else {
      result(FlutterError(code: "window_not_found", message: "No matching window is available", details: windowID))
      return
    }
    guard AXIsProcessTrusted() else {
      result(permissionError(code: "accessibility_denied"))
      return
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

    result([
      "ok": focused || app != nil,
      "windowId": window.windowID,
      "ownerPid": window.ownerPID,
      "appName": window.ownerName,
      "title": window.title,
      "focusedWindow": focused,
    ])
  }

  private func takeWindowScreenshot(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let windowID = windowID(arguments: arguments) else {
      result(FlutterError(code: "invalid_args", message: "window_id is required", details: nil))
      return
    }
    guard let window = findWindow(windowID: windowID) else {
      result(FlutterError(code: "window_not_found", message: "No matching window is available", details: windowID))
      return
    }

    guard let image = CGWindowListCreateImage(
      .null,
      .optionIncludingWindow,
      CGWindowID(windowID),
      [.boundsIgnoreFraming, .bestResolution]
    ) else {
      result(
        FlutterError(
          code: "screenshot_failed",
          message: "Failed to capture the window. Grant Screen Recording permission in System Settings.",
          details: windowID
        )
      )
      return
    }

    let maxWidth = arguments["max_width"] as? Int ?? arguments["maxWidth"] as? Int
    let encodedImage: EncodedImage
    do {
      encodedImage = try encodePng(image: image, maxWidth: maxWidth)
    } catch {
      result(
        FlutterError(
          code: "image_encode_failed",
          message: "Failed to encode the window screenshot",
          details: error.localizedDescription
        )
      )
      return
    }

    result([
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
    ])
  }

  private func click(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard AXIsProcessTrusted() else {
      result(permissionError(code: "accessibility_denied"))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let point = resolvePoint(arguments: arguments) else {
      result(FlutterError(code: "invalid_args", message: "x and y are required", details: nil))
      return
    }

    let buttonName = (arguments["button"] as? String ?? "left").lowercased()
    let clickCount = max(1, min(arguments["click_count"] as? Int ?? arguments["clickCount"] as? Int ?? 1, 3))
    let button = mouseButton(buttonName)
    let downType = mouseDownType(buttonName)
    let upType = mouseUpType(buttonName)

    for _ in 0..<clickCount {
      postMouseEvent(type: downType, point: point, button: button)
      postMouseEvent(type: upType, point: point, button: button)
      usleep(60_000)
    }

    result(["ok": true, "x": point.x, "y": point.y, "button": buttonName, "clickCount": clickCount])
  }

  private func moveMouse(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard AXIsProcessTrusted() else {
      result(permissionError(code: "accessibility_denied"))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let point = resolvePoint(arguments: arguments) else {
      result(FlutterError(code: "invalid_args", message: "x and y are required", details: nil))
      return
    }

    postMouseEvent(type: .mouseMoved, point: point, button: .left)
    result(["ok": true, "x": point.x, "y": point.y])
  }

  private func drag(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard AXIsProcessTrusted() else {
      result(permissionError(code: "accessibility_denied"))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard
      let fromX = number(arguments["from_x"] ?? arguments["fromX"]),
      let fromY = number(arguments["from_y"] ?? arguments["fromY"]),
      let toX = number(arguments["to_x"] ?? arguments["toX"]),
      let toY = number(arguments["to_y"] ?? arguments["toY"])
    else {
      result(FlutterError(code: "invalid_args", message: "from_x, from_y, to_x, and to_y are required", details: nil))
      return
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
      result(FlutterError(code: "invalid_args", message: "Unable to resolve drag coordinates", details: nil))
      return
    }

    let durationMs = max(50, min(arguments["duration_ms"] as? Int ?? arguments["durationMs"] as? Int ?? 300, 3000))
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

    result(["ok": true, "from": pointMap(fromPoint), "to": pointMap(toPoint), "durationMs": durationMs])
  }

  private func scroll(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard AXIsProcessTrusted() else {
      result(permissionError(code: "accessibility_denied"))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
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
      result(FlutterError(code: "event_failed", message: "Failed to create scroll event", details: nil))
      return
    }
    event.post(tap: .cghidEventTap)
    result(["ok": true, "deltaX": deltaX, "deltaY": deltaY])
  }

  private func typeText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard AXIsProcessTrusted() else {
      result(permissionError(code: "accessibility_denied"))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let text = arguments["text"] as? String, !text.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "text is required", details: nil))
      return
    }

    for scalar in text.unicodeScalars {
      var value = UniChar(scalar.value)
      guard
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
      else {
        continue
      }
      down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
      up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &value)
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
      usleep(10_000)
    }

    result(["ok": true, "characters": text.count])
  }

  private func pressKey(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard AXIsProcessTrusted() else {
      result(permissionError(code: "accessibility_denied"))
      return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    guard let rawKey = arguments["key"] as? String, let keyCode = keyCodes[rawKey.lowercased()] else {
      result(FlutterError(code: "invalid_args", message: "Unsupported key", details: arguments["key"]))
      return
    }

    let flags = eventFlags(arguments["modifiers"] as? [String] ?? [])
    guard
      let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else {
      result(FlutterError(code: "event_failed", message: "Failed to create key event", details: nil))
      return
    }

    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    result(["ok": true, "key": rawKey, "modifiers": arguments["modifiers"] as? [String] ?? []])
  }

  private func startSystemAudioRecording(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard isSystemAudioRecordingSupported() else {
      result(FlutterError(code: "unsupported", message: "System audio recording requires macOS 13 or later", details: nil))
      return
    }
    guard audioRecorder == nil else {
      result(FlutterError(code: "already_recording", message: "System audio recording is already active", details: nil))
      return
    }

    let arguments = call.arguments as? [String: Any] ?? [:]
    let outputPath = arguments["output_path"] as? String ?? arguments["outputPath"] as? String
    let excludeCurrentProcessAudio = arguments["exclude_current_process_audio"] as? Bool
      ?? arguments["excludeCurrentProcessAudio"] as? Bool
      ?? true

    if #available(macOS 13.0, *) {
      let recorder = SystemAudioRecorder()
      audioRecorder = recorder
      recorder.start(outputPath: outputPath, excludeCurrentProcessAudio: excludeCurrentProcessAudio) { [weak self] response in
        if response["ok"] as? Bool != true {
          self?.audioRecorder = nil
        }
        result(response)
      }
    }
  }

  private func stopSystemAudioRecording(result: @escaping FlutterResult) {
    guard let recorder = audioRecorder else {
      result(FlutterError(code: "not_recording", message: "System audio recording is not active", details: nil))
      return
    }

    if #available(macOS 13.0, *), let typedRecorder = recorder as? SystemAudioRecorder {
      typedRecorder.stop { [weak self] response in
        self?.audioRecorder = nil
        result(response)
      }
    } else {
      audioRecorder = nil
      result(FlutterError(code: "unsupported", message: "System audio recording requires macOS 13 or later", details: nil))
    }
  }

  private func resolveScreen(arguments: [String: Any]?) -> ScreenDescriptor? {
    let requestedDisplayId = arguments?["display_id"] as? UInt32 ?? arguments?["displayId"] as? UInt32
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
        let windowID = info[kCGWindowNumber as String] as? Int,
        let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
        let ownerName = info[kCGWindowOwnerName as String] as? String,
        let layer = info[kCGWindowLayer as String] as? Int,
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
    return visibleWindows().first { $0.windowID == windowID }
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
    if let value = arguments["window_id"] as? Int {
      return value
    }
    if let value = arguments["windowId"] as? Int {
      return value
    }
    if let value = arguments["window_id"] as? NSNumber {
      return value.intValue
    }
    if let value = arguments["windowId"] as? NSNumber {
      return value.intValue
    }
    return nil
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
    return EncodedImage(base64: data.base64EncodedString(), width: targetImage.width, height: targetImage.height)
  }

  private func postMouseEvent(type: CGEventType, point: CGPoint, button: CGMouseButton) {
    let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
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
    return [
      "x": Double(rect.origin.x),
      "y": Double(rect.origin.y),
      "width": Double(rect.width),
      "height": Double(rect.height),
    ]
  }

  private func pointMap(_ point: CGPoint) -> [String: Double] {
    return ["x": Double(point.x), "y": Double(point.y)]
  }

  private func permissionError(code: String) -> FlutterError {
    return FlutterError(
      code: code,
      message: "Accessibility permission is required. Grant access in System Settings > Privacy & Security > Accessibility.",
      details: nil
    )
  }
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
    return [
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
    return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
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
final class SystemAudioRecorder: NSObject, SCStreamOutput {
  private var stream: SCStream?
  private var audioFile: AVAudioFile?
  private var outputURL: URL?
  private var startedAt: Date?
  private let queue = DispatchQueue(label: "com.caverno.system-audio-recorder")

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
        completion(["ok": false, "code": "display_not_found", "error": "No display is available"])
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
        completion(["ok": false, "code": "audio_output_failed", "error": error.localizedDescription])
        return
      }

      self.stream = stream
      stream.startCapture { error in
        if let error {
          completion(["ok": false, "code": "recording_start_failed", "error": error.localizedDescription])
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
      completion(["ok": false, "code": "not_recording", "error": "System audio recording is not active"])
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
        completion(["ok": false, "code": "recording_stop_failed", "error": error.localizedDescription])
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

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
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
