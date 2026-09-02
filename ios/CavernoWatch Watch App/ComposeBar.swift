import SwiftUI

/// The pinned input row: a "+" for everything that is not typing, and the
/// field itself.
///
/// The field is a `TextFieldLink` rather than a `TextField`. Both open watchOS
/// dictation, but only the link lets the collapsed state be drawn — a capsule
/// with a placeholder, which is the part that makes the screen read as a
/// message thread instead of a form.
struct ComposeBar: View {
  let placeholder: String
  let onSend: (String) -> Void
  let onOpenActions: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Button(action: onOpenActions) {
        Image(systemName: "plus")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
          .frame(width: 30, height: 30)
          .background(Circle().fill(Color.gray.opacity(0.3)))
      }
      .buttonStyle(.plain)

      TextFieldLink(prompt: Text(placeholder)) {
        HStack(spacing: 0) {
          Text(placeholder)
            .font(.footnote)
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.gray.opacity(0.25)))
      } onSubmit: { text in
        onSend(text)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 4)
    .padding(.bottom, 2)
  }
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
