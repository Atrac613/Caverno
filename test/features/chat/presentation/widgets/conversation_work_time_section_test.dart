import 'package:caverno/features/chat/domain/entities/conversation_work_time.dart';
import 'package:caverno/features/chat/presentation/providers/conversation_work_time_providers.dart';
import 'package:caverno/features/chat/presentation/widgets/conversation_work_time_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    ConversationWorkTimeSummary summary,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationWorkTimeSummaryProvider(
            'c1',
          ).overrideWith((ref) => Stream.value(summary)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ConversationWorkTimeSection(conversationId: 'c1'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('formatWorkDuration picks a unit a glance can read', () {
    expect(formatWorkDuration(0), '0s');
    expect(formatWorkDuration(850), '850ms');
    expect(formatWorkDuration(45000), '45s');
    expect(formatWorkDuration(141000), '2m 21s');
    expect(formatWorkDuration(3780000), '1h 03m');
  });

  testWidgets('shows each kind with its total and top details', (tester) async {
    await pump(
      tester,
      ConversationWorkTimeSummary(const [
        ConversationWorkTimeEntry(
          kind: ConversationWorkKind.llmInference,
          detail: 'chat',
          count: 4,
          durationMs: 90000,
        ),
        ConversationWorkTimeEntry(
          kind: ConversationWorkKind.llmInference,
          detail: 'memoryExtraction',
          count: 1,
          durationMs: 30000,
        ),
        ConversationWorkTimeEntry(
          kind: ConversationWorkKind.toolExecution,
          detail: 'run_tests',
          count: 2,
          durationMs: 12000,
        ),
      ]),
    );

    expect(find.byKey(const ValueKey('work-time-llmInference')), findsOne);
    expect(find.text('2m 0s'), findsOne, reason: 'LLM total');
    expect(find.text('×5'), findsOne);
    expect(find.text('chat 1m 30s · memoryExtraction 30s'), findsOne);
    expect(find.byKey(const ValueKey('work-time-toolExecution')), findsOne);
    expect(
      find.byKey(const ValueKey('work-time-backgroundProcess')),
      findsNothing,
      reason: 'kinds with no work stay hidden',
    );
  });

  testWidgets('says so when nothing has been recorded', (tester) async {
    await pump(tester, ConversationWorkTimeSummary.empty);

    expect(find.text('chat.work_time_empty'), findsOne);
  });
}
