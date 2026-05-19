#!/usr/bin/env swift

import Cocoa
import Foundation

private enum Ipc {
  static let protocolVersion = 1
  static let mainAppBundleIdentifier = "com.noguwo.apps.caverno"
  static let helperBundleIdentifier = "com.noguwo.apps.caverno.computer-use"
  static let requestName = Notification.Name("com.caverno.computer_use.helper.request")
  static let responseName = Notification.Name("com.caverno.computer_use.helper.response")

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

private struct Config {
  var appPath: String
  var helperPath: String
  var reportPath: String
  var launchMissingApps = true
  var launchMissingApp = true
  var launchMissingHelper = true
  var requireCaptureReady = false
  var requireInputReady = false
  var requireAudioResolved = false
  var requireAppPathMatch = false
  var requireHelperPathMatch = false
  var replaceMismatchedApp = false
  var replaceMismatchedHelper = false
  var desktopActionCanary = false
  var spacesCanary = false
  var spacesFocusCanary = false
  var spacesSwitchCanary = false
  var spacesSwitchDirection = "next"
  var requireInactiveSpaceWindow = false
  var fixtureTarget = false
}

private final class HelperProbeClient: NSObject {
  private let center = DistributedNotificationCenter.default()
  private var pendingRequestId: String?
  private var receivedUserInfo: [AnyHashable: Any]?

  override init() {
    super.init()
    center.addObserver(
      self,
      selector: #selector(handleResponse(_:)),
      name: Ipc.responseName,
      object: nil,
      suspensionBehavior: .deliverImmediately
    )
    center.suspended = false
  }

  deinit {
    center.removeObserver(self)
  }

  func send(
    command: String,
    arguments: [String: Any],
    senderProcessIdentifier: Int,
    timeout: TimeInterval
  ) -> [String: Any] {
    let requestId = UUID().uuidString
    pendingRequestId = requestId
    receivedUserInfo = nil

    center.postNotificationName(
      Ipc.requestName,
      object: Ipc.mainAppBundleIdentifier,
      userInfo: [
        Ipc.Field.protocolVersion: Ipc.protocolVersion,
        Ipc.Field.requestId: requestId,
        Ipc.Field.command: command,
        Ipc.Field.senderBundleIdentifier: Ipc.mainAppBundleIdentifier,
        Ipc.Field.senderProcessIdentifier: senderProcessIdentifier,
        Ipc.Field.arguments: arguments,
      ],
      deliverImmediately: true
    )

    let deadline = Date().addingTimeInterval(timeout)
    while receivedUserInfo == nil && Date() < deadline {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    guard let userInfo = receivedUserInfo else {
      return [
        "ok": false,
        "code": "timeout",
        "error": "Caverno Computer Use did not respond before the probe timeout.",
        "requestId": requestId,
        "command": command,
      ]
    }
    let protocolVersion = userInfo[Ipc.Field.protocolVersion] as? Int ?? 0
    let responseCommand = userInfo[Ipc.Field.command] as? String ?? ""
    guard protocolVersion == Ipc.protocolVersion else {
      return [
        "ok": false,
        "code": "unsupported_protocol",
        "error": "Caverno Computer Use returned an unsupported protocol version.",
        "protocolVersion": protocolVersion,
        "requestId": requestId,
        "command": command,
      ]
    }
    guard responseCommand == command else {
      return [
        "ok": false,
        "code": "response_mismatch",
        "error": "Caverno Computer Use returned a response for a different command.",
        "expectedCommand": command,
        "actualCommand": responseCommand,
        "requestId": requestId,
      ]
    }
    guard var response = userInfo[Ipc.Field.response] as? [String: Any] else {
      return [
        "ok": false,
        "code": "invalid_response",
        "error": "Caverno Computer Use returned an invalid response envelope.",
        "requestId": requestId,
        "command": command,
      ]
    }
    response["requestId"] = requestId
    response["command"] = command
    return response
  }

  @objc private func handleResponse(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let requestId = userInfo[Ipc.Field.requestId] as? String,
      requestId == pendingRequestId
    else {
      return
    }
    receivedUserInfo = userInfo
  }
}

private func parseConfig(arguments: [String]) -> Config {
  let root = FileManager.default.currentDirectoryPath
  let defaultAppPath = "\(root)/build/macos/Build/Products/Debug/Caverno.app"
  let defaultHelperPath = "\(defaultAppPath)/Contents/Helpers/Caverno Computer Use.app"
  var config = Config(
    appPath: defaultAppPath,
    helperPath: defaultHelperPath,
    reportPath: "/tmp/caverno-macos-computer-use-existing-helper-probe.json"
  )
  var index = 0
  while index < arguments.count {
    switch arguments[index] {
    case "--app":
      index += 1
      config.appPath = arguments[index]
    case "--helper":
      index += 1
      config.helperPath = arguments[index]
    case "--report":
      index += 1
      config.reportPath = arguments[index]
    case "--no-launch":
      config.launchMissingApps = false
      config.launchMissingApp = false
      config.launchMissingHelper = false
    case "--no-launch-app":
      config.launchMissingApp = false
    case "--no-launch-helper":
      config.launchMissingHelper = false
    case "--require-capture", "--require-capture-ready":
      config.requireCaptureReady = true
    case "--require-input", "--require-input-ready":
      config.requireInputReady = true
    case "--require-audio", "--require-audio-resolved":
      config.requireAudioResolved = true
    case "--require-app-path-match":
      config.requireAppPathMatch = true
    case "--require-helper-path-match":
      config.requireHelperPathMatch = true
    case "--replace-app":
      config.replaceMismatchedApp = true
    case "--replace-helper":
      config.replaceMismatchedHelper = true
    case "--desktop-action-canary":
      config.desktopActionCanary = true
    case "--spaces-canary":
      config.spacesCanary = true
    case "--focus-inactive-space-window", "--spaces-focus-canary":
      config.spacesCanary = true
      config.spacesFocusCanary = true
      config.requireInactiveSpaceWindow = true
    case "--switch-space-next", "--switch-next-space":
      config.spacesCanary = true
      config.spacesSwitchCanary = true
      config.spacesSwitchDirection = "next"
    case "--switch-space-previous", "--switch-previous-space":
      config.spacesCanary = true
      config.spacesSwitchCanary = true
      config.spacesSwitchDirection = "previous"
    case "--switch-space":
      index += 1
      guard index < arguments.count else {
        fatalError("--switch-space requires a value.")
      }
      config.spacesCanary = true
      config.spacesSwitchCanary = true
      config.spacesSwitchDirection = arguments[index].lowercased()
    case "--require-inactive-space-window":
      config.spacesCanary = true
      config.requireInactiveSpaceWindow = true
    case "--fixture-target", "--mvp-fixture":
      config.desktopActionCanary = true
      config.fixtureTarget = true
    default:
      fatalError("Unknown option: \(arguments[index])")
    }
    index += 1
  }
  if config.helperPath.isEmpty {
    config.helperPath = "\(config.appPath)/Contents/Helpers/Caverno Computer Use.app"
  }
  return config
}

private func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
  NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    .first { !$0.isTerminated }
}

private func openApplication(path: String) -> [String: Any] {
  let url = URL(fileURLWithPath: path)
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.activates = true
  let semaphore = DispatchSemaphore(value: 0)
  var result: [String: Any] = ["path": path]
  NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
    if let error {
      result["ok"] = false
      result["error"] = error.localizedDescription
    } else {
      result["ok"] = true
      if let application {
        result["processIdentifier"] = Int(application.processIdentifier)
      }
    }
    semaphore.signal()
  }
  _ = semaphore.wait(timeout: .now() + 8)
  return result
}

private func waitForRunningApplication(
  bundleIdentifier: String,
  timeout: TimeInterval
) -> NSRunningApplication? {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if let application = runningApplication(bundleIdentifier: bundleIdentifier) {
      return application
    }
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
  }
  return runningApplication(bundleIdentifier: bundleIdentifier)
}

private func waitForNoRunningApplication(
  bundleIdentifier: String,
  timeout: TimeInterval
) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if runningApplication(bundleIdentifier: bundleIdentifier) == nil {
      return true
    }
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
  }
  return runningApplication(bundleIdentifier: bundleIdentifier) == nil
}

private func runStep(
  _ steps: inout [[String: Any]],
  id: String,
  label: String,
  operation: () -> [String: Any]
) -> [String: Any] {
  let startedAt = Date()
  let response = operation()
  let ok = response["ok"] as? Bool ?? false
  let step: [String: Any] = [
    "id": id,
    "label": label,
    "ok": ok,
    "elapsedMs": Int(Date().timeIntervalSince(startedAt) * 1000),
    "response": response,
  ]
  steps.append(step)
  return response
}

private func runRetriedStep(
  _ steps: inout [[String: Any]],
  id: String,
  label: String,
  attempts: Int,
  delay: TimeInterval,
  operation: (_ attempt: Int) -> [String: Any]
) -> [String: Any] {
  let startedAt = Date()
  var attemptReports: [[String: Any]] = []
  var finalResponse: [String: Any] = [:]
  for attempt in 1...max(1, attempts) {
    let attemptStartedAt = Date()
    let response = operation(attempt)
    finalResponse = response
    attemptReports.append([
      "attempt": attempt,
      "ok": response["ok"] as? Bool ?? false,
      "code": jsonValue(response["code"] as? String),
      "elapsedMs": Int(Date().timeIntervalSince(attemptStartedAt) * 1000),
    ])
    if response["ok"] as? Bool ?? false {
      break
    }
    if attempt < attempts {
      Thread.sleep(forTimeInterval: delay)
    }
  }
  let ok = finalResponse["ok"] as? Bool ?? false
  let step: [String: Any] = [
    "id": id,
    "label": label,
    "ok": ok,
    "elapsedMs": Int(Date().timeIntervalSince(startedAt) * 1000),
    "attempts": attemptReports,
    "response": finalResponse,
  ]
  steps.append(step)
  return finalResponse
}

private func firstWindowId(_ response: [String: Any]) -> Int? {
  firstWindow(response)?["windowId"] as? Int
}

private func firstWindow(_ response: [String: Any]) -> [String: Any]? {
  for window in windowsArray(response) {
    if let normalized = normalizedWindow(window) {
      return normalized
    }
  }
  return nil
}

private func normalizedWindow(_ window: [String: Any]) -> [String: Any]? {
  if window["windowId"] is Int {
    return window
  }
  if let id = window["window_id"] as? Int {
    var normalized = window
    normalized["windowId"] = id
    return normalized
  }
  return nil
}

private func windowsArray(_ response: [String: Any]) -> [[String: Any]] {
  guard let windows = response["windows"] as? [[String: Any]] else {
    return []
  }
  return windows
}

private func isInactiveSpaceWindow(_ window: [String: Any]) -> Bool {
  let status = (window["spaceStatus"] as? String ?? "").lowercased()
  return !status.isEmpty && status != "active_space_visible"
}

private func numberValue(_ value: Any?) -> Double? {
  if let number = value as? NSNumber {
    return number.doubleValue
  }
  if let double = value as? Double {
    return double
  }
  if let int = value as? Int {
    return Double(int)
  }
  return nil
}

private func focusableInactiveSpaceWindowScore(_ window: [String: Any]) -> Int? {
  guard isInactiveSpaceWindow(window) else {
    return nil
  }

  let appName = (window["appName"] as? String ?? "").lowercased()
  let title = (window["title"] as? String ?? "").trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  let knownServiceApps = [
    "cursoruiviewservice",
    "systemuiserver",
    "controlcenter",
    "notificationcenter",
    "textinputmenuagent",
  ]
  if knownServiceApps.contains(where: { appName.contains($0) }) {
    return nil
  }

  if let layer = numberValue(window["layer"]), layer != 0 {
    return nil
  }
  if let alpha = numberValue(window["alpha"]), alpha <= 0 {
    return nil
  }

  let bounds = window["bounds"] as? [String: Any] ?? [:]
  let width = numberValue(bounds["width"]) ?? 0
  let height = numberValue(bounds["height"]) ?? 0
  guard width >= 160, height >= 120 else {
    return nil
  }

  var score = 0
  if !title.isEmpty {
    score += 100
  }
  if width >= 360, height >= 240 {
    score += 40
  }
  if !appName.isEmpty {
    score += 20
  }
  return score
}

private func windowFocusSignature(_ window: [String: Any]) -> String? {
  let appName = (window["appName"] as? String ?? "").trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  let title = (window["title"] as? String ?? "").trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  guard !appName.isEmpty, !title.isEmpty else {
    return nil
  }
  return "\(appName.lowercased())\u{0}\(title.lowercased())"
}

private func windowAppName(_ window: [String: Any]) -> String? {
  let appName = (window["appName"] as? String ?? "").trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  return appName.isEmpty ? nil : appName.lowercased()
}

private func activeWindowAppNames(_ response: [String: Any]) -> Set<String> {
  Set(windowsArray(response).compactMap { window in
    windowAppName(normalizedWindow(window) ?? window)
  })
}

private func activeWindowFocusSignatures(_ response: [String: Any]) -> Set<String> {
  Set(windowsArray(response).compactMap { window in
    windowFocusSignature(normalizedWindow(window) ?? window)
  })
}

private func firstFocusableInactiveSpaceWindow(
  _ response: [String: Any],
  activeWindows: [String: Any]
) -> [String: Any]? {
  let activeApps = activeWindowAppNames(activeWindows)
  let activeSignatures = activeWindowFocusSignatures(activeWindows)
  var bestDistinctAppWindow: [String: Any]?
  var bestDistinctAppScore = Int.min
  var bestDistinctWindow: [String: Any]?
  var bestDistinctScore = Int.min
  var bestFallbackWindow: [String: Any]?
  var bestFallbackScore = Int.min

  for window in windowsArray(response) {
    guard let normalized = normalizedWindow(window),
      let score = focusableInactiveSpaceWindowScore(normalized) else {
      continue
    }
    if score > bestFallbackScore {
      bestFallbackWindow = normalized
      bestFallbackScore = score
    }
    let signature = windowFocusSignature(normalized)
    let duplicatesActiveWindow = signature.map(activeSignatures.contains) ?? false
    let appName = windowAppName(normalized)
    let duplicatesActiveApp = appName.map(activeApps.contains) ?? false
    if !duplicatesActiveApp, !duplicatesActiveWindow, score > bestDistinctAppScore {
      bestDistinctAppWindow = normalized
      bestDistinctAppScore = score
    }
    if !duplicatesActiveWindow, score > bestDistinctScore {
      bestDistinctWindow = normalized
      bestDistinctScore = score
    }
  }
  return bestDistinctAppWindow ?? bestDistinctWindow ?? bestFallbackWindow
}

private func windowInventoryContains(windowID: Int, response: [String: Any]) -> Bool {
  windowsArray(response).contains { window in
    intWindowId(normalizedWindow(window) ?? window) == windowID
  }
}

private func windowIdSet(_ response: [String: Any]) -> Set<Int> {
  Set(windowsArray(response).compactMap { window in
    intWindowId(normalizedWindow(window) ?? window)
  })
}

private func sortedWindowIds(_ response: [String: Any]) -> [Int] {
  windowIdSet(response).sorted()
}

private func activeSpaceInventoryAttempt(
  attempt: Int,
  response: [String: Any],
  beforeWindowIds: Set<Int>
) -> [String: Any] {
  let currentWindowIds = windowIdSet(response)
  return [
    "attempt": attempt,
    "ok": response["ok"] as? Bool ?? false,
    "activeWindowCount": currentWindowIds.count,
    "activeWindowIds": currentWindowIds.sorted(),
    "activeWindowInventoryChanged": currentWindowIds != beforeWindowIds,
  ]
}

private func fixtureWindow(_ response: [String: Any]) -> [String: Any]? {
  windowsArray(response).first { window in
    let appName = (window["appName"] as? String ?? "").lowercased()
    let title = (window["title"] as? String ?? "").lowercased()
    return appName.contains("caverno computer use mvp fixtur")
      || title.contains("caverno computer use mvp fixture")
  }
}

private func intWindowId(_ window: [String: Any]?) -> Int? {
  guard let window else {
    return nil
  }
  if let id = window["windowId"] as? Int {
    return id
  }
  if let id = window["window_id"] as? Int {
    return id
  }
  return nil
}

private func hasImage(_ response: [String: Any]) -> Bool {
  guard let image = response["imageBase64"] as? String else {
    return false
  }
  return !image.isEmpty
}

private func clickPoint(for capture: [String: Any], fixtureTarget: Bool) -> [String: Any] {
  let width = (capture["width"] as? NSNumber)?.doubleValue
    ?? capture["width"] as? Double
    ?? 400
  let height = (capture["height"] as? NSNumber)?.doubleValue
    ?? capture["height"] as? Double
    ?? 300
  let xRatio = fixtureTarget ? 0.18 : 0.50
  let yRatio = fixtureTarget ? 0.58 : 0.50
  return [
    "x": max(8, min(width - 8, width * xRatio)),
    "y": max(8, min(height - 8, height * yRatio)),
    "source_width": Int(width),
    "source_height": Int(height),
  ]
}

private func desktopActionGate(
  preObserve: [String: Any],
  click: [String: Any],
  postObserve: [String: Any],
  targetWindow: [String: Any]?
) -> [String: Any] {
  let preOk = preObserve["ok"] as? Bool ?? false
  let clickOk = click["ok"] as? Bool ?? false
  let postOk = postObserve["ok"] as? Bool ?? false
  let preImage = hasImage(preObserve)
  let postImage = hasImage(postObserve)
  let ready = preOk && preImage && clickOk && postOk && postImage
  var blockers: [String] = []
  if !preOk {
    blockers.append("initial_vision_observe_failed")
  }
  if preOk && !preImage {
    blockers.append("initial_vision_image_missing")
  }
  if !clickOk {
    blockers.append("armed_click_failed_or_skipped")
  }
  if !postOk {
    blockers.append("post_click_vision_observe_failed")
  }
  if postOk && !postImage {
    blockers.append("post_click_vision_image_missing")
  }
  return [
    "status": ready ? "ready" : "blocked",
    "ok": ready,
    "purpose": "computer_use_desktop_action_canary",
    "tccBoundary": "manual_user_operated",
    "requiredAction": "computer_click",
    "targetWindow": jsonValue(targetWindow),
    "initialObservationImageAttached": preImage,
    "clickPassed": clickOk,
    "postClickObservationImageAttached": postImage,
    "blockers": blockers,
    "nextAction": ready
      ? "Desktop action canary observed, clicked, and observed again without rebuilding."
      : "Grant required TCC permissions to the existing helper path, keep the safe target visible, then rerun the no-build desktop action canary.",
  ]
}

private func buildSpacesCanaryGate(
  activeWindows: [String: Any],
  allSpacesWindows: [String: Any],
  requireInactiveSpaceWindow: Bool
) -> [String: Any] {
  let activeOk = activeWindows["ok"] as? Bool ?? false
  let allSpacesOk = allSpacesWindows["ok"] as? Bool ?? false
  let allSpacesScope = allSpacesWindows["spaceScope"] as? String ?? ""
  let support = allSpacesWindows["spaceSupport"] as? [String: Any] ?? [:]
  let desktopModel = support["desktopModel"] as? String ?? ""
  let allSpacesBestEffort = support["allSpacesBestEffort"] as? Bool ?? false
  let switchingRequiresApprovedInput =
    support["switchingRequiresApprovedInput"] as? Bool ?? false
  let activeWindowCount = windowsArray(activeWindows).count
  let allSpacesWindowList = windowsArray(allSpacesWindows)
  let allSpacesWindowCount = allSpacesWindowList.count
  let windowsCarrySpaceStatus = allSpacesWindowList.allSatisfy { window in
    window["spaceStatus"] is String
  }
  let inactiveSpaceWindows = allSpacesWindowList.filter { window in
    let status = (window["spaceStatus"] as? String ?? "").lowercased()
    return !status.isEmpty && status != "active_space_visible"
  }

  var blockers: [String] = []
  if !activeOk {
    blockers.append("active_space_window_inventory_failed")
  }
  if !allSpacesOk {
    blockers.append("all_spaces_window_inventory_failed")
  }
  if allSpacesScope != "all_spaces" {
    blockers.append("all_spaces_scope_missing")
  }
  if desktopModel != "macos_spaces" {
    blockers.append("macos_spaces_support_metadata_missing")
  }
  if !allSpacesBestEffort {
    blockers.append("all_spaces_best_effort_metadata_missing")
  }
  if !switchingRequiresApprovedInput {
    blockers.append("approved_space_switch_boundary_missing")
  }
  if !windowsCarrySpaceStatus {
    blockers.append("window_space_status_missing")
  }
  if requireInactiveSpaceWindow && inactiveSpaceWindows.isEmpty {
    blockers.append("inactive_space_window_missing")
  }

  let ready = blockers.isEmpty
  return [
    "status": ready ? "ready" : "blocked",
    "ok": ready,
    "purpose": "computer_use_spaces_canary",
    "desktopModel": "macos_spaces",
    "desktopActionBoundary": "no_desktop_action_observe_only",
    "spaceScope": allSpacesScope,
    "activeSpaceWindowCount": activeWindowCount,
    "allSpacesWindowCount": allSpacesWindowCount,
    "inactiveSpaceWindowCount": inactiveSpaceWindows.count,
    "requireInactiveSpaceWindow": requireInactiveSpaceWindow,
    "windowsCarrySpaceStatus": windowsCarrySpaceStatus,
    "requiresApprovedInputBeforeSwitching": switchingRequiresApprovedInput,
    "spaceIdentifiersAvailable": support["spaceIdentifiersAvailable"] as? Bool ?? false,
    "blockers": blockers,
    "nextAction": ready
      ? "Spaces canary verified all-Spaces window discovery metadata. Focus or switch Spaces only with explicit user approval, then observe again before input."
      : "Prepare at least two macOS Spaces with a harmless target window when inactive Space evidence is required, keep Caverno.app and the helper running, then rerun the Spaces canary.",
  ]
}

private func buildSpacesFocusCanaryGate(
  targetWindow: [String: Any]?,
  focusResult: [String: Any],
  postFocusActiveWindows: [String: Any]
) -> [String: Any] {
  let targetWindowId = intWindowId(targetWindow)
  let focusOk = focusResult["ok"] as? Bool ?? false
  let focusConfirmed = focusResult["focusedWindow"] as? Bool ?? false
  let postFocusOk = postFocusActiveWindows["ok"] as? Bool ?? false
  let targetVisibleAfterFocus = targetWindowId.map {
    windowInventoryContains(windowID: $0, response: postFocusActiveWindows)
  } ?? false

  var blockers: [String] = []
  if targetWindowId == nil {
    blockers.append("inactive_space_focus_target_missing")
  }
  if !focusOk {
    blockers.append("focus_window_failed")
  }
  if focusOk && !focusConfirmed {
    blockers.append("focus_window_not_confirmed")
  }
  if !postFocusOk {
    blockers.append("post_focus_active_space_inventory_failed")
  }
  if targetWindowId != nil && postFocusOk && !targetVisibleAfterFocus {
    blockers.append("focused_window_not_active_after_observe")
  }

  let ready = blockers.isEmpty
  return [
    "status": ready ? "ready" : "blocked",
    "ok": ready,
    "purpose": "computer_use_spaces_focus_canary",
    "desktopModel": "macos_spaces",
    "desktopActionBoundary": "user_operated_focus_only_no_pointer_or_text",
    "targetWindow": jsonValue(targetWindow),
    "targetWindowId": jsonValue(targetWindowId),
    "focusWindowSent": targetWindowId != nil,
    "focusWindowOk": focusOk,
    "focusWindowConfirmed": focusConfirmed,
    "postFocusActiveSpaceObserved": postFocusOk,
    "postFocusTargetVisible": targetVisibleAfterFocus,
    "blockers": blockers,
    "nextAction": ready
      ? "Focus canary verified that the inactive-Space target became visible in the active Space inventory. Run computer_vision_observe before any pointer or keyboard input."
      : "Prepare a normal harmless app window from an app that is not visible on the active Space, grant Accessibility to the helper, then rerun the focus canary.",
  ]
}

private func switchKeyName(direction: String) -> String? {
  switch direction.lowercased() {
  case "next", "right":
    return "right"
  case "previous", "prev", "left":
    return "left"
  default:
    return nil
  }
}

private func normalizedSwitchDirection(_ direction: String) -> String {
  switch direction.lowercased() {
  case "next", "right":
    return "next"
  case "previous", "prev", "left":
    return "previous"
  default:
    return direction.lowercased()
  }
}

private func buildSpacesSwitchCanaryGate(
  direction: String,
  beforeActiveWindows: [String: Any],
  switchResult: [String: Any],
  postSwitchActiveWindows: [String: Any]
) -> [String: Any] {
  let normalizedDirection = normalizedSwitchDirection(direction)
  let keyName = switchKeyName(direction: direction)
  let beforeWindowIds = sortedWindowIds(beforeActiveWindows)
  let postSwitchWindowIds = sortedWindowIds(postSwitchActiveWindows)
  let switchKeyOk = switchResult["ok"] as? Bool ?? false
  let physicalModifiers = switchResult["physicalModifiers"] as? Bool ?? false
  let physicalModifierKeys = switchResult["physicalModifierKeys"] as? [Any] ?? []
  let postSwitchOk = postSwitchActiveWindows["ok"] as? Bool ?? false
  let activeWindowInventoryChanged = beforeWindowIds != postSwitchWindowIds
  let observationAttempts =
    postSwitchActiveWindows["observationAttempts"] as? [[String: Any]] ?? []

  var blockers: [String] = []
  if keyName == nil {
    blockers.append("invalid_space_switch_direction")
  }
  if !switchKeyOk {
    blockers.append("space_switch_keypress_failed")
  }
  if switchKeyOk && !physicalModifiers {
    blockers.append("physical_modifier_key_events_missing")
  }
  if !postSwitchOk {
    blockers.append("post_switch_active_space_inventory_failed")
  }
  if postSwitchOk && !activeWindowInventoryChanged {
    blockers.append("active_space_inventory_unchanged_after_switch")
  }

  let ready = blockers.isEmpty
  return [
    "status": ready ? "ready" : "blocked",
    "ok": ready,
    "purpose": "computer_use_spaces_switch_canary",
    "desktopModel": "macos_spaces",
    "desktopActionBoundary": "user_operated_space_switch_keypress_no_pointer_or_text",
    "direction": normalizedDirection,
    "key": jsonValue(keyName),
    "modifiers": ["control"],
    "switchKeySent": keyName != nil,
    "switchKeyOk": switchKeyOk,
    "physicalModifiers": physicalModifiers,
    "physicalModifierKeys": physicalModifierKeys,
    "postSwitchActiveSpaceObserved": postSwitchOk,
    "activeWindowInventoryChanged": activeWindowInventoryChanged,
    "beforeActiveWindowIds": beforeWindowIds,
    "postSwitchActiveWindowIds": postSwitchWindowIds,
    "beforeActiveWindowCount": beforeWindowIds.count,
    "postSwitchActiveWindowCount": postSwitchWindowIds.count,
    "postSwitchObservationAttempts": observationAttempts,
    "blockers": blockers,
    "nextAction": ready
      ? "Space switch canary verified Control-Left/Right changed the active Space inventory. Run computer_vision_observe before any pointer or keyboard input."
      : "Prepare an adjacent macOS Space with a different harmless window, confirm Mission Control Control-Left/Right shortcuts are enabled, then rerun the Space switch canary.",
  ]
}

private func writeReport(_ report: [String: Any], path: String) {
  guard JSONSerialization.isValidJSONObject(report) else {
    fatalError("Probe report is not valid JSON.")
  }
  let data = try! JSONSerialization.data(
    withJSONObject: report,
    options: [.prettyPrinted, .sortedKeys]
  )
  try! data.write(to: URL(fileURLWithPath: path), options: [.atomic])
  let redactedReport = redactForStdout(report)
  let stdoutData = try! JSONSerialization.data(
    withJSONObject: redactedReport,
    options: [.prettyPrinted, .sortedKeys]
  )
  FileHandle.standardOutput.write(stdoutData)
  FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

private func jsonValue<T>(_ value: T?) -> Any {
  value as Any? ?? NSNull()
}

private func redactForStdout(_ value: Any) -> Any {
  if let dictionary = value as? [String: Any] {
    return dictionary.reduce(into: [String: Any]()) { partial, entry in
      if entry.key == "imageBase64" {
        partial[entry.key] = "<redacted: written to report file>"
      } else {
        partial[entry.key] = redactForStdout(entry.value)
      }
    }
  }
  if let array = value as? [Any] {
    return array.map(redactForStdout)
  }
  return value
}

private let config = parseConfig(arguments: Array(CommandLine.arguments.dropFirst()))
let fileManager = FileManager.default
let appExists = fileManager.fileExists(atPath: config.appPath)
let helperExists = fileManager.fileExists(atPath: config.helperPath)
let configuredAppPath = URL(fileURLWithPath: config.appPath).standardizedFileURL.path
let configuredHelperPath = URL(fileURLWithPath: config.helperPath).standardizedFileURL.path
var launchEvents: [[String: Any]] = []

if config.replaceMismatchedApp,
  let app = runningApplication(bundleIdentifier: Ipc.mainAppBundleIdentifier) {
  let runningPath = app.bundleURL?.standardizedFileURL.path
  if runningPath != configuredAppPath {
    let terminated = app.terminate()
    let stopped = waitForNoRunningApplication(
      bundleIdentifier: Ipc.mainAppBundleIdentifier,
      timeout: 4
    )
    launchEvents.append([
      "role": "app_replace",
      "terminated": terminated,
      "stopped": stopped,
      "previousPath": jsonValue(runningPath),
      "expectedPath": configuredAppPath,
      "previousProcessIdentifier": Int(app.processIdentifier),
    ])
  }
}

if config.replaceMismatchedHelper,
  let helper = runningApplication(bundleIdentifier: Ipc.helperBundleIdentifier) {
  let runningPath = helper.bundleURL?.standardizedFileURL.path
  if runningPath != configuredHelperPath {
    let terminated = helper.terminate()
    let stopped = waitForNoRunningApplication(
      bundleIdentifier: Ipc.helperBundleIdentifier,
      timeout: 4
    )
    launchEvents.append([
      "role": "helper_replace",
      "terminated": terminated,
      "stopped": stopped,
      "previousPath": jsonValue(runningPath),
      "expectedPath": configuredHelperPath,
      "previousProcessIdentifier": Int(helper.processIdentifier),
    ])
  }
}

if config.launchMissingApps && config.launchMissingApp && appExists &&
  runningApplication(bundleIdentifier: Ipc.mainAppBundleIdentifier) == nil {
  launchEvents.append([
    "role": "app",
    "result": openApplication(path: config.appPath),
  ])
  _ = waitForRunningApplication(
    bundleIdentifier: Ipc.mainAppBundleIdentifier,
    timeout: 8
  )
}

if config.launchMissingApps && config.launchMissingHelper && helperExists &&
  runningApplication(bundleIdentifier: Ipc.helperBundleIdentifier) == nil {
  launchEvents.append([
    "role": "helper",
    "result": openApplication(path: config.helperPath),
  ])
  _ = waitForRunningApplication(
    bundleIdentifier: Ipc.helperBundleIdentifier,
    timeout: 8
  )
}

let app = runningApplication(bundleIdentifier: Ipc.mainAppBundleIdentifier)
let helper = runningApplication(bundleIdentifier: Ipc.helperBundleIdentifier)
let appProcessIdentifier = app.map { Int($0.processIdentifier) }
let helperProcessIdentifier = helper.map { Int($0.processIdentifier) }
let runningAppPath = app?.bundleURL?.standardizedFileURL.path
let runningHelperPath = helper?.bundleURL?.standardizedFileURL.path
var steps: [[String: Any]] = []
private let client = HelperProbeClient()

var permissionStatus: [String: Any] = [
  "ok": false,
  "code": "app_not_running",
  "error": config.launchMissingApp
    ? "Caverno.app must be running so the helper can validate the sender bundle."
    : "Caverno.app is not running. Launch it manually, then rerun the probe.",
]
var displayScreenshot: [String: Any] = [:]
var windows: [String: Any] = [:]
var windowCapture: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "Window capture was skipped because no window id was available.",
]
var desktopActionClick: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "Desktop action canary was not requested.",
]
var desktopActionPostCapture: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "Post-click capture was skipped because no click was sent.",
]
var desktopActionTargetWindow: [String: Any]?
var allSpacesWindows: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "macOS Spaces canary was not requested.",
]
var spacesFocusTargetWindow: [String: Any]?
var spacesFocusWindow: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "macOS Spaces focus canary was not requested.",
]
var spacesPostFocusActiveWindows: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "Post-focus active Space inventory was skipped.",
]
var spacesSwitchKeyPress: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "macOS Spaces switch canary was not requested.",
]
var spacesPostSwitchActiveWindows: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "Post-switch active Space inventory was skipped.",
]

if let appProcessIdentifier {
  permissionStatus = runRetriedStep(
    &steps,
    id: "permission_status",
    label: "Read helper-owned permission status",
    attempts: 3,
    delay: 0.5
  ) { _ in
    client.send(
      command: "permissionStatus",
      arguments: [:],
      senderProcessIdentifier: appProcessIdentifier,
      timeout: 6
    )
  }
  displayScreenshot = runStep(
    &steps,
    id: "display_screenshot",
    label: "Capture a display screenshot without rebuilding"
  ) {
    client.send(
      command: "screenshot",
      arguments: ["max_width": 400],
      senderProcessIdentifier: appProcessIdentifier,
      timeout: 8
    )
  }
  windows = runStep(
    &steps,
    id: "list_windows",
    label: "List visible windows without rebuilding"
  ) {
    client.send(
      command: "listWindows",
      arguments: [
        "max_windows": 20,
        "include_current_app": false,
        "main_app_pid": appProcessIdentifier,
      ],
      senderProcessIdentifier: appProcessIdentifier,
      timeout: 4
    )
  }
  if config.spacesCanary {
    allSpacesWindows = runStep(
      &steps,
      id: "list_windows_all_spaces",
      label: "List macOS windows across Spaces without rebuilding"
    ) {
      client.send(
        command: "listWindows",
        arguments: [
          "max_windows": 80,
          "include_current_app": false,
          "include_hidden": true,
          "main_app_pid": appProcessIdentifier,
          "space_scope": "all_spaces",
        ],
        senderProcessIdentifier: appProcessIdentifier,
        timeout: 4
      )
    }
  }
  if config.spacesFocusCanary {
    spacesFocusTargetWindow = firstFocusableInactiveSpaceWindow(
      allSpacesWindows,
      activeWindows: windows
    )
    if let windowId = intWindowId(spacesFocusTargetWindow) {
      spacesFocusWindow = runStep(
        &steps,
        id: "spaces_focus_inactive_window",
        label: "Focus a harmless inactive-Space window without pointer or text input"
      ) {
        client.send(
          command: "focusWindow",
          arguments: [
            "window_id": windowId,
            "reason": "Spaces focus canary was explicitly user-operated and limited to window focus plus re-observation.",
          ],
          senderProcessIdentifier: appProcessIdentifier,
          timeout: 6
        )
      }
      spacesPostFocusActiveWindows = runStep(
        &steps,
        id: "spaces_post_focus_active_windows",
        label: "List active Space windows after focusing the inactive-Space target"
      ) {
        client.send(
          command: "listWindows",
          arguments: [
            "max_windows": 80,
            "include_current_app": false,
            "main_app_pid": appProcessIdentifier,
          ],
          senderProcessIdentifier: appProcessIdentifier,
          timeout: 4
        )
      }
    } else {
      steps.append([
        "id": "spaces_focus_inactive_window",
        "label": "Focus a harmless inactive-Space window without pointer or text input",
        "ok": false,
        "skipped": true,
        "reason": "No inactive Space window was returned.",
      ])
      steps.append([
        "id": "spaces_post_focus_active_windows",
        "label": "List active Space windows after focusing the inactive-Space target",
        "ok": false,
        "skipped": true,
        "reason": "Focus was skipped because no inactive Space window was returned.",
      ])
    }
  }
  if config.spacesSwitchCanary {
    if let keyName = switchKeyName(direction: config.spacesSwitchDirection) {
      spacesSwitchKeyPress = runStep(
        &steps,
        id: "spaces_switch_keypress",
        label: "Switch macOS Space with Control-Left or Control-Right"
      ) {
        client.send(
          command: "pressKey",
          arguments: [
            "key": keyName,
            "modifiers": ["control"],
            "physical_modifiers": true,
            "reason": "Spaces switch canary was explicitly user-operated and limited to a Space-switch keypress plus re-observation.",
          ],
          senderProcessIdentifier: appProcessIdentifier,
          timeout: 4
        )
      }
      spacesPostSwitchActiveWindows = runStep(
        &steps,
        id: "spaces_post_switch_active_windows",
        label: "List active Space windows after switching Spaces"
      ) {
        let beforeWindowIds = windowIdSet(windows)
        var attempts: [[String: Any]] = []
        var finalResponse: [String: Any] = [:]
        for attempt in 1...6 {
          Thread.sleep(forTimeInterval: 0.45)
          let response = client.send(
            command: "listWindows",
            arguments: [
              "max_windows": 80,
              "include_current_app": false,
              "main_app_pid": appProcessIdentifier,
            ],
            senderProcessIdentifier: appProcessIdentifier,
            timeout: 4
          )
          finalResponse = response
          let attemptReport = activeSpaceInventoryAttempt(
            attempt: attempt,
            response: response,
            beforeWindowIds: beforeWindowIds
          )
          attempts.append(attemptReport)
          if attemptReport["ok"] as? Bool ?? false,
            attemptReport["activeWindowInventoryChanged"] as? Bool ?? false {
            break
          }
        }
        finalResponse["observationAttempts"] = attempts
        finalResponse["observedInventoryChange"] = windowIdSet(finalResponse) != beforeWindowIds
        return finalResponse
      }
    } else {
      steps.append([
        "id": "spaces_switch_keypress",
        "label": "Switch macOS Space with Control-Left or Control-Right",
        "ok": false,
        "skipped": true,
        "reason": "Invalid Space switch direction.",
      ])
      steps.append([
        "id": "spaces_post_switch_active_windows",
        "label": "List active Space windows after switching Spaces",
        "ok": false,
        "skipped": true,
        "reason": "Space switch was skipped because the requested direction was invalid.",
      ])
    }
  }
  desktopActionTargetWindow = config.fixtureTarget ? fixtureWindow(windows) : firstWindow(windows)
  let captureWindowId = config.desktopActionCanary
    ? intWindowId(desktopActionTargetWindow)
    : firstWindowId(windows)
  if let windowId = captureWindowId {
    windowCapture = runStep(
      &steps,
      id: "window_capture",
      label: "Capture the first visible window without rebuilding"
    ) {
      client.send(
        command: "screenshotWindow",
        arguments: [
          "window_id": windowId,
          "max_width": 400,
        ],
        senderProcessIdentifier: appProcessIdentifier,
        timeout: 8
      )
    }
  } else {
    steps.append([
      "id": "window_capture",
      "label": "Capture the first visible window without rebuilding",
      "ok": false,
      "skipped": true,
      "reason": "No visible windows were returned.",
    ])
  }
  if config.desktopActionCanary,
     let windowId = intWindowId(desktopActionTargetWindow) {
    _ = runStep(
      &steps,
      id: "desktop_action_focus_window",
      label: "Focus the safe desktop action target without rebuilding"
    ) {
      client.send(
        command: "focusWindow",
        arguments: ["window_id": windowId],
        senderProcessIdentifier: appProcessIdentifier,
        timeout: 4
      )
    }
    if windowCapture["ok"] as? Bool ?? false {
      var clickArguments = clickPoint(
        for: windowCapture,
        fixtureTarget: config.fixtureTarget
      )
      clickArguments["window_id"] = windowId
      clickArguments["button"] = "left"
      clickArguments["click_count"] = 1
      clickArguments["reason"] = "Desktop action canary was explicitly user-operated and armed for a harmless target."
      desktopActionClick = runStep(
        &steps,
        id: "desktop_action_click",
        label: "Click the safe desktop action target without rebuilding"
      ) {
        client.send(
          command: "click",
          arguments: clickArguments,
          senderProcessIdentifier: appProcessIdentifier,
          timeout: 4
        )
      }
      desktopActionPostCapture = runStep(
        &steps,
        id: "desktop_action_post_click_window_capture",
        label: "Capture the desktop action target after clicking without rebuilding"
      ) {
        client.send(
          command: "screenshotWindow",
          arguments: [
            "window_id": windowId,
            "max_width": 400,
          ],
          senderProcessIdentifier: appProcessIdentifier,
          timeout: 8
        )
      }
    } else {
      steps.append([
        "id": "desktop_action_click",
        "label": "Click the safe desktop action target without rebuilding",
        "ok": false,
        "skipped": true,
        "reason": "Initial target capture failed.",
      ])
      steps.append([
        "id": "desktop_action_post_click_window_capture",
        "label": "Capture the desktop action target after clicking without rebuilding",
        "ok": false,
        "skipped": true,
        "reason": "Click was skipped because initial target capture failed.",
      ])
    }
  } else if config.desktopActionCanary {
    steps.append([
      "id": "desktop_action_click",
      "label": "Click the safe desktop action target without rebuilding",
      "ok": false,
      "skipped": true,
      "reason": "No safe target window was available.",
    ])
    steps.append([
      "id": "desktop_action_post_click_window_capture",
      "label": "Capture the desktop action target after clicking without rebuilding",
      "ok": false,
      "skipped": true,
      "reason": "Click was skipped because no target window was available.",
    ])
  }
}

let accessibilityGranted = permissionStatus["accessibilityGranted"] as? Bool ?? false
let screenCaptureGranted = permissionStatus["screenCaptureGranted"] as? Bool ?? false
let audioSupported = permissionStatus["systemAudioRecordingSupported"] as? Bool ?? false
let captureReady = (displayScreenshot["ok"] as? Bool ?? false) &&
  (windows["ok"] as? Bool ?? false) &&
  (windowCapture["ok"] as? Bool ?? false)
let inputReady = accessibilityGranted
let audioResolved = !audioSupported || screenCaptureGranted
let appPathMatchesExpected = runningAppPath == nil ||
  runningAppPath == configuredAppPath
let helperPathMatchesExpected = runningHelperPath == nil ||
  runningHelperPath == configuredHelperPath
let pathMismatchInvalidatesSignoff = (!appPathMatchesExpected || !helperPathMatchesExpected) &&
  (captureReady || inputReady || audioResolved)
let helperPathMismatchInvalidatesSignoff = !helperPathMatchesExpected &&
  (captureReady || inputReady || audioResolved)
let nextAction: String
if !appPathMatchesExpected {
  nextAction = "Stop the running Caverno.app and rerun the probe with --replace-app before using these results for release runtime sign-off."
} else if !helperPathMatchesExpected {
  nextAction = "Stop the standalone helper and rerun the probe with --replace-helper before using these results for embedded-helper sign-off."
} else if !screenCaptureGranted {
  nextAction = "Grant Screen & System Audio Recording to the expected Caverno.app path, then rerun this probe with --require-capture."
} else if !inputReady {
  nextAction = "Grant Accessibility to the expected embedded helper path, then rerun this probe with --require-input."
} else {
  nextAction = "Embedded helper sign-off gates are ready for the requested checks."
}
let requiredChecks: [[String: Any]] = [
  [
    "id": "capture_ready",
    "required": config.requireCaptureReady,
    "ok": !config.requireCaptureReady || captureReady,
  ],
  [
    "id": "input_ready",
    "required": config.requireInputReady,
    "ok": !config.requireInputReady || inputReady,
  ],
  [
    "id": "audio_resolved",
    "required": config.requireAudioResolved,
    "ok": !config.requireAudioResolved || audioResolved,
  ],
  [
    "id": "app_path_match",
    "required": config.requireAppPathMatch,
    "ok": !config.requireAppPathMatch || appPathMatchesExpected,
  ],
  [
    "id": "helper_path_match",
    "required": config.requireHelperPathMatch,
    "ok": !config.requireHelperPathMatch || helperPathMatchesExpected,
  ],
]
let failedRequiredChecks = requiredChecks
  .filter { ($0["required"] as? Bool ?? false) && !($0["ok"] as? Bool ?? false) }
  .compactMap { $0["id"] as? String }
let coreOk = appProcessIdentifier != nil &&
  helperProcessIdentifier != nil &&
  (permissionStatus["ok"] as? Bool ?? false)
let desktopActionCanaryGate: [String: Any] = config.desktopActionCanary
  ? desktopActionGate(
    preObserve: windowCapture,
    click: desktopActionClick,
    postObserve: desktopActionPostCapture,
    targetWindow: desktopActionTargetWindow
  )
  : [
    "status": "not_run",
    "ok": true,
    "blockers": [],
    "nextAction": "Rerun with --desktop-action-canary to run a no-build desktop action canary.",
  ]
let desktopActionOk = !config.desktopActionCanary ||
  (desktopActionCanaryGate["ok"] as? Bool ?? false)
let spacesCanaryGate: [String: Any] = config.spacesCanary
  ? buildSpacesCanaryGate(
    activeWindows: windows,
    allSpacesWindows: allSpacesWindows,
    requireInactiveSpaceWindow: config.requireInactiveSpaceWindow
  )
  : [
    "status": "not_run",
    "ok": true,
    "blockers": [],
    "nextAction": "Rerun with --spaces-canary to validate macOS Spaces window discovery metadata.",
  ]
let spacesCanaryOk = !config.spacesCanary ||
  (spacesCanaryGate["ok"] as? Bool ?? false)
let spacesFocusCanaryGate: [String: Any] = config.spacesFocusCanary
  ? buildSpacesFocusCanaryGate(
    targetWindow: spacesFocusTargetWindow,
    focusResult: spacesFocusWindow,
    postFocusActiveWindows: spacesPostFocusActiveWindows
  )
  : [
    "status": "not_run",
    "ok": true,
    "blockers": [],
    "nextAction": "Rerun with --focus-inactive-space-window to validate user-operated Space focus and re-observation.",
  ]
let spacesFocusCanaryOk = !config.spacesFocusCanary ||
  (spacesFocusCanaryGate["ok"] as? Bool ?? false)
let spacesSwitchCanaryGate: [String: Any] = config.spacesSwitchCanary
  ? buildSpacesSwitchCanaryGate(
    direction: config.spacesSwitchDirection,
    beforeActiveWindows: windows,
    switchResult: spacesSwitchKeyPress,
    postSwitchActiveWindows: spacesPostSwitchActiveWindows
  )
  : [
    "status": "not_run",
    "ok": true,
    "blockers": [],
    "nextAction": "Rerun with --switch-space-next or --switch-space-previous to validate user-operated Space switching and re-observation.",
  ]
let spacesSwitchCanaryOk = !config.spacesSwitchCanary ||
  (spacesSwitchCanaryGate["ok"] as? Bool ?? false)
let ok = coreOk &&
  failedRequiredChecks.isEmpty &&
  desktopActionOk &&
  spacesCanaryOk &&
  spacesFocusCanaryOk &&
  spacesSwitchCanaryOk

let report: [String: Any] = [
  "schemaName": "macos_computer_use_existing_helper_probe",
  "schemaVersion": 1,
  "generatedAt": ISO8601DateFormatter().string(from: Date()),
  "noRebuild": true,
  "desktopActionCanary": config.desktopActionCanary,
  "spacesCanary": config.spacesCanary,
  "spacesFocusCanary": config.spacesFocusCanary,
  "spacesSwitchCanary": config.spacesSwitchCanary,
  "spacesSwitchDirection": normalizedSwitchDirection(config.spacesSwitchDirection),
  "requireInactiveSpaceWindow": config.requireInactiveSpaceWindow,
  "fixtureTarget": config.fixtureTarget,
  "replaceMismatchedApp": config.replaceMismatchedApp,
  "replaceMismatchedHelper": config.replaceMismatchedHelper,
  "launchMissingApp": config.launchMissingApps && config.launchMissingApp,
  "launchMissingHelper": config.launchMissingApps && config.launchMissingHelper,
  "ok": ok,
  "coreOk": coreOk,
  "captureReady": captureReady,
  "inputReady": inputReady,
  "audioResolved": audioResolved,
  "appPathMatchesExpected": appPathMatchesExpected,
  "helperPathMatchesExpected": helperPathMatchesExpected,
  "pathMismatchInvalidatesSignoff": pathMismatchInvalidatesSignoff,
  "helperPathMismatchInvalidatesSignoff": helperPathMismatchInvalidatesSignoff,
  "nextAction": nextAction,
  "requiredChecks": requiredChecks,
  "failedRequiredChecks": failedRequiredChecks,
  "app": [
    "bundleIdentifier": Ipc.mainAppBundleIdentifier,
    "expectedPath": configuredAppPath,
    "exists": appExists,
    "running": appProcessIdentifier != nil,
    "processIdentifier": jsonValue(appProcessIdentifier),
    "runningPath": jsonValue(runningAppPath),
    "pathMatchesExpected": appPathMatchesExpected,
  ],
  "helper": [
    "bundleIdentifier": Ipc.helperBundleIdentifier,
    "expectedPath": configuredHelperPath,
    "exists": helperExists,
    "running": helperProcessIdentifier != nil,
    "processIdentifier": jsonValue(helperProcessIdentifier),
    "runningPath": jsonValue(runningHelperPath),
    "pathMatchesExpected": helperPathMatchesExpected,
  ],
  "launchEvents": launchEvents,
  "permissionSummary": [
    "accessibilityGranted": accessibilityGranted,
    "screenCaptureGranted": screenCaptureGranted,
    "systemAudioRecordingSupported": audioSupported,
  ],
  "desktopActionCanaryGate": desktopActionCanaryGate,
  "spacesCanaryGate": spacesCanaryGate,
  "spacesFocusCanaryGate": spacesFocusCanaryGate,
  "spacesSwitchCanaryGate": spacesSwitchCanaryGate,
  "steps": steps,
]

writeReport(report, path: config.reportPath)
exit(ok ? 0 : 1)
