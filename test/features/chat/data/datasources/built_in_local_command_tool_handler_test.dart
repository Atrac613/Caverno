import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/built_in_local_command_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _CommandCall = ({String command, String workingDirectory});
typedef _ProcessStartCall = ({
  String command,
  String workingDirectory,
  String? label,
});
typedef _ProcessValueCall = ({String jobId, int? value});
typedef _ProcessListCall = ({
  List<String>? jobIds,
  bool includeFinished,
  int? limit,
});

void main() {
  group('BuiltInLocalCommandToolHandler', () {
    test('owns the exact ordered local command family', () {
      final unsupportedTools = _FakeBackgroundProcessTools(supported: false);
      final unsupportedHandler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: unsupportedTools,
      );
      final supportedHandler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: _FakeBackgroundProcessTools(),
      );

      expect(BuiltInLocalCommandToolHandler.toolNames, const [
        'local_execute_command',
        'process_start',
        'process_status',
        'process_tail',
        'process_wait',
        'process_cancel',
        'process_list',
        'run_tests',
      ]);
      expect(
        _definitionName(unsupportedHandler.localExecuteCommandDefinition),
        'local_execute_command',
      );
      expect(unsupportedHandler.processDefinitions.map(_definitionName), const [
        'process_start',
        'process_status',
        'process_tail',
        'process_wait',
        'process_cancel',
        'process_list',
      ]);
      expect(
        _definitionName(unsupportedHandler.runTestsDefinition),
        'run_tests',
      );
      for (final name in BuiltInLocalCommandToolHandler.toolNames) {
        expect(unsupportedHandler.handles(name), isTrue, reason: name);
      }
      expect(unsupportedHandler.handles('run_python_script'), isFalse);
      expect(unsupportedHandler.supportsBackgroundProcesses, isFalse);
      expect(supportedHandler.supportsBackgroundProcesses, isTrue);
    });

    test('rejects an unknown tool name', () async {
      final handler = BuiltInLocalCommandToolHandler();

      expect(
        () => handler.execute(name: 'unknown', arguments: const {}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            'unknown',
          ),
        ),
      );
    });

    test(
      'rejects missing required arguments without invoking dependencies',
      () async {
        final foregroundCalls = <_CommandCall>[];
        final tools = _FakeBackgroundProcessTools();
        final handler = BuiltInLocalCommandToolHandler(
          backgroundProcessTools: tools,
          foregroundCommandRunner:
              ({required command, required workingDirectory}) async {
                foregroundCalls.add((
                  command: command,
                  workingDirectory: workingDirectory,
                ));
                return 'unexpected';
              },
        );
        const cases = [
          (
            'local_execute_command',
            <String, dynamic>{},
            'command and working_directory are required',
          ),
          (
            'local_execute_command',
            <String, dynamic>{'command': 'echo ok'},
            'command and working_directory are required',
          ),
          (
            'process_start',
            <String, dynamic>{'working_directory': '/tmp'},
            'command and working_directory are required',
          ),
          ('process_status', <String, dynamic>{}, 'job_id is required'),
          ('process_tail', <String, dynamic>{}, 'job_id is required'),
          ('process_wait', <String, dynamic>{}, 'job_id is required'),
          ('process_cancel', <String, dynamic>{}, 'job_id is required'),
        ];

        for (final testCase in cases) {
          final result = await handler.execute(
            name: testCase.$1,
            arguments: testCase.$2,
          );
          expect(result.toolName, testCase.$1);
          expect(result.result, isEmpty);
          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, testCase.$3);
        }
        expect(foregroundCalls, isEmpty);
        expect(tools.totalCalls, 0);
      },
    );

    test('normalizes and forwards a foreground command', () async {
      final calls = <_CommandCall>[];
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              calls.add((command: command, workingDirectory: workingDirectory));
              return '{"ok":false,"code":"runner_failure"}';
            },
      );

      final result = await handler.execute(
        name: 'local_execute_command',
        arguments: const {
          'command': '  echo ok<|im_end|>  ',
          'working_directory': ' /tmp/project ',
          'background': 'no',
        },
      );

      expect(calls, const [
        (command: 'echo ok', workingDirectory: '/tmp/project'),
      ]);
      expect(result.result, '{"ok":false,"code":"runner_failure"}');
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('carries the reported exit status without failing the tool', () async {
      // A command that exits non-zero is a command outcome, not a tool
      // failure: the result stays successful and the status rides along as a
      // fact, so downstream consumers stop parsing stdout to find it.
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async =>
                '{"exit_code":2,"stdout":"","stderr":"tests failed"}',
      );

      final result = await handler.execute(
        name: 'local_execute_command',
        arguments: const {
          'command': 'flutter test',
          'working_directory': '/tmp/project',
        },
      );

      expect(result.isSuccess, isTrue);
      expect(result.outcome?.exitCode, 2);
      expect(result.outcome?.hasFailingExitCode, isTrue);
    });

    test('reports no exit status when the command never reached one', () async {
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async =>
                'command runner unavailable',
      );

      final result = await handler.execute(
        name: 'local_execute_command',
        arguments: const {
          'command': 'flutter test',
          'working_directory': '/tmp/project',
        },
      );

      expect(result.outcome, isNull);
    });

    test('coerces every supported truthy background value', () async {
      final foregroundCalls = <_CommandCall>[];
      final tools = _FakeBackgroundProcessTools(startResult: 'started');
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              foregroundCalls.add((
                command: command,
                workingDirectory: workingDirectory,
              ));
              return 'foreground';
            },
      );

      for (final value in <Object>[true, 1, -1, 'true', ' 1 ', 'YES']) {
        final result = await handler.execute(
          name: 'local_execute_command',
          arguments: <String, dynamic>{
            'command': ' sleep 1 ',
            'working_directory': ' /tmp/project ',
            'background': value,
            'label': ' job ',
          },
        );
        expect(result.result, 'started', reason: '$value');
        expect(result.isSuccess, isTrue, reason: '$value');
      }

      expect(foregroundCalls, isEmpty);
      expect(tools.startCalls, hasLength(6));
      expect(tools.startCalls.toSet(), {
        const (
          command: 'sleep 1',
          workingDirectory: '/tmp/project',
          label: 'job',
        ),
      });
    });

    test('treats unsupported background values as foreground', () async {
      final calls = <_CommandCall>[];
      final tools = _FakeBackgroundProcessTools();
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              calls.add((command: command, workingDirectory: workingDirectory));
              return 'foreground';
            },
      );

      for (final value in <Object?>[null, false, 0, 'false', 'no', const []]) {
        final result = await handler.execute(
          name: 'local_execute_command',
          arguments: <String, dynamic>{
            'command': 'echo ok',
            'working_directory': '/tmp',
            'background': value,
          },
        );
        expect(result.result, 'foreground', reason: '$value');
      }

      expect(calls, hasLength(6));
      expect(tools.startCalls, isEmpty);
    });

    test('blocks Git writes before foreground or background runners', () async {
      final foregroundCalls = <_CommandCall>[];
      final tools = _FakeBackgroundProcessTools();
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              foregroundCalls.add((
                command: command,
                workingDirectory: workingDirectory,
              ));
              return 'unexpected';
            },
      );
      final cases = <(String, Map<String, dynamic>)>[
        (
          'local_execute_command',
          const {
            'command': 'git merge feature/work',
            'working_directory': '/tmp',
          },
        ),
        (
          'local_execute_command',
          const {
            'command': 'git worktree remove /tmp/worktree',
            'working_directory': '/tmp',
            'background': true,
          },
        ),
        (
          'process_start',
          const {'command': 'git checkout main', 'working_directory': '/tmp'},
        ),
      ];

      for (final testCase in cases) {
        final result = await handler.execute(
          name: testCase.$1,
          arguments: testCase.$2,
        );
        expect(result.isSuccess, isFalse, reason: testCase.$1);
        expect(
          result.errorMessage,
          'Use git_execute_command for git write commands',
        );
        expect(
          jsonDecode(result.result),
          containsPair('code', 'local_shell_git_write_blocked'),
        );
      }
      expect(foregroundCalls, isEmpty);
      expect(tools.startCalls, isEmpty);
    });

    test('preserves every unavailable dependency envelope', () async {
      final handler = BuiltInLocalCommandToolHandler();
      final expectedToolsUnavailable = {
        'ok': false,
        'code': 'background_process_tools_unavailable',
        'error': 'Background process tools are not available',
      };

      final localBackground = await handler.execute(
        name: 'local_execute_command',
        arguments: const {
          'command': 'sleep 1',
          'working_directory': '/tmp',
          'background': true,
        },
      );
      expect(jsonDecode(localBackground.result), expectedToolsUnavailable);
      expect(localBackground.isSuccess, isFalse);
      expect(
        localBackground.errorMessage,
        'Background process tools are not available',
      );

      final processStart = await handler.execute(
        name: 'process_start',
        arguments: const {'command': 'sleep 1', 'working_directory': '/tmp'},
      );
      expect(processStart.result, isEmpty);
      expect(processStart.isSuccess, isFalse);
      expect(
        processStart.errorMessage,
        'Background process tools are not available',
      );

      for (final name in const [
        'process_status',
        'process_tail',
        'process_wait',
        'process_cancel',
      ]) {
        final result = await handler.execute(
          name: name,
          arguments: const {'job_id': 'missing'},
        );
        expect(
          jsonDecode(result.result),
          expectedToolsUnavailable,
          reason: name,
        );
        expect(result.isSuccess, isFalse, reason: name);
        expect(
          result.errorMessage,
          'Background process tools are not available',
          reason: name,
        );
      }

      final processList = await handler.execute(
        name: 'process_list',
        arguments: const {},
      );
      expect(jsonDecode(processList.result), {
        'ok': false,
        'code': 'background_process_monitor_unavailable',
        'error': 'Background process monitor is not available',
      });
      expect(processList.isSuccess, isFalse);
      expect(
        processList.errorMessage,
        'Background process monitor is not available',
      );
    });

    test('preserves legacy success for provider failure payloads', () async {
      const failure = '{"ok":false,"code":"provider_failure"}';
      final tools = _FakeBackgroundProcessTools(
        startResult: failure,
        statusResult: failure,
        tailResult: failure,
        waitResult: failure,
        cancelResult: failure,
      );
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async => failure,
      );
      final calls = <(String, Map<String, dynamic>)>[
        (
          'local_execute_command',
          const {'command': 'echo foreground', 'working_directory': '/tmp'},
        ),
        (
          'local_execute_command',
          const {
            'command': 'sleep 1',
            'working_directory': '/tmp',
            'background': true,
          },
        ),
        (
          'process_start',
          const {'command': 'sleep 1', 'working_directory': '/tmp'},
        ),
        ('process_status', const {'job_id': 'job'}),
        ('process_tail', const {'job_id': 'job'}),
        ('process_wait', const {'job_id': 'job'}),
        ('process_cancel', const {'job_id': 'job'}),
      ];

      for (final call in calls) {
        final result = await handler.execute(name: call.$1, arguments: call.$2);
        expect(result.result, failure, reason: call.$1);
        expect(result.isSuccess, isTrue, reason: call.$1);
        expect(result.errorMessage, isNull, reason: call.$1);
      }
    });

    test(
      'forwards process operation arguments without reinterpretation',
      () async {
        final tools = _FakeBackgroundProcessTools(
          startResult: 'start',
          statusResult: 'status',
          tailResult: 'tail',
          waitResult: 'wait',
          cancelResult: 'cancel',
        );
        final handler = BuiltInLocalCommandToolHandler(
          backgroundProcessTools: tools,
        );

        await handler.execute(
          name: 'process_start',
          arguments: const {
            'command': ' sleep 1<|end|> ',
            'working_directory': ' /tmp/project ',
            'label': ' build ',
          },
        );
        await handler.execute(
          name: 'process_status',
          arguments: const {'job_id': ' job ', 'tail_chars': 123.9},
        );
        await handler.execute(
          name: 'process_tail',
          arguments: const {'job_id': ' job ', 'max_chars': 456.8},
        );
        await handler.execute(
          name: 'process_wait',
          arguments: const {'job_id': ' job ', 'wait_ms': 789.7},
        );
        await handler.execute(
          name: 'process_cancel',
          arguments: const {'job_id': ' job '},
        );

        expect(tools.startCalls, const [
          (
            command: 'sleep 1',
            workingDirectory: '/tmp/project',
            label: 'build',
          ),
        ]);
        expect(tools.statusCalls, const [(jobId: 'job', value: 123)]);
        expect(tools.tailCalls, const [(jobId: 'job', value: 456)]);
        expect(tools.waitCalls, const [(jobId: 'job', value: 789)]);
        expect(tools.cancelCalls, const ['job']);
      },
    );

    test('rejects invalid process_list job_ids before monitor calls', () async {
      final monitor = _FakeBackgroundProcessMonitorService();
      addTearDown(monitor.dispose);
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessMonitorService: monitor,
      );

      final result = await handler.execute(
        name: 'process_list',
        arguments: const {'job_ids': 'job-a'},
      );

      expect(result.isSuccess, isFalse);
      expect(jsonDecode(result.result), {
        'ok': false,
        'code': 'invalid_job_ids',
        'error': 'job_ids must be an array of strings',
      });
      expect(result.errorMessage, 'job_ids must be an array of strings');
      expect(monitor.listCalls, isEmpty);
      expect(monitor.refreshActiveCalls, 0);
      expect(monitor.refreshJobCalls, isEmpty);
    });

    test(
      'filters process_list ids and serializes counts at a fixed time',
      () async {
        final running = _snapshot(jobId: 'job-a', status: 'running');
        final finished = _snapshot(
          jobId: 'job-b',
          status: 'exited',
          exitCode: 0,
        );
        final monitor = _FakeBackgroundProcessMonitorService(
          snapshots: [running, finished],
          active: [
            running,
            _snapshot(jobId: 'job-c', status: 'running'),
          ],
        );
        addTearDown(monitor.dispose);
        final handler = BuiltInLocalCommandToolHandler(
          backgroundProcessMonitorService: monitor,
          clock: () => DateTime.parse('2026-07-17T03:04:05.000Z'),
        );

        final result = await handler.execute(
          name: 'process_list',
          arguments: const {
            'job_ids': [' job-a ', 3, '', 'job-b', null],
            'include_finished': 'false',
            'refresh': 'true',
            'limit': 2.9,
          },
        );

        expect(monitor.listCalls, hasLength(1));
        expect(monitor.listCalls.single.jobIds, ['job-a', 'job-b']);
        expect(monitor.listCalls.single.includeFinished, isTrue);
        expect(monitor.listCalls.single.limit, 2);
        expect(monitor.refreshActiveCalls, 0);
        expect(monitor.refreshJobCalls, isEmpty);
        expect(result.isSuccess, isTrue);
        expect(jsonDecode(result.result), {
          'ok': true,
          'generated_at': '2026-07-17T03:04:05.000Z',
          'job_count': 2,
          'jobs': [running.toJson(), finished.toJson()],
          'active_count': 2,
          'finished_count': 1,
        });
      },
    );

    test('uses process_list defaults and refreshes active jobs', () async {
      final monitor = _FakeBackgroundProcessMonitorService();
      addTearDown(monitor.dispose);
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessMonitorService: monitor,
      );

      await handler.execute(
        name: 'process_list',
        arguments: const {'refresh': true},
      );

      expect(monitor.refreshActiveCalls, 1);
      expect(monitor.refreshJobCalls, isEmpty);
      expect(monitor.listCalls, hasLength(1));
      expect(monitor.listCalls.single.jobIds, isEmpty);
      expect(monitor.listCalls.single.includeFinished, isTrue);
      expect(monitor.listCalls.single.limit, isNull);
    });

    test('refreshes only requested process_list jobs', () async {
      final monitor = _FakeBackgroundProcessMonitorService();
      addTearDown(monitor.dispose);
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessMonitorService: monitor,
      );

      await handler.execute(
        name: 'process_list',
        arguments: const {
          'job_ids': [' job-a ', false, 'job-b'],
          'include_finished': false,
          'refresh': true,
          'limit': 1,
        },
      );

      expect(monitor.refreshActiveCalls, 0);
      expect(monitor.refreshJobCalls, const [
        ['job-a', 'job-b'],
      ]);
      expect(monitor.listCalls, hasLength(1));
      expect(monitor.listCalls.single.jobIds, ['job-a', 'job-b']);
      expect(monitor.listCalls.single.includeFinished, isFalse);
      expect(monitor.listCalls.single.limit, 1);
    });

    test('returns the exact run_tests approval sentinel', () async {
      final handler = BuiltInLocalCommandToolHandler();

      final result = await handler.execute(
        name: 'run_tests',
        arguments: const {},
      );

      expect(result.toolName, 'run_tests');
      expect(
        result.result,
        '{"error":"run_tests must be executed through the chat command approval flow.","code":"approval_required"}',
      );
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'run_tests must be executed through the chat command approval flow',
      );
    });

    test('propagates command provider exceptions', () async {
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              throw StateError('provider failed');
            },
      );

      expect(
        () => handler.execute(
          name: 'local_execute_command',
          arguments: const {'command': 'echo ok', 'working_directory': '/tmp'},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

String _definitionName(Map<String, dynamic> definition) {
  return (definition['function']! as Map<String, dynamic>)['name']! as String;
}

BackgroundProcessMonitorSnapshot _snapshot({
  required String jobId,
  required String status,
  int? exitCode,
}) {
  return BackgroundProcessMonitorSnapshot(
    jobId: jobId,
    status: status,
    command: 'command-$jobId',
    workingDirectory: '/tmp',
    startedAt: DateTime.parse('2026-07-17T01:00:00.000Z'),
    lastCheckedAt: DateTime.parse('2026-07-17T02:00:00.000Z'),
    exitCode: exitCode,
  );
}

class _FakeBackgroundProcessTools extends BackgroundProcessTools {
  _FakeBackgroundProcessTools({
    this.supported = true,
    this.startResult = '{}',
    this.statusResult = '{}',
    this.tailResult = '{}',
    this.waitResult = '{}',
    this.cancelResult = '{}',
  });

  final bool supported;
  final String startResult;
  final String statusResult;
  final String tailResult;
  final String waitResult;
  final String cancelResult;
  final List<_ProcessStartCall> startCalls = <_ProcessStartCall>[];
  final List<_ProcessValueCall> statusCalls = <_ProcessValueCall>[];
  final List<_ProcessValueCall> tailCalls = <_ProcessValueCall>[];
  final List<_ProcessValueCall> waitCalls = <_ProcessValueCall>[];
  final List<String> cancelCalls = <String>[];

  int get totalCalls =>
      startCalls.length +
      statusCalls.length +
      tailCalls.length +
      waitCalls.length +
      cancelCalls.length;

  @override
  bool get isSupported => supported;

  @override
  Future<String> start({
    required String command,
    required String workingDirectory,
    String? label,
  }) async {
    startCalls.add((
      command: command,
      workingDirectory: workingDirectory,
      label: label,
    ));
    return startResult;
  }

  @override
  Future<String> status({required String jobId, int? tailChars}) async {
    statusCalls.add((jobId: jobId, value: tailChars));
    return statusResult;
  }

  @override
  Future<String> tail({required String jobId, int? maxChars}) async {
    tailCalls.add((jobId: jobId, value: maxChars));
    return tailResult;
  }

  @override
  Future<String> wait({required String jobId, int? waitMs}) async {
    waitCalls.add((jobId: jobId, value: waitMs));
    return waitResult;
  }

  @override
  Future<String> cancel({required String jobId}) async {
    cancelCalls.add(jobId);
    return cancelResult;
  }
}

class _FakeBackgroundProcessMonitorService
    extends BackgroundProcessMonitorService {
  _FakeBackgroundProcessMonitorService({
    List<BackgroundProcessMonitorSnapshot> snapshots = const [],
    List<BackgroundProcessMonitorSnapshot> active = const [],
  }) : _snapshots = snapshots,
       _active = active,
       super(tools: BackgroundProcessTools());

  final List<BackgroundProcessMonitorSnapshot> _snapshots;
  final List<BackgroundProcessMonitorSnapshot> _active;
  final List<_ProcessListCall> listCalls = <_ProcessListCall>[];
  int refreshActiveCalls = 0;
  final List<List<String>> refreshJobCalls = <List<String>>[];

  @override
  List<BackgroundProcessMonitorSnapshot> get activeSnapshots => _active;

  @override
  List<BackgroundProcessMonitorSnapshot> listJobs({
    Iterable<String>? jobIds,
    bool includeFinished = true,
    int? limit,
  }) {
    listCalls.add((
      jobIds: jobIds?.toList(growable: false),
      includeFinished: includeFinished,
      limit: limit,
    ));
    return _snapshots;
  }

  @override
  Future<List<BackgroundProcessMonitorSnapshot>> refreshActiveJobs() async {
    refreshActiveCalls += 1;
    return const <BackgroundProcessMonitorSnapshot>[];
  }

  @override
  Future<List<BackgroundProcessMonitorSnapshot>> refreshJobs(
    Iterable<String> jobIds,
  ) async {
    refreshJobCalls.add(jobIds.toList(growable: false));
    return const <BackgroundProcessMonitorSnapshot>[];
  }
}
