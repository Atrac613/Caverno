import '../../../chat/domain/entities/conversation.dart';
import '../../../chat/domain/entities/message.dart';
import '../entities/dashboard_stats.dart';

class DashboardStatsCalculator {
  DashboardStatsCalculator._();

  // Approximate token count for "Harry Potter and the Philosopher's Stone".
  static const int philosopherStoneTokenReference = 135000;
  static const String _defaultConversationTitle = '__new_conversation__';
  static const int _minimumAllRangeWeeks = 16;
  static const int _maximumAllRangeWeeks = 53;
  static const int _weekLengthDays = 7;
  static const int _sunday = DateTime.sunday;

  static DashboardStats compute({
    required List<Conversation> conversations,
    required DashboardRange range,
    DateTime? now,
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = _localDay(localNow);
    final entries = _collectEntries(conversations);
    final filteredEntries = _filterEntries(entries, range, localNow);

    final sessionIds = <String>{};
    final activeDays = <int>{};
    final fullActiveDays = <int>{};
    final hourCounts = List<int>.filled(24, 0);
    final heatmapCounts = <int, int>{};
    var totalTokens = 0;

    for (final entry in entries) {
      fullActiveDays.add(_dayNumber(entry.day));
    }

    for (final entry in filteredEntries) {
      sessionIds.add(entry.conversationId);
      final dayNumber = _dayNumber(entry.day);
      activeDays.add(dayNumber);
      heatmapCounts.update(dayNumber, (value) => value + 1, ifAbsent: () => 1);
      hourCounts[entry.timestamp.hour]++;
      if (entry.message.role == MessageRole.assistant) {
        totalTokens += entry.message.responseMetrics?.totalTokens ?? 0;
      }
    }

    final heatmap = _buildHeatmap(
      range: range,
      today: today,
      countsByDay: heatmapCounts,
    );
    return DashboardStats(
      sessionCount: sessionIds.length,
      messageCount: filteredEntries.length,
      totalTokens: totalTokens,
      activeDays: activeDays.length,
      currentStreakDays: _currentStreakDays(fullActiveDays, today),
      longestStreakDays: _longestStreakDays(fullActiveDays),
      peakHour: _peakHour(hourCounts, filteredEntries.isEmpty),
      heatmap: heatmap,
      funFactMultiple: _funFactMultiple(totalTokens),
    );
  }

  static List<_DashboardMessageEntry> _collectEntries(
    List<Conversation> conversations,
  ) {
    final entries = <_DashboardMessageEntry>[];
    for (final conversation in conversations) {
      if (conversation.title == _defaultConversationTitle &&
          conversation.messages.isEmpty) {
        continue;
      }
      for (final message in conversation.messages) {
        if (message.role == MessageRole.system || message.isStreaming) {
          continue;
        }
        final localTimestamp = message.timestamp.toLocal();
        entries.add(
          _DashboardMessageEntry(
            conversationId: conversation.id,
            message: message,
            timestamp: localTimestamp,
            day: _localDay(localTimestamp),
          ),
        );
      }
    }
    return entries;
  }

  static List<_DashboardMessageEntry> _filterEntries(
    List<_DashboardMessageEntry> entries,
    DashboardRange range,
    DateTime localNow,
  ) {
    final lowerBound = switch (range) {
      DashboardRange.all => null,
      DashboardRange.last30Days => localNow.subtract(const Duration(days: 30)),
      DashboardRange.last7Days => localNow.subtract(const Duration(days: 7)),
    };
    if (lowerBound == null) {
      return entries;
    }
    return entries
        .where((entry) => !entry.timestamp.isBefore(lowerBound))
        .toList(growable: false);
  }

  static ActivityHeatmap _buildHeatmap({
    required DashboardRange range,
    required DateTime today,
    required Map<int, int> countsByDay,
  }) {
    final startDay = _heatmapStartDay(
      range: range,
      today: today,
      countsByDay: countsByDay,
    );
    final dayCount = _dayNumber(today) - _dayNumber(startDay) + 1;
    final dailyCounts = List<int>.generate(dayCount, (index) {
      final day = DateTime(startDay.year, startDay.month, startDay.day + index);
      return countsByDay[_dayNumber(day)] ?? 0;
    }, growable: false);
    final buckets = _bucketCounts(dailyCounts);
    return ActivityHeatmap(
      startDay: startDay,
      endDay: today,
      dailyCounts: dailyCounts,
      dailyBuckets: buckets,
    );
  }

  static DateTime _heatmapStartDay({
    required DashboardRange range,
    required DateTime today,
    required Map<int, int> countsByDay,
  }) {
    final todayNumber = _dayNumber(today);
    return switch (range) {
      DashboardRange.last7Days => _startOfWeek(
        DateTime(today.year, today.month, today.day - 7),
      ),
      DashboardRange.last30Days => _startOfWeek(
        DateTime(today.year, today.month, today.day - 30),
      ),
      DashboardRange.all => () {
        final maximumStart = _startOfWeek(
          DateTime(
            today.year,
            today.month,
            today.day - (_maximumAllRangeWeeks * _weekLengthDays - 1),
          ),
        );
        final minimumStart = _startOfWeek(
          DateTime(
            today.year,
            today.month,
            today.day - (_minimumAllRangeWeeks * _weekLengthDays - 1),
          ),
        );
        if (countsByDay.isEmpty) {
          return minimumStart;
        }
        final firstActiveNumber = countsByDay.keys.reduce(
          (value, element) => value < element ? value : element,
        );
        final firstActiveDay = _dayFromNumber(firstActiveNumber);
        final activityStart = _startOfWeek(firstActiveDay);
        final cappedForMinimum =
            _dayNumber(activityStart) > _dayNumber(minimumStart)
            ? minimumStart
            : activityStart;
        final cappedForMaximum =
            _dayNumber(cappedForMinimum) < _dayNumber(maximumStart)
            ? maximumStart
            : cappedForMinimum;
        if (_dayNumber(cappedForMaximum) > todayNumber) {
          return _startOfWeek(today);
        }
        return cappedForMaximum;
      }(),
    };
  }

  static List<int> _bucketCounts(List<int> counts) {
    final positiveCounts = counts.where((count) => count > 0).toList()..sort();
    if (positiveCounts.isEmpty) {
      return List<int>.filled(counts.length, 0, growable: false);
    }
    return counts
        .map((count) {
          if (count <= 0) {
            return 0;
          }
          final rank = _upperBound(positiveCounts, count);
          final bucket =
              ((rank * 4 + positiveCounts.length - 1) ~/ positiveCounts.length);
          return bucket.clamp(1, 4);
        })
        .toList(growable: false);
  }

  static int _upperBound(List<int> sortedValues, int value) {
    var low = 0;
    var high = sortedValues.length;
    while (low < high) {
      final mid = low + ((high - low) >> 1);
      if (value < sortedValues[mid]) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  static int _currentStreakDays(Set<int> activeDays, DateTime today) {
    var cursor = _dayNumber(today);
    var streak = 0;
    while (activeDays.contains(cursor)) {
      streak++;
      cursor--;
    }
    return streak;
  }

  static int _longestStreakDays(Set<int> activeDays) {
    if (activeDays.isEmpty) {
      return 0;
    }
    final sortedDays = activeDays.toList()..sort();
    var longest = 1;
    var current = 1;
    for (var index = 1; index < sortedDays.length; index++) {
      if (sortedDays[index] == sortedDays[index - 1] + 1) {
        current++;
      } else {
        current = 1;
      }
      if (current > longest) {
        longest = current;
      }
    }
    return longest;
  }

  static int? _peakHour(List<int> hourCounts, bool isEmpty) {
    if (isEmpty) {
      return null;
    }
    var peakHour = 0;
    var peakCount = hourCounts[0];
    for (var hour = 1; hour < hourCounts.length; hour++) {
      if (hourCounts[hour] > peakCount) {
        peakHour = hour;
        peakCount = hourCounts[hour];
      }
    }
    return peakHour;
  }

  static double? _funFactMultiple(int totalTokens) {
    if (totalTokens < philosopherStoneTokenReference) {
      return null;
    }
    return totalTokens / philosopherStoneTokenReference;
  }

  static DateTime _localDay(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _startOfWeek(DateTime day) {
    final normalizedDay = _localDay(day);
    final offset = normalizedDay.weekday % _sunday;
    return DateTime(
      normalizedDay.year,
      normalizedDay.month,
      normalizedDay.day - offset,
    );
  }

  static int _dayNumber(DateTime day) {
    final normalizedDay = _localDay(day);
    return DateTime.utc(
          normalizedDay.year,
          normalizedDay.month,
          normalizedDay.day,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  static DateTime _dayFromNumber(int dayNumber) {
    final utcDay = DateTime.fromMillisecondsSinceEpoch(
      dayNumber * Duration.millisecondsPerDay,
      isUtc: true,
    );
    return DateTime(utcDay.year, utcDay.month, utcDay.day);
  }
}

class _DashboardMessageEntry {
  const _DashboardMessageEntry({
    required this.conversationId,
    required this.message,
    required this.timestamp,
    required this.day,
  });

  final String conversationId;
  final Message message;
  final DateTime timestamp;
  final DateTime day;
}
