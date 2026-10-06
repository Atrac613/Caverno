import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/project_farm/application/project_task_commit_turn_evidence.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolResultInfo result(
    String name, {
    String command = 'diff --cached',
    Map<String, dynamic> payload = const {},
    ToolOutcome? outcome,
  }) => ToolResultInfo(
    id: 'current-owner-call',
    name: name,
    arguments: {'command': command},
    result: jsonEncode(payload),
    outcome: outcome,
  );
  ProjectTaskCommitTurnEvidence observe(
    List<ToolResultInfo> results, {
    bool normal = true,
  }) => ProjectTaskCommitTurnEvidence.fromResults(
    completedNormally: normal,
    results: results,
  );
  test('normal idle and read-only turns can recover', () {
    expect(observe([]).mayRecover, isTrue);
    expect(
      observe([result('read_file'), result('git_execute_command')]).mayRecover,
      isTrue,
    );
  });
  test('native error messages without a JSON payload still stop recovery', () {
    final observation = observe([
      ToolResultInfo(
        id: 'denied-read',
        name: 'read_file',
        arguments: {},
        result: 'Error: User denied file inspection',
      ),
    ]);
    expect(observation.failed, isTrue);
    expect(observation.mayRecover, isFalse);
  });
  test('abnormal termination cannot recover even without tools', () {
    expect(observe([], normal: false).mayRecover, isFalse);
  });
  for (final payload in [
    {'exit_code': 1},
    {'ok': false},
    {'error': 'Read denied'},
    ToolResultOrigin.refusal.marker,
    ToolResultOrigin.malformed.marker,
  ]) {
    test('read failures and refusals block recovery: $payload', () {
      final observation = observe([result('read_file', payload: payload)]);
      expect(observation.failed, isTrue);
      expect(observation.mayRecover, isFalse);
    });
  }
  test('typed process failure overrides successful text', () {
    expect(
      observe([
        result(
          'git_execute_command',
          payload: {'exit_code': 0},
          outcome: const ToolOutcome(exitCode: 1),
        ),
      ]).failed,
      isTrue,
    );
  });
  for (final name in [
    'write_file',
    'edit_file',
    'local_execute_command',
    'unknown',
  ]) {
    test(
      'every mutation attempt blocks recovery, including failed attempts: $name',
      () {
        for (final payload in [
          <String, dynamic>{},
          {'ok': false},
        ]) {
          final observation = observe([result(name, payload: payload)]);
          expect(observation.mutationAttempted, isTrue);
          expect(observation.mayRecover, isFalse);
        }
      },
    );
  }
  test('denied staging and commit attempts cannot recover', () {
    for (final command in ['add -- task.py', 'commit -m "fix: task"']) {
      final observation = observe([
        result(
          'git_execute_command',
          command: command,
          payload: {'ok': false, ...ToolResultOrigin.refusal.marker},
        ),
      ]);
      expect(observation.mutationAttempted, isTrue);
      expect(observation.failed, isTrue);
      expect(observation.mayRecover, isFalse);
    }
  });
  test(
    'harness inspection notices allow recovery without hiding write attempts',
    () {
      expect(
        observe([
          result(
            'read_file',
            payload: {
              'ok': false,
              'error': 'Inspection claim is unverified.',
              ...ToolResultOrigin.harness.marker,
            },
          ),
        ]).mayRecover,
        isTrue,
      );
      final attempted = observe([
        result(
          'write_file',
          payload: {'ok': false, ...ToolResultOrigin.harness.marker},
        ),
      ]);
      expect(attempted.failed, isFalse);
      expect(attempted.mutationAttempted, isTrue);
      expect(attempted.mayRecover, isFalse);
      expect(
        observe([
          result(
            'read_file',
            payload: ToolResultOrigin.harness.marker,
            outcome: const ToolOutcome(exitCode: 1),
          ),
        ]).mayRecover,
        isFalse,
      );
    },
  );
}
