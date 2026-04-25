import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/routines/domain/entities/routine.dart';

void main() {
  group('RoutineRunRecord', () {
    test('preserves trigger and duration through JSON serialization', () {
      final record = RoutineRunRecord(
        id: 'run-1',
        startedAt: DateTime(2026, 4, 21, 10, 0, 0),
        finishedAt: DateTime(2026, 4, 21, 10, 0, 4),
        status: RoutineRunStatus.completed,
        trigger: RoutineRunTrigger.scheduled,
        durationMs: 4321,
        usedTools: true,
        toolCallCount: 2,
        toolNames: const ['web_search', 'read_file'],
        toolSourceLabels: const {'web_search': 'search.local:8765'},
        deliveryStatus: RoutineDeliveryStatus.delivered,
        deliveredAt: DateTime(2026, 4, 21, 10, 0, 5),
        deliveryMessage: 'Posted to Google Chat.',
        preview: 'Finished successfully',
        output: 'Full output',
        failureAcknowledged: true,
      );

      final decoded = RoutineRunRecord.fromJson(record.toJson());

      expect(decoded.trigger, RoutineRunTrigger.scheduled);
      expect(decoded.durationMs, 4321);
      expect(decoded.usedTools, isTrue);
      expect(decoded.toolCallCount, 2);
      expect(decoded.toolNames, ['web_search', 'read_file']);
      expect(decoded.toolSourceLabels, {'web_search': 'search.local:8765'});
      expect(decoded.toolDisplayNames, [
        'web_search (search.local:8765)',
        'read_file',
      ]);
      expect(decoded.deliveryStatus, RoutineDeliveryStatus.delivered);
      expect(decoded.deliveredAt, DateTime(2026, 4, 21, 10, 0, 5));
      expect(decoded.deliveryMessage, 'Posted to Google Chat.');
      expect(decoded.preview, 'Finished successfully');
      expect(decoded.output, 'Full output');
      expect(decoded.failureAcknowledged, isTrue);
    });

    test('falls back to measured duration when durationMs is not stored', () {
      final record = RoutineRunRecord(
        id: 'run-2',
        startedAt: DateTime(2026, 4, 21, 10, 0, 0),
        finishedAt: DateTime(2026, 4, 21, 10, 0, 3, 250),
      );

      expect(record.effectiveDurationMs, 3250);
    });

    test('requires attention only for unreviewed failed runs', () {
      final failedRecord = RoutineRunRecord(
        id: 'run-failed',
        startedAt: DateTime(2026, 4, 21, 10),
        finishedAt: DateTime(2026, 4, 21, 10, 0, 3),
        status: RoutineRunStatus.failed,
        error: 'Request timed out',
      );

      expect(failedRecord.requiresAttention, isTrue);
      expect(
        failedRecord.copyWith(failureAcknowledged: true).requiresAttention,
        isFalse,
      );
    });
  });

  group('Routine', () {
    test('counts consecutive failed runs from the latest run', () {
      final routine = Routine(
        id: 'routine-1',
        name: 'Morning summary',
        prompt: 'Summarize the latest updates.',
        createdAt: DateTime(2026, 4, 21, 8),
        updatedAt: DateTime(2026, 4, 21, 9),
        runs: [
          RoutineRunRecord(
            id: 'run-failed-2',
            startedAt: DateTime(2026, 4, 21, 9),
            finishedAt: DateTime(2026, 4, 21, 9, 0, 5),
            status: RoutineRunStatus.failed,
          ),
          RoutineRunRecord(
            id: 'run-failed-1',
            startedAt: DateTime(2026, 4, 21, 8),
            finishedAt: DateTime(2026, 4, 21, 8, 0, 5),
            status: RoutineRunStatus.failed,
            failureAcknowledged: true,
          ),
          RoutineRunRecord(
            id: 'run-completed',
            startedAt: DateTime(2026, 4, 21, 7),
            finishedAt: DateTime(2026, 4, 21, 7, 0, 5),
          ),
          RoutineRunRecord(
            id: 'run-old-failed',
            startedAt: DateTime(2026, 4, 21, 6),
            finishedAt: DateTime(2026, 4, 21, 6, 0, 5),
            status: RoutineRunStatus.failed,
          ),
        ],
      );

      expect(routine.consecutiveFailureCount, 2);
    });

    test('reports zero consecutive failures after the latest run succeeds', () {
      final routine = Routine(
        id: 'routine-1',
        name: 'Morning summary',
        prompt: 'Summarize the latest updates.',
        createdAt: DateTime(2026, 4, 21, 8),
        updatedAt: DateTime(2026, 4, 21, 9),
        runs: [
          RoutineRunRecord(
            id: 'run-completed',
            startedAt: DateTime(2026, 4, 21, 9),
            finishedAt: DateTime(2026, 4, 21, 9, 0, 5),
          ),
          RoutineRunRecord(
            id: 'run-failed',
            startedAt: DateTime(2026, 4, 21, 8),
            finishedAt: DateTime(2026, 4, 21, 8, 0, 5),
            status: RoutineRunStatus.failed,
          ),
        ],
      );

      expect(routine.consecutiveFailureCount, 0);
    });

    test(
      'preserves notification and tool settings through JSON serialization',
      () {
        final routine = Routine(
          id: 'routine-1',
          name: 'Morning summary',
          prompt: 'Summarize the latest updates.',
          createdAt: DateTime(2026, 4, 21, 8),
          updatedAt: DateTime(2026, 4, 21, 9),
          notifyOnCompletion: false,
          toolsEnabled: true,
          completionAction: RoutineCompletionAction.googleChat,
          googleChatRule: RoutineGoogleChatRule.always,
          workspaceDirectory: '/tmp/caverno-routines/lan-watch',
          allowWorkspaceWrites: true,
        );

        final decoded = Routine.fromJson(routine.toJson());

        expect(decoded.notifyOnCompletion, isFalse);
        expect(decoded.toolsEnabled, isTrue);
        expect(decoded.completionAction, RoutineCompletionAction.googleChat);
        expect(decoded.googleChatRule, RoutineGoogleChatRule.always);
        expect(decoded.workspaceDirectory, '/tmp/caverno-routines/lan-watch');
        expect(decoded.allowWorkspaceWrites, isTrue);
        expect(decoded.hasWorkspaceWriteAccess, isTrue);
      },
    );

    test('preserves prompt-controlled Google Chat action', () {
      final routine = Routine(
        id: 'routine-1',
        name: 'LAN watch',
        prompt: 'Post to Google Chat only when new devices are found.',
        createdAt: DateTime(2026, 4, 21, 8),
        updatedAt: DateTime(2026, 4, 21, 9),
        completionAction: RoutineCompletionAction.promptGoogleChat,
      );

      final decoded = Routine.fromJson(routine.toJson());

      expect(
        decoded.completionAction,
        RoutineCompletionAction.promptGoogleChat,
      );
      expect(decoded.postsToGoogleChat, isFalse);
      expect(decoded.allowsPromptGoogleChatPost, isTrue);
    });
  });
}
