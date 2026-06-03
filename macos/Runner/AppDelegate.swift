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
    if Self.activateExistingInstanceIfNeeded() {
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

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
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
