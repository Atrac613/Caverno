enum RemoteCodingNotificationOutcome { completed, failed }

/// Privacy-safe terminal notification data shared by the relay and FCM.
///
/// This contract deliberately excludes prompts, model output, tool data, file
/// contents, command output, and authentication material. Adding a field is a
/// privacy-boundary change and requires an explicit contract review.
final class RemoteCodingNotificationPayload {
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

  final String eventId;
  final String turnId;
  final String conversationId;
  final RemoteCodingNotificationOutcome outcome;
  final String title;
  final String body;
  final DateTime completedAt;

  /// Encodes only fields approved for transport through the notification relay.
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
