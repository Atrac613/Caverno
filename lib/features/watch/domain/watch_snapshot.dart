/// Wire models for the paired Apple Watch companion app.
///
/// These are deliberately separate from the Remote Coding snapshot models.
/// `RemoteCodingServerNotifier._buildSnapshot` carries the full transcript and
/// dashboard statistics, which does not fit a WatchConnectivity payload; the
/// watch only needs enough to render one glance and one decision. Keeping the
/// projection small is a correctness requirement, not an optimisation, so the
/// truncation limits below are part of the contract and are asserted by tests.
library;

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

/// What the watch should show for the conversation it is mirroring.
enum WatchTurnStatus {
  idle,
  streaming,
  waitingApproval,
  waitingQuestion,
  error,
}

WatchTurnStatus _watchTurnStatusFromName(String name) => switch (name) {
  'streaming' => WatchTurnStatus.streaming,
  'waitingApproval' => WatchTurnStatus.waitingApproval,
  'waitingQuestion' => WatchTurnStatus.waitingQuestion,
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'title': truncateForWatch(title, watchSnapshotTitleLimit),
    'subtitle': truncateForWatch(subtitle, watchSnapshotTitleLimit),
    'detail': truncateForWatch(detail, watchSnapshotDetailLimit),
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': truncateForWatch(label, watchSnapshotOptionLabelLimit),
  };
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': truncateForWatch(question, watchSnapshotDetailLimit),
    'options': options
        .take(watchSnapshotMaxQuestionOptions)
        .map((option) => option.toJson())
        .toList(growable: false),
    'allowMultiple': allowMultiple,
    'allowOther': allowOther,
    // Tells the watch that the option list was cut, so it can offer "more on
    // iPhone" instead of silently presenting a partial choice as complete.
    'optionsTruncated': options.length > watchSnapshotMaxQuestionOptions,
  };
}

/// One frame of iPhone chat state, projected for the watch.
class WatchSnapshot {
  const WatchSnapshot({
    required this.sequence,
    required this.generatedAt,
    this.conversationId,
    this.conversationTitle = '',
    this.status = WatchTurnStatus.idle,
    this.lastAssistantText = '',
    this.approval,
    this.question,
    this.elapsedSeconds = 0,
    this.queuedCount = 0,
    this.busyThreadCount = 0,
    this.error,
  });

  /// Monotonic per-session counter. The watch drops any frame whose sequence
  /// is not greater than the last one it rendered, because WatchConnectivity
  /// does not guarantee delivery order across transports.
  final int sequence;
  final DateTime generatedAt;
  final String? conversationId;
  final String conversationTitle;
  final WatchTurnStatus status;
  final String lastAssistantText;
  final WatchApproval? approval;
  final WatchQuestion? question;
  final int elapsedSeconds;
  final int queuedCount;
  final int busyThreadCount;
  final String? error;

  bool get needsAttention =>
      status == WatchTurnStatus.waitingApproval ||
      status == WatchTurnStatus.waitingQuestion;

  factory WatchSnapshot.fromJson(Map<String, dynamic> json) {
    final approval = json['approval'];
    final question = json['question'];
    return WatchSnapshot(
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      generatedAt:
          DateTime.tryParse((json['generatedAt'] as String?) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      conversationId: (json['conversationId'] as String?)?.trim(),
      conversationTitle: (json['conversationTitle'] as String?)?.trim() ?? '',
      status: _watchTurnStatusFromName((json['status'] as String?) ?? ''),
      lastAssistantText: (json['lastAssistantText'] as String?) ?? '',
      approval: approval is Map<String, dynamic>
          ? WatchApproval.fromJson(approval)
          : null,
      question: question is Map<String, dynamic>
          ? WatchQuestion.fromJson(question)
          : null,
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      queuedCount: (json['queuedCount'] as num?)?.toInt() ?? 0,
      busyThreadCount: (json['busyThreadCount'] as num?)?.toInt() ?? 0,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'sequence': sequence,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    if (conversationId != null && conversationId!.isNotEmpty)
      'conversationId': conversationId,
    'conversationTitle': truncateForWatch(
      conversationTitle,
      watchSnapshotTitleLimit,
    ),
    'status': status.name,
    'lastAssistantText': truncateForWatch(
      lastAssistantText,
      watchSnapshotAssistantTextLimit,
    ),
    if (approval != null) 'approval': approval!.toJson(),
    if (question != null) 'question': question!.toJson(),
    'elapsedSeconds': elapsedSeconds,
    'queuedCount': queuedCount,
    'busyThreadCount': busyThreadCount,
    if (error != null && error!.isNotEmpty)
      'error': truncateForWatch(error!, watchSnapshotTitleLimit),
  };
}
