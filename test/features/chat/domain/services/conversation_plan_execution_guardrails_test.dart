import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_execution_guardrails.dart';

void main() {
  List<ToolResultInfo> loadFixtureToolResults(String fixtureName) {
    final fixture =
        jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
            as Map<String, dynamic>;
    return (fixture['toolResults'] as List<dynamic>)
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => ToolResultInfo(
            id: item['id'] as String,
            name: item['name'] as String,
            arguments: item['arguments'] as Map<String, dynamic>,
            result: item['result'] as String,
          ),
        )
        .toList(growable: false);
  }

  ConversationWorkflowTask loadFixtureTask(String fixtureName) {
    final fixture =
        jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
            as Map<String, dynamic>;
    return ConversationWorkflowTask.fromJson(
      fixture['task'] as Map<String, dynamic>,
    );
  }

  test('assessTaskDrift flags scaffolding replay fixture as drift', () {
    final task = loadFixtureTask(
      'plan_mode_ping_cli_execution_stall_replay.json',
    );
    final toolResults = loadFixtureToolResults(
      'plan_mode_ping_cli_execution_stall_replay.json',
    );

    final assessment = ConversationPlanExecutionGuardrails.assessTaskDrift(
      task: task,
      toolResults: toolResults,
    );

    expect(assessment.hasDrift, isTrue);
    expect(assessment.touchedTargetFiles, isEmpty);
    expect(assessment.unrelatedTouchedPaths, contains('pyproject.toml'));
    expect(
      assessment.unrelatedTouchedPaths,
      contains('live_ping_cli/__init__.py'),
    );
    expect(assessment.scaffoldCommands, contains('mkdir -p live_ping_cli'));
  });

  test('assessTaskCompletion marks the post-task replay as complete', () {
    final task = loadFixtureTask(
      'plan_mode_ping_cli_post_task1_timeout_replay.json',
    );
    final toolResults = loadFixtureToolResults(
      'plan_mode_ping_cli_post_task1_timeout_replay.json',
    );

    final assessment = ConversationPlanExecutionGuardrails.assessTaskCompletion(
      task: task,
      toolResults: toolResults,
    );

    expect(assessment.hasFailure, isFalse);
    expect(assessment.shouldMarkCompleted, isTrue);
    expect(assessment.touchedTargetFiles, contains('ping_cli.py'));
    expect(assessment.touchedTargetFiles, contains('hosts.txt'));
    expect(
      assessment.successfulValidationCommands,
      contains('python3 ping_cli.py google.com hosts.txt'),
    );
  });

  test(
    'canFinalizeScaffoldFromWorkspaceTargets accepts scaffold targets that already exist',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_scaffold_workspace_completion_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final task = ConversationWorkflowTask.fromJson(
        fixture['task'] as Map<String, dynamic>,
      );
      final existingTargetPaths =
          (fixture['existingTargetPaths'] as List<dynamic>).cast<String>();

      final canFinalize =
          ConversationPlanExecutionGuardrails.canFinalizeScaffoldFromWorkspaceTargets(
            task: task,
            existingTargetPaths: existingTargetPaths,
          );

      expect(canFinalize, isTrue);
      expect(
        ConversationPlanExecutionGuardrails.missingWorkspaceTargetFiles(
          task: task,
          existingTargetPaths: existingTargetPaths,
        ),
        isEmpty,
      );
    },
  );

  test(
    'canPromoteScaffoldCompletionFromWorkspaceValidation accepts validation-only evidence',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_scaffold_validation_workspace_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final task = ConversationWorkflowTask.fromJson(
        fixture['task'] as Map<String, dynamic>,
      );
      final existingTargetPaths =
          (fixture['existingTargetPaths'] as List<dynamic>).cast<String>();
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_scaffold_validation_workspace_replay.json',
      );

      final canPromote =
          ConversationPlanExecutionGuardrails.canPromoteScaffoldCompletionFromWorkspaceValidation(
            task: task,
            toolResults: toolResults,
            existingTargetPaths: existingTargetPaths,
          );

      expect(canPromote, isTrue);
    },
  );

  test(
    'canPromoteCompletionFromWorkspaceValidation accepts non-scaffold validation retries when targets already exist',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-ping-lib',
        title:
            'Implement core ping functionality and CLI interface in ping_cli.py',
        targetFiles: ['ping_lib.py'],
        validationCommand: 'python3 ping_lib.py --help',
      );
      final toolResults = [
        ToolResultInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: {'command': 'python3 ping_lib.py --help'},
          result:
              '{"command":"python3 ping_lib.py --help","exit_code":0,"stdout":"usage: ping_lib.py [-h] host","stderr":""}',
        ),
      ];

      final canPromote =
          ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceValidation(
            task: task,
            toolResults: toolResults,
            existingTargetPaths: const ['ping_lib.py'],
          );

      expect(canPromote, isTrue);
    },
  );

  test(
    'assessTaskDrift flags repeated writes when scaffold targets remain',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_post_approval_scaffold_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_post_approval_scaffold_replay.json',
      ).take(2).toList(growable: false);

      final assessment = ConversationPlanExecutionGuardrails.assessTaskDrift(
        task: task,
        toolResults: toolResults,
      );

      expect(assessment.hasDrift, isTrue);
      expect(assessment.touchedTargetFiles, contains('pyproject.toml'));
      expect(assessment.repeatedTargetFiles, contains('pyproject.toml'));
      expect(assessment.remainingTargetFiles, contains('README.md'));
      expect(assessment.remainingTargetFiles, contains('src/__init__.py'));
    },
  );

  test(
    'assessTaskCompletion accepts scaffold target coverage with light validation',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_post_approval_scaffold_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_post_approval_scaffold_replay.json',
      );

      final assessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );

      expect(assessment.hasFailure, isFalse);
      expect(assessment.shouldMarkCompleted, isTrue);
      expect(assessment.completedFromSuccessfulValidation, isFalse);
      expect(assessment.completedFromTargetCoverage, isTrue);
      expect(assessment.touchedAllTargetFiles, isTrue);
      expect(assessment.untouchedTargetFiles, isEmpty);
    },
  );

  test(
    'assessTaskCompletion keeps scaffold completion after post-validation rewrites',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_post_validation_loop_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_post_validation_loop_replay.json',
      );

      final completionAssessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );
      final driftAssessment =
          ConversationPlanExecutionGuardrails.assessTaskDrift(
            task: task,
            toolResults: toolResults,
          );

      expect(completionAssessment.shouldMarkCompleted, isTrue);
      expect(completionAssessment.completedFromTargetCoverage, isTrue);
      expect(
        completionAssessment.successfulValidationCommands,
        contains('ls -R src'),
      );
      expect(driftAssessment.hasDrift, isFalse);
      expect(driftAssessment.repeatedTargetFiles, contains('README.md'));
      expect(driftAssessment.remainingTargetFiles, isEmpty);
    },
  );

  test('extracts missing target files from failed validation commands', () {
    final task = loadFixtureTask(
      'plan_mode_ping_cli_missing_main_validation_replay.json',
    );
    final toolResults = loadFixtureToolResults(
      'plan_mode_ping_cli_missing_main_validation_replay.json',
    );

    final missingTarget =
        ConversationPlanExecutionGuardrails.missingTargetFileFromValidationFailure(
          task: task,
          toolResults: toolResults,
        );

    expect(missingTarget, 'main.py');
  });

  test(
    'extracts inferred src target files from failed validation commands when metadata is empty',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_src_ping_cli_missing_validation_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_src_ping_cli_missing_validation_replay.json',
      );

      final missingTarget =
          ConversationPlanExecutionGuardrails.missingTargetFileFromValidationFailure(
            task: task,
            toolResults: toolResults,
          );

      expect(missingTarget, 'src/ping_cli.py');
    },
  );

  test(
    'assessTaskDrift infers implementation targets from the task title when metadata is empty',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_main_py_execution_stall_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_main_py_execution_stall_replay.json',
      );

      final driftAssessment =
          ConversationPlanExecutionGuardrails.assessTaskDrift(
            task: task,
            toolResults: toolResults,
          );
      final completionAssessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );

      expect(driftAssessment.hasDrift, isFalse);
      expect(driftAssessment.touchedTargetFiles, contains('main.py'));
      expect(driftAssessment.unrelatedTouchedPaths, isEmpty);
      expect(completionAssessment.hasTargetFiles, isTrue);
      expect(completionAssessment.touchedTargetFiles, contains('main.py'));
      expect(completionAssessment.shouldMarkCompleted, isFalse);
      expect(
        ConversationPlanExecutionGuardrails.missingWorkspaceTargetFiles(
          task: task,
          existingTargetPaths: const ['main.py'],
        ),
        isEmpty,
      );
    },
  );

  test(
    'assessTaskCompletion treats target-directory scaffolding as benign support',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-scaffold-support',
        title: 'Initialize package layout',
        targetFiles: [
          'pyproject.toml',
          'README.md',
          '.gitignore',
          'src/ping_cli/__init__.py',
        ],
        validationCommand: 'ls -R src',
      );
      final toolResults = [
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: {'path': 'pyproject.toml'},
          result:
              '{"path":"/tmp/project/pyproject.toml","bytes_written":120,"created":true}',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'write_file',
          arguments: {'path': 'README.md'},
          result:
              '{"path":"/tmp/project/README.md","bytes_written":180,"created":true}',
        ),
        ToolResultInfo(
          id: 'tool-3',
          name: 'write_file',
          arguments: {'path': '.gitignore'},
          result:
              '{"path":"/tmp/project/.gitignore","bytes_written":24,"created":true}',
        ),
        ToolResultInfo(
          id: 'tool-4',
          name: 'local_execute_command',
          arguments: {'command': 'mkdir -p src/ping_cli'},
          result:
              '{"command":"mkdir -p src/ping_cli","exit_code":0,"stdout":"","stderr":""}',
        ),
        ToolResultInfo(
          id: 'tool-5',
          name: 'write_file',
          arguments: {'path': 'src/ping_cli/__init__.py'},
          result:
              '{"path":"/tmp/project/src/ping_cli/__init__.py","bytes_written":0,"created":true}',
        ),
        ToolResultInfo(
          id: 'tool-6',
          name: 'local_execute_command',
          arguments: {'command': 'ls -R src'},
          result:
              '{"command":"ls -R src","exit_code":0,"stdout":"src\\nping_cli\\n__init__.py","stderr":""}',
        ),
      ];

      final completionAssessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );
      final driftAssessment =
          ConversationPlanExecutionGuardrails.assessTaskDrift(
            task: task,
            toolResults: toolResults,
          );

      expect(completionAssessment.shouldMarkCompleted, isTrue);
      expect(
        completionAssessment.benignSupportCommands,
        contains('mkdir -p src/ping_cli'),
      );
      expect(completionAssessment.scaffoldCommands, isEmpty);
      expect(driftAssessment.hasDrift, isFalse);
      expect(
        driftAssessment.benignSupportCommands,
        contains('mkdir -p src/ping_cli'),
      );
    },
  );

  test('assessTaskCompletion accepts run_tests as saved validation evidence', () {
    const task = ConversationWorkflowTask(
      id: 'task-config-loader',
      title: 'Validate the config loader',
      targetFiles: ['src/config_loader.py', 'tests/test_config_loader.py'],
      validationCommand: 'pytest tests/test_config_loader.py',
    );
    final toolResults = [
      ToolResultInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: {'path': 'src/config_loader.py'},
        result:
            '{"path":"/tmp/project/src/config_loader.py","bytes_written":600,"created":false}',
      ),
      ToolResultInfo(
        id: 'tool-2',
        name: 'run_tests',
        arguments: {'test_path': 'tests/test_config_loader.py'},
        result: '{"success":true,"summary":"5 tests passed"}',
      ),
    ];

    final assessment = ConversationPlanExecutionGuardrails.assessTaskCompletion(
      task: task,
      toolResults: toolResults,
    );

    expect(assessment.hasFailure, isFalse);
    expect(assessment.shouldMarkCompleted, isTrue);
    expect(
      assessment.successfulValidationCommands,
      contains('run_tests tests/test_config_loader.py'),
    );
  });

  test(
    'assessTaskCompletion preserves completion evidence despite a later malformed failure',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-ping-cli',
        title: 'Implement the ping CLI',
        targetFiles: ['ping_cli.py', 'hosts.txt'],
        validationCommand: 'python3 ping_cli.py google.com hosts.txt',
      );
      final toolResults = [
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: {'path': 'ping_cli.py'},
          result:
              '{"path":"/tmp/project/ping_cli.py","bytes_written":420,"created":true}',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'write_file',
          arguments: {'path': 'hosts.txt'},
          result:
              '{"path":"/tmp/project/hosts.txt","bytes_written":32,"created":true}',
        ),
        ToolResultInfo(
          id: 'tool-3',
          name: 'local_execute_command',
          arguments: {'command': 'python3 ping_cli.py google.com hosts.txt'},
          result:
              '{"command":"python3 ping_cli.py google.com hosts.txt","exit_code":0,"stdout":"google.com ok","stderr":""}',
        ),
        ToolResultInfo(
          id: 'tool-4',
          name: 'google',
          arguments: const {},
          result: 'Error: No matching tool available: google',
        ),
      ];

      final assessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );

      expect(assessment.hasFailure, isTrue);
      expect(assessment.shouldMarkCompleted, isFalse);
      expect(assessment.hasCompletionEvidenceIgnoringFailures, isTrue);
      expect(
        assessment.successfulValidationCommands,
        contains('python3 ping_cli.py google.com hosts.txt'),
      );
    },
  );

  test(
    'assessTaskCompletion keeps completion evidence after an unavailable tool',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_unknown_tool_after_completion_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_unknown_tool_after_completion_replay.json',
      );

      final assessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );

      expect(assessment.hasFailure, isTrue);
      expect(assessment.shouldMarkCompleted, isFalse);
      expect(assessment.hasCompletionEvidenceIgnoringFailures, isTrue);
      expect(
        assessment.successfulValidationCommands,
        contains('python3 ping_cli.py --help'),
      );
      expect(
        ConversationPlanExecutionGuardrails.unavailableToolNames(toolResults),
        contains('print'),
      );
    },
  );

  test('assistantMentionsTaskHandoff detects a later saved task title', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/plan_mode_ping_cli_cli_interface_handoff_stall_replay.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final task = ConversationWorkflowTask.fromJson(
      fixture['task'] as Map<String, dynamic>,
    );

    final mentionsHandoff =
        ConversationPlanExecutionGuardrails.assistantMentionsTaskHandoff(
          task: task,
          assistantResponse: fixture['assistantResponse'] as String,
          futureTaskTitles: (fixture['futureTaskTitles'] as List<dynamic>)
              .cast<String>(),
        );

    expect(mentionsHandoff, isTrue);
  });

  test(
    'canPromoteCompletionFromHistoricalValidationHandoff accepts passed validation before future-task narration',
    () {
      final task = const ConversationWorkflowTask(
        id: 'task-implement-cli',
        title: 'Implement the ping CLI tool',
        status: ConversationWorkflowTaskStatus.inProgress,
        targetFiles: ['ping_cli.py'],
        validationCommand: 'python3 ping_cli.py --help',
      );
      final progress = ConversationExecutionTaskProgress(
        taskId: task.id,
        status: ConversationWorkflowTaskStatus.inProgress,
        validationStatus: ConversationExecutionValidationStatus.passed,
        lastValidationCommand: 'python3 ping_cli.py --help',
        lastValidationSummary:
            'The validation command `python3 ping_cli.py --help` was successful.',
      );

      final canPromote =
          ConversationPlanExecutionGuardrails.canPromoteCompletionFromHistoricalValidationHandoff(
            task: task,
            progress: progress,
            assistantResponse:
                'The current task being executed (according to the context) is "Verify CLI functionality with a live host". '
                'This means the verification task was successful.',
            futureTaskTitles: const ['Verify CLI functionality with a live host'],
          );

      expect(canPromote, isTrue);
    },
  );

  test(
    'canPromoteCompletionFromCurrentValidationHandoff accepts same-turn validation success before future-task narration',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_main_task_validation_handoff_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final task = ConversationWorkflowTask.fromJson(
        fixture['task'] as Map<String, dynamic>,
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_main_task_validation_handoff_replay.json',
      );

      final canPromote =
          ConversationPlanExecutionGuardrails.canPromoteCompletionFromCurrentValidationHandoff(
            task: task,
            toolResults: toolResults,
            assistantResponse: fixture['assistantResponse'] as String,
            futureTaskTitles:
                (fixture['futureTaskTitles'] as List<dynamic>).cast<String>(),
          );

      expect(canPromote, isTrue);
    },
  );

  test(
    'canPromoteCompletionFromWorkspaceTargets accepts complete task target coverage',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_cli_interface_handoff_stall_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final task = ConversationWorkflowTask.fromJson(
        fixture['task'] as Map<String, dynamic>,
      );

      final canPromote =
          ConversationPlanExecutionGuardrails.canPromoteCompletionFromWorkspaceTargets(
            task: task,
            existingTargetPaths:
                (fixture['existingTargetPaths'] as List<dynamic>)
                    .cast<String>(),
          );

      expect(canPromote, isTrue);
    },
  );

  test(
    'hasOnlyUnavailableToolFailures accepts unavailable-tool-only failures',
    () {
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_cli_interface_handoff_stall_replay.json',
      );

      expect(
        ConversationPlanExecutionGuardrails.hasOnlyUnavailableToolFailures(
          toolResults,
        ),
        isTrue,
      );
    },
  );

  test('effectiveTargetPathsForTask infers file paths from the task title', () {
    final task = loadFixtureTask(
      'plan_mode_ping_cli_main_py_execution_stall_replay.json',
    );

    expect(
      ConversationPlanExecutionGuardrails.effectiveTargetPathsForTask(task),
      contains('main.py'),
    );
  });

  test(
    'assessTaskCompletion preserves scaffold completion after malformed write failures',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_malformed_scaffold_completion_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_malformed_scaffold_completion_replay.json',
      );

      final assessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );

      expect(assessment.hasFailure, isTrue);
      expect(assessment.shouldMarkCompleted, isFalse);
      expect(assessment.hasCompletionEvidenceIgnoringFailures, isTrue);
      expect(assessment.successfulValidationCommands, contains('ls -a'));
      expect(
        ConversationPlanExecutionGuardrails.hasOnlyRecoverableMalformedFailures(
          toolResults,
        ),
        isTrue,
      );
    },
  );

  test(
    'extracts Python src-layout import blocks and suggested retry commands',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_src_layout_import_block_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_src_layout_import_block_replay.json',
      );

      final failedCommand =
          ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
            task: task,
            toolResults: toolResults,
          );

      expect(
        ConversationPlanExecutionGuardrails.blockedPythonImportModule(
          toolResults,
        ),
        'ping_cli',
      );
      expect(failedCommand, isNotNull);
      expect(
        ConversationPlanExecutionGuardrails.suggestPythonSrcLayoutRetryCommand(
          task: task,
          failedCommand: failedCommand!,
        ),
        'PYTHONPATH=src $failedCommand',
      );
    },
  );

  test('detects pytest-missing verification failures and suggests fallback', () {
    final task = loadFixtureTask(
      'plan_mode_ping_cli_pytest_missing_verification_replay.json',
    );
    final toolResults = loadFixtureToolResults(
      'plan_mode_ping_cli_pytest_missing_verification_replay.json',
    );

    final failedCommand =
        ConversationPlanExecutionGuardrails.failedPythonValidationCommand(
          task: task,
          toolResults: toolResults,
        );

    expect(
      ConversationPlanExecutionGuardrails.missingPythonTestDependency(
        task: task,
        toolResults: toolResults,
      ),
      'pytest',
    );
    expect(failedCommand, 'python3 -m pytest tests/test_ping.py');
    expect(
      ConversationPlanExecutionGuardrails
          .suggestPythonTestDependencyFallbackCommand(
            task: task,
            failedCommand: failedCommand!,
            missingDependency: 'pytest',
          ),
      'python3 tests/test_ping.py',
    );
  });

  test(
    'assessTaskCompletion accepts direct Python fallback validation after pytest is unavailable',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-verify-cli',
        title: 'Create a test script to verify the CLI functionality',
        targetFiles: ['tests/test_ping.py'],
        validationCommand: 'python3 -m pytest tests/test_ping.py',
        notes:
            'Verify that the script can successfully ping a known host like 8.8.8.8.',
      );
      final toolResults = [
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: {'path': 'tests/test_ping.py'},
          result:
              '{"path":"/tmp/project/tests/test_ping.py","bytes_written":412,"created":false}',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'local_execute_command',
          arguments: {'command': 'python3 tests/test_ping.py'},
          result:
              '{"command":"python3 tests/test_ping.py","exit_code":0,"stdout":"ping ok","stderr":""}',
        ),
      ];

      final assessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );

      expect(assessment.hasFailure, isFalse);
      expect(assessment.shouldMarkCompleted, isTrue);
      expect(
        assessment.successfulValidationCommands,
        contains('python3 tests/test_ping.py'),
      );
    },
  );

  test(
    'assessTaskDrift ignores scaffold support files for scaffold-like tasks',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-scaffold',
        title: 'Scaffold the initial project files',
        targetFiles: ['ping_monitor.py'],
        notes: 'Create the first project skeleton and dependency files.',
        validationCommand: 'ls ping_monitor.py',
      );
      final toolResults = [
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: {'path': 'requirements.txt'},
          result:
              '{"path":"/tmp/project/requirements.txt","bytes_written":6,"created":true}',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'write_file',
          arguments: {'path': 'main.py'},
          result:
              '{"path":"/tmp/project/main.py","bytes_written":120,"created":true}',
        ),
      ];

      final assessment = ConversationPlanExecutionGuardrails.assessTaskDrift(
        task: task,
        toolResults: toolResults,
      );

      expect(assessment.hasDrift, isFalse);
      expect(assessment.unrelatedTouchedPaths, isEmpty);
    },
  );

  test(
    'extracts malformed file mutation failures when a target path exists',
    () {
      final toolResults = [
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: {'path': 'src/config_loader.py'},
          result: 'Error: invalid arguments',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'edit_file',
          arguments: {'path': 'tests/test_config_loader.py'},
          result: '{"error":"old_text must not be empty"}',
        ),
      ];

      expect(
        ConversationPlanExecutionGuardrails.hasMalformedFileMutationFailure(
          toolResults,
        ),
        isTrue,
      );
      expect(
        ConversationPlanExecutionGuardrails.malformedFileMutationPaths(
          toolResults,
        ),
        containsAll(<String>[
          'src/config_loader.py',
          'tests/test_config_loader.py',
        ]),
      );
    },
  );

  test(
    'assessTaskCompletion treats validation-only success as completion evidence',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_main_entrypoint_validation_success_replay.json',
      );
      final toolResults = loadFixtureToolResults(
        'plan_mode_ping_cli_main_entrypoint_validation_success_replay.json',
      );

      final assessment =
          ConversationPlanExecutionGuardrails.assessTaskCompletion(
            task: task,
            toolResults: toolResults,
          );

      expect(assessment.hasFailure, isFalse);
      expect(
        assessment.successfulValidationCommands,
        contains('python3 main.py --help'),
      );
      expect(assessment.completedFromSuccessfulValidation, isTrue);
      expect(assessment.shouldMarkCompleted, isTrue);
      expect(assessment.hasCompletionEvidenceIgnoringFailures, isTrue);
    },
  );
}
