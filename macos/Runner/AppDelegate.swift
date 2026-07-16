import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    // Finder launches can inherit a closed output pipe; ignore SIGPIPE so
    // incidental logging cannot terminate the app.
    _ = signal(SIGPIPE, SIG_IGN)
    super.init()
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    let arguments = ProcessInfo.processInfo.arguments
    if !Self.isCommandLineInvocation(arguments: arguments) &&
      Self.activateExistingInstanceIfNeeded()
    {
      Darwin.exit(0)
    }
    super.applicationWillFinishLaunching(notification)
  }

  @IBAction func checkForUpdates(_ sender: Any?) {
    MacosSparkleUpdateController.shared.checkForUpdatesFromMenu(sender)
  }

  @IBAction func showSettings(_ sender: Any?) {
    (mainFlutterWindow as? MainFlutterWindow)?.requestOpenSettings()
  }

  @IBAction func requestQuit(_ sender: Any?) {
    (mainFlutterWindow as? MainFlutterWindow)?.requestQuit()
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      sender.unhide(nil)
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  static func isCommandLineInvocation(arguments: [String]) -> Bool {
    guard let firstArgument = arguments.dropFirst().first?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !firstArgument.isEmpty,
      !firstArgument.hasPrefix("-psn_")
    else {
      return false
    }

    let commands: Set<String> = [
      "chat",
      "coding",
      "plan",
      "conversations",
      "--help",
      "-h",
      "--version",
    ]
    return commands.contains(firstArgument) || !firstArgument.hasPrefix("-")
  }

  private static func activateExistingInstanceIfNeeded() -> Bool {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
      return false
    }

    let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    let existingApplication = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ).first { application in
      !application.isTerminated &&
        application.processIdentifier != currentProcessIdentifier
    }
    guard let existingApplication = existingApplication else {
      return false
    }

    _ = existingApplication.activate(
      options: [.activateAllWindows, .activateIgnoringOtherApps]
    )
    return true
  }
}
