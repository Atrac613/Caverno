import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/verified_pytest_replay_policy.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const root = '/workspace';
  final call = ToolCallInfo(
    id: 'retry',
    name: 'local_execute_command',
    arguments: {
      'command':
          'cd /workspace && python3 -m pytest test.py -v 2>&1 | tail -30',
    },
  );
  ToolResultInfo verification(
    String id,
    String runner, {
    bool failed = false,
    String directory = root,
    String target = 'test.py',
    bool typed = true,
    bool background = false,
    String? stdout,
    ToolProcessState? state,
  }) => ToolResultInfo(
    id: id,
    name: 'local_execute_command',
    arguments: {
      'command': '$runner -m pytest $target -v 2>&1 | tail -40',
      'working_directory': directory,
      if (background) 'background': true,
    },
    result: jsonEncode({
      'command': '$runner -m pytest $target -v 2>&1 | tail -40',
      'working_directory': directory,
      'stdout':
          stdout ??
          (failed
              ? 'python3: No module named pytest'
              : '=== 6 passed in 3.05s ==='),
    }),
    outcome: typed
        ? ToolOutcome(exitCode: failed ? 1 : 0, processState: state)
        : null,
  );
  final failure = verification('failed', 'python3', failed: true);
  final success = verification('passed', '.venv/bin/python');
  ToolResultInfo read(String id, String hash) => ToolResultInfo(
    id: id,
    name: 'read_file',
    arguments: {'path': '$root/test.py'},
    result: '{}',
    outcome: ToolOutcome(
      readOutcome: ToolReadOutcome(
        path: '$root/test.py',
        contentHash: hash,
        byteSize: 1,
        lineCount: 1,
      ),
    ),
  );
  ToolResultInfo mutation() => ToolResultInfo(
    id: 'mutation',
    name: 'write_file',
    arguments: {'path': '$root/test.py'},
    result: '{}',
    outcome: const ToolOutcome(
      fileMutations: [
        ToolFileMutation(path: '/workspace/test.py', changed: true),
      ],
    ),
  );

  test(
    'reuses the captured passing runner instead of the earlier failed runner',
    () {
      final result = VerifiedPytestReplayPolicy.reuse(
        call: call,
        results: [
          read('before', 'hash'),
          failure,
          success,
          read('after', 'hash'),
        ],
        pendingCalls: [call],
        projectRoot: root,
      )!;
      expect(result.outcome?.exitCode, 0);
      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      expect(payload['execution_reused'], isTrue);
      expect(payload['result_origin'], 'harness');
      expect(payload['prior_tool_call_id'], 'passed');
      expect(payload['command'], contains('.venv/bin/python'));
      expect(payload['requested_command'], call.arguments['command']);
    },
  );
  test('allows literal environment discovery and Git inspection', () {
    ToolResultInfo inspection(String name, String command, {int? exitCode}) =>
        ToolResultInfo(
          id: command,
          name: name,
          arguments: {'command': command},
          result: '{}',
          outcome: exitCode == null ? null : ToolOutcome(exitCode: exitCode),
        );
    expect(
      VerifiedPytestReplayPolicy.reuse(
        call: call,
        results: [
          failure,
          inspection(
            'local_execute_command',
            'cd /workspace && ls -a && which python3 && python3 --version '
                '&& ls .venv 2>/dev/null; which pytest',
          ),
          success,
          inspection(
            'local_execute_command',
            'cd /workspace && ls -d .venv venv 2>/dev/null; '
                'which pytest 2>/dev/null; '
                'python3 -m pip show pytest 2>/dev/null | head -3',
            exitCode: 1,
          ),
          inspection('git_execute_command', 'status'),
          inspection('git_execute_command', 'diff HEAD -- test.py'),
          inspection('git_execute_command', 'log --oneline -5'),
        ],
        pendingCalls: [call],
        projectRoot: root,
      ),
      isNotNull,
    );
  });
  test('does not replay a different reporting mode as an exact result', () {
    final quiet = ToolResultInfo(
      id: 'quiet',
      name: success.name,
      arguments: {
        'command': '.venv/bin/python -m pytest test.py -q',
        'working_directory': root,
      },
      result: '{"stdout":"6 passed in 0.1s"}',
      outcome: const ToolOutcome(exitCode: 0),
    );
    expect(
      VerifiedPytestReplayPolicy.reuse(
        call: call,
        results: [failure, quiet],
        pendingCalls: [call],
        projectRoot: root,
      ),
      isNull,
    );
  });
  for (final output in ['=== 6 passed in 3.05s ===', 'done']) {
    test('validates counts when the result uses the project directory', () {
      final candidate = ToolResultInfo(
        id: 'default-directory',
        name: 'local_execute_command',
        arguments: {'command': '.venv/bin/python -m pytest test.py -v'},
        result: jsonEncode({'stdout': output}),
        outcome: const ToolOutcome(exitCode: 0),
      );
      expect(
        VerifiedPytestReplayPolicy.reuse(
          call: call,
          results: [failure, candidate],
          pendingCalls: [call],
          projectRoot: root,
        ),
        output == 'done' ? isNull : isNotNull,
      );
    });
  }
  for (final variant in [
    'no earlier failure',
    'later failure',
    'later mutation',
    'changed read',
    'untyped read',
    'other target',
    'other directory',
    'missing typed exit',
    'unknown counts',
    'failed test counts',
    'running',
    'dependency install',
    'unknown command',
    'pending mutation',
    'background',
    'background candidate',
    'unknown syntax',
    'mutation before success',
    'install before success',
    'Git mutation',
    'Git output write',
    'inspection word in script arguments',
  ]) {
    test('does not reuse verification for $variant', () {
      final candidate = verification(
        'candidate',
        '.venv/bin/python',
        directory: variant == 'other directory' ? '/other' : root,
        target: variant == 'other target' ? 'other.py' : 'test.py',
        typed: variant != 'missing typed exit',
        background: variant == 'background candidate',
        stdout: variant == 'unknown counts'
            ? 'done'
            : variant == 'failed test counts'
            ? '=== 2 failed, 4 passed in 3.05s ==='
            : null,
        state: variant == 'running' ? ToolProcessState.running : null,
      );
      final current = ToolCallInfo(
        id: call.id,
        name: call.name,
        arguments: {
          ...call.arguments,
          if (variant == 'background') 'background': true,
          if (variant == 'unknown syntax')
            'command': 'python3 -m pytest test.py -v && echo done',
        },
      );
      final results = [
        if (variant != 'no earlier failure') failure,
        read('before', 'hash'),
        if (variant == 'mutation before success') mutation(),
        if (variant == 'install before success')
          ToolResultInfo(
            id: 'install',
            name: 'local_execute_command',
            arguments: {'command': 'pip install pytest'},
            result: '{}',
          ),
        candidate,
        if (variant == 'later failure') failure,
        if (variant == 'later mutation') mutation(),
        if (variant == 'changed read') read('after', 'changed'),
        if (variant == 'untyped read')
          ToolResultInfo(
            id: 'unknown',
            name: 'read_file',
            arguments: {},
            result: '{}',
          ),
        if (const ['dependency install', 'unknown command'].contains(variant))
          ToolResultInfo(
            id: 'change',
            name: 'local_execute_command',
            arguments: {
              'command': variant == 'dependency install'
                  ? 'pip install pytest'
                  : 'python3 script.py',
            },
            result: '{}',
          ),
        if (const [
          'Git mutation',
          'Git output write',
          'inspection word in script arguments',
        ].contains(variant))
          ToolResultInfo(
            id: 'unknown-effect',
            name: variant == 'inspection word in script arguments'
                ? 'local_execute_command'
                : 'git_execute_command',
            arguments: {
              'command': switch (variant) {
                'Git mutation' => 'branch -D feature/task',
                'Git output write' => 'diff --output=patch.txt',
                _ => 'python3 script.py cat',
              },
            },
            result: '{}',
          ),
      ];
      expect(
        VerifiedPytestReplayPolicy.reuse(
          call: current,
          results: results,
          pendingCalls: [
            current,
            if (variant == 'pending mutation')
              ToolCallInfo(
                id: 'write',
                name: 'write_file',
                arguments: {'path': '$root/test.py'},
              ),
          ],
          projectRoot: root,
        ),
        isNull,
      );
    });
  }
}
