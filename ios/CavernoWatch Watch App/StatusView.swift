import SwiftUI

/// The glance: what the agent is doing right now, and the two things worth
/// doing from the wrist while it does — speak a new instruction, or stop it.
struct StatusView: View {
  @EnvironmentObject private var client: WatchSessionClient
  let snapshot: WatchSnapshot

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        header

        if !displayText.isEmpty {
          Text(displayText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        if let error = snapshot.error, !error.isEmpty {
          Text(error)
            .font(.footnote)
            .foregroundStyle(.red)
        }

        NavigationLink {
          VoiceView()
        } label: {
          Label("Speak", systemImage: "mic.fill")
        }

        if snapshot.status == .streaming {
          Button(role: .destructive) {
            client.cancelStreaming()
          } label: {
            Label("Stop", systemImage: "stop.fill")
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 4)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.headline)
      HStack(spacing: 6) {
        if snapshot.status == .streaming {
          ProgressView().controlSize(.mini)
          Text(elapsed)
        }
        if snapshot.queuedCount > 0 {
          Text("· \(snapshot.queuedCount) queued")
        }
        if snapshot.busyThreadCount > 1 {
          Text("· \(snapshot.busyThreadCount) threads")
        }
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
  }

  private var title: String {
    if !snapshot.conversationTitle.isEmpty { return snapshot.conversationTitle }
    return snapshot.status == .streaming ? "Working" : "Idle"
  }

  /// Prefers live stream text over the last completed answer, so a turn in
  /// flight reads as progress rather than as stale history.
  private var displayText: String {
    client.streamedText.isEmpty ? snapshot.lastAssistantText
      : client.streamedText
  }

  private var elapsed: String {
    let seconds = snapshot.elapsedSeconds
    if seconds < 60 { return "\(seconds)s" }
    return "\(seconds / 60)m \(seconds % 60)s"
  }
}
