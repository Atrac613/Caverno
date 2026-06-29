import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:caverno/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:caverno/features/remote_coding/presentation/remote_coding_client_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses remote desktop dashboard stats while connected', () {
    final remoteStats = DashboardStats(
      sessionCount: 9,
      messageCount: 42,
      totalTokens: 123456,
      activeDays: 6,
      currentStreakDays: 3,
      longestStreakDays: 8,
      peakHour: 10,
      heatmap: ActivityHeatmap(
        startDay: DateTime(2026, 6, 1),
        endDay: DateTime(2026, 6, 7),
        dailyCounts: const [1, 2],
        dailyBuckets: const [2, 4],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        remoteCodingClientProvider.overrideWith(
          () => _RemoteDashboardStatsNotifier(remoteStats),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(dashboardRangeProvider.notifier)
        .setRange(DashboardRange.last7Days);

    expect(container.read(dashboardStatsProvider), remoteStats);
  });

  test(
    'falls back to local conversations when remote dashboard stats are absent',
    () {
      final container = ProviderContainer(
        overrides: [
          remoteCodingClientProvider.overrideWith(
            _DisconnectedRemoteCodingClientNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _LocalConversationsNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final stats = container.read(dashboardStatsProvider);

      expect(stats.sessionCount, 1);
      expect(stats.messageCount, 2);
      expect(stats.totalTokens, 320);
    },
  );
}

class _RemoteDashboardStatsNotifier extends RemoteCodingClientNotifier {
  _RemoteDashboardStatsNotifier(this.stats);

  final DashboardStats stats;

  @override
  RemoteCodingClientState build() {
    return RemoteCodingClientState(
      status: RemoteCodingConnectionStatus.connected,
      dashboardStatsByRange: {DashboardRange.last7Days: stats},
    );
  }
}

class _DisconnectedRemoteCodingClientNotifier
    extends RemoteCodingClientNotifier {
  @override
  RemoteCodingClientState build() => const RemoteCodingClientState();
}

class _LocalConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() {
    final conversation = Conversation(
      id: 'local-1',
      title: 'Local chat',
      messages: [
        Message(
          id: 'user-1',
          content: 'Hello',
          role: MessageRole.user,
          timestamp: DateTime(2026, 6, 1, 9),
        ),
        Message(
          id: 'assistant-1',
          content: 'Hi',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 1, 9, 1),
          responseMetrics: const MessageResponseMetrics(totalTokens: 320),
        ),
      ],
      createdAt: DateTime(2026, 6, 1, 9),
      updatedAt: DateTime(2026, 6, 1, 9, 1),
    );
    return ConversationsState(
      conversations: [conversation],
      currentConversationId: conversation.id,
      activeWorkspaceMode: WorkspaceMode.chat,
      activeProjectId: null,
    );
  }
}
