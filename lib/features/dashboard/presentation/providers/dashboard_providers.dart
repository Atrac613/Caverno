import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../../remote_coding/presentation/remote_coding_client_notifier.dart';
import '../../domain/entities/dashboard_stats.dart';
import '../../domain/services/dashboard_stats_calculator.dart';

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
