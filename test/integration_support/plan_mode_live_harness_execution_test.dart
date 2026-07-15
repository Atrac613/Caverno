import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

import '../../integration_test/test_support/plan_mode_heartbeat.dart';
import '../../integration_test/test_support/plan_mode_live_harness_execution.dart';

void main() {
  test('reads the latest assistant message after a previous id', () {
    final conversation = _conversation(<Message>[
      _message(id: 'user-1', role: MessageRole.user, content: 'Build it'),
      _message(id: 'assistant-1', content: 'Old answer'),
      _message(id: 'assistant-2', content: '  New answer  '),
    ]);

    expect(
      latestPlanModeHarnessAssistantMessageId(conversation),
      'assistant-2',
    );
    expect(
      latestPlanModeHarnessAssistantResponseAfter(conversation, 'assistant-1'),
      'New answer',
    );
    expect(
      latestPlanModeHarnessAssistantResponseAfter(conversation, 'assistant-2'),
      '',
    );
    expect(latestPlanModeHarnessAssistantMessageId(null), isNull);
  });

  test('builds fallback assistant response from hidden text or tool names', () {
    expect(
      buildPlanModeHarnessFallbackAssistantResponse(
        toolResults: const <ToolResultInfo>[],
        hiddenAssistantResponse: '  Hidden completion  ',
      ),
      'Hidden completion',
    );
    expect(
      buildPlanModeHarnessFallbackAssistantResponse(
        toolResults: <ToolResultInfo>[
          _toolResult(name: 'write_file'),
          _toolResult(name: ' local_execute_command '),
          _toolResult(name: 'write_file'),
        ],
        hiddenAssistantResponse: null,
      ),
      'The saved task completed with tool execution evidence from: write_file, local_execute_command.',
    );
    expect(
      buildPlanModeHarnessFallbackAssistantResponse(
        toolResults: <ToolResultInfo>[_toolResult(name: ' ')],
        hiddenAssistantResponse: null,
      ),
      'The saved task completed with tool execution evidence.',
    );
    expect(
      buildPlanModeHarnessFallbackAssistantResponse(
        toolResults: const <ToolResultInfo>[],
        hiddenAssistantResponse: null,
      ),
      '',
    );
  });

  test('requires matching tool evidence before completing a saved task', () {
    const task = ConversationWorkflowTask(
      id: 'task-add-list',
      title: 'Implement add and list',
      targetFiles: <String>['bin/todo_cli.dart', 'lib/storage.dart'],
      validationCommand:
          'dart run bin/todo_cli.dart add test && dart run bin/todo_cli.dart list',
    );

    final staleAssessment = assessPlanModeHarnessTaskCompletion(
      task: task,
      toolResults: <ToolResultInfo>[
        _toolResult(
          name: 'local_execute_command',
          arguments: const <String, dynamic>{
            'command': 'dart analyze lib/storage.dart',
          },
          result:
              '{"command":"dart analyze lib/storage.dart","exit_code":0,"stdout":"No issues found!"}',
        ),
      ],
    );
    final matchingAssessment = assessPlanModeHarnessTaskCompletion(
      task: task,
      toolResults: <ToolResultInfo>[
        _toolResult(
          name: 'local_execute_command',
          arguments: const <String, dynamic>{
            'command':
                'dart run bin/todo_cli.dart add test && dart run bin/todo_cli.dart list',
          },
          result:
              '{"command":"dart run bin/todo_cli.dart add test && dart run bin/todo_cli.dart list","exit_code":0,"stdout":"Added task\\n[test]"}',
        ),
      ],
    );

    expect(staleAssessment.shouldMarkCompleted, isFalse);
    expect(matchingAssessment.shouldMarkCompleted, isTrue);
  });

  test('resolves cleanup timeout for fake and live runs', () {
    final shortBudgets = _budgets(
      executionTimeout: const Duration(seconds: 20),
    );
    final longBudgets = _budgets(
      executionTimeout: const Duration(seconds: 120),
    );

    expect(
      resolvePlanModeHarnessCleanupTimeout(
        usesLiveLlm: false,
        budgets: shortBudgets,
      ),
      const Duration(seconds: 30),
    );
    expect(
      resolvePlanModeHarnessCleanupTimeout(
        usesLiveLlm: true,
        budgets: shortBudgets,
      ),
      const Duration(seconds: 90),
    );
    expect(
      resolvePlanModeHarnessCleanupTimeout(
        usesLiveLlm: true,
        budgets: longBudgets,
      ),
      const Duration(seconds: 120),
    );
  });

  test('cleanup timeout is swallowed for background harness futures', () async {
    final completer = Completer<void>();
    final handle = PlanModeHarnessExecutionHandle(completer.future);

    await awaitPlanModeHarnessExecutionCleanup(
      handle,
      scenarioName: 'timeout_case',
      timeout: const Duration(milliseconds: 1),
    );

    expect(completer.isCompleted, isFalse);
    expect(handle.cleanupCancellationRequested, isTrue);
  });

  test('recognizes provider container disposal after cleanup cancellation', () {
    expect(
      isPlanModeHarnessProviderContainerDisposedError(
        StateError(
          'Tried to read a provider from a ProviderContainer that was already disposed',
        ),
      ),
      isTrue,
    );
    expect(
      isPlanModeHarnessProviderContainerDisposedError(
        StateError('Some other harness failure'),
      ),
      isFalse,
    );
  });

  test('detects missing target files before harness auto-continues', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_targets_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    File('${tempDir.path}/README.md').writeAsStringSync('# Ready\n');

    const task = ConversationWorkflowTask(
      id: 'task-implementation',
      title: 'Implement ping_cli.py',
      targetFiles: <String>['README.md', 'ping_cli.py'],
      validationCommand: 'python3 ping_cli.py --help',
    );

    expect(missingPlanModeHarnessTargetFiles(tempDir, task), <String>[
      'ping_cli.py',
    ]);
  });

  test('approves exact saved read-only validation command chains', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_validation_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-readme',
      title: 'Create README.md with usage instructions',
      targetFiles: <String>['README.md'],
      validationCommand:
          "test -f README.md && grep -qi 'usage\\|install\\|click' README.md",
    );

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isTrue,
    );
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: '${task.validationCommand} && echo "VALIDATION PASSED"',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: Directory.systemTemp.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
  });

  test('approves exact saved read-only validation pipelines', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_pipeline_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-requirements',
      title: 'Create requirements.txt',
      targetFiles: <String>['requirements.txt'],
      validationCommand: 'cat requirements.txt | grep click',
    );

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isTrue,
    );
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: '${task.validationCommand} && echo "VALIDATION PASSED"',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: 'cat ../requirements.txt | grep click',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
  });

  test('approves exact saved python help validation for target file', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_python_help_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-python-help',
      title: 'Create ping_cli.py',
      targetFiles: <String>['ping_cli.py'],
      validationCommand: 'python3 ping_cli.py --help',
    );

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isTrue,
    );
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: '${task.validationCommand} && echo "VALIDATION PASSED"',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: 'python3 other.py --help',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
  });

  test('approves exact saved Dart help validation for target file', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_help_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-dart-help',
      title: 'Create the Dart CLI',
      targetFiles: <String>['bin/todo_cli.dart'],
      validationCommand: 'dart run bin/todo_cli.dart help',
    );

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isTrue,
    );
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: 'dart run bin/other.dart help',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: 'dart run bin/todo_cli.dart add unsafe',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
  });

  test('approves exact saved Dart project setup and analysis commands', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_project_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    for (final command in <String>[
      'dart pub get',
      'fvm dart pub get',
      'dart analyze lib/',
      'fvm flutter analyze --fatal-warnings lib/',
    ]) {
      final task = ConversationWorkflowTask(
        id: 'task-dart-project',
        title: 'Prepare and analyze the Dart project',
        targetFiles: const <String>['pubspec.yaml', 'lib/'],
        validationCommand: command,
      );
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isTrue,
        reason: command,
      );
    }
  });

  test('approves contained saved Dart compile validations', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_compile_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    for (final command in <String>[
      'dart compile exe bin/todo.dart -o /dev/null',
      'dart compile exe bin/todo.dart -o build/todo',
    ]) {
      final task = ConversationWorkflowTask(
        id: 'task-dart-compile',
        title: 'Compile the Dart CLI',
        targetFiles: const <String>['bin/todo.dart'],
        validationCommand: command,
      );
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isTrue,
        reason: command,
      );
    }
  });

  test('rejects uncontained saved Dart compile validations', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_compile_reject_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    for (final command in <String>[
      'dart compile exe bin/other.dart -o /dev/null',
      'dart compile exe bin/todo.dart -o /tmp/todo',
      'dart compile exe ../todo.dart -o build/todo',
    ]) {
      final task = ConversationWorkflowTask(
        id: 'task-dart-compile',
        title: 'Compile the Dart CLI',
        targetFiles: const <String>['bin/todo.dart'],
        validationCommand: command,
      );
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isFalse,
        reason: command,
      );
    }
  });

  test('approves safe Dart runtime information commands', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_runtime_info_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-dart-project',
      title: 'Prepare the Dart project',
      targetFiles: <String>['pubspec.yaml'],
      validationCommand: 'dart pub get',
    );
    for (final command in <String>[
      'dart --version',
      'flutter --version',
      'fvm dart --version',
    ]) {
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(command: command, workingDirectory: ''),
          scenarioDir: tempDir,
          task: task,
        ),
        isTrue,
        reason: command,
      );
    }
  });

  test('approves workspace-root Dart CLI scaffolding for a saved task', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_scaffold_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-dart-scaffold',
      title: 'Create the Dart CLI scaffold',
      targetFiles: <String>['pubspec.yaml', 'bin/todo_app.dart'],
      validationCommand: 'dart pub get',
    );
    for (final command in <String>[
      'dart create -t console-full .',
      'dart create -t console-full --force .',
      'fvm dart create --template=console --no-pub .',
      'dart create --template console ${tempDir.path}',
    ]) {
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isTrue,
        reason: command,
      );
    }
  });

  test('rejects Dart scaffolding outside the saved workspace contract', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_unsafe_dart_scaffold_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-dart-scaffold',
      title: 'Create the Dart CLI scaffold',
      targetFiles: <String>['pubspec.yaml', 'bin/todo_app.dart'],
      validationCommand: 'dart pub get',
    );
    for (final command in <String>[
      'dart create -t console-full ../outside',
      'dart create -t package .',
      'dart create --output .',
    ]) {
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isFalse,
        reason: command,
      );
    }
    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: 'dart create -t console-full .',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task.copyWith(targetFiles: const <String>['lib/main.dart']),
      ),
      isFalse,
    );
  });

  test('approves saved validation chains with safe Dart project commands', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_validation_chain_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-dart-project',
      title: 'Prepare the Dart project',
      targetFiles: <String>['pubspec.yaml'],
      validationCommand: 'ls pubspec.yaml && dart pub get',
    );

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: '',
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isTrue,
    );

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: 'cd ${tempDir.path} && ${task.validationCommand}',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isTrue,
    );
  });

  test('approves saved Dart format only for active task targets', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_format_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final binDir = Directory('${tempDir.path}/bin')..createSync();
    File('${binDir.path}/todo_app.dart').writeAsStringSync('void main() {}\n');

    const task = ConversationWorkflowTask(
      id: 'task-dart-format',
      title: 'Format and analyze the Dart application',
      targetFiles: <String>['bin/todo_app.dart', 'pubspec.yaml'],
      validationCommand:
          'dart format --set-exit-if-changed bin/ && dart analyze',
    );

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isTrue,
    );

    final unrelatedFile = File('${binDir.path}/unrelated.dart')
      ..writeAsStringSync('void unrelated() {}\n');

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );

    unrelatedFile.deleteSync();
    Link(
      '${binDir.path}/linked.dart',
    ).createSync('${binDir.path}/todo_app.dart');

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: task.validationCommand,
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isFalse,
    );
  });

  test('rejects unsafe Dart format saved validation variants', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_unsafe_dart_format_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final binDir = Directory('${tempDir.path}/bin')..createSync();
    File('${binDir.path}/todo_app.dart').writeAsStringSync('void main() {}\n');

    for (final command in <String>[
      'dart format',
      'dart format --output=show bin/todo_app.dart',
      'dart format ../outside.dart',
    ]) {
      final task = ConversationWorkflowTask(
        id: 'task-unsafe-dart-format',
        title: 'Reject unsafe Dart format commands',
        targetFiles: const <String>['bin/todo_app.dart'],
        validationCommand: command,
      );
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isFalse,
        reason: command,
      );
    }
  });

  test(
    'rejects saved validation directory changes outside the scenario root',
    () {
      final tempDir = Directory.systemTemp.createTempSync(
        'plan_mode_harness_dart_validation_cd_',
      );
      final childDir = Directory('${tempDir.path}/child')..createSync();
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      const task = ConversationWorkflowTask(
        id: 'task-dart-project',
        title: 'Prepare the Dart project',
        targetFiles: <String>['pubspec.yaml'],
        validationCommand: 'dart pub get && dart analyze',
      );

      for (final directory in <String>[
        childDir.path,
        Directory.systemTemp.path,
        '${tempDir.path}/../${tempDir.path.split(Platform.pathSeparator).last}',
      ]) {
        expect(
          isSafePlanModeHarnessLocalCommand(
            pending: _pendingLocalCommand(
              command: 'cd $directory && ${task.validationCommand}',
              workingDirectory: tempDir.path,
            ),
            scenarioDir: tempDir,
            task: task,
          ),
          isFalse,
          reason: directory,
        );
      }
    },
  );

  test('approves contained wrappers around a saved Dart CLI validation', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_dart_cli_wrapper_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-add-list',
      title: 'Implement add and list',
      targetFiles: <String>['bin/todo_cli.dart', 'lib/storage.dart'],
      validationCommand:
          'dart run bin/todo_cli.dart add test && dart run bin/todo_cli.dart list',
    );

    for (final command in <String>[
      'rm -f tasks.json && ${task.validationCommand}',
      'dart analyze bin/todo_cli.dart lib/storage.dart && ${task.validationCommand}',
    ]) {
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isTrue,
        reason: command,
      );
    }

    for (final command in <String>[
      'rm -f heartbeat.json && ${task.validationCommand}',
      'rm -rf tasks.json && ${task.validationCommand}',
      'rm -f ../tasks.json && ${task.validationCommand}',
    ]) {
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isFalse,
        reason: command,
      );
    }
  });

  test('approves safe Dart commands with the implicit scenario workspace', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_implicit_workspace_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-dart-implementation',
      title: 'Implement the Dart application',
      targetFiles: <String>['lib/main.dart'],
      validationCommand: 'dart run lib/main.dart --help',
    );

    for (final command in <String>[
      'dart pub get',
      'dart analyze lib/main.dart',
      'dart run lib/main.dart --help',
    ]) {
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(command: command, workingDirectory: ''),
          scenarioDir: tempDir,
          task: task,
        ),
        isTrue,
        reason: command,
      );
    }
  });

  test('approves safe proactive Dart analysis in the scenario workspace', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_proactive_analysis_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-dart-help',
      title: 'Create the Dart CLI',
      targetFiles: <String>['bin/todo_cli.dart'],
      validationCommand: 'dart run bin/todo_cli.dart help',
    );

    expect(
      isSafePlanModeHarnessLocalCommand(
        pending: _pendingLocalCommand(
          command: 'dart analyze bin/todo_cli.dart',
          workingDirectory: tempDir.path,
        ),
        scenarioDir: tempDir,
        task: task,
      ),
      isTrue,
    );
  });

  test('approves workspace-contained directory creation', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_mkdir_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    const task = ConversationWorkflowTask(
      id: 'task-scaffold',
      title: 'Create the project scaffold',
      targetFiles: <String>['bin/main.dart'],
      validationCommand: 'dart pub get',
    );

    for (final command in <String>['mkdir bin', 'mkdir -p bin lib/src']) {
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(command: command, workingDirectory: ''),
          scenarioDir: tempDir,
          task: task,
        ),
        isTrue,
        reason: command,
      );
    }
    for (final command in <String>[
      'mkdir -p ../outside',
      'mkdir --mode 777 bin',
      'rm -rf bin',
    ]) {
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isFalse,
        reason: command,
      );
    }
  });

  test('rejects unsafe Dart project command variants', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_harness_unsafe_dart_project_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    for (final command in <String>[
      'dart pub publish',
      'dart analyze ../outside',
      'dart analyze --packages=../outside/package_config.json',
      'dart run tool/mutate.dart',
    ]) {
      final task = ConversationWorkflowTask(
        id: 'task-unsafe-dart-project',
        title: 'Reject unsafe commands',
        targetFiles: const <String>['pubspec.yaml'],
        validationCommand: command,
      );
      expect(
        isSafePlanModeHarnessLocalCommand(
          pending: _pendingLocalCommand(
            command: command,
            workingDirectory: tempDir.path,
          ),
          scenarioDir: tempDir,
          task: task,
        ),
        isFalse,
        reason: command,
      );
    }
  });
}

Conversation _conversation(List<Message> messages) {
  final now = DateTime(2026, 5, 12, 12);
  return Conversation(
    id: 'conversation-1',
    title: 'Harness',
    messages: messages,
    createdAt: now,
    updatedAt: now,
  );
}

Message _message({
  required String id,
  MessageRole role = MessageRole.assistant,
  required String content,
}) {
  return Message(
    id: id,
    role: role,
    content: content,
    timestamp: DateTime(2026, 5, 12, 12),
  );
}

ToolResultInfo _toolResult({
  required String name,
  Map<String, dynamic> arguments = const <String, dynamic>{},
  String result = 'ok',
}) {
  return ToolResultInfo(
    id: name,
    name: name,
    arguments: arguments,
    result: result,
  );
}

PlanModeTimeoutBudgets _budgets({required Duration executionTimeout}) {
  return PlanModeTimeoutBudgets(
    planningTimeout: const Duration(seconds: 5),
    executionTimeout: executionTimeout,
    executionStallTimeout: const Duration(seconds: 45),
    overallTimeout: const Duration(seconds: 120),
  );
}

PendingLocalCommand _pendingLocalCommand({
  required String command,
  required String workingDirectory,
}) {
  return PendingLocalCommand(
    id: 'local-command',
    command: command,
    workingDirectory: workingDirectory,
    reason: 'Validate saved task output.',
    warningTitle: null,
    warningMessage: null,
    completer: Completer<LocalCommandApproval>(),
  );
}
