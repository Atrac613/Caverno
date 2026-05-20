import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/domain/services/routine_schedule_service.dart';

void main() {
  Routine buildRoutine({
    bool enabled = true,
    int intervalValue = 2,
    RoutineIntervalUnit intervalUnit = RoutineIntervalUnit.hours,
    RoutineScheduleMode scheduleMode = RoutineScheduleMode.interval,
    int timeOfDayMinutes = 480,
    DateTime? nextRunAt,
  }) {
    final now = DateTime(2026, 4, 21, 10);
    return Routine(
      id: 'routine-1',
      name: 'Daily check',
      prompt: 'Summarize the latest updates.',
      createdAt: now,
      updatedAt: now,
      enabled: enabled,
      intervalValue: intervalValue,
      intervalUnit: intervalUnit,
      scheduleMode: scheduleMode,
      timeOfDayMinutes: timeOfDayMinutes,
      nextRunAt: nextRunAt,
    );
  }

  group('RoutineScheduleService', () {
    test('flags routines as due when next run is now or earlier', () {
      final now = DateTime(2026, 4, 21, 10);
      final routine = buildRoutine(
        nextRunAt: now.subtract(const Duration(minutes: 1)),
      );

      expect(RoutineScheduleService.isDue(routine, now: now), isTrue);
    });

    test('does not flag disabled routines as due', () {
      final now = DateTime(2026, 4, 21, 10);
      final routine = buildRoutine(
        enabled: false,
        nextRunAt: now.subtract(const Duration(minutes: 1)),
      );

      expect(RoutineScheduleService.isDue(routine, now: now), isFalse);
    });

    test('computes next run based on the configured interval', () {
      final routine = buildRoutine(
        intervalValue: 3,
        intervalUnit: RoutineIntervalUnit.days,
      );
      final from = DateTime(2026, 4, 21, 10);

      final nextRunAt = RoutineScheduleService.computeNextRunAt(
        routine: routine,
        from: from,
      );

      expect(nextRunAt, DateTime(2026, 4, 24, 10));
    });

    test('computes the next daily wall-clock run today', () {
      final routine = buildRoutine(
        scheduleMode: RoutineScheduleMode.dailyTime,
        timeOfDayMinutes: 8 * 60,
      );
      final from = DateTime(2026, 4, 21, 7, 30);

      final nextRunAt = RoutineScheduleService.computeNextRunAt(
        routine: routine,
        from: from,
      );

      expect(nextRunAt, DateTime(2026, 4, 21, 8));
    });

    test(
      'computes the next daily wall-clock run tomorrow after time passes',
      () {
        final routine = buildRoutine(
          scheduleMode: RoutineScheduleMode.dailyTime,
          timeOfDayMinutes: 8 * 60,
        );
        final from = DateTime(2026, 4, 21, 8, 1);

        final nextRunAt = RoutineScheduleService.computeNextRunAt(
          routine: routine,
          from: from,
        );

        expect(nextRunAt, DateTime(2026, 4, 22, 8));
      },
    );

    test('summarizes only visible text content', () {
      final summary = RoutineScheduleService.summarizeOutput(
        '<think>private reasoning</think>\n\nVisible result with   extra spacing.',
      );

      expect(summary, 'Visible result with extra spacing.');
    });

    test('detects when output contains only thinking content', () {
      final visible = RoutineScheduleService.visibleOutput(
        '<think>private reasoning only</think>',
      );

      expect(visible, isEmpty);
    });
  });
}
