import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:caverno/features/dashboard/domain/services/dashboard_stats_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardStatsCalculator', () {
    final now = DateTime(2026, 6, 27, 15, 30);

    test('computes session, message, token, day, streak, and peak metrics', () {
      final conversations = [
        _conversation(
          id: 'a',
          messages: [
            _message('u1', MessageRole.user, DateTime(2026, 6, 25, 9)),
            _message(
              'a1',
              MessageRole.assistant,
              DateTime(2026, 6, 25, 14),
              tokens: 100000,
            ),
            _message('u2', MessageRole.user, DateTime(2026, 6, 26, 14)),
            _message(
              'a2',
              MessageRole.assistant,
              DateTime(2026, 6, 27, 14),
              tokens: 35000,
            ),
          ],
        ),
        _conversation(
          id: 'b',
          messages: [
            _message('u3', MessageRole.user, DateTime(2026, 6, 27, 10)),
            _message(
              'a3',
              MessageRole.assistant,
              DateTime(2026, 6, 27, 10),
              tokens: 135000,
            ),
            _message('s1', MessageRole.system, DateTime(2026, 6, 27, 10)),
            _message(
              'streaming',
              MessageRole.assistant,
              DateTime(2026, 6, 27, 11),
              isStreaming: true,
              tokens: 999999,
            ),
          ],
        ),
        _conversation(id: 'draft', title: '__new_conversation__'),
      ];

      final stats = DashboardStatsCalculator.compute(
        conversations: conversations,
        range: DashboardRange.all,
        now: now,
      );

      expect(stats.sessionCount, 2);
      expect(stats.messageCount, 6);
      expect(stats.totalTokens, 270000);
      expect(stats.activeDays, 3);
      expect(stats.currentStreakDays, 3);
      expect(stats.longestStreakDays, 3);
      expect(stats.peakHour, 14);
      expect(stats.funFactMultiple, 2);
    });

    test('range filters message metrics but keeps streaks all-time', () {
      final conversations = [
        _conversation(
          id: 'a',
          messages: [
            _message('old', MessageRole.user, DateTime(2026, 5, 20, 9)),
            _message('today', MessageRole.user, DateTime(2026, 6, 27, 9)),
          ],
        ),
        _conversation(
          id: 'b',
          messages: [
            _message('yesterday', MessageRole.user, DateTime(2026, 6, 26, 9)),
          ],
        ),
      ];

      final all = DashboardStatsCalculator.compute(
        conversations: conversations,
        range: DashboardRange.all,
        now: now,
      );
      final last7Days = DashboardStatsCalculator.compute(
        conversations: conversations,
        range: DashboardRange.last7Days,
        now: now,
      );

      expect(all.messageCount, 3);
      expect(last7Days.messageCount, 2);
      expect(last7Days.sessionCount, 2);
      expect(last7Days.currentStreakDays, 2);
      expect(last7Days.longestStreakDays, 2);
    });

    test('returns zero message metrics when no recent activity exists', () {
      final stats = DashboardStatsCalculator.compute(
        conversations: [
          _conversation(
            id: 'a',
            messages: [
              _message('old', MessageRole.user, DateTime(2026, 1, 1, 9)),
            ],
          ),
        ],
        range: DashboardRange.last7Days,
        now: now,
      );

      expect(stats.sessionCount, 0);
      expect(stats.messageCount, 0);
      expect(stats.activeDays, 0);
      expect(stats.peakHour, isNull);
      expect(stats.currentStreakDays, 0);
      expect(stats.longestStreakDays, 1);
      expect(stats.heatmap.dailyCounts.any((count) => count > 0), isFalse);
    });

    test('buckets heatmap counts with an adaptive intensity ramp', () {
      final stats = DashboardStatsCalculator.compute(
        conversations: [
          _conversation(
            id: 'a',
            messages: [
              _message('d1', MessageRole.user, DateTime(2026, 6, 24, 9)),
              for (var index = 0; index < 2; index++)
                _message(
                  'd2-$index',
                  MessageRole.user,
                  DateTime(2026, 6, 25, 9, index),
                ),
              for (var index = 0; index < 4; index++)
                _message(
                  'd3-$index',
                  MessageRole.user,
                  DateTime(2026, 6, 26, 9, index),
                ),
              for (var index = 0; index < 8; index++)
                _message(
                  'd4-$index',
                  MessageRole.user,
                  DateTime(2026, 6, 27, 9, index),
                ),
            ],
          ),
        ],
        range: DashboardRange.last7Days,
        now: now,
      );

      final nonZeroBuckets = stats.heatmap.dailyBuckets
          .where((bucket) => bucket > 0)
          .toList(growable: false);

      expect(nonZeroBuckets, [1, 2, 3, 4]);
      expect(stats.heatmap.dailyCounts.last, 8);
      expect(stats.heatmap.dailyBuckets.last, 4);
    });
  });
}

Conversation _conversation({
  required String id,
  String title = 'Conversation',
  List<Message> messages = const [],
}) {
  final createdAt = messages.isEmpty
      ? DateTime(2026)
      : messages.first.timestamp;
  final updatedAt = messages.isEmpty ? createdAt : messages.last.timestamp;
  return Conversation(
    id: id,
    title: title,
    messages: messages,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

Message _message(
  String id,
  MessageRole role,
  DateTime timestamp, {
  int? tokens,
  bool isStreaming = false,
}) {
  return Message(
    id: id,
    content: id,
    role: role,
    timestamp: timestamp,
    isStreaming: isStreaming,
    responseMetrics: tokens == null
        ? null
        : MessageResponseMetrics(totalTokens: tokens),
  );
}
