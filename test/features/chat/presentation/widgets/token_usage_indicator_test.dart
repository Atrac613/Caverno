import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/token_usage_indicator.dart';

void main() {
  String formatTokenCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }

  testWidgets('shows compact model label and circular prompt usage progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenUsageIndicator(
            chatState: const ChatState(
              messages: [],
              isLoading: false,
              promptTokens: 1200,
              completionTokens: 300,
              totalTokens: 1500,
              estimatedPromptTokens: 3000,
            ),
            model: 'anthropic/claude-opus-4.7',
            contextWindowTokens: 6000,
            formatTokenCount: formatTokenCount,
          ),
        ),
      ),
    );

    expect(find.text('Claude Opus 4.7'), findsOneWidget);
    expect(find.text('1.2k / 6.0k (20%)'), findsNothing);
    expect(find.text(' / Max'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.value, 0.2);
  });

  testWidgets('opens context window popover from the ring', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TokenUsageIndicator(
              chatState: const ChatState(
                messages: [],
                isLoading: false,
                promptTokens: 1200,
                completionTokens: 300,
                totalTokens: 1500,
                estimatedPromptTokens: 3000,
              ),
              model: 'anthropic/claude-opus-4.7',
              contextWindowTokens: 6000,
              formatTokenCount: formatTokenCount,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();

    expect(find.text('Context window'), findsOneWidget);
    expect(find.text('1.2k / 6.0k (20%)'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    final gauge = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(gauge.value, 0.2);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Completion'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
  });

  testWidgets(
    'falls back to estimated prompt tokens when server usage is absent',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TokenUsageIndicator(
              chatState: const ChatState(
                messages: [],
                isLoading: false,
                totalTokens: 0,
                estimatedPromptTokens: 3000,
              ),
              model: 'anthropic/claude-opus-4.7',
              contextWindowTokens: 6000,
              formatTokenCount: formatTokenCount,
            ),
          ),
        ),
      );

      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.value, 0.5);

      await tester.tap(find.byType(CircularProgressIndicator));
      await tester.pumpAndSettle();

      expect(find.text('3.0k / 6.0k (50%)'), findsOneWidget);
    },
  );

  testWidgets('estimates image-only messages when usage has not arrived', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenUsageIndicator(
            chatState: ChatState(
              messages: [
                Message(
                  id: 'image-message',
                  content: '',
                  role: MessageRole.user,
                  timestamp: DateTime(2026, 6, 5),
                  imageBase64: 'A' * 4096,
                  imageMimeType: 'image/png',
                ),
              ],
              isLoading: true,
            ),
            model: 'qwen/qwen3-vl',
            contextWindowTokens: 65536,
            formatTokenCount: formatTokenCount,
          ),
        ),
      ),
    );

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.value, greaterThan(0));

    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();

    expect(find.textContaining('0 / 65.5k'), findsNothing);
  });

  testWidgets('shows unknown state when context metadata is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenUsageIndicator(
            chatState: const ChatState(
              messages: [],
              isLoading: false,
              totalTokens: 1200,
              estimatedPromptTokens: 5200,
              contextTokenPressureLevel: ContextTokenPressureLevel.warning,
              promptCompactionActive: true,
            ),
            model: 'mlx-community/gemma-4-26B-A4B-it-Q4_K_M.gguf',
            contextWindowTokens: null,
            formatTokenCount: formatTokenCount,
          ),
        ),
      ),
    );

    expect(find.text('Gemma 4 26B'), findsOneWidget);
    expect(find.text('5.2k / 6.0k (87%)'), findsNothing);

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.value, 0);

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('Prompt compaction active'));

    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();

    expect(find.text('Context window'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(
      find.text('Context metadata unavailable from /models.'),
      findsOneWidget,
    );
  });
}
