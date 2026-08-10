import 'package:caverno/features/remote_coding/data/remote_coding_notification_payload.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_terminal_notification_mapper.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = RemoteCodingTerminalNotificationMapper();
  final completedAt = DateTime.utc(2026, 8, 10, 13, 30);

  test('maps a remote completion without exposing runtime content', () {
    final payload = mapper.mapTerminal(
      CavernoRuntimeRunCompleted(
        sequence: 8,
        timestamp: completedAt,
        turnId: 'gen-8',
        conversationId: 'conversation-8',
        interactionOrigin: CavernoRuntimeInteractionOrigin.remoteCoding,
        content: 'Private model output',
      ),
      eventId: 'event-8',
    );

    expect(payload, isNotNull);
    expect(payload!.outcome, RemoteCodingNotificationOutcome.completed);
    expect(payload.turnId, 'gen-8');
    expect(payload.conversationId, 'conversation-8');
    expect(payload.title, 'Remote coding completed');
    expect(payload.body, 'Open Caverno to review the result.');
    expect(payload.toFcmData().values, isNot(contains('Private model output')));
  });

  test('maps a remote failure without exposing failure details', () {
    final payload = mapper.mapTerminal(
      CavernoRuntimeRunFailed(
        sequence: 9,
        timestamp: completedAt,
        turnId: 'gen-9',
        conversationId: 'conversation-9',
        interactionOrigin: CavernoRuntimeInteractionOrigin.remoteCoding,
        code: 'provider_error',
        message: 'Private provider response',
        exitCode: 1,
      ),
      eventId: 'event-9',
    );

    expect(payload, isNotNull);
    expect(payload!.outcome, RemoteCodingNotificationOutcome.failed);
    expect(payload.title, 'Remote coding failed');
    expect(payload.body, 'Open Caverno to review the failure.');
    expect(
      payload.toFcmData().values,
      isNot(contains('Private provider response')),
    );
  });

  test('ignores local terminal events', () {
    final payload = mapper.mapTerminal(
      CavernoRuntimeRunCompleted(
        sequence: 1,
        timestamp: completedAt,
        turnId: 'gen-local',
        conversationId: 'conversation-local',
        content: 'Local result',
      ),
      eventId: 'event-local',
    );

    expect(payload, isNull);
  });

  test('ignores terminal events without a conversation owner', () {
    final payload = mapper.mapTerminal(
      CavernoRuntimeRunCompleted(
        sequence: 1,
        timestamp: completedAt,
        turnId: 'gen-orphan',
        interactionOrigin: CavernoRuntimeInteractionOrigin.remoteCoding,
        content: 'Orphan result',
      ),
      eventId: 'event-orphan',
    );

    expect(payload, isNull);
  });
}
