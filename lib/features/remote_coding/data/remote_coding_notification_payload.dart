import '../domain/remote_coding_grant_kinds.dart';

enum RemoteCodingNotificationOutcome { completed, failed }

/// Anything the desktop may hand the relay for delivery to a paired device.
///
/// The relay stores and forwards `toFcmData()` verbatim, so every implementer
/// is a privacy boundary: prompts, model output, tool data, file contents,
/// command output, command text, and authentication material never appear in
/// one. Adding a field to any implementer requires an explicit contract
/// review, and the relay validates the resulting keys against its own
/// allow-list rather than trusting the sender.
abstract interface class RemoteCodingRelayNotification {
  /// Discriminates the payload shape. The relay allow-lists these.
  ///
  /// Named apart from each implementer's `static const kind` wire literal,
  /// which callers reference through the class and which cannot also be an
  /// instance getter.
  String get notificationKind;

  /// Deduplicates a redelivery and collapses the platform notification.
  String get eventId;

  /// The thread a tap should open.
  String get conversationId;

  /// What the platform shows. Composed from closed sets, never from request
  /// data — see [RemoteCodingApprovalNotificationPayload.forApproval].
  String get title;
  String get body;

  Map<String, String> toFcmData();
}

/// Parses whichever notification shape [data] carries.
///
/// Dispatching on `kind` before validating fields keeps an unknown payload a
/// `FormatException` naming the kind, rather than a confusing complaint about
/// a missing field that shape never had.
RemoteCodingRelayNotification parseRemoteCodingRelayNotification(
  Map<String, dynamic> data,
) {
  final kind = data['kind']?.toString().trim() ?? '';
  return switch (kind) {
    RemoteCodingNotificationPayload.kind =>
      RemoteCodingNotificationPayload.fromFcmData(data),
    RemoteCodingApprovalNotificationPayload.kind =>
      RemoteCodingApprovalNotificationPayload.fromFcmData(data),
    _ => throw FormatException(
      'Unsupported remote coding notification kind: $kind',
    ),
  };
}

/// Privacy-safe terminal notification data shared by the relay and FCM.
///
/// This contract deliberately excludes prompts, model output, tool data, file
/// contents, command output, and authentication material. Adding a field is a
/// privacy-boundary change and requires an explicit contract review.
final class RemoteCodingNotificationPayload
    implements RemoteCodingRelayNotification {
  const RemoteCodingNotificationPayload({
    required this.eventId,
    required this.turnId,
    required this.conversationId,
    required this.outcome,
    required this.title,
    required this.body,
    required this.completedAt,
  });

  static const String kind = 'remote_coding_run_terminal';
  static const int schemaVersion = 1;

  @override
  final String eventId;
  final String turnId;
  @override
  final String conversationId;
  final RemoteCodingNotificationOutcome outcome;
  @override
  final String title;
  @override
  final String body;
  final DateTime completedAt;

  @override
  String get notificationKind => kind;

  /// Encodes only fields approved for transport through the notification relay.
  @override
  Map<String, String> toFcmData() => <String, String>{
    'kind': kind,
    'schemaVersion': schemaVersion.toString(),
    'eventId': eventId,
    'turnId': turnId,
    'conversationId': conversationId,
    'outcome': outcome.name,
    'title': title,
    'body': body,
    'completedAt': completedAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingNotificationPayload.fromFcmData(
    Map<String, dynamic> data,
  ) {
    final payloadKind = _requiredString(data, 'kind');
    if (payloadKind != kind) {
      throw FormatException(
        'Unsupported remote coding notification kind: $payloadKind',
      );
    }

    final version = int.tryParse(_requiredString(data, 'schemaVersion'));
    if (version != schemaVersion) {
      throw FormatException(
        'Unsupported remote coding notification version: $version',
      );
    }

    final outcomeName = _requiredString(data, 'outcome');
    final outcome = switch (outcomeName) {
      'completed' => RemoteCodingNotificationOutcome.completed,
      'failed' => RemoteCodingNotificationOutcome.failed,
      _ => throw FormatException(
        'Unsupported remote coding notification outcome: $outcomeName',
      ),
    };
    final completedAt = DateTime.tryParse(_requiredString(data, 'completedAt'));
    if (completedAt == null) {
      throw const FormatException(
        'Remote coding notification completion time is invalid.',
      );
    }

    return RemoteCodingNotificationPayload(
      eventId: _requiredString(data, 'eventId'),
      turnId: _requiredString(data, 'turnId'),
      conversationId: _requiredString(data, 'conversationId'),
      outcome: outcome,
      title: _requiredString(data, 'title'),
      body: _requiredString(data, 'body'),
      completedAt: completedAt.toUtc(),
    );
  }

  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw FormatException(
        'Remote coding notification field "$key" is required.',
      );
    }
    return value;
  }
}

/// Privacy-safe "the desktop is blocked on you" notification.
///
/// This exists because the local path cannot reach a suspended app. An
/// approval reaches the phone over the live WebSocket and is raised as a local
/// notification from there; iOS suspends a backgrounded app within seconds,
/// tears the socket down, and runs no Dart, so nothing arrives at all until a
/// push wakes the device.
///
/// **What it deliberately does not carry.** No command text, no path, no
/// target, no warning prose. A lock screen is the least private surface the
/// app has, and the relay is the only place Caverno data leaves the machine,
/// so the wire carries an allow-listed [approvalKind] and the boolean
/// [hasWarning] and nothing else about the request. Today's warning strings
/// happen to be static catalogue entries, but forwarding them would make every
/// future edit to those catalogues a privacy decision made by someone who does
/// not know they are making one. The phone renders both lines from its own
/// strings; the command itself is one tap away in the app.
final class RemoteCodingApprovalNotificationPayload
    implements RemoteCodingRelayNotification {
  const RemoteCodingApprovalNotificationPayload({
    required this.eventId,
    required this.approvalId,
    required this.conversationId,
    required this.approvalKind,
    required this.hasWarning,
    required this.title,
    required this.body,
    required this.requestedAt,
  });

  /// Builds the payload for [approvalKind], composing the displayed text from
  /// closed sets so that no caller can route request data onto a lock screen.
  ///
  /// [hostName] is the one caller-supplied string, and it is the desktop's own
  /// name: "wants to run something" without saying *which machine* is the
  /// failure this whole surface exists to avoid. It is trimmed and length-
  /// capped rather than trusted.
  factory RemoteCodingApprovalNotificationPayload.forApproval({
    required String eventId,
    required String approvalId,
    required String conversationId,
    required String approvalKind,
    required bool hasWarning,
    required String hostName,
    required DateTime requestedAt,
  }) {
    if (!RemoteCodingGrantKinds.all.contains(approvalKind)) {
      throw FormatException(
        'Unsupported remote coding approval kind: $approvalKind',
      );
    }
    final host = hostName.trim();
    final subject = host.isEmpty ? 'Your Mac' : _clampHostName(host);
    return RemoteCodingApprovalNotificationPayload(
      eventId: eventId,
      approvalId: approvalId,
      conversationId: conversationId,
      approvalKind: approvalKind,
      hasWarning: hasWarning,
      title: 'Caverno needs your approval',
      body: hasWarning
          ? '$subject is waiting on ${_kindPhrase(approvalKind)}. '
                'Review it before approving.'
          : '$subject is waiting on ${_kindPhrase(approvalKind)}.',
      requestedAt: requestedAt,
    );
  }

  static const String kind = 'remote_coding_approval_requested';
  static const int schemaVersion = 1;

  /// Longest host name the body will carry. A paired device name is user
  /// supplied, and a lock screen truncates in the middle of a word rather than
  /// at a boundary the sender chose.
  static const int _maxHostNameLength = 40;

  @override
  final String eventId;

  /// The approval this notification answers. Resolution is by id, never by
  /// thread: a second approval can queue behind the first while the
  /// notification is still on screen.
  final String approvalId;

  @override
  final String conversationId;

  /// One of [RemoteCodingGrantKinds.all]. Validated on both sides so an
  /// unknown kind cannot reach the phone's rendering switch.
  final String approvalKind;

  /// Whether the desktop attached a risk warning. The prose stays on the
  /// desktop; this says only whether the person should look before answering.
  final bool hasWarning;

  @override
  final String title;
  @override
  final String body;
  final DateTime requestedAt;

  @override
  String get notificationKind => kind;

  @override
  Map<String, String> toFcmData() => <String, String>{
    'kind': kind,
    'schemaVersion': schemaVersion.toString(),
    'eventId': eventId,
    'approvalId': approvalId,
    'conversationId': conversationId,
    'approvalKind': approvalKind,
    'hasWarning': hasWarning.toString(),
    'title': title,
    'body': body,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingApprovalNotificationPayload.fromFcmData(
    Map<String, dynamic> data,
  ) {
    final payloadKind = _requiredString(data, 'kind');
    if (payloadKind != kind) {
      throw FormatException(
        'Unsupported remote coding notification kind: $payloadKind',
      );
    }
    final version = int.tryParse(_requiredString(data, 'schemaVersion'));
    if (version != schemaVersion) {
      throw FormatException(
        'Unsupported remote coding notification version: $version',
      );
    }
    final approvalKind = _requiredString(data, 'approvalKind');
    if (!RemoteCodingGrantKinds.all.contains(approvalKind)) {
      throw FormatException(
        'Unsupported remote coding approval kind: $approvalKind',
      );
    }
    final hasWarning = switch (_requiredString(data, 'hasWarning')) {
      'true' => true,
      'false' => false,
      final value => throw FormatException(
        'Remote coding approval warning flag is invalid: $value',
      ),
    };
    final requestedAt = DateTime.tryParse(_requiredString(data, 'requestedAt'));
    if (requestedAt == null) {
      throw const FormatException(
        'Remote coding approval request time is invalid.',
      );
    }
    return RemoteCodingApprovalNotificationPayload(
      eventId: _requiredString(data, 'eventId'),
      approvalId: _requiredString(data, 'approvalId'),
      conversationId: _requiredString(data, 'conversationId'),
      approvalKind: approvalKind,
      hasWarning: hasWarning,
      title: _requiredString(data, 'title'),
      body: _requiredString(data, 'body'),
      requestedAt: requestedAt.toUtc(),
    );
  }

  static String _clampHostName(String host) => host.length <= _maxHostNameLength
      ? host
      : '${host.substring(0, _maxHostNameLength - 1)}\u2026';

  /// Reads as the object of "is waiting on ...", so a new kind that does not
  /// fit that sentence is a rendering bug rather than a silent fallback.
  static String _kindPhrase(String approvalKind) => switch (approvalKind) {
    'file' => 'a file write',
    'localCommand' => 'a shell command',
    'gitCommand' => 'a git command',
    'sshCommand' => 'an SSH command',
    'sshConnect' => 'an SSH connection',
    'bleConnect' => 'a Bluetooth connection',
    'serialOpen' => 'a serial port',
    'browserAction' => 'a browser action',
    'computerUse' => 'a computer-use action',
    'participantTool' => 'a participant tool',
    'assumptionConfirmation' => 'an assumption check',
    'askUserQuestion' => 'a question',
    _ => 'an approval',
  };

  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw FormatException(
        'Remote coding notification field "$key" is required.',
      );
    }
    return value;
  }
}

