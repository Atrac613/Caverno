import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../../chat/presentation/providers/model_usage_providers.dart';
import '../../../remote_coding/presentation/remote_coding_client_notifier.dart';
import '../../domain/entities/dashboard_stats.dart';
import '../../domain/entities/model_usage_stats.dart';
import '../../domain/services/dashboard_stats_calculator.dart';
import '../../domain/services/model_usage_stats_calculator.dart';

final dashboardRangeProvider =
    NotifierProvider<DashboardRangeNotifier, DashboardRange>(
      DashboardRangeNotifier.new,
    );

class DashboardRangeNotifier extends Notifier<DashboardRange> {
  @override
  DashboardRange build() => DashboardRange.all;

  void setRange(DashboardRange range) {
    state = range;
  }
}

final dashboardStatsProvider = Provider<DashboardStats>((ref) {
  final range = ref.watch(dashboardRangeProvider);
  final remoteCodingState = ref.watch(remoteCodingClientProvider);
  final remoteStats = remoteCodingState.dashboardStatsByRange[range];
  if (remoteCodingState.isConnected && remoteStats != null) {
    return remoteStats;
  }

  final conversations = ref.watch(
    conversationsNotifierProvider.select((state) => state.conversations),
  );
  return DashboardStatsCalculator.compute(
    conversations: conversations,
    range: range,
  );
});

/// Per-model token usage for the selected range.
///
/// Local-only: unlike [dashboardStatsProvider] there is no remote-coding
/// fallback, so a paired session shows this device's own accounting.
final modelUsageStatsProvider = StreamProvider<ModelUsageStats>((ref) {
  final store = ref.watch(driftModelUsageStoreProvider);
  if (store == null) {
    return Stream<ModelUsageStats>.value(ModelUsageStats.empty);
  }
  final range = ref.watch(dashboardRangeProvider);
  return store
      .watchRows(fromDayNumber: ModelUsageStatsCalculator.lowerBoundDay(range))
      .map(ModelUsageStatsCalculator.compute);
});
