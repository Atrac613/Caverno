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
        preview: 'Finished successfully',
        output: 'Full output',
      );

      final decoded = RoutineRunRecord.fromJson(record.toJson());

      expect(decoded.trigger, RoutineRunTrigger.scheduled);
      expect(decoded.durationMs, 4321);
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
}
