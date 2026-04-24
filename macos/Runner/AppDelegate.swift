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

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
