import 'package:caverno/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:caverno/features/dashboard/domain/services/dashboard_stats_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips dashboard stats by range', () {
    final stats = DashboardStats(
      sessionCount: 3,
      messageCount: 12,
      totalTokens: 3456,
      activeDays: 4,
      currentStreakDays: 2,
      longestStreakDays: 5,
      peakHour: 14,
      heatmap: ActivityHeatmap(
        startDay: DateTime(2026, 6, 1),
        endDay: DateTime(2026, 6, 7),
        dailyCounts: const [0, 1, 2],
        dailyBuckets: const [0, 2, 4],
      ),
      funFactMultiple: 1.5,
    );

    final encoded = DashboardStatsCodec.encodeByRange({
      DashboardRange.all: stats,
    });
    final decoded = DashboardStatsCodec.decodeByRange(encoded);

    expect(decoded.keys, contains(DashboardRange.all));
    expect(decoded[DashboardRange.all], stats);
  });

  test('ignores unknown ranges and malformed stats payloads', () {
    final decoded = DashboardStatsCodec.decodeByRange({
      'unknown': {'messageCount': 99},
      DashboardRange.last7Days.name: 'bad',
      DashboardRange.last30Days.name: {
        'messageCount': 7,
        'heatmap': {
          'startDay': DateTime(2026, 6, 1).toIso8601String(),
          'endDay': DateTime(2026, 6, 7).toIso8601String(),
          'dailyCounts': [1, 2],
          'dailyBuckets': [3, 4],
        },
      },
    });

    expect(decoded.keys, [DashboardRange.last30Days]);
    expect(decoded[DashboardRange.last30Days]?.messageCount, 7);
    expect(decoded[DashboardRange.last30Days]?.heatmap.dailyBuckets, [3, 4]);
  });
}
