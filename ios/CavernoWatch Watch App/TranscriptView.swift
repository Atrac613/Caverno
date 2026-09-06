import SwiftUI

private struct TranscriptBottomOffsetKey: PreferenceKey {
  static var defaultValue = CGFloat.greatestFiniteMagnitude

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

/// The thread, drawn as a message transcript.
///
/// This replaces the single-answer glance the companion shipped with. The
/// glance answered "what is it doing"; a wrist conversation also needs "what
/// did I just ask", which one trailing paragraph cannot give. The controls
/// that used to sit between the answer and the bottom of the screen moved
/// into the compose bar and the toolbar, so the scroll area holds nothing but
/// the exchange.
struct TranscriptView: View {
  @EnvironmentObject private var client: WatchSessionClient
  @EnvironmentObject private var speaker: WatchSpeaker
  let snapshot: WatchSnapshot

  @State private var showsActions = false
  @State private var isNearBottom = true

  /// Identifies the end of the list so a new bubble can be scrolled to.
  private static let bottomAnchor = "transcript-bottom"
  private static let scrollSpace = "transcript-scroll"

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { proxy in
        GeometryReader { viewport in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
              if snapshot.messagesTruncated {
                caption("Earlier on iPhone")
              }

              if rows.isEmpty {
                emptyState
              } else {
                ForEach(rows) { row in
                  switch row.kind {
                  case .timestamp(let label):
                    caption(label).padding(.vertical, 3)
                  case .message(let message):
                    MessageBubbleView(
                      message: message,
                      liveText: client.streamedText
                    )
                  }
                }
              }

              footer

              Color.clear
                .frame(height: 1)
                .id(Self.bottomAnchor)
                .background {
                  GeometryReader { marker in
                    Color.clear.preference(
                      key: TranscriptBottomOffsetKey.self,
                      value: marker.frame(in: .named(Self.scrollSpace)).maxY
                    )
                  }
                }
            }
            .padding(.horizontal, 2)
          }
          .coordinateSpace(name: Self.scrollSpace)
          // Opens on the newest bubble. `onAppear` alone is not enough: it runs
          // before the scroll view has laid its content out, so the first frame
          // stayed pinned to the top of the thread.
          .defaultScrollAnchor(.bottom)
          .onPreferenceChange(TranscriptBottomOffsetKey.self) { bottom in
            isNearBottom = bottom <= viewport.size.height + 24
          }
          .onChange(of: snapshot.sequence) { _, _ in
            scrollToBottomIfFollowing(proxy)
          }
          .onChange(of: snapshot.conversationId) { _, _ in
            scrollToBottom(proxy)
          }
          .onChange(of: client.streamedText) { _, text in
            speaker.speakIncremental(text)
            scrollToBottomIfFollowing(proxy)
          }
          .onChange(of: client.streamCompletionSequence) { _, _ in
            speaker.finishIncremental(client.streamedText)
          }
        }
      }

      if let attention {
        attentionBanner(attention)
      }

      ComposeBar(
        placeholder: "Message",
        onSend: send,
        onOpenActions: { showsActions = true }
      )
      .background(Color.black)
    }
    .ignoresSafeArea(edges: .bottom)
    .sheet(isPresented: $showsActions) {
      ComposeActionsView(isStreaming: snapshot.status == .streaming)
    }
    // Messages tints the recipient's name; watchOS has no `.principal`
    // toolbar placement to reproduce that with, and a navigation title takes
    // the system's own colour. The thread name is worth more than its hue.
    .navigationTitle(title)
    .toolbar {
      // `conversationsTruncated` alone is enough to open the picker: a frame
      // that overran the payload budget sheds the thread list first, and
      // gating the button on the list itself would take the "More threads on
      // iPhone" notice away with it, leaving the wrist with no sign that
      // other threads exist.
      if snapshot.conversations.count > 1 || snapshot.conversationsTruncated {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink {
            ThreadPickerView(
              conversations: snapshot.conversations,
              currentId: snapshot.conversationId,
              truncated: snapshot.conversationsTruncated
            )
          } label: {
            Image(systemName: "bubble.left.and.bubble.right.fill")
              .foregroundStyle(.white)
          }
          // Tinted here rather than app-wide. A tint on the whole app also
          // repaints every `role: .destructive` button in the accent colour,
          // which turned Deny on the approval screen into an ordinary-looking
          // blue button — the one place on this watch where a destructive
          // action must not look ordinary.
          .tint(BubbleStyle.outgoing)
        }
      }
    }
  }

  // MARK: - Attention

  /// What the wrist is being asked for, if anything.
  ///
  /// These three used to be mutually exclusive `ToolbarItem`s at
  /// `.topBarTrailing`, ranked against each other. watchOS renders one item per
  /// placement, and the thread picker declares that same slot — so on any watch
  /// whose phone has more than one thread, which is the ordinary case, the
  /// picker won and none of them could be reached. The wrist showed no sign at
  /// all that a turn was blocked, while the frame it was drawing said
  /// `waitingApproval`. Ranking the three was never the problem; sharing a slot
  /// with an unranked fourth item was.
  ///
  /// Pinned above the compose bar instead. It cannot collide, it cannot scroll
  /// away, and a blocked turn is worth more than a corner glyph.
  private enum Attention {
    case approval(WatchApproval)
    case question(WatchQuestion)
    case goal(WatchGoal)
  }

  /// A turn blocked on a tool outranks one blocked on a question, and both
  /// outrank a goal that has merely run out of work.
  private var attention: Attention? {
    if let approval = snapshot.approval { return .approval(approval) }
    if let question = snapshot.question { return .question(question) }
    if let goal = snapshot.goalAwaitingConfirmation { return .goal(goal) }
    return nil
  }

  @ViewBuilder
  private func attentionBanner(_ attention: Attention) -> some View {
    NavigationLink {
      switch attention {
      case .approval(let approval): ApprovalView(approval: approval)
      case .question(let question): QuestionView(question: question)
      case .goal(let goal): GoalView(goal: goal)
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: symbol(for: attention))
        Text(label(for: attention))
          .font(.caption2)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .opacity(0.7)
      }
      .foregroundStyle(.orange)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity)
      .background(Color.orange.opacity(0.18), in: Capsule())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 4)
    .padding(.bottom, 4)
    .background(Color.black)
    .accessibilityLabel(accessibilityLabel(for: attention))
  }

  private func symbol(for attention: Attention) -> String {
    switch attention {
    case .approval: return "exclamationmark.triangle.fill"
    case .question: return "questionmark.bubble.fill"
    case .goal: return "target"
    }
  }

  /// Names the thing being asked about, not the category.
  ///
  /// The banner is one line on a small screen, so it carries the command or the
  /// question itself: "Approval required" tells the reader nothing they cannot
  /// see from the colour.
  private func label(for attention: Attention) -> String {
    switch attention {
    case .approval(let approval):
      return approval.title.isEmpty ? "Approval required" : approval.title
    case .question(let question):
      return question.question.isEmpty ? "Question waiting" : question.question
    case .goal(let goal):
      return goal.objective.isEmpty
        ? "Goal awaiting confirmation" : goal.objective
    }
  }

  private func accessibilityLabel(for attention: Attention) -> String {
    switch attention {
    case .approval: return "Approval required"
    case .question: return "Question waiting"
    case .goal: return "Goal awaiting confirmation"
    }
  }

  // MARK: - Rows

  private struct TranscriptRow: Identifiable {
    enum Kind {
      case timestamp(String)
      case message(WatchMessage)
    }

    let id: String
    let kind: Kind
  }

  /// The bubbles to draw.
  ///
  /// Falls back to the standalone last answer when the frame carries no
  /// transcript. The two apps ship as one bundle but are not guaranteed to be
  /// the same build at runtime — a watch keeps its installed companion until
  /// it syncs — and an empty thread would read as lost history rather than as
  /// an older iPhone build.
  private var bubbles: [WatchMessage] {
    if !snapshot.messages.isEmpty { return snapshot.messages }
    let text = snapshot.lastAssistantText
    guard !text.isEmpty else { return [] }
    return [
      WatchMessage(
        id: "last-assistant",
        role: .assistant,
        text: text,
        timestamp: Date()
      )
    ]
  }

  /// Bubbles with a day-and-time header inserted wherever the conversation
  /// paused, the way Messages groups a burst of replies under one timestamp.
  private var rows: [TranscriptRow] {
    var rows: [TranscriptRow] = []
    var previous: Date?
    for message in bubbles {
      let gap = previous.map { message.timestamp.timeIntervalSince($0) }
      if gap == nil || gap! > TranscriptTimestamp.groupingInterval {
        rows.append(
          TranscriptRow(
            id: "timestamp-\(message.id)",
            kind: .timestamp(TranscriptTimestamp.label(for: message.timestamp))
          )
        )
      }
      previous = message.timestamp
      rows.append(TranscriptRow(id: message.id, kind: .message(message)))
    }
    return rows
  }

  // MARK: - Chrome

  private var title: String {
    let title = PlainText.from(snapshot.conversationTitle)
    if !title.isEmpty { return title }
    return snapshot.status == .streaming ? "Working" : "Caverno"
  }

  /// What is true about the turn but is not part of the conversation: how long
  /// it has been running, what is queued behind it, and what failed.
  ///
  /// No spinner here. The typing bubble already says a turn is running, and a
  /// second indicator next to a caption that wraps to two lines left a lone
  /// spinner floating beside them.
  @ViewBuilder
  private var footer: some View {
    if !statusParts.isEmpty {
      caption(statusParts.joined(separator: " · "))
        .multilineTextAlignment(.center)
        .padding(.top, 3)
    }

    if let error = snapshot.error, !error.isEmpty {
      Text(error)
        .font(.caption2)
        .foregroundStyle(.red)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 3)
    }

    if let error = client.lastCommandError, !error.isEmpty {
      Text(error)
        .font(.caption2)
        .foregroundStyle(.red)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 3)
    } else if let notice = client.lastCommandNotice, !notice.isEmpty {
      caption(notice)
        .multilineTextAlignment(.center)
        .padding(.top, 3)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 6) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.title3)
        .foregroundStyle(.secondary)
      Text("No messages yet")
        .font(.headline)
      Text("Tap Message to start")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
    .multilineTextAlignment(.center)
    .accessibilityElement(children: .combine)
  }

  private var statusParts: [String] {
    var parts: [String] = []
    if snapshot.status == .streaming { parts.append(elapsed) }
    // A blocked goal used to read as an idle thread. Naming the blocker is
    // the difference between "this is finished" and "this is stuck".
    if let goal = snapshot.goal, goal.status == .blocked,
      !goal.blockedReason.isEmpty
    {
      parts.append("Blocked: \(goal.blockedReason)")
    }
    if snapshot.queuedCount > 0 { parts.append("\(snapshot.queuedCount) queued") }
    if snapshot.busyThreadCount > 1 {
      parts.append("\(snapshot.busyThreadCount) threads")
    }
    return parts
  }

  private var elapsed: String {
    let seconds = snapshot.elapsedSeconds
    if seconds < 60 { return "\(seconds)s" }
    return "\(seconds / 60)m \(seconds % 60)s"
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption2)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
  }

  // MARK: - Actions

  private func send(_ content: String) {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    speaker.reset()
    // Voice mode is what the person chose to hear, not how they typed: it
    // shortens the phone's answers for speech and holds back auto-continue.
    // Sending it unconditionally, as the old voice screen did, made every
    // wrist message a spoken turn even with the speaker switched off.
    client.sendMessage(trimmed, isVoiceMode: speaker.isEnabled)
  }

  private func scrollToBottom(_ proxy: ScrollViewProxy) {
    withAnimation(.easeOut(duration: 0.2)) {
      proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
    }
  }

  private func scrollToBottomIfFollowing(_ proxy: ScrollViewProxy) {
    guard isNearBottom else { return }
    scrollToBottom(proxy)
  }
}
