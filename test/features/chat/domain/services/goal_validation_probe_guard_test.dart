import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal_validation_probe_guard.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _guard = GoalValidationProbeGuard();

ToolCallInfo _call(String name, {Map<String, dynamic> arguments = const {}}) {
  return ToolCallInfo(id: 'call-$name', name: name, arguments: arguments);
}

Map<String, dynamic> _payload(McpToolResult result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}

void main() {
  final cases = <ToolCommandEffect, ToolCallInfo>{
    ToolCommandEffect.inspection: _call(
      'local_execute_command',
      arguments: const {'command': 'ls'},
    ),
    ToolCommandEffect.dependencyResolution: _call(
      'local_execute_command',
      arguments: const {'command': 'flutter pub get'},
    ),
    ToolCommandEffect.build: _call(
      'local_execute_command',
      arguments: const {'command': 'flutter build apk'},
    ),
    ToolCommandEffect.verification: _call(
      'local_execute_command',
      arguments: const {'command': 'flutter test'},
    ),
    ToolCommandEffect.formatting: _call(
      'local_execute_command',
      arguments: const {'command': 'dart format .'},
    ),
    ToolCommandEffect.codeGeneration: _call(
      'local_execute_command',
      arguments: const {'command': 'dart run build_runner build'},
    ),
    ToolCommandEffect.workspaceMutation: _call(
      'write_file',
      arguments: const {'path': 'lib/main.dart', 'content': 'void main() {}'},
    ),
    ToolCommandEffect.processLifecycle: _call(
      'process_start',
      arguments: const {'command': 'dart run server.dart'},
    ),
    ToolCommandEffect.deploymentOrRelease: _call(
      'local_execute_command',
      arguments: const {'command': './deploy.sh'},
    ),
    ToolCommandEffect.externalSideEffect: _call(
      'ssh_execute_command',
      arguments: const {'command': 'hostname'},
    ),
    ToolCommandEffect.unknown: _call('unknown_tool'),
  };

  test('returns null for every effect when verifier-only mode is false', () {
    for (final entry in cases.entries) {
      expect(
        _guard.evaluate(entry.value, verifierOnlyContinuation: false),
        isNull,
        reason: entry.key.name,
      );
    }
  });

  test('false mode returns before classifying malformed command arguments', () {
    final malformedCommand = _call(
      'local_execute_command',
      arguments: const {'command': 7},
    );

    expect(
      _guard.evaluate(malformedCommand, verifierOnlyContinuation: false),
      isNull,
    );
  });

  test('allows only the verification effect in verifier-only mode', () {
    for (final entry in cases.entries) {
      final result = _guard.evaluate(
        entry.value,
        verifierOnlyContinuation: true,
      );
      if (entry.key == ToolCommandEffect.verification) {
        expect(result, isNull);
        continue;
      }
      expect(result, isNotNull, reason: entry.key.name);
      expect(result!.toolName, entry.value.name);
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(_payload(result), {
        'ok': false,
        'code': GoalValidationProbeGuard.blockedCode,
        'result_origin': 'harness',
        'error':
            'A validation-only continuation rejected a non-verification tool call.',
        'attempted_effect': entry.key.name,
        'required_action':
            'Run one project verification command now. If it fails, report the concrete failure and end this turn so the next continuation can repair it.',
      });
    }
  });

  test('detects only the exact blocked code in valid JSON objects', () {
    final blocked = _guard.evaluate(
      cases[ToolCommandEffect.inspection]!,
      verifierOnlyContinuation: true,
    )!;
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
