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
  var requireCaptureReady = false
  var requireInputReady = false
  var requireAudioResolved = false
  var requireHelperPathMatch = false
  var replaceMismatchedHelper = false
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
    case "--require-capture", "--require-capture-ready":
      config.requireCaptureReady = true
    case "--require-input", "--require-input-ready":
      config.requireInputReady = true
    case "--require-audio", "--require-audio-resolved":
      config.requireAudioResolved = true
    case "--require-helper-path-match":
      config.requireHelperPathMatch = true
    case "--replace-helper":
      config.replaceMismatchedHelper = true
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
  guard let windows = response["windows"] as? [[String: Any]] else {
    return nil
  }
  for window in windows {
    if let id = window["windowId"] as? Int {
      return id
    }
    if let id = window["window_id"] as? Int {
      return id
    }
  }
  return nil
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
let configuredHelperPath = URL(fileURLWithPath: config.helperPath).standardizedFileURL.path
var launchEvents: [[String: Any]] = []

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

if config.launchMissingApps && appExists &&
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

if config.launchMissingApps && helperExists &&
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
let runningHelperPath = helper?.bundleURL?.standardizedFileURL.path
var steps: [[String: Any]] = []
private let client = HelperProbeClient()

var permissionStatus: [String: Any] = [
  "ok": false,
  "code": "app_not_running",
  "error": "Caverno.app must be running so the helper can validate the sender bundle.",
]
var displayScreenshot: [String: Any] = [:]
var windows: [String: Any] = [:]
var windowCapture: [String: Any] = [
  "ok": false,
  "skipped": true,
  "reason": "Window capture was skipped because no window id was available.",
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
  if let windowId = firstWindowId(windows) {
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
}

let accessibilityGranted = permissionStatus["accessibilityGranted"] as? Bool ?? false
let screenCaptureGranted = permissionStatus["screenCaptureGranted"] as? Bool ?? false
let audioSupported = permissionStatus["systemAudioRecordingSupported"] as? Bool ?? false
let captureReady = (displayScreenshot["ok"] as? Bool ?? false) &&
  (windows["ok"] as? Bool ?? false) &&
  (windowCapture["ok"] as? Bool ?? false)
let inputReady = accessibilityGranted
let audioResolved = !audioSupported || screenCaptureGranted
let helperPathMatchesExpected = runningHelperPath == nil ||
  runningHelperPath == configuredHelperPath
let helperPathMismatchInvalidatesSignoff = !helperPathMatchesExpected &&
  (captureReady || inputReady || audioResolved)
let nextAction: String
if !helperPathMatchesExpected {
  nextAction = "Stop the standalone helper and rerun the probe with --replace-helper before using these results for embedded-helper sign-off."
} else if !screenCaptureGranted {
  nextAction = "Grant Screen & System Audio Recording to the expected embedded helper path, then rerun this probe with --require-capture."
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
let ok = coreOk && failedRequiredChecks.isEmpty

let report: [String: Any] = [
  "schemaName": "macos_computer_use_existing_helper_probe",
  "schemaVersion": 1,
  "generatedAt": ISO8601DateFormatter().string(from: Date()),
  "noRebuild": true,
  "replaceMismatchedHelper": config.replaceMismatchedHelper,
  "ok": ok,
  "coreOk": coreOk,
  "captureReady": captureReady,
  "inputReady": inputReady,
  "audioResolved": audioResolved,
  "helperPathMatchesExpected": helperPathMatchesExpected,
  "helperPathMismatchInvalidatesSignoff": helperPathMismatchInvalidatesSignoff,
  "nextAction": nextAction,
  "requiredChecks": requiredChecks,
  "failedRequiredChecks": failedRequiredChecks,
  "app": [
    "bundleIdentifier": Ipc.mainAppBundleIdentifier,
    "path": config.appPath,
    "exists": appExists,
    "running": appProcessIdentifier != nil,
    "processIdentifier": jsonValue(appProcessIdentifier),
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
  "steps": steps,
]

writeReport(report, path: config.reportPath)
exit(ok ? 0 : 1)
