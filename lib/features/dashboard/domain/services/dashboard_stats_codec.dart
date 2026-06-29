import '../entities/dashboard_stats.dart';

class DashboardStatsCodec {
  const DashboardStatsCodec._();

  static Map<String, dynamic> encode(DashboardStats stats) {
    return {
      'sessionCount': stats.sessionCount,
      'messageCount': stats.messageCount,
      'totalTokens': stats.totalTokens,
      'activeDays': stats.activeDays,
      'currentStreakDays': stats.currentStreakDays,
      'longestStreakDays': stats.longestStreakDays,
      'peakHour': stats.peakHour,
      'heatmap': encodeHeatmap(stats.heatmap),
      'funFactMultiple': stats.funFactMultiple,
    };
  }

  static DashboardStats decode(Map<String, dynamic> json) {
    final heatmapJson = json['heatmap'];
    return DashboardStats(
      sessionCount: _intValue(json['sessionCount']),
      messageCount: _intValue(json['messageCount']),
      totalTokens: _intValue(json['totalTokens']),
      activeDays: _intValue(json['activeDays']),
      currentStreakDays: _intValue(json['currentStreakDays']),
      longestStreakDays: _intValue(json['longestStreakDays']),
      peakHour: _nullableIntValue(json['peakHour']),
      heatmap: heatmapJson is Map<String, dynamic>
          ? decodeHeatmap(heatmapJson)
          : ActivityHeatmap.empty(),
      funFactMultiple: _nullableDoubleValue(json['funFactMultiple']),
    );
  }

  static Map<String, dynamic> encodeHeatmap(ActivityHeatmap heatmap) {
    return {
      'startDay': heatmap.startDay.toIso8601String(),
      'endDay': heatmap.endDay.toIso8601String(),
      'dailyCounts': heatmap.dailyCounts,
      'dailyBuckets': heatmap.dailyBuckets,
    };
  }

  static ActivityHeatmap decodeHeatmap(Map<String, dynamic> json) {
    return ActivityHeatmap(
      startDay:
          DateTime.tryParse((json['startDay'] as String?) ?? '') ??
          DateTime(2000),
      endDay:
          DateTime.tryParse((json['endDay'] as String?) ?? '') ??
          DateTime(2000),
      dailyCounts: _intList(json['dailyCounts']),
      dailyBuckets: _intList(json['dailyBuckets']),
    );
  }

  static Map<String, dynamic> encodeByRange(
    Map<DashboardRange, DashboardStats> statsByRange,
  ) {
    return {
      for (final entry in statsByRange.entries)
        entry.key.name: encode(entry.value),
    };
  }

  static Map<DashboardRange, DashboardStats> decodeByRange(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const <DashboardRange, DashboardStats>{};
    }
    return {
      for (final entry in raw.entries)
        if (_rangeFromName(entry.key) != null &&
            entry.value is Map<String, dynamic>)
          _rangeFromName(entry.key)!: decode(
            entry.value as Map<String, dynamic>,
          ),
    };
  }

  static DashboardRange? _rangeFromName(String name) {
    for (final range in DashboardRange.values) {
      if (range.name == name) {
        return range;
      }
    }
    return null;
  }

  static int _intValue(Object? value) => _nullableIntValue(value) ?? 0;

  static int? _nullableIntValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static double? _nullableDoubleValue(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return null;
  }

  static List<int> _intList(Object? value) {
    if (value is! List<dynamic>) {
      return const <int>[];
    }
    return value
        .whereType<num>()
        .map((item) => item.toInt())
        .toList(growable: false);
  }
}
