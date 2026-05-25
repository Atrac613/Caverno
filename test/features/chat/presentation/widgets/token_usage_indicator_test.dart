import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/token_usage_indicator.dart';

void main() {
  String formatTokenCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }

  testWidgets('shows compact model label and circular token progress', (
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
            formatTokenCount: formatTokenCount,
          ),
        ),
      ),
    );

    expect(find.text('Claude Opus 4.7'), findsOneWidget);
    expect(find.text('3.0k/6.0k'), findsOneWidget);
    expect(find.text(' / Max'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.value, 0.5);
  });

  testWidgets('uses pressure color and compaction detail for warnings', (
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
            formatTokenCount: formatTokenCount,
          ),
        ),
      ),
    );

    expect(find.text('Gemma 4 26B'), findsOneWidget);
    expect(find.text('5.2k/6.0k'), findsOneWidget);

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.value, closeTo(0.866, 0.001));

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('Prompt compaction active'));
  });
}
