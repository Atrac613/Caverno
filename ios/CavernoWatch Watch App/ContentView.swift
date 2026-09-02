import SwiftUI

/// Root view. Routes on the snapshot's status rather than on a tab selection,
/// because the reason to look at the watch is almost always "something is
/// blocked" — putting that behind a tab would defeat the point. Everything
/// else lands on the transcript, which is the screen a person expects when
/// they raise their wrist mid-conversation.
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
    if let approval = snapshot.approval {
      ApprovalView(approval: approval)
    } else if let question = snapshot.question {
      QuestionView(question: question)
    } else {
      TranscriptView(snapshot: snapshot)
    }
  }
}

private struct ConnectingView: View {
  @EnvironmentObject private var client: WatchSessionClient

  var body: some View {
    VStack(spacing: 8) {
      ProgressView()
      Text(client.isReachable ? "Loading…" : "iPhone not reachable")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .onAppear { client.requestSnapshot() }
  }
}
