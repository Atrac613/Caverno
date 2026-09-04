import SwiftUI

/// The pinned input row: additional actions and the system message input.
///
/// `TextFieldLink` is the public watchOS control for presenting the system
/// input experience. On watchOS 11 and later it resumes the last input method,
/// including Dictation, so the mic follows the same system-owned path as other
/// Watch apps without embedding a keyboard in the app.
struct ComposeBar: View {
  let placeholder: String
  let onSend: (String) -> Void
  let onOpenActions: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Button(action: onOpenActions) {
        Image(systemName: "plus")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: Self.actionsSize, height: Self.actionsSize)
          .background(Circle().fill(Color.gray.opacity(0.3)))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("More")

      TextFieldLink(prompt: Text(placeholder)) {
        HStack(spacing: 5) {
          Text(placeholder)
            .font(.footnote)
            .foregroundStyle(Color.black.opacity(0.65))
          Spacer(minLength: 0)
          Image(systemName: "mic.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.black)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: Self.inputHeight)
        .background(Capsule().fill(Color.white))
        .contentShape(Capsule())
      } onSubmit: { text in
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        onSend(message)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Compose message")
    }
    .padding(.horizontal, 8)
    .padding(.bottom, 10)
  }

  private static let actionsSize: CGFloat = 32
  private static let inputHeight: CGFloat = 40
}

/// What the "+" opens: the controls that used to sit in the middle of the
/// glance and pushed the conversation off the screen.
struct ComposeActionsView: View {
  @EnvironmentObject private var client: WatchSessionClient
  @EnvironmentObject private var speaker: WatchSpeaker
  @Environment(\.dismiss) private var dismiss

  let isStreaming: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        Toggle(isOn: $speaker.isEnabled) {
          Label("Read replies", systemImage: "speaker.wave.2.fill")
        }

        if speaker.isSpeaking {
          Button(role: .destructive) {
            speaker.stop()
            dismiss()
          } label: {
            Label("Stop speaking", systemImage: "speaker.slash.fill")
          }
        }

        if isStreaming {
          Button(role: .destructive) {
            client.cancelStreaming()
            dismiss()
          } label: {
            Label("Stop", systemImage: "stop.fill")
          }
        }
      }
      .padding(.horizontal, 4)
    }
  }
}
