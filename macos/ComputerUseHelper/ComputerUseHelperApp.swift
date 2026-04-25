import AppKit
import ApplicationServices
import CoreGraphics

@main
final class ComputerUseHelperApp: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private var accessibilityRow: PermissionRowView?
  private var screenRecordingRow: PermissionRowView?

  func applicationDidFinishLaunching(_ notification: Notification) {
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
    accessibilityRow?.setGranted(AXIsProcessTrusted())
    if #available(macOS 10.15, *) {
      screenRecordingRow?.setGranted(CGPreflightScreenCaptureAccess())
    } else {
      screenRecordingRow?.setGranted(true)
    }
  }
}

private enum SettingsPane {
  case accessibility
  case screenRecording

  var url: URL? {
    switch self {
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
