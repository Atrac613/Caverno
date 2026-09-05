import Foundation

/// Swift mirror of the wire models in
/// `lib/features/watch/domain/watch_snapshot.dart`.
///
/// Decoding is deliberately lenient. The iPhone app and this watch app ship as
/// one bundle but are not guaranteed to be the same build at runtime (a watch
/// keeps the previously installed companion until it syncs), so an unknown
/// status or approval kind must degrade rather than fail to decode.

enum WatchTurnStatus: String, Decodable {
  case idle
  case streaming
  case waitingApproval
  case waitingQuestion
  /// The goal harness stopped scheduling and is asking whether the objective
  /// was met. Distinct from `idle`, which is what it used to arrive as: both
  /// mean nothing is running, but only one is waiting on the person.
  case awaitingGoalConfirmation
  case error

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = WatchTurnStatus(rawValue: raw) ?? .idle
  }
}

struct WatchApproval: Decodable, Equatable {
  let id: String
  /// Free-form on purpose; see `WatchApprovalMapper` for why this is not an
  /// enum. An unrecognised kind still renders, read-only.
  let kind: String
  let title: String
  let subtitle: String
  let detail: String
  let canResolveOnWatch: Bool
}

struct WatchQuestionOption: Decodable, Equatable, Identifiable {
  let id: String
  let label: String
}

struct WatchQuestion: Decodable, Equatable {
  let id: String
  let question: String
  let options: [WatchQuestionOption]
  let allowMultiple: Bool
  let allowOther: Bool
  let optionsTruncated: Bool

  private enum CodingKeys: String, CodingKey {
    case id, question, options, allowMultiple, allowOther, optionsTruncated
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    question = try container.decode(String.self, forKey: .question)
    options = try container.decodeIfPresent(
      [WatchQuestionOption].self, forKey: .options) ?? []
    allowMultiple =
      try container.decodeIfPresent(Bool.self, forKey: .allowMultiple) ?? false
    allowOther =
      try container.decodeIfPresent(Bool.self, forKey: .allowOther) ?? false
    optionsTruncated =
      try container.decodeIfPresent(Bool.self, forKey: .optionsTruncated)
      ?? false
  }
}

/// Who a transcript bubble belongs to.
enum WatchMessageRole: String, Decodable {
  case user
  case assistant

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = WatchMessageRole(rawValue: raw) ?? .assistant
  }
}

/// One bubble in the transcript.
struct WatchMessage: Decodable, Equatable, Identifiable {
  let id: String
  let role: WatchMessageRole
  let text: String
  let timestamp: Date

  /// True while the answer is still being written. The bubble is then drawn
  /// from this watch's own stream deltas rather than from `text`: snapshots
  /// coalesce and deltas do not, so the live text runs ahead of any frame.
  let isStreaming: Bool

  init(
    id: String,
    role: WatchMessageRole,
    text: String,
    timestamp: Date,
    isStreaming: Bool = false
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.timestamp = timestamp
    self.isStreaming = isStreaming
  }

  private enum CodingKeys: String, CodingKey {
    case id, role, text, timestamp, isStreaming
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    role =
      try container.decodeIfPresent(WatchMessageRole.self, forKey: .role)
      ?? .assistant
    text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    timestamp = WatchMessage.parseTimestamp(
      try container.decodeIfPresent(String.self, forKey: .timestamp))
    isStreaming =
      try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
  }

  /// Dart's `toIso8601String()` always emits milliseconds, but a frame from a
  /// build that stops doing so must not lose its whole timestamp — an
  /// undated bubble would sort under the wrong day header.
  private static func parseTimestamp(_ raw: String?) -> Date {
    guard let raw else { return Date() }
    return fractionalFormatter.date(from: raw)
      ?? plainFormatter.date(from: raw)
      ?? Date()
  }

  private static let fractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let plainFormatter = ISO8601DateFormatter()
}

/// The workspace a thread belongs to.
///
/// Decoded from a string with an unknown case rather than a closed enum: the
/// phone gains modes, and a watch older than its phone must show the thread
/// without a label instead of failing to decode the picker.
enum WatchWorkspaceMode: String, Decodable {
  case chat
  case coding
  case routines

  var label: String {
    switch self {
    case .chat: return "Chat"
    case .coding: return "Coding"
    case .routines: return "Routine"
    }
  }
}

struct WatchConversation: Decodable, Equatable, Identifiable {
  let id: String
  let title: String
  let mode: WatchWorkspaceMode?

  private enum CodingKeys: String, CodingKey { case id, title, mode }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    mode = WatchWorkspaceMode(
      rawValue: try container.decodeIfPresent(String.self, forKey: .mode) ?? "")
  }

  init(id: String, title: String, mode: WatchWorkspaceMode? = nil) {
    self.id = id
    self.title = title
    self.mode = mode
  }
}

/// How the conversation goal stands, as the phone reports it.
///
/// A string rather than a closed enum for the same reason as the workspace
/// mode: `ConversationGoalStatus` gains members, and an unknown one must show
/// the objective rather than drop the goal.
enum WatchGoalStatus: String, Decodable {
  case active
  case completed
  case blocked
  case awaitingConfirmation
}

struct WatchGoal: Decodable, Equatable {
  let objective: String
  let status: WatchGoalStatus?
  let completionSummary: String
  let blockedReason: String

  private enum CodingKeys: String, CodingKey {
    case objective, status, completionSummary, blockedReason
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    objective =
      try container.decodeIfPresent(String.self, forKey: .objective) ?? ""
    status = WatchGoalStatus(
      rawValue: try container.decodeIfPresent(String.self, forKey: .status)
        ?? "")
    completionSummary =
      try container.decodeIfPresent(String.self, forKey: .completionSummary)
      ?? ""
    blockedReason =
      try container.decodeIfPresent(String.self, forKey: .blockedReason) ?? ""
  }

  init(
    objective: String,
    status: WatchGoalStatus?,
    completionSummary: String = "",
    blockedReason: String = ""
  ) {
    self.objective = objective
    self.status = status
    self.completionSummary = completionSummary
    self.blockedReason = blockedReason
  }
}

struct WatchSnapshot: Decodable, Equatable {
  let sequence: Int
  let generatedAt: String
  let sourceInstanceId: String
  let sourceStartedAtMicros: Int64
  let conversationId: String?
  let conversationTitle: String
  let workspaceMode: WatchWorkspaceMode?
  let goal: WatchGoal?
  let status: WatchTurnStatus
  /// The most recent answer on its own, kept for the case where this watch is
  /// newer than the iPhone build it is paired with and the frame carries no
  /// transcript. See `TranscriptView.bubbles`.
  let lastAssistantText: String
  let messages: [WatchMessage]
  let messagesTruncated: Bool
  let approval: WatchApproval?
  let question: WatchQuestion?
  let elapsedSeconds: Int
  let queuedCount: Int
  let busyThreadCount: Int
  let conversations: [WatchConversation]
  let conversationsTruncated: Bool
  let error: String?

  var needsAttention: Bool {
    status == .waitingApproval || status == .waitingQuestion
      || status == .awaitingGoalConfirmation
  }

  /// The goal, only while it is actually asking something.
  ///
  /// The transcript shows a goal it cannot act on as context; this is the one
  /// that earns an attention button.
  var goalAwaitingConfirmation: WatchGoal? {
    guard status == .awaitingGoalConfirmation, let goal,
      !goal.objective.isEmpty
    else { return nil }
    return goal
  }

  private enum CodingKeys: String, CodingKey {
    case sequence, generatedAt, sourceInstanceId, sourceStartedAtMicros
    case conversationId, conversationTitle, workspaceMode, goal, status
    case lastAssistantText, messages, messagesTruncated, approval, question
    case elapsedSeconds, queuedCount
    case busyThreadCount, conversations, conversationsTruncated, error
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sequence = try container.decodeIfPresent(Int.self, forKey: .sequence) ?? 0
    generatedAt =
      try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
    sourceInstanceId =
      try container.decodeIfPresent(String.self, forKey: .sourceInstanceId)
      ?? ""
    sourceStartedAtMicros =
      try container.decodeIfPresent(Int64.self, forKey: .sourceStartedAtMicros)
      ?? 0
    conversationId = try container.decodeIfPresent(
      String.self, forKey: .conversationId)
    conversationTitle =
      try container.decodeIfPresent(String.self, forKey: .conversationTitle)
      ?? ""
    workspaceMode = WatchWorkspaceMode(
      rawValue: try container.decodeIfPresent(
        String.self, forKey: .workspaceMode) ?? "")
    goal = try container.decodeIfPresent(WatchGoal.self, forKey: .goal)
    status =
      try container.decodeIfPresent(WatchTurnStatus.self, forKey: .status)
      ?? .idle
    lastAssistantText =
      try container.decodeIfPresent(String.self, forKey: .lastAssistantText)
      ?? ""
    messages =
      try container.decodeIfPresent([WatchMessage].self, forKey: .messages)
      ?? []
    messagesTruncated =
      try container.decodeIfPresent(Bool.self, forKey: .messagesTruncated)
      ?? false
    approval = try container.decodeIfPresent(
      WatchApproval.self, forKey: .approval)
    question = try container.decodeIfPresent(
      WatchQuestion.self, forKey: .question)
    elapsedSeconds =
      try container.decodeIfPresent(Int.self, forKey: .elapsedSeconds) ?? 0
    queuedCount =
      try container.decodeIfPresent(Int.self, forKey: .queuedCount) ?? 0
    busyThreadCount =
      try container.decodeIfPresent(Int.self, forKey: .busyThreadCount) ?? 0
    conversations =
      try container.decodeIfPresent(
        [WatchConversation].self, forKey: .conversations) ?? []
    conversationsTruncated =
      try container.decodeIfPresent(
        Bool.self, forKey: .conversationsTruncated) ?? false
    error = try container.decodeIfPresent(String.self, forKey: .error)
  }
}

/// Orders coalesced and immediate snapshots across iPhone process restarts.
///
/// A sequence is monotonic only for one `WatchSessionNotifier` lifetime. The
/// source start time selects the newest lifetime, then the sequence orders its
/// frames. Source-less snapshots keep the legacy behavior until a source-aware
/// iPhone build has been observed.
struct WatchSnapshotCursor {
  private(set) var sourceInstanceId = ""
  private(set) var sourceStartedAtMicros: Int64 = 0
  private(set) var sequence = 0

  mutating func accepts(_ next: WatchSnapshot) -> Bool {
    let nextSourceId = next.sourceInstanceId.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let hasSource = !nextSourceId.isEmpty && next.sourceStartedAtMicros > 0

    guard hasSource else {
      // Once a source-aware process is active, an unversioned frame can only
      // be an older application context. Accepting it could resurrect a
      // resolved approval. A legacy phone remains supported after the watch
      // app itself restarts, when this cursor is empty again.
      guard sourceStartedAtMicros == 0, next.sequence > sequence else {
        return false
      }
      sequence = next.sequence
      return true
    }

    if sourceStartedAtMicros > 0 {
      guard next.sourceStartedAtMicros >= sourceStartedAtMicros else {
        return false
      }
      if next.sourceStartedAtMicros == sourceStartedAtMicros {
        guard nextSourceId == sourceInstanceId, next.sequence > sequence else {
          return false
        }
        sequence = next.sequence
        return true
      }
    }

    sourceInstanceId = nextSourceId
    sourceStartedAtMicros = next.sourceStartedAtMicros
    sequence = next.sequence
    return true
  }
}

/// One incremental chunk of a streaming answer, pushed during a turn so the
/// watch can read it aloud without waiting for the turn to finish.
struct WatchStreamChunk: Decodable {
  let turnId: String
  let text: String
  let isFinal: Bool
}

/// Reply to a command this watch sent.
struct WatchCommandResult: Decodable, Equatable {
  let ok: Bool
  let id: String?
  let code: String?
  let message: String?
}

/// Command vocabulary, mirroring `WatchCommand` on the Dart side.
enum WatchCommandType: String {
  case sendMessage
  case resolveApproval
  case resolveQuestion
  case cancelStreaming
  case requestSnapshot
  case selectConversation
  case resolveGoal
}
