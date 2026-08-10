import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';

import 'remote_coding_notification_payload.dart';

/// Maps canonical runtime terminal events into the privacy-safe notification
/// contract used by Remote Coding delivery paths.
final class RemoteCodingTerminalNotificationMapper {
  const RemoteCodingTerminalNotificationMapper();

  RemoteCodingNotificationPayload? mapTerminal(
    CavernoRuntimeTerminalEvent event, {
    required String eventId,
  }) {
    if (event.interactionOrigin !=
        CavernoRuntimeInteractionOrigin.remoteCoding) {
      return null;
    }
    final conversationId = event.conversationId?.trim() ?? '';
    if (conversationId.isEmpty) {
      return null;
    }

    final outcome = switch (event) {
      CavernoRuntimeRunCompleted() => RemoteCodingNotificationOutcome.completed,
      CavernoRuntimeRunFailed() => RemoteCodingNotificationOutcome.failed,
    };
    final (title, body) = switch (outcome) {
      RemoteCodingNotificationOutcome.completed => (
        'Remote coding completed',
        'Open Caverno to review the result.',
      ),
      RemoteCodingNotificationOutcome.failed => (
        'Remote coding failed',
        'Open Caverno to review the failure.',
      ),
    };

    return RemoteCodingNotificationPayload(
      eventId: eventId,
      turnId: event.turnId,
      conversationId: conversationId,
      outcome: outcome,
      title: title,
      body: body,
      completedAt: event.timestamp.toUtc(),
    );
  }
}
