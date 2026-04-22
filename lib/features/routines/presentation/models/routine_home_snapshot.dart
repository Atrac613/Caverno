import '../../domain/entities/routine.dart';
import '../../domain/services/routine_schedule_service.dart';

enum RoutineHomeSectionKind { attention, scheduled, paused }

class RoutineHomeSection {
  const RoutineHomeSection({required this.kind, required this.routines});

  final RoutineHomeSectionKind kind;
  final List<Routine> routines;
}

class RoutineHomeSnapshot {
  const RoutineHomeSnapshot({
    required this.enabledCount,
    required this.dueCount,
    required this.runningCount,
    required this.attentionCount,
    required this.sections,
  });

  final int enabledCount;
  final int dueCount;
  final int runningCount;
  final int attentionCount;
  final List<RoutineHomeSection> sections;
}

class RoutineHomeSnapshotBuilder {
  RoutineHomeSnapshotBuilder._();

  static RoutineHomeSnapshot build({
    required List<Routine> routines,
    required Set<String> runningRoutineIds,
  }) {
    final attention = <Routine>[];
    final scheduled = <Routine>[];
    final paused = <Routine>[];

    for (final routine in routines) {
      if (!routine.enabled) {
        paused.add(routine);
        continue;
      }

      if (_needsAttention(routine, runningRoutineIds: runningRoutineIds)) {
        attention.add(routine);
        continue;
      }

      scheduled.add(routine);
    }

    _sortAttention(attention, runningRoutineIds: runningRoutineIds);
    _sortScheduled(scheduled);
    _sortPaused(paused);

    return RoutineHomeSnapshot(
      enabledCount: routines.where((routine) => routine.enabled).length,
      dueCount: routines.where(RoutineScheduleService.isDue).length,
      runningCount: runningRoutineIds.length,
      attentionCount: attention.length,
      sections: [
        if (attention.isNotEmpty)
          RoutineHomeSection(
            kind: RoutineHomeSectionKind.attention,
            routines: attention,
          ),
        if (scheduled.isNotEmpty)
          RoutineHomeSection(
            kind: RoutineHomeSectionKind.scheduled,
            routines: scheduled,
          ),
        if (paused.isNotEmpty)
          RoutineHomeSection(
            kind: RoutineHomeSectionKind.paused,
            routines: paused,
          ),
      ],
    );
  }

  static bool _needsAttention(
    Routine routine, {
    required Set<String> runningRoutineIds,
  }) {
    if (runningRoutineIds.contains(routine.id)) {
      return true;
    }
    if (RoutineScheduleService.isDue(routine)) {
      return true;
    }
    return routine.latestRun?.status == RoutineRunStatus.failed;
  }

  static void _sortAttention(
    List<Routine> routines, {
    required Set<String> runningRoutineIds,
  }) {
    routines.sort((left, right) {
      final byPriority =
          _attentionPriority(
            left,
            runningRoutineIds: runningRoutineIds,
          ).compareTo(
            _attentionPriority(right, runningRoutineIds: runningRoutineIds),
          );
      if (byPriority != 0) {
        return byPriority;
      }

      final byNextRun = _compareNullableDate(
        left.nextRunAt,
        right.nextRunAt,
        nullsLast: true,
      );
      if (byNextRun != 0) {
        return byNextRun;
      }

      final byLatestRun = _compareNullableDate(
        right.latestRun?.startedAt,
        left.latestRun?.startedAt,
        nullsLast: true,
      );
      if (byLatestRun != 0) {
        return byLatestRun;
      }

      return right.updatedAt.compareTo(left.updatedAt);
    });
  }

  static void _sortScheduled(List<Routine> routines) {
    routines.sort((left, right) {
      final byNextRun = _compareNullableDate(
        left.nextRunAt,
        right.nextRunAt,
        nullsLast: true,
      );
      if (byNextRun != 0) {
        return byNextRun;
      }

      return right.updatedAt.compareTo(left.updatedAt);
    });
  }

  static void _sortPaused(List<Routine> routines) {
    routines.sort((left, right) {
      final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
      if (byUpdatedAt != 0) {
        return byUpdatedAt;
      }
      return left.trimmedName.compareTo(right.trimmedName);
    });
  }

  static int _attentionPriority(
    Routine routine, {
    required Set<String> runningRoutineIds,
  }) {
    if (runningRoutineIds.contains(routine.id)) {
      return 0;
    }
    if (RoutineScheduleService.isDue(routine)) {
      return 1;
    }
    if (routine.latestRun?.status == RoutineRunStatus.failed) {
      return 2;
    }
    return 3;
  }

  static int _compareNullableDate(
    DateTime? left,
    DateTime? right, {
    required bool nullsLast,
  }) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return nullsLast ? 1 : -1;
    }
    if (right == null) {
      return nullsLast ? -1 : 1;
    }
    return left.compareTo(right);
  }
}
