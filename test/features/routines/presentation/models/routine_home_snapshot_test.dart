import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/models/routine_home_snapshot.dart';

void main() {
  Routine buildRoutine({
    required String id,
    required String name,
    required DateTime updatedAt,
    bool enabled = true,
    DateTime? nextRunAt,
    List<RoutineRunRecord> runs = const [],
  }) {
    final createdAt = DateTime(2026, 4, 21, 8);
    return Routine(
      id: id,
      name: name,
      prompt: 'Summarize the latest updates.',
      createdAt: createdAt,
      updatedAt: updatedAt,
      enabled: enabled,
      intervalValue: 1,
      intervalUnit: RoutineIntervalUnit.hours,
      nextRunAt: nextRunAt,
      runs: runs,
    );
  }

  group('RoutineHomeSnapshotBuilder', () {
    test('groups routines by attention, scheduled, and paused state', () {
      final dueRoutine = buildRoutine(
        id: 'due',
        name: 'Due routine',
        updatedAt: DateTime(2026, 4, 21, 9),
        nextRunAt: DateTime(2026, 4, 21, 8, 30),
      );
      final failedRoutine = buildRoutine(
        id: 'failed',
        name: 'Failed routine',
        updatedAt: DateTime(2026, 4, 21, 9, 30),
        nextRunAt: DateTime(3026, 4, 21, 12),
        runs: [
          RoutineRunRecord(
            id: 'run-failed',
            startedAt: DateTime(2026, 4, 21, 8, 45),
            finishedAt: DateTime(2026, 4, 21, 8, 45, 10),
            status: RoutineRunStatus.failed,
            error: 'Request timed out',
          ),
        ],
      );
      final scheduledRoutine = buildRoutine(
        id: 'scheduled',
        name: 'Scheduled routine',
        updatedAt: DateTime(2026, 4, 21, 8, 50),
        nextRunAt: DateTime(3026, 4, 21, 11),
      );
      final pausedRoutine = buildRoutine(
        id: 'paused',
        name: 'Paused routine',
        updatedAt: DateTime(2026, 4, 21, 10),
        enabled: false,
        nextRunAt: DateTime(2026, 4, 21, 7),
      );

      final snapshot = RoutineHomeSnapshotBuilder.build(
        routines: [scheduledRoutine, pausedRoutine, failedRoutine, dueRoutine],
        runningRoutineIds: const <String>{},
      );

      expect(snapshot.enabledCount, 3);
      expect(snapshot.dueCount, 1);
      expect(snapshot.runningCount, 0);
      expect(snapshot.attentionCount, 2);
      expect(snapshot.sections.map((section) => section.kind).toList(), [
        RoutineHomeSectionKind.attention,
        RoutineHomeSectionKind.scheduled,
        RoutineHomeSectionKind.paused,
      ]);
      expect(
        snapshot.sections[0].routines.map((routine) => routine.id).toList(),
        ['due', 'failed'],
      );
      expect(
        snapshot.sections[1].routines.map((routine) => routine.id).toList(),
        ['scheduled'],
      );
      expect(
        snapshot.sections[2].routines.map((routine) => routine.id).toList(),
        ['paused'],
      );
    });

    test('prioritizes running routines within the attention section', () {
      final runningRoutine = buildRoutine(
        id: 'running',
        name: 'Running routine',
        updatedAt: DateTime(2026, 4, 21, 10),
        nextRunAt: DateTime(2026, 4, 21, 9),
      );
      final dueRoutine = buildRoutine(
        id: 'due',
        name: 'Due routine',
        updatedAt: DateTime(2026, 4, 21, 9),
        nextRunAt: DateTime(2026, 4, 21, 8, 30),
      );
      final failedRoutine = buildRoutine(
        id: 'failed',
        name: 'Failed routine',
        updatedAt: DateTime(2026, 4, 21, 8),
        nextRunAt: DateTime(3026, 4, 21, 11),
        runs: [
          RoutineRunRecord(
            id: 'run-failed',
            startedAt: DateTime(2026, 4, 21, 7, 30),
            finishedAt: DateTime(2026, 4, 21, 7, 30, 8),
            status: RoutineRunStatus.failed,
            error: 'Unauthorized',
          ),
        ],
      );

      final snapshot = RoutineHomeSnapshotBuilder.build(
        routines: [failedRoutine, dueRoutine, runningRoutine],
        runningRoutineIds: const {'running'},
      );

      expect(
        snapshot.sections.first.routines.map((routine) => routine.id).toList(),
        ['running', 'due', 'failed'],
      );
    });

    test('keeps disabled routines out of the attention section', () {
      final pausedFailedRoutine = buildRoutine(
        id: 'paused-failed',
        name: 'Paused failed routine',
        updatedAt: DateTime(2026, 4, 21, 10),
        enabled: false,
        nextRunAt: DateTime(2026, 4, 21, 8),
        runs: [
          RoutineRunRecord(
            id: 'run-failed',
            startedAt: DateTime(2026, 4, 21, 7),
            finishedAt: DateTime(2026, 4, 21, 7, 0, 5),
            status: RoutineRunStatus.failed,
            error: 'Network error',
          ),
        ],
      );

      final snapshot = RoutineHomeSnapshotBuilder.build(
        routines: [pausedFailedRoutine],
        runningRoutineIds: const <String>{},
      );

      expect(snapshot.attentionCount, 0);
      expect(snapshot.sections.single.kind, RoutineHomeSectionKind.paused);
    });
  });
}
