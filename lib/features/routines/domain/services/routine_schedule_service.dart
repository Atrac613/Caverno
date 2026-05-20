import '../../../../core/utils/content_parser.dart';
import '../entities/routine.dart';

class RoutineScheduleService {
  RoutineScheduleService._();

  static int normalizeIntervalValue(int value) => value < 1 ? 1 : value;

  static int normalizeTimeOfDayMinutes(int value) {
    return value.clamp(0, Duration.minutesPerDay - 1);
  }

  static String formatTimeOfDayMinutes(int value) {
    final minutes = normalizeTimeOfDayMinutes(value);
    final hour = minutes ~/ Duration.minutesPerHour;
    final minute = minutes % Duration.minutesPerHour;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static Duration intervalDuration(Routine routine) {
    final intervalValue = normalizeIntervalValue(routine.intervalValue);
    return switch (routine.intervalUnit) {
      RoutineIntervalUnit.minutes => Duration(minutes: intervalValue),
      RoutineIntervalUnit.hours => Duration(hours: intervalValue),
      RoutineIntervalUnit.days => Duration(days: intervalValue),
    };
  }

  static DateTime computeNextRunAt({required Routine routine, DateTime? from}) {
    final currentTime = from ?? DateTime.now();
    if (routine.scheduleMode == RoutineScheduleMode.dailyTime) {
      return _computeNextDailyRunAt(routine: routine, from: currentTime);
    }
    return currentTime.add(intervalDuration(routine));
  }

  static DateTime _computeNextDailyRunAt({
    required Routine routine,
    required DateTime from,
  }) {
    final minutes = normalizeTimeOfDayMinutes(routine.timeOfDayMinutes);
    final candidate = DateTime(
      from.year,
      from.month,
      from.day,
      minutes ~/ Duration.minutesPerHour,
      minutes % Duration.minutesPerHour,
    );
    return candidate.isAfter(from)
        ? candidate
        : candidate.add(const Duration(days: 1));
  }

  static bool isDue(Routine routine, {DateTime? now}) {
    if (!routine.enabled || !routine.hasPrompt) {
      return false;
    }

    final nextRunAt = routine.nextRunAt;
    if (nextRunAt == null) {
      return false;
    }

    return !nextRunAt.isAfter(now ?? DateTime.now());
  }

  static List<Routine> dueRoutines(
    Iterable<Routine> routines, {
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final due = routines
        .where((routine) => isDue(routine, now: currentTime))
        .toList(growable: false);
    due.sort((left, right) {
      final leftNext = left.nextRunAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightNext =
          right.nextRunAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return leftNext.compareTo(rightNext);
    });
    return due;
  }

  static String summarizeOutput(String content, {int maxLength = 220}) {
    final normalized = visibleOutput(content);
    if (normalized.isEmpty) {
      return '';
    }
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }

  static String visibleOutput(String content) {
    final parsed = ContentParser.parse(content);
    final buffer = StringBuffer();

    for (final segment in parsed.segments) {
      if (segment.type == ContentType.text) {
        buffer.write(segment.content);
      }
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String truncateOutput(String content, {int maxLength = 4000}) {
    final trimmed = content.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    return '${trimmed.substring(0, maxLength - 3)}...';
  }
}
