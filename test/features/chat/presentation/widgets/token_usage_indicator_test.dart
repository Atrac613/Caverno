import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/context_surgery_observation_service.dart';
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
    // The segmented breakdown bar replaces the single linear gauge.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // With no observed sections the whole used portion falls to Messages and
    // the remainder of the window to Free space.
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Free space'), findsOneWidget);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Completion'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
  });

  testWidgets('partitions the prompt into non-overlapping breakdown rows', (
    tester,
  ) async {
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
                contextSurgerySnapshot: ContextSurgeryObservationSnapshot(
                  sections: [
                    ContextSurgerySectionSummary(
                      kind: ContextSurgeryBlockKind.systemPrompt,
                      label: 'System prompt',
                      blockCount: 1,
                      charCount: 400,
                    ),
                    ContextSurgerySectionSummary(
                      kind: ContextSurgeryBlockKind.repoMap,
                      label: 'Repo map',
                      blockCount: 1,
                      charCount: 160,
                    ),
                    ContextSurgerySectionSummary(
                      kind: ContextSurgeryBlockKind.fileReadToolResult,
                      label: 'File reads',
                      blockCount: 2,
                      charCount: 240,
                    ),
                  ],
                  staleToolResultCandidateCount: 1,
                  staleToolResultEstimatedTokens: 30,
                ),
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

    // The whole system prompt (charCount 400 -> 100 tokens) embeds the repo
    // map (160 -> 40 tokens), so the base instructions slice is 100 - 40 = 60.
    expect(find.text('System prompt'), findsOneWidget);
    expect(find.text('Project context'), findsOneWidget);
    expect(find.text('Tool results'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Free space'), findsOneWidget);
    // The embedded sub-blocks are no longer listed as their own top-level rows.
    expect(find.text('Context sections'), findsNothing);
    expect(find.text('Repo map'), findsNothing);

    // System prompt base (60) and tool results (60) each render their tokens.
    expect(find.text('60'), findsNWidgets(2));
    // Project context = repo map (40).
    expect(find.text('40'), findsOneWidget);
    // Messages = used (promptTokens 1200) - attributed (160) = 1040.
    expect(find.text('1.0k'), findsOneWidget);
    // Free space = window (6000) - used (1200) = 4800.
    expect(find.text('4.8k'), findsOneWidget);

    // Reclaimable stale tool results are surfaced with their token estimate.
    expect(
      find.text('Stale tool candidates (1) · 30 reclaimable'),
      findsOneWidget,
    );
  });

  testWidgets('surfaces system and mcp tool schema rows in the popover', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TokenUsageIndicator(
              chatState: const ChatState(
                messages: [],
                isLoading: false,
                promptTokens: 2000,
                completionTokens: 300,
                totalTokens: 2300,
                contextSurgerySnapshot: ContextSurgeryObservationSnapshot(
                  sections: [
                    ContextSurgerySectionSummary(
                      kind: ContextSurgeryBlockKind.systemToolSchema,
                      label: 'System tools',
                      blockCount: 40,
                      charCount: 2400,
                    ),
                    ContextSurgerySectionSummary(
                      kind: ContextSurgeryBlockKind.mcpToolSchema,
                      label: 'MCP tools',
                      blockCount: 4,
                      charCount: 800,
                    ),
                  ],
                ),
              ),
              model: 'anthropic/claude-opus-4.7',
              contextWindowTokens: 8000,
              formatTokenCount: formatTokenCount,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();

    // Tool-definition payload is now a first-class breakdown category.
    expect(find.text('System tools'), findsOneWidget);
    expect(find.text('MCP tools'), findsOneWidget);
    // System tools = 2400 chars -> 600 tokens; MCP tools = 800 -> 200 tokens.
    expect(find.text('600'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    // Messages = used (promptTokens 2000) - attributed (800) = 1200, so the
    // tool schemas are no longer hidden inside the Messages residual.
    expect(find.text('1.2k'), findsOneWidget);
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
      find.text(
        'Context window size unavailable from /models; showing usage only.',
      ),
      findsOneWidget,
    );
    // Without a known window the breakdown percentages fall back to the used
    // total, so Messages absorbs the full estimated prompt (5.2k -> 100%).
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Free space'), findsNothing);
  });
}
