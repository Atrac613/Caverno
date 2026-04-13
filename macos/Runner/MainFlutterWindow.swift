import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var securityScopedBookmarkChannel: SecurityScopedBookmarkChannel?

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
