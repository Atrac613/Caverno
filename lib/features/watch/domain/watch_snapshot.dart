/// Wire models for the paired Apple Watch companion app.
///
/// These are deliberately separate from the Remote Coding snapshot models.
/// `RemoteCodingServerNotifier._buildSnapshot` carries the full transcript and
/// dashboard statistics, which does not fit a WatchConnectivity payload; the
/// watch only needs enough to render one glance and one decision. Keeping the
/// projection small is a correctness requirement, not an optimisation, so the
/// truncation limits below are part of the contract and are enforced by
/// [WatchSnapshot.toJson], not merely asserted by tests.
library;

import 'dart:convert';

/// Payload budget for a single snapshot encoded as JSON.
///
/// `WCSession.updateApplicationContext` and `sendMessage` both reject oversized
/// dictionaries at runtime rather than failing at compile time, so the
/// projection caps every unbounded field instead of trusting callers.
const int watchSnapshotMaxEncodedBytes = 16 * 1024;

const int watchSnapshotAssistantTextLimit = 400;
const int watchSnapshotTitleLimit = 120;
const int watchSnapshotDetailLimit = 300;
const int watchSnapshotOptionLabelLimit = 60;
const int watchSnapshotMaxQuestionOptions = 4;

/// How many transcript messages the watch is given.
///
/// The watch renders a Messages-style transcript rather than a single last
/// answer, so the frame has to carry history. The cap is a payload
/// constraint first — see [watchSnapshotMaxEncodedBytes] — and a screen
/// constraint second. The frame says when the list was cut so the watch can
/// point at the iPhone instead of implying it holds the whole thread.
const int watchSnapshotMaxMessages = 8;

/// Per-bubble text budget, with a larger allowance for the newest message.
///
/// The last bubble is the one being read right now; clipping it to the same
/// length as scrollback would truncate the answer the person came to the
/// wrist for, while older bubbles only need to be recognisable.
const int watchSnapshotMessageTextLimit = 180;
const int watchSnapshotLastMessageTextLimit = 400;

/// How many threads the watch is offered to switch between.
///
/// A cap, not a preference: the snapshot has a payload budget and a watch
/// screen cannot usefully present more. The frame says when the list was cut
/// so the watch can point at the iPhone instead of implying it is complete.
const int watchSnapshotMaxConversations = 8;

/// Per-field budget for the projected goal.
///
/// Sized against measured headroom, not picked: a maximal frame in Japanese
/// leaves 1,755 bytes, and three fields of this length cost about 1,200 of
/// them. A larger goal does not fail — the ladder in this file sheds the
/// thread picker instead — but it would spend a real affordance on text a
/// wrist cannot read anyway.
const int watchSnapshotGoalTextLimit = 120;

/// What the watch should show for the conversation it is mirroring.
enum WatchTurnStatus {
  idle,
  streaming,
  waitingApproval,
  waitingQuestion,

  /// The goal harness stopped scheduling and is asking whether the objective
  /// was met.
  ///
  /// Its own status rather than [idle], which is what it used to render as:
  /// nothing is running either way, but one of the two is a decision waiting
  /// for the person and the other is a finished thread. The measured behaviour
  /// is that the model does not volunteer `update_goal` and answers when
  /// asked, so being asked is the whole mechanism — and a wrist is where the
  /// asking is cheapest.
  awaitingGoalConfirmation,
  error,
}

WatchTurnStatus _watchTurnStatusFromName(String name) => switch (name) {
  'streaming' => WatchTurnStatus.streaming,
  'waitingApproval' => WatchTurnStatus.waitingApproval,
  'waitingQuestion' => WatchTurnStatus.waitingQuestion,
  'awaitingGoalConfirmation' => WatchTurnStatus.awaitingGoalConfirmation,
  'error' => WatchTurnStatus.error,
  _ => WatchTurnStatus.idle,
};

/// Truncates [value] to [limit] characters, marking the cut with an ellipsis.
///
/// Operates on runes so a multi-byte character is never split in half; a split
/// surrogate pair would make the JSON undecodable on the Swift side.
String truncateForWatch(String value, int limit) {
  final normalized = value.trim();
  if (normalized.runes.length <= limit) return normalized;
  return '${String.fromCharCodes(normalized.runes.take(limit))}…';
}

/// A pending approval flattened into the one shape the watch can render.
///
/// [kind] is a free-form string rather than an enum on purpose: `ChatState`
/// carries ten independent pending-approval fields and gains more over time.
/// An unrecognised kind must degrade to "open on iPhone" instead of vanishing,
/// which a closed enum would make impossible without a coordinated release of
/// both the Flutter app and the watch target.
class WatchApproval {
  const WatchApproval({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.canResolveOnWatch,
  });

  final String id;
  final String kind;
  final String title;
  final String subtitle;
  final String detail;

  /// Whether Approve/Deny on the watch is sufficient to resolve this request.
  ///
  /// False for approvals that need structured input the watch cannot collect
  /// (SSH credentials, computer-use smoke arming). Those are shown read-only
  /// with a prompt to continue on the iPhone.
  final bool canResolveOnWatch;

  factory WatchApproval.fromJson(Map<String, dynamic> json) => WatchApproval(
    id: (json['id'] as String?)?.trim() ?? '',
    kind: (json['kind'] as String?)?.trim() ?? 'unknown',
    title: (json['title'] as String?)?.trim() ?? 'Approval required',
    subtitle: (json['subtitle'] as String?)?.trim() ?? '',
    detail: (json['detail'] as String?) ?? '',
    canResolveOnWatch: json['canResolveOnWatch'] == true,
  );

  Map<String, dynamic> toJson({
    int titleLimit = watchSnapshotTitleLimit,
    int detailLimit = watchSnapshotDetailLimit,
  }) => {
    'id': id,
    'kind': kind,
    'title': truncateForWatch(title, titleLimit),
    'subtitle': truncateForWatch(subtitle, titleLimit),
    'detail': truncateForWatch(detail, detailLimit),
    'canResolveOnWatch': canResolveOnWatch,
  };
}

class WatchQuestionOption {
  const WatchQuestionOption({required this.id, required this.label});

  final String id;
  final String label;

  factory WatchQuestionOption.fromJson(Map<String, dynamic> json) =>
      WatchQuestionOption(
        id: (json['id'] as String?)?.trim() ?? '',
        label: (json['label'] as String?)?.trim() ?? '',
      );

  Map<String, dynamic> toJson({
    int labelLimit = watchSnapshotOptionLabelLimit,
  }) => {'id': id, 'label': truncateForWatch(label, labelLimit)};
}

/// A pending `ask_user_question` reduced to a tappable option list.
class WatchQuestion {
  const WatchQuestion({
    required this.id,
    required this.question,
    required this.options,
    this.allowMultiple = false,
    this.allowOther = false,
  });

  final String id;
  final String question;
  final List<WatchQuestionOption> options;
  final bool allowMultiple;
  final bool allowOther;

  factory WatchQuestion.fromJson(Map<String, dynamic> json) => WatchQuestion(
    id: (json['id'] as String?)?.trim() ?? '',
    question: (json['question'] as String?)?.trim() ?? '',
    options: (json['options'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(WatchQuestionOption.fromJson)
        .toList(growable: false),
    allowMultiple: json['allowMultiple'] == true,
    allowOther: json['allowOther'] == true,
  );

  Map<String, dynamic> toJson({
    int questionLimit = watchSnapshotDetailLimit,
    int optionLabelLimit = watchSnapshotOptionLabelLimit,
  }) => {
    'id': id,
    'question': truncateForWatch(question, questionLimit),
    'options': options
        .take(watchSnapshotMaxQuestionOptions)
        .map((option) => option.toJson(labelLimit: optionLabelLimit))
        .toList(growable: false),
    'allowMultiple': allowMultiple,
    'allowOther': allowOther,
    // Tells the watch that the option list was cut, so it can offer "more on
    // iPhone" instead of silently presenting a partial choice as complete.
    'optionsTruncated': options.length > watchSnapshotMaxQuestionOptions,
  };
}

/// The conversation goal, reduced to what a wrist can act on.
///
/// [status] is a free-form string for the same reason `WatchApproval.kind` is:
/// `ConversationGoalStatus` gains members, and a watch build older than its
/// phone must degrade to showing the objective rather than dropping the goal
/// entirely.
class WatchGoal {
  const WatchGoal({
    required this.objective,
    required this.status,
    this.completionSummary = '',
    this.blockedReason = '',
  });

  final String objective;
  final String status;

  /// What the harness believes it achieved, shown beside the confirm choice.
  ///
  /// Answering "was this met?" without it is answering blind, which is the
  /// failure this projection exists to avoid.
  final String completionSummary;
  final String blockedReason;

  factory WatchGoal.fromJson(Map<String, dynamic> json) => WatchGoal(
    objective: (json['objective'] as String?)?.trim() ?? '',
    status: (json['status'] as String?)?.trim() ?? 'active',
    completionSummary: (json['completionSummary'] as String?)?.trim() ?? '',
    blockedReason: (json['blockedReason'] as String?)?.trim() ?? '',
  );

  Map<String, dynamic> toJson({int limit = watchSnapshotGoalTextLimit}) => {
    'objective': truncateForWatch(objective, limit),
    'status': status,
    if (completionSummary.isNotEmpty)
      'completionSummary': truncateForWatch(completionSummary, limit),
    if (blockedReason.isNotEmpty)
      'blockedReason': truncateForWatch(blockedReason, limit),
  };
}

/// A thread the watch can switch to.
class WatchConversation {
  const WatchConversation({
    required this.id,
    required this.title,
    this.mode = '',
  });

  final String id;
  final String title;

  /// The thread's `WorkspaceMode`, by name.
  ///
  /// `ConversationsState.conversations` is unfiltered, so chat, coding and
  /// routine threads reach the picker as if they were the same kind of thing.
  /// Sent by name rather than as an enum so an unknown mode renders as no
  /// label instead of collapsing the thread into the wrong one.
  final String mode;

  factory WatchConversation.fromJson(Map<String, dynamic> json) =>
      WatchConversation(
        id: (json['id'] as String?)?.trim() ?? '',
        title: (json['title'] as String?)?.trim() ?? '',
        mode: (json['mode'] as String?)?.trim() ?? '',
      );

  Map<String, dynamic> toJson({int titleLimit = watchSnapshotTitleLimit}) => {
    'id': id,
    'title': truncateForWatch(title, titleLimit),
    if (mode.isNotEmpty) 'mode': mode,
  };
}

/// Who a transcript bubble belongs to.
///
/// Narrower than `MessageRole` on purpose: the watch draws two bubble styles
/// and has nothing to do with a system message.
enum WatchMessageRole { user, assistant }

WatchMessageRole _watchMessageRoleFromName(String name) =>
    name == 'user' ? WatchMessageRole.user : WatchMessageRole.assistant;

/// One bubble in the watch's transcript.
class WatchMessage {
  const WatchMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.isStreaming = false,
  });

  final String id;
  final WatchMessageRole role;
  final String text;

  /// When the message was created, so the watch can group bubbles under a
  /// relative day-and-time header the way Messages does. Sent as UTC and
  /// rendered in the watch's own locale — the phone has no business
  /// formatting a date for a device whose locale it does not know.
  final DateTime timestamp;

  /// True while the answer is still being written.
  ///
  /// The watch renders this bubble from its own stream deltas rather than
  /// from [text]: snapshots coalesce, deltas do not, so the live bubble is
  /// further ahead than any frame that carries it.
  final bool isStreaming;

  factory WatchMessage.fromJson(Map<String, dynamic> json) => WatchMessage(
    id: (json['id'] as String?)?.trim() ?? '',
    role: _watchMessageRoleFromName((json['role'] as String?) ?? ''),
    text: (json['text'] as String?) ?? '',
    timestamp:
        DateTime.tryParse((json['timestamp'] as String?) ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    isStreaming: json['isStreaming'] == true,
  );

  Map<String, dynamic> toJson({int limit = watchSnapshotMessageTextLimit}) => {
    'id': id,
    'role': role.name,
    'text': truncateForWatch(text, limit),
    'timestamp': timestamp.toUtc().toIso8601String(),
    if (isStreaming) 'isStreaming': true,
  };
}

/// One rung of the payload-shedding ladder used when encoding a frame.
///
/// The rune caps above are a *screen* constraint;
/// [watchSnapshotMaxEncodedBytes] is a *transport* one, and the two do not
/// agree. A rune costs one byte in English, three in Japanese and four in
/// emoji, so a maximal frame sized only by runes lands at 36% of the budget in
/// English, 89% in Japanese and 116% in emoji. WatchConnectivity does not clip
/// an oversized dictionary — it refuses it — and the refusal surfaces as an
/// `NSLog` in `WatchBridgePlugin`, so the visible symptom is a watch silently
/// stuck on stale state.
class _WatchFrameCaps {
  const _WatchFrameCaps({
    required this.conversations,
    required this.messages,
    required this.messageText,
    required this.lastMessageText,
    required this.assistantText,
    required this.title,
    required this.detail,
    required this.optionLabel,
    required this.goalText,
  });

  final int conversations;
  final int messages;
  final int messageText;
  final int lastMessageText;

  /// Zero omits `lastAssistantText` from the frame entirely.
  final int assistantText;
  final int title;
  final int detail;
  final int optionLabel;

  /// The goal shrinks with the rest but is never shed: a goal awaiting
  /// confirmation is a pending decision, and this frame exists to carry one.
  final int goalText;
}

/// What a frame sheds when it does not fit, and in what order.
///
/// The first rung is the full projection, and it is what every frame in a
/// one-byte or three-byte script encodes to. The rest exist so that the budget
/// is an enforced invariant rather than a hope, and their order follows what
/// the frame is *for*: answering a blocked turn.
///
/// The thread picker goes first — it is navigation, not the decision, and
/// `conversationsTruncated` already tells the watch to point at the iPhone
/// instead of implying the list is complete. Transcript depth follows, under
/// the `messagesTruncated` signal that exists for the same reason.
/// `lastAssistantText` is next: it duplicates the newest bubble and is kept
/// only for a watch build older than its phone, which is a smaller loss than a
/// frame that reaches no watch at all. The pending approval and question shrink
/// last, and never disappear.
const List<_WatchFrameCaps> _watchFrameCapLadder = [
  _WatchFrameCaps(
    conversations: watchSnapshotMaxConversations,
    messages: watchSnapshotMaxMessages,
    messageText: watchSnapshotMessageTextLimit,
    lastMessageText: watchSnapshotLastMessageTextLimit,
    assistantText: watchSnapshotAssistantTextLimit,
    title: watchSnapshotTitleLimit,
    detail: watchSnapshotDetailLimit,
    optionLabel: watchSnapshotOptionLabelLimit,
    goalText: watchSnapshotGoalTextLimit,
  ),
  _WatchFrameCaps(
    conversations: 0,
    messages: watchSnapshotMaxMessages,
    messageText: watchSnapshotMessageTextLimit,
    lastMessageText: watchSnapshotLastMessageTextLimit,
    assistantText: watchSnapshotAssistantTextLimit,
    title: watchSnapshotTitleLimit,
    detail: watchSnapshotDetailLimit,
    optionLabel: watchSnapshotOptionLabelLimit,
    goalText: watchSnapshotGoalTextLimit,
  ),
  _WatchFrameCaps(
    conversations: 0,
    messages: 4,
    messageText: 120,
    lastMessageText: 300,
    assistantText: 0,
    title: watchSnapshotTitleLimit,
    detail: watchSnapshotDetailLimit,
    optionLabel: watchSnapshotOptionLabelLimit,
    goalText: watchSnapshotGoalTextLimit,
  ),
  _WatchFrameCaps(
    conversations: 0,
    messages: 2,
    messageText: 60,
    lastMessageText: 160,
    assistantText: 0,
    title: 80,
    detail: 160,
    optionLabel: 40,
    goalText: 80,
  ),
  _WatchFrameCaps(
    conversations: 0,
    messages: 1,
    messageText: 40,
    lastMessageText: 80,
    assistantText: 0,
    title: 60,
    detail: 100,
    optionLabel: 24,
    goalText: 60,
  ),
];

/// One frame of iPhone chat state, projected for the watch.
class WatchSnapshot {
  const WatchSnapshot({
    required this.sequence,
    required this.generatedAt,
    this.sourceInstanceId = '',
    this.sourceStartedAtMicros = 0,
    this.conversationId,
    this.conversationTitle = '',
    this.workspaceMode = '',
    this.goal,
    this.status = WatchTurnStatus.idle,
    this.lastAssistantText = '',
    this.messages = const <WatchMessage>[],
    this.messagesTruncated = false,
    this.approval,
    this.question,
    this.elapsedSeconds = 0,
    this.queuedCount = 0,
    this.busyThreadCount = 0,
    this.conversations = const <WatchConversation>[],
    this.conversationsTruncated = false,
    this.error,
  });

  /// Monotonic per-source counter. The watch drops any frame whose sequence is
  /// not greater than the last one it rendered from the same source, because
  /// WatchConnectivity does not guarantee delivery order across transports.
  final int sequence;
  final DateTime generatedAt;

  /// Identifies one lifetime of the iPhone-side watch projection.
  ///
  /// [sequence] restarts when the Flutter process restarts. These fields let
  /// the watch accept the new source's first frame without later accepting a
  /// delayed frame from the retired process.
  final String sourceInstanceId;
  final int sourceStartedAtMicros;
  final String? conversationId;
  final String conversationTitle;

  /// The mirrored thread's `WorkspaceMode`, by name. See
  /// [WatchConversation.mode] for why this travels as a string.
  final String workspaceMode;

  /// The thread's goal, when it has one worth showing.
  final WatchGoal? goal;

  final WatchTurnStatus status;

  /// The most recent assistant answer, kept for watch builds older than the
  /// transcript. The two apps ship as one bundle but are not guaranteed to be
  /// the same build at runtime, and a watch that has not synced yet would
  /// otherwise show nothing at all.
  final String lastAssistantText;

  /// The tail of the thread, oldest first, already capped.
  final List<WatchMessage> messages;
  final bool messagesTruncated;

  final WatchApproval? approval;
  final WatchQuestion? question;
  final int elapsedSeconds;
  final int queuedCount;
  final int busyThreadCount;

  /// Threads the watch may switch to, most recent first, already capped.
  final List<WatchConversation> conversations;
  final bool conversationsTruncated;
  final String? error;

  bool get needsAttention =>
      status == WatchTurnStatus.waitingApproval ||
      status == WatchTurnStatus.waitingQuestion ||
      status == WatchTurnStatus.awaitingGoalConfirmation;

  factory WatchSnapshot.fromJson(Map<String, dynamic> json) {
    final approval = json['approval'];
    final question = json['question'];
    final goal = json['goal'];
    return WatchSnapshot(
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      generatedAt:
          DateTime.tryParse((json['generatedAt'] as String?) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sourceInstanceId: (json['sourceInstanceId'] as String?)?.trim() ?? '',
      sourceStartedAtMicros:
          (json['sourceStartedAtMicros'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversationId'] as String?)?.trim(),
      conversationTitle: (json['conversationTitle'] as String?)?.trim() ?? '',
      workspaceMode: (json['workspaceMode'] as String?)?.trim() ?? '',
      goal: goal is Map<String, dynamic> ? WatchGoal.fromJson(goal) : null,
      status: _watchTurnStatusFromName((json['status'] as String?) ?? ''),
      lastAssistantText: (json['lastAssistantText'] as String?) ?? '',
      messages: (json['messages'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(WatchMessage.fromJson)
          .toList(growable: false),
      messagesTruncated: json['messagesTruncated'] == true,
      approval: approval is Map<String, dynamic>
          ? WatchApproval.fromJson(approval)
          : null,
      question: question is Map<String, dynamic>
          ? WatchQuestion.fromJson(question)
          : null,
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      queuedCount: (json['queuedCount'] as num?)?.toInt() ?? 0,
      busyThreadCount: (json['busyThreadCount'] as num?)?.toInt() ?? 0,
      conversations:
          (json['conversations'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(WatchConversation.fromJson)
              .toList(growable: false),
      conversationsTruncated: json['conversationsTruncated'] == true,
      error: json['error'] as String?,
    );
  }

  /// Encodes the frame, shedding payload until it fits the byte budget.
  ///
  /// Walks [_watchFrameCapLadder] and returns the first encoding inside
  /// [watchSnapshotMaxEncodedBytes]. Almost every real frame fits on the first
  /// rung, so this costs one encode in the common case. If even the tightest
  /// rung overruns, that frame is still returned: sending the smallest thing
  /// that can be built is strictly better than sending nothing, and the caps
  /// there are small enough that no input reaches this.
  Map<String, dynamic> toJson() {
    var encoded = _encodeWith(_watchFrameCapLadder.first);
    for (final caps in _watchFrameCapLadder.skip(1)) {
      if (_encodedByteLength(encoded) <= watchSnapshotMaxEncodedBytes) {
        return encoded;
      }
      encoded = _encodeWith(caps);
    }
    return encoded;
  }

  static int _encodedByteLength(Map<String, dynamic> json) =>
      utf8.encode(jsonEncode(json)).length;

  Map<String, dynamic> _encodeWith(_WatchFrameCaps caps) => {
    'sequence': sequence,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    if (sourceInstanceId.isNotEmpty) 'sourceInstanceId': sourceInstanceId,
    if (sourceStartedAtMicros > 0)
      'sourceStartedAtMicros': sourceStartedAtMicros,
    if (conversationId != null && conversationId!.isNotEmpty)
      'conversationId': conversationId,
    'conversationTitle': truncateForWatch(conversationTitle, caps.title),
    if (workspaceMode.isNotEmpty) 'workspaceMode': workspaceMode,
    if (goal != null) 'goal': goal!.toJson(limit: caps.goalText),
    'status': status.name,
    if (caps.assistantText > 0)
      'lastAssistantText': truncateForWatch(
        lastAssistantText,
        caps.assistantText,
      ),
    'messages': _encodedMessages(caps),
    'messagesTruncated': messagesTruncated || messages.length > caps.messages,
    if (approval != null)
      'approval': approval!.toJson(
        titleLimit: caps.title,
        detailLimit: caps.detail,
      ),
    if (question != null)
      'question': question!.toJson(
        questionLimit: caps.detail,
        optionLabelLimit: caps.optionLabel,
      ),
    'elapsedSeconds': elapsedSeconds,
    'queuedCount': queuedCount,
    'busyThreadCount': busyThreadCount,
    'conversations': conversations
        .take(caps.conversations)
        .map((conversation) => conversation.toJson(titleLimit: caps.title))
        .toList(growable: false),
    'conversationsTruncated':
        conversationsTruncated || conversations.length > caps.conversations,
    if (error != null && error!.isNotEmpty)
      'error': truncateForWatch(error!, caps.title),
  };

  /// Encodes the newest [_WatchFrameCaps.messages] bubbles, giving the last
  /// one the larger text allowance.
  List<Map<String, dynamic>> _encodedMessages(_WatchFrameCaps caps) {
    final kept = messages.length <= caps.messages
        ? messages
        : messages.sublist(messages.length - caps.messages);
    return [
      for (var i = 0; i < kept.length; i++)
        kept[i].toJson(
          limit: i == kept.length - 1
              ? caps.lastMessageText
              : caps.messageText,
        ),
    ];
  }
}
