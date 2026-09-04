import SwiftUI

/// Root view. Once a snapshot arrives, the watch always opens on the message
/// transcript. Pending interactions stay reachable from the transcript's
/// toolbar instead of replacing the conversation the person came to read.
struct ContentView: View {
  @EnvironmentObject private var client: WatchSessionClient

  var body: some View {
    NavigationStack {
      Group {
        if let snapshot = client.snapshot {
          content(for: snapshot)
        } else {
          ConnectingView()
        }
      }
      // Each screen titles itself: a title set here sits above them in the
      // tree and would win the preference, pinning the bar to one word while
      // the transcript wants to name the thread.
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  @ViewBuilder
  private func content(for snapshot: WatchSnapshot) -> some View {
    TranscriptView(snapshot: snapshot)
  }
}

private struct ConnectingView: View {
  @EnvironmentObject private var client: WatchSessionClient

  var body: some View {
    VStack(spacing: 8) {
      ProgressView()
      Text(connectionLabel)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .onAppear { client.requestSnapshot() }
  }

  private var connectionLabel: String {
    if !client.hasActivated || client.isReachable { return "Loading…" }
    return "iPhone not reachable"
  }
}
