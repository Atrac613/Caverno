import 'package:freezed_annotation/freezed_annotation.dart';

part 'dashboard_stats.freezed.dart';

enum DashboardRange { all, last30Days, last7Days }

@freezed
abstract class DashboardStats with _$DashboardStats {
  const factory DashboardStats({
    @Default(0) int sessionCount,
    @Default(0) int messageCount,
    @Default(0) int totalTokens,
    @Default(0) int activeDays,
    @Default(0) int currentStreakDays,
    @Default(0) int longestStreakDays,
    int? peakHour,
    required ActivityHeatmap heatmap,
    double? funFactMultiple,
  }) = _DashboardStats;

  factory DashboardStats.empty() =>
      DashboardStats(heatmap: ActivityHeatmap.empty());
}

@freezed
abstract class ActivityHeatmap with _$ActivityHeatmap {
  const factory ActivityHeatmap({
    required DateTime startDay,
    required DateTime endDay,
    @Default(<int>[]) List<int> dailyCounts,
    @Default(<int>[]) List<int> dailyBuckets,
  }) = _ActivityHeatmap;

  factory ActivityHeatmap.empty() =>
      ActivityHeatmap(startDay: DateTime(2000), endDay: DateTime(2000));
}
