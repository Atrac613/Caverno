import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/anabasis_parent_authority_guard.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _guard = AnabasisParentAuthorityGuard();

ToolCallInfo _call(String name, [Map<String, dynamic> arguments = const {}]) =>
    ToolCallInfo(id: 'call-$name', name: name, arguments: arguments);

/// One tool per effect the parent must be kept away from, so the test names
/// the policy rather than a list of tool names.
final _byEffect = <ToolCommandEffect, ToolCallInfo>{
  ToolCommandEffect.inspection: _call('read_file', {'path': 'lib/main.dart'}),
  ToolCommandEffect.verification: _call('local_execute_command', {
    'command': 'dart test',
  }),
  ToolCommandEffect.workspaceMutation: _call('write_file', {
    'path': 'lib/main.dart',
    'content': '// ...',
  }),
  ToolCommandEffect.build: _call('local_execute_command', {
    'command': 'flutter build apk',
  }),
  ToolCommandEffect.unknown: _call('some_unclassified_tool'),
};

void main() {
  setUpAll(() {
    // The fixture is only honest if each tool really carries the effect the
    // policy is being asserted against.
    const classifier = ToolCapabilityClassifier();
    for (final entry in _byEffect.entries) {
      expect(
        classifier
            .classify(entry.value.name, arguments: entry.value.arguments)
            .commandEffect,
        entry.key,
        reason: '${entry.value.name} must classify as ${entry.key.name}',
      );
    }
  });

  group('only the parent is restricted', () {
    test('every other role passes untouched', () {
      for (final role in ModelUsageRole.values) {
        if (role == ModelUsageRole.anabasisParent) continue;
        expect(
          _guard.evaluate(
            _byEffect[ToolCommandEffect.workspaceMutation]!,
            executingRole: role,
          ),
          isNull,
          reason:
              '${role.name}: this guard is the parent boundary, not a second '
              'mutation policy for the whole app.',
        );
      }
    });
  });

  group('the parent may inspect, verify and delegate', () {
    test('inspection and verification are allowed', () {
      for (final effect in [
        ToolCommandEffect.inspection,
        ToolCommandEffect.verification,
      ]) {
        expect(
          _guard.evaluate(
            _byEffect[effect]!,
            executingRole: ModelUsageRole.anabasisParent,
          ),
          isNull,
          reason: effect.name,
        );
      }
    });

    test('delegation is allowed, and is the only route to effect', () {
      expect(
        _guard.evaluate(
          _call('spawn_subagent', {'prompt': 'Implement the store'}),
          executingRole: ModelUsageRole.anabasisParent,
        ),
        isNull,
        reason:
            'The child inherits mutation rights and escalates to the user at '
            'dispatch, so delegation is not equivalent to mutating.',
      );
    });

    // A live run had accept_task refused here in 0 ms, before the handler's own
    // grounds could be reached, and with advice -- "delegate this to a child"
    // -- that no child can act on: accept_task refuses a non-parent. The tool
    // had no caller at all. update_goal and ask_user_question were refused the
    // same way, and the parent's prompt tells it to do all three.
    test('the parent may record, own the goal, and ask the user', () {
      for (final call in [
        _call('accept_task', {
          'workflow_task_id': 'task-1',
          'rationale': 'The child ran the saved validation command green.',
        }),
        _call('update_goal', {'status': 'in_progress'}),
        _call('ask_user_question', {'question': 'Which id format?'}),
      ]) {
        expect(
          _guard.evaluate(call, executingRole: ModelUsageRole.anabasisParent),
          isNull,
          reason:
              '${call.name}: the parent cannot delegate its own bookkeeping, '
              'and this guard refusing it leaves the instruction impossible.',
        );
      }
    });

    // The keep-it-closed default is the right answer for a tool with no claim
    // in the parent's instructions, so the exemption stays a named list.
    test('an unrelated unclassified tool is still refused', () {
      expect(
        _guard.evaluate(
          _call('create_routine', {'prompt': 'nightly release'}),
          executingRole: ModelUsageRole.anabasisParent,
        ),
        isNotNull,
      );
    });
  });

  group('the parent may not change the workspace', () {
    test('a mutation is refused as a result, not a throw', () {
      final refusal = _guard.evaluate(
        _byEffect[ToolCommandEffect.workspaceMutation]!,
        executingRole: ModelUsageRole.anabasisParent,
      );

      expect(refusal, isNotNull);
      expect(refusal!.isSuccess, isFalse);
      final payload = jsonDecode(refusal.result) as Map<String, dynamic>;
      expect(payload['code'], AnabasisParentAuthorityGuard.refusedCode);
      expect(payload['effect'], ToolCommandEffect.workspaceMutation.name);
      expect(
        payload['required_action'],
        contains('spawn_subagent'),
        reason:
            'A refusal that does not name the way forward reads as a dead end, '
            'and the parent has exactly one.',
      );
    });

    test('a build is refused too — the list is effects, not tool names', () {
      expect(
        _guard.evaluate(
          _byEffect[ToolCommandEffect.build]!,
          executingRole: ModelUsageRole.anabasisParent,
        ),
        isNotNull,
      );
    });

    test('an unclassified tool is refused, unlike in the assumption guard', () {
      expect(
        _guard.evaluate(
          _byEffect[ToolCommandEffect.unknown]!,
          executingRole: ModelUsageRole.anabasisParent,
        ),
        isNotNull,
        reason:
            'MaterialContractAssumptionGuard treats unknown as "not a '
            'mutation" because a false positive there blocks ordinary work. '
            'Here an unclassified tool is not proof of safety, and the '
            'boundary is easier to keep closed than to retrofit.',
      );
    });
  });
}
