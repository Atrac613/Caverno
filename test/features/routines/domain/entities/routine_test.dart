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
        preview: 'Finished successfully',
        output: 'Full output',
      );

      final decoded = RoutineRunRecord.fromJson(record.toJson());

      expect(decoded.trigger, RoutineRunTrigger.scheduled);
      expect(decoded.durationMs, 4321);
      expect(decoded.usedTools, isTrue);
      expect(decoded.toolCallCount, 2);
      expect(decoded.toolNames, ['web_search', 'read_file']);
      expect(decoded.preview, 'Finished successfully');
      expect(decoded.output, 'Full output');
    });

    test('falls back to measured duration when durationMs is not stored', () {
      final record = RoutineRunRecord(
        id: 'run-2',
        startedAt: DateTime(2026, 4, 21, 10, 0, 0),
        finishedAt: DateTime(2026, 4, 21, 10, 0, 3, 250),
      );

      expect(record.effectiveDurationMs, 3250);
    });
  });

  group('Routine', () {
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
        );

        final decoded = Routine.fromJson(routine.toJson());

        expect(decoded.notifyOnCompletion, isFalse);
        expect(decoded.toolsEnabled, isTrue);
      },
    );
  });
}
