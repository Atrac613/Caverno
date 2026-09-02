import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/command_diagnostic_verifier_replay_guard.dart';
import 'package:caverno/features/chat/domain/services/stalled_diagnostic_repair_contract.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _guard = CommandDiagnosticVerifierReplayGuard();
const _focus = CommandDiagnosticRepairFocus(
  commandKey: 'verify-key',
  streak: 3,
  diagnosticSummary: 'lib/main.dart: [compile_error] Build failed.',
  hasPathBackedDiagnostic: true,
);

ToolCallInfo _call(
  String id,
  String name, {
  Map<String, dynamic> arguments = const {},
}) {
  return ToolCallInfo(id: id, name: name, arguments: arguments);
}

CommandDiagnosticVerifierReplayInput _input({
  CommandDiagnosticRepairFocus? focus = _focus,
  String attemptedCommandKey = 'verify-key',
  ToolCommandEffect commandEffect = ToolCommandEffect.verification,
  List<ToolCallInfo>? pendingToolCalls,
  ToolCallInfo? currentToolCall,
}) {
  final current =
      currentToolCall ??
      _call(
        'verify',
        'local_execute_command',
        arguments: const {'command': 'flutter test'},
      );
  return CommandDiagnosticVerifierReplayInput(
    currentToolCall: current,
    focus: focus,
    attemptedCommandKey: attemptedCommandKey,
    commandEffect: commandEffect,
    pendingToolCalls: pendingToolCalls ?? [current],
  );
}

Map<String, dynamic> _payload(McpToolResult result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}

void main() {
  test('returns allowed without an active diagnostic focus', () {
    final decision = _guard.evaluate(_input(focus: null));

    expect(decision.isBlocked, isFalse);
    expect(decision.result, isNull);
    expect(decision.logFields, isNull);
  });

  test('allows a pathless diagnostic focus', () {
    const pathlessFocus = CommandDiagnosticRepairFocus(
      commandKey: 'verify-key',
      streak: 2,
      diagnosticSummary: '[dependency_error] Resolve the dependency.',
      hasPathBackedDiagnostic: false,
    );

    expect(_guard.evaluate(_input(focus: pathlessFocus)).isBlocked, isFalse);
  });

  test('allows a non-verification current command effect', () {
    for (final effect in ToolCommandEffect.values) {
      final decision = _guard.evaluate(_input(commandEffect: effect));
      expect(
        decision.isBlocked,
        effect == ToolCommandEffect.verification,
        reason: effect.name,
      );
    }
  });

  test('allows a changed command identity', () {
    expect(
      _guard.evaluate(_input(attemptedCommandKey: 'different-key')).isBlocked,
      isFalse,
    );
  });

  test('allows a verifier when a mutation precedes the current call', () {
    final current = _call(
      'verify',
      'local_execute_command',
      arguments: const {'command': 'flutter test'},
    );
    final decision = _guard.evaluate(
      _input(
        currentToolCall: current,
        pendingToolCalls: [
          _call(
            'mutation',
            'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': 'void main() {}',
            },
          ),
          current,
        ],
      ),
    );

    expect(decision.isBlocked, isFalse);
  });

  test('blocks when only non-mutations precede the current call', () {
    final current = _call(
      'verify',
      'local_execute_command',
      arguments: const {'command': 'flutter test'},
    );
    final precedingCalls = [
      _call(
        'inspection',
        'local_execute_command',
        arguments: const {'command': 'ls'},
      ),
      _call(
        'previous-verifier',
        'local_execute_command',
        arguments: const {'command': 'flutter test'},
      ),
      _call('unknown', 'unknown_tool'),
    ];

    for (final precedingCall in precedingCalls) {
      final decision = _guard.evaluate(
        _input(
          currentToolCall: current,
          pendingToolCalls: [precedingCall, current],
        ),
      );

      expect(decision.isBlocked, isTrue, reason: precedingCall.id);
    }
  });

  test('blocks when the only mutation follows the current call', () {
    final current = _call(
      'verify',
      'local_execute_command',
      arguments: const {'command': 'flutter test'},
    );
    final decision = _guard.evaluate(
      _input(
        currentToolCall: current,
        pendingToolCalls: [
          current,
          _call(
            'later-mutation',
            'edit_file',
            arguments: const {
              'path': 'lib/main.dart',
              'old_text': 'old',
              'new_text': 'new',
            },
          ),
        ],
      ),
    );

    expect(decision.isBlocked, isTrue);
  });

  test('blocks when the current call is absent from pending calls', () {
    final decision = _guard.evaluate(
      _input(
        pendingToolCalls: [
          _call(
            'inspection',
            'local_execute_command',
            arguments: const {'command': 'ls'},
          ),
        ],
      ),
    );

    expect(decision.isBlocked, isTrue);
  });

  test('returns the exact payload, success flag, and structured log fields', () {
    final decision = _guard.evaluate(_input());
    final result = decision.result!;

    expect(decision.isBlocked, isTrue);
    expect(result.toolName, 'local_execute_command');
    expect(result.isSuccess, isTrue);
    expect(result.errorMessage, isNull);
    expect(_payload(result), {
      'ok': false,
      'code': CommandDiagnosticVerifierReplayGuard.blockedCode,
      'result_origin': 'harness',
      'error':
          'The same verifier was not rerun because its path-backed diagnostic '
          'has not been addressed by a mutation.',
      'diagnostic': 'lib/main.dart: [compile_error] Build failed.',
      'required_action':
          'Make one concrete mutation that directly addresses the sourced '
          'diagnostic, then rerun this verifier.',
    });
    expect(decision.logFields!.signatureStreak, 3);
    expect(decision.logFields!.commandKey, 'verify-key');
    expect(decision.logFields!.toolCallId, 'verify');
  });

  test('recursively freezes current and pending tool-call snapshots', () {
    final rawTags = <String>['stable'];
    final rawMetadata = <String, dynamic>{'primary': rawTags};
    final nested = <String, dynamic>{
      'paths': <Object?>[
        'lib/main.dart',
        <String, dynamic>{
          'commands': <Object?>['flutter test'],
        },
      ],
      'raw_metadata': rawMetadata,
    };
    final arguments = <String, dynamic>{'metadata': nested};
    final current = _call(
      'verify',
      'local_execute_command',
      arguments: arguments,
    );
    final pending = <ToolCallInfo>[current];
    final input = _input(currentToolCall: current, pendingToolCalls: pending);

    arguments['metadata'] = 'mutated';
    nested['paths'] = <Object?>['mutated'];
    rawMetadata['secondary'] = 'mutated';
    rawTags.add('mutated');
    pending.add(_call('visible-mutation', 'write_file'));

    final frozenMetadata =
        input.currentToolCall.arguments['metadata'] as Map<String, dynamic>;
    final frozenPaths = frozenMetadata['paths'] as List<Object?>;
    final frozenCommands =
        (frozenPaths[1] as Map<String, dynamic>)['commands'] as List<Object?>;
    final frozenRawMetadata =
        frozenMetadata['raw_metadata'] as Map<String, dynamic>;
    final frozenTags = frozenRawMetadata['primary'] as List<Object?>;
    expect(frozenPaths.first, 'lib/main.dart');
    expect(frozenCommands.single, 'flutter test');
    expect(frozenRawMetadata.keys, ['primary']);
    expect(frozenTags, ['stable']);
    expect(input.pendingToolCalls, hasLength(1));
    expect(() => frozenCommands.add('mutated'), throwsUnsupportedError);
    expect(
      () => frozenRawMetadata['secondary'] = 'mutated',
      throwsUnsupportedError,
    );
    expect(() => frozenTags.add('mutated'), throwsUnsupportedError);
    expect(
      () => input.pendingToolCalls.add(_call('mutated', 'write_file')),
      throwsUnsupportedError,
    );
  });

  test('rejects non-JSON tool-call snapshots', () {
    for (final invalidValue in <Object?>[
      <Object?>{'owner-a'},
      <Object?, Object?>{7: 'owner-a'},
      double.negativeInfinity,
    ]) {
      expect(
        () => _input(
          currentToolCall: _call(
            'verify',
            'local_execute_command',
            arguments: {'invalid': invalidValue},
          ),
        ),
        throwsArgumentError,
        reason: invalidValue.runtimeType.toString(),
      );
    }
  });

  test('uses owner focus and pending calls instead of visible-turn poison', () {
    const visibleFocus = CommandDiagnosticRepairFocus(
      commandKey: 'visible-key',
      streak: 99,
      diagnosticSummary: 'visible.dart: Poison.',
      hasPathBackedDiagnostic: true,
    );
    final visibleCurrent = _call(
      'verify',
      'local_execute_command',
      arguments: const {'command': 'flutter test'},
    );
    final visiblePendingCalls = [
      _call('visible-mutation', 'write_file'),
      visibleCurrent,
    ];
    final visibleInput = _input(
      focus: visibleFocus,
      attemptedCommandKey: 'visible-key',
      currentToolCall: visibleCurrent,
      pendingToolCalls: visiblePendingCalls,
    );
    visiblePendingCalls
      ..clear()
      ..add(_call('owner-poison', 'unknown_tool'));

    final ownerDecision = _guard.evaluate(_input());
    final visibleDecision = _guard.evaluate(visibleInput);

    expect(ownerDecision.isBlocked, isTrue);
    expect(ownerDecision.logFields!.commandKey, isNot(visibleFocus.commandKey));
    expect(
      ownerDecision.logFields!.signatureStreak,
      isNot(visibleFocus.streak),
    );
    expect(ownerDecision.result!.result, isNot(contains('visible.dart')));
    expect(visibleDecision.isBlocked, isFalse);
    expect(visibleDecision.result, isNull);
    expect(visibleDecision.logFields, isNull);
  });

  test('detects only the exact blocked code in valid JSON objects', () {
    final blocked = _guard.evaluate(_input()).result!;
    expect(_guard.matches(blocked), isTrue);

    for (final result in [
      const McpToolResult(
        toolName: 'local_execute_command',
        result: '{"code":"other"}',
        isSuccess: true,
      ),
      const McpToolResult(
        toolName: 'local_execute_command',
        result: '[]',
        isSuccess: true,
      ),
      const McpToolResult(
        toolName: 'local_execute_command',
        result: '{malformed',
        isSuccess: true,
      ),
      const McpToolResult(
        toolName: 'local_execute_command',
        result: '',
        isSuccess: true,
      ),
    ]) {
      expect(_guard.matches(result), isFalse, reason: result.result);
    }
  });
}
