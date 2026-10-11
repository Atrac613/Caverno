import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/incomplete_content_tool_recovery_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Message message(String content, {MessageRole role = MessageRole.assistant}) =>
    Message(
      id: 'fixture',
      content: content,
      role: role,
      timestamp: DateTime(2026),
    );
const unfinished =
    '<tool_use>{"name":"read_file","arguments":{"path":"README.md"}}';

void main() {
  for (final input in [
    null,
    message(unfinished, role: MessageRole.user),
    message(unfinished, role: MessageRole.system),
    message('plain text'),
    message('$unfinished</tool_use>'),
  ]) {
    test(
      'ineligible message never invokes acceptance: ${input?.content} ${input?.role}',
      () {
        final plan = IncompleteContentToolRecoveryPlan.assess(
          input,
          acceptCall: (_) => throw StateError('must not accept a candidate'),
        );
        expect(plan, isNull);
      },
    );
  }
  for (final tag in ['tool_use', 'tool_call']) {
    test('recovers parseable unfinished $tag with original arguments', () {
      var calls = 0;
      final plan = IncompleteContentToolRecoveryPlan.assess(
        message('<$tag>{"name":"read_file","arguments":{"path":"README.md"}}'),
        acceptCall: (call) {
          calls++;
          expect(call.name, 'read_file');
          expect(call.arguments, {'path': 'README.md'});
          return true;
        },
      )!;
      expect(calls, 1);
      expect(plan.recoveredToolCalls.single.isComplete, true);
      expect(plan.recoveredToolCalls.single.occurrenceId, isNotNull);
      expect(
        plan.logMessage,
        '[ContentTool] Recovering incomplete tool_call(s): 1',
      );
      expect(plan.pendingResult, isNull);
    });
  }
  test('all rejected candidates use the original continuation fallback', () {
    var calls = 0;
    final plan = IncompleteContentToolRecoveryPlan.assess(
      message(unfinished),
      acceptCall: (_) {
        calls++;
        return false;
      },
    )!;
    expect(calls, 1);
    expect(plan.recoveredToolCalls, isEmpty);
    expect(
      plan.logMessage,
      '[ContentTool] Incomplete tool call could not be parsed; requesting continuation recovery',
    );
    expect(
      plan.pendingResult,
      '[Incomplete assistant tool call]\n'
      'The assistant emitted an unfinished tool call tag. Reissue the needed '
      'tool call as one complete <tool_use>...</tool_use> tag, or finish with '
      'a concise text answer if no more tools are needed. Do not write '
      '<tool_result> tags yourself.',
    );
  });
  for (final content in [
    '<think>$unfinished</think>Visible answer',
    '<tool_use>...',
    '<tool_use>{"name":"memory_update","arguments":{}}',
  ]) {
    test('unparseable or exempt candidate requests continuation: $content', () {
      final plan = IncompleteContentToolRecoveryPlan.assess(
        message(content),
        acceptCall: (_) => throw StateError('no candidate to accept'),
      )!;
      expect(plan.recoveredToolCalls, isEmpty);
      expect(plan.pendingResult, isNotNull);
    });
  }
  test('acceptance exceptions retain their propagation', () {
    final failure = StateError('acceptance failure');
    expect(
      () => IncompleteContentToolRecoveryPlan.assess(
        message(unfinished),
        acceptCall: (_) => throw failure,
      ),
      throwsA(same(failure)),
    );
  });
}
