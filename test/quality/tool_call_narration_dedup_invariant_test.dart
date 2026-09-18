import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_call_execution_policy.dart';
import 'package:caverno/features/chat/presentation/providers/tool_approval_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// Holds `toolExecutionKey` and `ToolApprovalCache` to the same policy on
/// model narration, across the real catalog rather than a hand-kept list.
///
/// They share `nonSemanticArgumentKeys` but once applied it differently:
/// the approval cache stripped `reason` for every tool while the execution key
/// stripped it only for file mutations. A reworded `browser_submit` was then a
/// cache hit for approval and a fresh key for execution -- approved once,
/// submitted twice, with no second prompt. A comment asserted the two could not
/// disagree; nothing checked it, and a browser tool added later was exposed the
/// day it landed.
///
/// Scanning the assembled catalog is the point: a new consequential tool must
/// fail this test rather than wait for someone to remember the allow-list.
///
/// Command execution is deliberately outside the invariant: its read-only
/// classifier does not recognise `git status`, `git tag --list` or
/// `gh pr checks`, so narration is still what lets those inspections re-run. A
/// reworded mutating command can therefore still re-execute; the fix is a
/// trustworthy read-only classifier, tracked separately.
void main() {
  const policy = ToolCallExecutionPolicy();
  final owner = ChatTurnOwner(
    conversationId: 'invariant',
    interactionGeneration: 1,
  );

  List<String> toolNamesDeclaringReason() {
    final names = <String>[];
    for (final definition in McpToolService().getOpenAiToolDefinitions()) {
      final function = definition['function'];
      if (function is! Map) continue;
      final name = function['name'];
      final parameters = function['parameters'];
      if (name is! String || parameters is! Map) continue;
      final properties = parameters['properties'];
      if (properties is Map && properties.containsKey('reason')) {
        names.add(name);
      }
    }
    return names;
  }

  ToolCallInfo callWith(String name, String reason) => ToolCallInfo(
    id: 'call',
    name: name,
    arguments: {'path': 'a', 'command': 'ls', 'reason': reason},
  );

  test('the catalog actually exposes narration-carrying tools', () {
    // Guards the scan itself: an empty list would make every assertion below
    // vacuously true.
    expect(toolNamesDeclaringReason(), isNotEmpty);
  });

  test('rewording reason cannot re-run a consequential tool', () {
    final offenders = <String>[];
    for (final name in toolNamesDeclaringReason()) {
      final first = callWith(name, 'because the user asked');
      final second = callWith(name, 'trying once more to be sure');
      if (policy.shouldAllowRepeatedToolExecution(first) ||
          policy.isRepeatableCommandTool(first)) {
        continue;
      }
      if (policy.toolExecutionKey(first) != policy.toolExecutionKey(second)) {
        offenders.add(name);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These tools re-execute under a reworded reason while the approval '
          'cache still reports them approved: ${offenders.join(', ')}',
    );
  });

  test('the approval cache agrees on every one of them', () {
    for (final name in toolNamesDeclaringReason()) {
      final first = callWith(name, 'because the user asked');
      final second = callWith(name, 'trying once more to be sure');
      final cache = ToolApprovalCache();
      cache.rememberApproval(owner, name, first.arguments);

      final reusesApproval =
          cache.lookup(owner, name, second.arguments) != null;
      final reusesExecution =
          policy.toolExecutionKey(first) == policy.toolExecutionKey(second);

      // A tool may be allowed to repeat, but it must never be the case that
      // the approval is reused while the execution is treated as new.
      expect(
        reusesApproval && !reusesExecution,
        policy.shouldAllowRepeatedToolExecution(first) ||
            policy.isRepeatableCommandTool(first),
        reason:
            '$name: approval reuse and execution reuse disagree in the unsafe '
            'direction',
      );
    }
  });

  test('a read-only inspection may still re-run after re-narration', () {
    final first = ToolCallInfo(
      id: 'r1',
      name: 'read_file',
      arguments: {'path': 'a.txt', 'reason': 'first look'},
    );
    final second = ToolCallInfo(
      id: 'r2',
      name: 'read_file',
      arguments: {'path': 'a.txt', 'reason': 'checking again after the edit'},
    );

    expect(policy.shouldAllowRepeatedToolExecution(first), isTrue);
    expect(
      policy.toolExecutionKey(first),
      isNot(policy.toolExecutionKey(second)),
    );
  });

  test('a side-effecting browser call collides on a reworded repeat', () {
    ToolCallInfo submit(String reason) => ToolCallInfo(
      id: 'call',
      name: 'browser_submit',
      arguments: {'selector': '#checkout', 'reason': reason},
    );

    expect(
      policy.toolExecutionKey(submit('placing the order')),
      policy.toolExecutionKey(submit('confirming the order once more')),
    );
  });
}
