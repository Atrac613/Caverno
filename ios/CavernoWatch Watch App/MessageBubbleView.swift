import SwiftUI

/// One transcript bubble.
struct MessageBubbleView: View {
  let message: WatchMessage

  /// Text accumulated from this watch's own stream deltas, used in place of
  /// the frame's copy while the answer is being written.
  let liveText: String

  var body: some View {
    HStack(spacing: 0) {
      if isOutgoing { Spacer(minLength: 20) }

      Group {
        if displayText.isEmpty {
          TypingIndicator()
        } else {
          Text(displayText)
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .foregroundStyle(isOutgoing ? Color.white : Color.primary)
        }
      }
      .padding(.vertical, 6)
      .padding(.leading, isOutgoing ? 9 : 13)
      .padding(.trailing, isOutgoing ? 13 : 9)
      .background(
        BubbleShape(isOutgoing: isOutgoing)
          .fill(isOutgoing ? BubbleStyle.outgoing : BubbleStyle.incoming)
      )

      if !isOutgoing { Spacer(minLength: 20) }
    }
  }

  private var isOutgoing: Bool { message.role == .user }

  /// While a turn is in flight the live text is usually ahead of the frame,
  /// but not always: a watch that joined mid-turn has only the deltas sent
  /// since it connected, and the frame carries the whole answer. Taking
  /// whichever is longer covers both without the watch having to know which
  /// case it is in.
  private var displayText: String {
    // Only the model writes Markdown. Running the person's own words through
    // the reducer would eat a literal asterisk or hash they dictated.
    guard !isOutgoing else { return message.text }
    let frameText = PlainText.from(message.text)
    guard message.isStreaming else { return frameText }
    let live = PlainText.from(liveText)
    return live.count >= frameText.count ? live : frameText
  }
}

/// The three-dot bubble Messages shows while the other side is writing.
struct TypingIndicator: View {
  @State private var isAnimating = false

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .frame(width: 5, height: 5)
          .foregroundStyle(.secondary)
          .opacity(isAnimating ? 1 : 0.3)
          .animation(
            .easeInOut(duration: 0.6)
              .repeatForever()
              .delay(Double(index) * 0.2),
            value: isAnimating
          )
      }
    }
    .padding(.vertical, 2)
    .onAppear { isAnimating = true }
  }
}
