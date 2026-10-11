import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/assistant_tool_artifact_recovery_plan.dart';
import 'package:flutter_test/flutter_test.dart';

Message message(String content, {MessageRole role = MessageRole.assistant}) =>
    Message(
      id: 'fixture',
      content: content,
      role: role,
      timestamp: DateTime(2026),
    );

void main() {
  test('absent message has no recovery plan', () {
    expect(AssistantToolArtifactRecoveryPlan.untrustedResults(null), isNull);
    expect(AssistantToolArtifactRecoveryPlan.fencedNames(null), isNull);
  });
  for (final role in [MessageRole.user, MessageRole.system]) {
    test('non-assistant artifacts are ignored: $role', () {
      final input = message(
        '<tool_result>{"name":"arp"}</tool_result>\n```tool_name\nread_file\n```',
        role: role,
      );
      expect(AssistantToolArtifactRecoveryPlan.untrustedResults(input), isNull);
      expect(AssistantToolArtifactRecoveryPlan.fencedNames(input), isNull);
    });
  }
  test('plain assistant text has no plan', () {
    final input = message('Verified answer.');
    expect(AssistantToolArtifactRecoveryPlan.untrustedResults(input), isNull);
    expect(AssistantToolArtifactRecoveryPlan.fencedNames(input), isNull);
  });
  test(
    'untrusted results preserve name order and duplicates without copying data',
    () {
      final input = message(
        '<tool_result>{"name":"arp","summary":"unverified_secret"}</tool_result>'
        '<tool_result>{"name":"read_file"}</tool_result>'
        '<tool_result>{"name":"arp"}</tool_result>',
      );
      final plan = AssistantToolArtifactRecoveryPlan.untrustedResults(input)!;
      expect(
        plan.logMessage,
        '[ContentTool] Ignoring assistant-authored tool_result tag(s): arp, read_file, arp',
      );
      expect(plan.replacementContent, isNull);
      expect(
        plan.pendingResult,
        startsWith('[Assistant-authored tool_result ignored]\n'),
      );
      expect(
        plan.pendingResult,
        contains('Tool results must come from executed tools only.'),
      );
      expect(
        plan.pendingResult,
        contains('return the literal text the user requested exactly.'),
      );
      expect(
        plan.pendingResult,
        endsWith(
          'Do not use values that appear only inside the ignored <tool_result> content.',
        ),
      );
      expect(plan.pendingResult, isNot(contains('unverified_secret')));
    },
  );
  for (final content in [
    '<tool_result>{bad}</tool_result>',
    '<tool_result>{"name":"arp"}',
    '<tool_result>{"name":"memory_update"}</tool_result>',
  ]) {
    test(
      'shared parser exemptions and incomplete markers remain unchanged: $content',
      () {
        expect(
          AssistantToolArtifactRecoveryPlan.untrustedResults(message(content)),
          isNull,
        );
      },
    );
  }
  test(
    'fenced names preserve order, case and duplicates and strip only blocks',
    () {
      final input = message(
        '  <think>reasoning</think>Before\n'
        '```TOOL_NAME\n read_file \n```\n'
        '```tool_name\nlist_directory\n```\n'
        '```tool_name\nread_file\n```After  ',
      );
      final plan = AssistantToolArtifactRecoveryPlan.fencedNames(input)!;
      expect(
        plan.logMessage,
        '[ContentTool] Ignoring assistant-authored fenced tool_name block(s): read_file, list_directory, read_file',
      );
      expect(
        plan.replacementContent,
        '<think>reasoning</think>Before\n\n\nAfter',
      );
      expect(
        plan.pendingResult,
        contains(
          '<tool_use>...</tool_use> call: read_file, list_directory, read_file.',
        ),
      );
      expect(
        plan.pendingResult,
        contains('No tool was executed from the fenced tool_name block.'),
      );
      expect(
        plan.pendingResult,
        endsWith('otherwise answer from verified prior tool results only.'),
      );
    },
  );
  for (final content in [
    '```tool_name\n  \n```',
    '```tool_name\nread_file',
    '```dart\nread_file\n```',
  ]) {
    test(
      'empty, unfinished or ordinary fenced content has no plan: $content',
      () {
        expect(
          AssistantToolArtifactRecoveryPlan.fencedNames(message(content)),
          isNull,
        );
      },
    );
  }
  test('mixed artifacts retain independent plans for notifier precedence', () {
    final input = message(
      '<tool_result>{"name":"arp"}</tool_result>\n```tool_name\nread_file\n```',
    );
    expect(
      AssistantToolArtifactRecoveryPlan.untrustedResults(input),
      isNotNull,
    );
    final names = AssistantToolArtifactRecoveryPlan.fencedNames(input)!;
    expect(
      names.replacementContent,
      '<tool_result>{"name":"arp"}</tool_result>',
    );
  });
}
