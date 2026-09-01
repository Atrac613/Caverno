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

struct WatchSnapshot: Decodable, Equatable {
  let sequence: Int
  let generatedAt: String
  let conversationId: String?
  let conversationTitle: String
  let status: WatchTurnStatus
  let lastAssistantText: String
  let approval: WatchApproval?
  let question: WatchQuestion?
  let elapsedSeconds: Int
  let queuedCount: Int
  let busyThreadCount: Int
  let error: String?

  var needsAttention: Bool {
    status == .waitingApproval || status == .waitingQuestion
  }

  private enum CodingKeys: String, CodingKey {
    case sequence, generatedAt, conversationId, conversationTitle, status
    case lastAssistantText, approval, question, elapsedSeconds, queuedCount
    case busyThreadCount, error
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
struct WatchCommandResult: Decodable {
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
}
