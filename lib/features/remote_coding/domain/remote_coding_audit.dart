/// What happened when a paired device tried to answer one of this desktop's
/// interactions.
enum RemoteCodingAuditOutcome {
  /// The desktop applied the device's decision.
  resolved,

  /// The desktop refused it. Kept because a refusal is the more interesting
  /// half: it is what a misconfigured grant, a stale client, or a device
  /// reaching for something it was never given all look like.
  refused,
}

/// One entry in the desktop's record of remote decisions (SA-26, T4).
///
/// A paired device can approve commands that change this machine, and until
/// this existed the machine kept no account of which device approved what.
/// That is a gap on its own — "did I approve that, or did the phone in my bag?"
/// had no answer — and it is the evidence any later dispute about a grant would
/// need.
///
/// Deliberately **not** part of `RemoteCodingDiagnostics`, and therefore not in
/// the support packet: entries carry command text and paths, and the support
/// packet exists to be copied out of the machine.
class RemoteCodingAuditEntry {
  const RemoteCodingAuditEntry({
    required this.at,
    required this.deviceId,
    required this.deviceName,
    required this.kind,
    required this.origin,
    required this.outcome,
    required this.approved,
    required this.title,
    this.subtitle = '',
    this.warning,
    this.refusedReason,
    this.conversationId,
  });

  /// Longest a recorded field may be. A file approval's preview can be a whole
  /// diff, and this log lives in shared preferences.
  static const int maxFieldLength = 400;

  /// How many entries are kept. Old enough to answer "what did it do while I
  /// was out", small enough not to turn settings storage into a database.
  static const int maxEntries = 200;

  final DateTime at;
  final String deviceId;

  /// The device's name when the decision was taken, not now: a device can be
  /// renamed or revoked, and the record should say who it was at the time.
  final String deviceName;
  final String kind;

  /// `remote` when the device answered a turn it started itself, `local` when
  /// it answered one started at this desktop under a grant. The distinction is
  /// the whole point of the record: the second is the authority SA-26 widened.
  final String origin;
  final RemoteCodingAuditOutcome outcome;
  final bool approved;
  final String title;
  final String subtitle;
  final String? warning;
  final String? refusedReason;
  final String? conversationId;

  bool get isDesktopOrigin => origin == 'local';

  factory RemoteCodingAuditEntry.fromJson(Map<String, dynamic> json) {
    return RemoteCodingAuditEntry(
      at:
          DateTime.tryParse((json['at'] as String?) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deviceId: _text(json['deviceId']),
      deviceName: _text(json['deviceName']),
      kind: _text(json['kind']),
      origin: _text(json['origin']),
      outcome: json['outcome'] == 'refused'
          ? RemoteCodingAuditOutcome.refused
          : RemoteCodingAuditOutcome.resolved,
      approved: json['approved'] == true,
      title: _text(json['title']),
      subtitle: _text(json['subtitle']),
      warning: _optional(json['warning']),
      refusedReason: _optional(json['refusedReason']),
      conversationId: _optional(json['conversationId']),
    );
  }

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'deviceName': deviceName,
    'kind': kind,
    'origin': origin,
    'outcome': outcome.name,
    'approved': approved,
    'title': title,
    if (subtitle.isNotEmpty) 'subtitle': subtitle,
    if (warning != null && warning!.isNotEmpty) 'warning': warning,
    if (refusedReason != null && refusedReason!.isNotEmpty)
      'refusedReason': refusedReason,
    if (conversationId != null && conversationId!.isNotEmpty)
      'conversationId': conversationId,
  };

  static String _text(Object? value) =>
      value is String ? truncate(value.trim()) : '';

  static String? _optional(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  /// Bounds one recorded field. An ellipsis marks the cut so a reader does not
  /// mistake a truncated command for the whole one.
  static String truncate(String value) => value.length <= maxFieldLength
      ? value
      : '${value.substring(0, maxFieldLength)}…';
}

/// Prepends [entry] to [existing], newest first, keeping at most
/// [RemoteCodingAuditEntry.maxEntries].
List<RemoteCodingAuditEntry> appendRemoteCodingAuditEntry(
  List<RemoteCodingAuditEntry> existing,
  RemoteCodingAuditEntry entry,
) => <RemoteCodingAuditEntry>[
  entry,
  ...existing.take(RemoteCodingAuditEntry.maxEntries - 1),
];
