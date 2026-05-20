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
        toolCalls: const [
          RoutineRunToolCall(
            id: 'tool-1',
            name: 'web_search',
            arguments: '{"query":"tokyo"}',
            result: '{"results":[]}',
          ),
        ],
        toolSourceLabels: const {'web_search': 'search.local:8765'},
        deliveryStatus: RoutineDeliveryStatus.delivered,
        deliveredAt: DateTime(2026, 4, 21, 10, 0, 5),
        deliveryMessage: 'Posted to Google Chat.',
        preview: 'Finished successfully',
        output: 'Full output',
        usedPlan: true,
        planSourceHash: 'plan-hash',
        failureAcknowledged: true,
      );

      final decoded = RoutineRunRecord.fromJson(record.toJson());

      expect(decoded.trigger, RoutineRunTrigger.scheduled);
      expect(decoded.durationMs, 4321);
      expect(decoded.usedTools, isTrue);
      expect(decoded.toolCallCount, 2);
      expect(decoded.toolNames, ['web_search', 'read_file']);
      expect(decoded.toolCalls, hasLength(1));
      expect(decoded.toolCalls.single.name, 'web_search');
      expect(decoded.toolCalls.single.arguments, '{"query":"tokyo"}');
      expect(decoded.toolCalls.single.result, '{"results":[]}');
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
      expect(decoded.usedPlan, isTrue);
      expect(decoded.planSourceHash, 'plan-hash');
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

    test('tracks approved routine plans against the current source hash', () {
      final routine = Routine(
        id: 'routine-1',
        name: 'LAN watch',
        prompt: 'Scan LAN and report new devices.',
        createdAt: DateTime(2026, 4, 21, 8),
        updatedAt: DateTime(2026, 4, 21, 9),
        toolsEnabled: true,
        workspaceDirectory: '/tmp/caverno-routines/lan-watch',
        allowWorkspaceWrites: true,
        completionAction: RoutineCompletionAction.promptGoogleChat,
      );
      final artifact = RoutinePlanArtifact(
        draftMarkdown: '# Routine Plan\nScan LAN.',
        approvedMarkdown: '# Routine Plan\nScan LAN.',
        approvedSourceHash: routine.planSourceHash,
        approvedAt: DateTime(2026, 4, 21, 9, 10),
      );
      final plannedRoutine = routine.copyWith(planArtifact: artifact);

      expect(plannedRoutine.isApprovedPlanFresh, isTrue);
      expect(plannedRoutine.hasStaleApprovedPlan, isFalse);
      expect(plannedRoutine.freshApprovedPlanMarkdown, contains('Scan LAN'));

      final changedRoutine = plannedRoutine.copyWith(
        prompt: 'Scan LAN and report all devices.',
      );

      expect(changedRoutine.isApprovedPlanFresh, isFalse);
      expect(changedRoutine.hasStaleApprovedPlan, isTrue);
      expect(changedRoutine.freshApprovedPlanMarkdown, isNull);

      final rescheduledRoutine = plannedRoutine.copyWith(
        scheduleMode: RoutineScheduleMode.dailyTime,
        timeOfDayMinutes: 8 * Duration.minutesPerHour,
      );

      expect(rescheduledRoutine.isApprovedPlanFresh, isFalse);
      expect(rescheduledRoutine.hasStaleApprovedPlan, isTrue);
      expect(rescheduledRoutine.freshApprovedPlanMarkdown, isNull);
    });

    test('preserves routine plan artifact revisions through JSON', () {
      final artifact = RoutinePlanArtifact(
        draftMarkdown: '# Draft',
        approvedMarkdown: '# Approved',
        approvedSourceHash: 'hash-1',
        approvedAt: DateTime(2026, 4, 21, 9),
        updatedAt: DateTime(2026, 4, 21, 9, 5),
        revisions: [
          RoutinePlanRevision(
            markdown: '# Approved',
            createdAt: DateTime(2026, 4, 21, 9),
            kind: RoutinePlanRevisionKind.approved,
            label: 'Approved routine plan',
          ),
        ],
      );
      final routine = Routine(
        id: 'routine-1',
        name: 'LAN watch',
        prompt: 'Scan LAN.',
        createdAt: DateTime(2026, 4, 21, 8),
        updatedAt: DateTime(2026, 4, 21, 9),
        planArtifact: artifact,
      );

      final decoded = Routine.fromJson(routine.toJson());

      expect(decoded.effectivePlanArtifact.normalizedDraftMarkdown, '# Draft');
      expect(
        decoded.effectivePlanArtifact.normalizedApprovedMarkdown,
        '# Approved',
      );
      expect(decoded.effectivePlanArtifact.approvedSourceHash, 'hash-1');
      expect(decoded.effectivePlanArtifact.historyEntries, hasLength(1));
      expect(
        decoded.effectivePlanArtifact.historyEntries.single.kind,
        RoutinePlanRevisionKind.approved,
      );
    });
  });
}
