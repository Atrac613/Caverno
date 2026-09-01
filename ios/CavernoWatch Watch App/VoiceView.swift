import SwiftUI

/// Voice chat from the wrist: dictate an instruction, hear the answer.
///
/// Input uses the system text field, which opens watchOS dictation on tap. That
/// keeps audio on the watch instead of shipping a recording to the phone for
/// Whisper, which would add a file transfer in the slowest possible place.
struct VoiceView: View {
  @EnvironmentObject private var client: WatchSessionClient
  @EnvironmentObject private var speaker: WatchSpeaker

  @State private var draft = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        TextField("Speak or type", text: $draft, axis: .vertical)
          .submitLabel(.send)
          .onSubmit(send)

        Button(action: send) {
          Label("Send", systemImage: "paperplane.fill")
            .frame(maxWidth: .infinity)
        }
        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)

        Toggle(isOn: $speaker.isEnabled) {
          Label("Read replies", systemImage: "speaker.wave.2.fill")
        }

        if speaker.isSpeaking {
          Button(role: .destructive, action: speaker.stop) {
            Label("Stop speaking", systemImage: "speaker.slash.fill")
          }
        }

        if !client.streamedText.isEmpty {
          Text(client.streamedText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle("Voice")
    .onChange(of: client.streamedText) { _, text in
      speaker.speakIncremental(text)
    }
  }

  private func send() {
    let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }
    speaker.reset()
    client.sendMessage(content, isVoiceMode: true)
    draft = ""
  }
}
