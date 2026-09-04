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

struct WatchConversation: Decodable, Equatable, Identifiable {
  let id: String
  let title: String
}

struct WatchSnapshot: Decodable, Equatable {
  let sequence: Int
  let generatedAt: String
  let conversationId: String?
  let conversationTitle: String
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
  }

  private enum CodingKeys: String, CodingKey {
    case sequence, generatedAt, conversationId, conversationTitle, status
    case lastAssistantText, messages, messagesTruncated, approval, question
    case elapsedSeconds, queuedCount
    case busyThreadCount, conversations, conversationsTruncated, error
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sequence = try container.decodeIfPresent(Int.self, forKey: .sequence) ?? 0
    generatedAt =
      try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
    conversationId = try container.decodeIfPresent(
      String.self, forKey: .conversationId)
    conversationTitle =
      try container.decodeIfPresent(String.self, forKey: .conversationTitle)
      ?? ""
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
}
