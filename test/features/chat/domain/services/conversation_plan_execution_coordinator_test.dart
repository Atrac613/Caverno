import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_execution_coordinator.dart';

void main() {
  Map<String, dynamic> loadFixture(String fixtureName) {
    return jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
        as Map<String, dynamic>;
  }

  test('buildTaskPrompt keeps task metadata in execution prompt order', () {
    final prompt = ConversationPlanExecutionCoordinator.buildTaskPrompt(
      task: const ConversationWorkflowTask(
        id: 'task-1',
        title: 'Ship the next slice',
        targetFiles: ['lib/main.dart'],
        validationCommand: 'flutter test',
        notes: 'Keep the first cut narrow.',
      ),
      intro: 'Implement the saved task.',
      targetFilesLabel: 'Target files',
      validationLabel: 'Validation',
      notesLabel: 'Notes',
      outro: 'Reply with the implementation result.',
    );

    expect(prompt, contains('Implement the saved task.'));
    expect(prompt, contains('Saved task ID: task-1'));
    expect(prompt, contains('Target files: lib/main.dart'));
    expect(prompt, contains('Validation: flutter test'));
    expect(prompt, contains('Notes: Keep the first cut narrow.'));
    expect(
      prompt,
      contains(
        'Work only on this saved task. Do not implement future saved tasks.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not create or modify files outside the target files unless the saved validation step requires it.',
      ),
    );
    expect(
      prompt,
      contains(
        'Stop after the saved validation step and report that result before moving on.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not run the saved validation command until the current task target files exist and you have created or updated the relevant target file for this task.',
      ),
    );
    expect(prompt, contains('Reply with the implementation result.'));
  });

  test('buildBlockedTaskReplanContext preserves unrelated task ids', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Plan thread',
      messages: const <Message>[],
      createdAt: DateTime(2026, 4, 18, 14),
      updatedAt: DateTime(2026, 4, 18, 14, 5),
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Unblock the current task',
            status: ConversationWorkflowTaskStatus.blocked,
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Keep the next validation slice stable',
          ),
        ],
      ),
      executionProgress: const [
        ConversationExecutionTaskProgress(
          taskId: 'task-1',
          status: ConversationWorkflowTaskStatus.blocked,
          blockedReason: 'Validation is red.',
        ),
      ],
    );

    final context =
        ConversationPlanExecutionCoordinator.buildBlockedTaskReplanContext(
          conversation: conversation,
          task: conversation.projectedExecutionTasks.first,
          blockedReason: 'Validation is red.',
        );

    expect(context, contains('- blockedTask: Unblock the current task'));
    expect(context, contains('- blockedReason: Validation is red.'));
    expect(context, contains('- preserveTaskIds:'));
    expect(context, contains('task-2: Keep the next validation slice stable'));
  });

  test('buildAutoContinueTaskPrompt carries the next task metadata', () {
    const completedTask = ConversationWorkflowTask(
      id: 'task-1',
      title: 'Implement the ping utility',
    );
    const nextTask = ConversationWorkflowTask(
      id: 'task-2',
      title: 'Load the config file',
      targetFiles: ['src/config_loader.py', 'config/config.yaml'],
      validationCommand: 'pytest tests/test_config_loader.py',
      notes: 'Keep the initial loader synchronous.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildAutoContinueTaskPrompt(
          completedTask: completedTask,
          nextTask: nextTask,
        );

    expect(prompt, contains('Completed task ID: task-1'));
    expect(prompt, contains('Completed task: Implement the ping utility'));
    expect(prompt, contains('Next task ID: task-2'));
    expect(prompt, contains('Next task: Load the config file'));
    expect(
      prompt,
      contains('Target files: src/config_loader.py, config/config.yaml'),
    );
    expect(prompt, contains('Validation: pytest tests/test_config_loader.py'));
    expect(prompt, contains('Notes: Keep the initial loader synchronous.'));
    expect(
      prompt,
      contains(
        'Work only on this saved task. Do not implement future saved tasks.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not create or modify files outside the target files unless the saved validation step requires it.',
      ),
    );
    expect(
      prompt,
      contains(
        'Stop after the saved validation step and report that result before moving on.',
      ),
    );
    expect(
      prompt,
      contains(
        'Continue immediately with the next pending saved task without asking for confirmation.',
      ),
    );
    expect(
      prompt,
      contains(
        'Ignore the previous saved task context in the transcript and focus only on the next task below.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not continue the completed task again. Follow only the next task ID listed above.',
      ),
    );
    expect(
      prompt,
      contains(
        'Persisted saved task statuses from the app are the source of truth.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not mark any other saved task complete, blocked, skipped, or in progress unless this turn produces concrete evidence for the current task.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not run the saved validation command until the current task target files exist and you have created or updated the relevant target file for this task.',
      ),
    );
  });

  test('buildToolLessExecutionRecoveryPrompt forces a concrete next action', () {
    const task = ConversationWorkflowTask(
      id: 'task-2',
      title: 'Implement the YAML config loader',
      targetFiles: ['src/config_loader.py', 'tests/test_config_loader.py'],
      validationCommand: 'pytest tests/test_config_loader.py',
      notes: 'Parse the YAML host list only.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildToolLessExecutionRecoveryPrompt(
          task: task,
        );

    expect(
      prompt,
      contains(
        'The saved task stalled without any concrete tool call, file change, or validation result.',
      ),
    );
    expect(prompt, contains('Saved task ID: task-2'));
    expect(
      prompt,
      contains(
        'Your next reply must either modify one of the saved target files or run the saved validation command now.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not restate the plan, do not ask for confirmation, and do not describe future tasks.',
      ),
    );
  });

  test(
    'buildToolLessExecutionRecoveryPrompt prioritizes validation for scaffold tasks',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-setup',
        title: 'Initialize project structure',
        targetFiles: ['pyproject.toml', 'README.md', 'src/ping_cli/main.py'],
        validationCommand: 'ls src/ping_cli/main.py',
        notes: 'Create the initial scaffold files.',
      );

      final prompt =
          ConversationPlanExecutionCoordinator.buildToolLessExecutionRecoveryPrompt(
            task: task,
          );

      expect(
        prompt,
        contains(
          'If the scaffold files are already in place, run the saved validation command now instead of repeating the setup plan.',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not restate the scaffold steps or file list without a tool call or validation result.',
        ),
      );
      expect(
        prompt,
        contains(
          'Your next reply must either run the saved validation command now or modify one missing target file.',
        ),
      );
    },
  );

  test(
    'buildToolLessExecutionRecoveryPrompt infers target files from task titles when metadata is empty',
    () {
      final fixture = loadFixture(
        'plan_mode_ping_cli_main_py_execution_stall_replay.json',
      );
      final task = ConversationWorkflowTask.fromJson(
        fixture['task'] as Map<String, dynamic>,
      );

      final prompt =
          ConversationPlanExecutionCoordinator.buildToolLessExecutionRecoveryPrompt(
            task: task,
          );

      expect(
        prompt,
        contains(
          'Saved task: Implement core ping logic using subprocess in main.py',
        ),
      );
      expect(prompt, contains('Target files: main.py'));
      expect(prompt, contains('Validation: python3 main.py 8.8.8.8'));
      expect(
        prompt,
        contains(
          'Your next reply must either modify one of the saved target files or run the saved validation command now.',
        ),
      );
    },
  );

  test(
    'buildScaffoldRemainingTargetRecoveryPrompt prioritizes one missing target file',
    () {
      final fixture = loadFixture(
        'plan_mode_ping_cli_scaffold_partial_coverage_replay.json',
      );
      final task = ConversationWorkflowTask.fromJson(
        fixture['task'] as Map<String, dynamic>,
      );
      final existingTargetFiles =
          (fixture['existingTargetFiles'] as List<dynamic>).cast<String>();
      final missingTargetFiles =
          (fixture['missingTargetFiles'] as List<dynamic>).cast<String>();

      final prompt =
          ConversationPlanExecutionCoordinator.buildScaffoldRemainingTargetRecoveryPrompt(
            task: task,
            existingTargetFiles: existingTargetFiles,
            missingTargetFiles: missingTargetFiles,
          );

      expect(
        prompt,
        contains('Already created target files: pyproject.toml, README.md'),
      );
      expect(
        prompt,
        contains('Remaining target files: src/__init__.py, src/main.py'),
      );
      expect(
        prompt,
        contains(
          'Create exactly one remaining target file now instead of restating the scaffold plan.',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not rewrite already-created scaffold files unless the saved validation step later proves they are wrong.',
        ),
      );
      expect(
        prompt,
        contains(
          'After every remaining target file exists, run the saved validation command immediately.',
        ),
      );
    },
  );

  test('buildScaffoldMissingTargetRecoveryPrompt forces exact target recovery', () {
    const task = ConversationWorkflowTask(
      id: 'task-bootstrap',
      title: 'Initialize project structure',
      targetFiles: ['pyproject.toml', 'README.md', 'src/__init__.py'],
      validationCommand: 'ls -R',
      notes: 'Create the basic scaffold files only.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildScaffoldMissingTargetRecoveryPrompt(
          task: task,
          missingTargetFiles: const [
            'pyproject.toml',
            'README.md',
            'src/__init__.py',
          ],
        );

    expect(prompt, contains('Saved task ID: task-bootstrap'));
    expect(
      prompt,
      contains(
        'Create exactly one missing target file now using its saved path.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not create alternative filenames, test files, or extra scaffold files that are not listed in the saved targets.',
      ),
    );
    expect(
      prompt,
      contains('Do not run validation until every missing target file exists.'),
    );
  });

  test('buildValidationFirstRecoveryPrompt prioritizes saved validation', () {
    const task = ConversationWorkflowTask(
      id: 'task-validation-first',
      title: 'Implement the multi-host CLI flow',
      targetFiles: ['ping_cli.py', 'hosts.txt'],
      validationCommand: 'python3 ping_cli.py google.com hosts.txt',
      notes: 'Prefer the saved command over extra planning text.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildValidationFirstRecoveryPrompt(
          task: task,
          touchedTargetFiles: const ['ping_cli.py'],
          remainingTargetFiles: const ['hosts.txt'],
          preferValidationNow: true,
        );

    expect(
      prompt,
      contains('The saved task already made concrete file progress.'),
    );
    expect(prompt, contains('Saved task ID: task-validation-first'));
    expect(prompt, contains('Already updated target files: ping_cli.py'));
    expect(prompt, contains('Remaining target files: hosts.txt'));
    expect(
      prompt,
      contains(
        'Run the saved validation command now instead of restating the implementation plan.',
      ),
    );
    expect(
      prompt,
      contains(
        'Only return to file edits if the saved validation command fails and the failure points to a target file.',
      ),
    );
  });

  test('buildMissingTargetFileRecoveryPrompt requires file work before validation', () {
    const task = ConversationWorkflowTask(
      id: 'task-missing-target',
      title: 'Implement basic ping functionality in main.py',
      targetFiles: ['main.py'],
      validationCommand: 'python3 main.py 8.8.8.8',
      notes: 'Create the initial CLI entrypoint first.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildMissingTargetFileRecoveryPrompt(
          task: task,
          missingTargetFiles: const ['main.py'],
          failedCommand: 'python3 main.py 8.8.8.8',
        );

    expect(
      prompt,
      contains(
        'The saved validation command ran before every required target file existed.',
      ),
    );
    expect(prompt, contains('Missing target files: main.py'));
    expect(
      prompt,
      contains(
        'Create or edit one missing target file now before running the saved validation command again.',
      ),
    );
    expect(
      prompt,
      contains(
        'If you already tried to write the missing target file, confirm the exact saved path first by reading that file or listing its parent directory.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not rerun validation until the missing target files exist, and do not restate the plan without a tool call.',
      ),
    );
  });

  test(
    'buildMissingTargetFileRecoveryPrompt includes inferred target files from task text',
    () {
      final fixture = loadFixture(
        'plan_mode_ping_cli_src_ping_cli_missing_validation_replay.json',
      );
      final task = ConversationWorkflowTask.fromJson(
        fixture['task'] as Map<String, dynamic>,
      );

      final prompt =
          ConversationPlanExecutionCoordinator.buildMissingTargetFileRecoveryPrompt(
            task: task,
            missingTargetFiles: const ['src/ping_cli.py'],
            failedCommand: 'python3 src/ping_cli.py 8.8.8.8 -c 1',
          );

      expect(
        prompt,
        contains('Saved task: Implement ping logic and CLI in src/ping_cli.py'),
      );
      expect(prompt, contains('Target files: src/ping_cli.py'));
      expect(
        prompt,
        contains('Validation: python3 src/ping_cli.py 8.8.8.8 -c 1'),
      );
    },
  );

  test('buildPythonSrcLayoutValidationRecoveryPrompt retries with PYTHONPATH', () {
    const failedCommand =
        'python3 -c "from ping_cli.pinger import ping_host; print(ping_host(\'8.8.8.8\'))"';
    const retryCommand = 'PYTHONPATH=src $failedCommand';
    const task = ConversationWorkflowTask(
      id: 'task-src-layout',
      title: 'Implement core ping logic using subprocess',
      targetFiles: ['src/ping_cli/pinger.py'],
      validationCommand: failedCommand,
      notes: 'Keep the validation bounded to the saved command.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildPythonSrcLayoutValidationRecoveryPrompt(
          task: task,
          failedCommand: failedCommand,
          retryCommand: retryCommand,
          blockedModuleName: 'ping_cli',
        );

    expect(
      prompt,
      contains(
        'The saved validation command failed because the Python src-layout module import was not discoverable.',
      ),
    );
    expect(prompt, contains('Blocked module: ping_cli'));
    expect(prompt, contains('Retry validation command: $retryCommand'));
    expect(
      prompt,
      contains(
        'Run the retry validation command now before making any more file edits.',
      ),
    );
  });

  test('buildVerificationTaskRecoveryPrompt forces the saved verification command', () {
    const task = ConversationWorkflowTask(
      id: 'task-verify',
      title: 'Verify ping functionality with a real host',
      targetFiles: ['main.py'],
      validationCommand: 'python3 main.py 8.8.8.8',
      notes: 'Use a reachable host for the first end-to-end check.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildVerificationTaskRecoveryPrompt(
          task: task,
        );

    expect(
      prompt,
      contains(
        'The saved verification task stalled before running its concrete check.',
      ),
    );
    expect(prompt, contains('Saved task ID: task-verify'));
    expect(prompt, contains('Target files: main.py'));
    expect(
      prompt,
      contains('Saved validation command: python3 main.py 8.8.8.8'),
    );
    expect(
      prompt,
      contains(
        'Run the saved validation command now instead of restating the verification steps.',
      ),
    );
    expect(
      prompt,
      contains(
        'If the saved validation command fails, fix only the failing saved target file or report the blocker clearly.',
      ),
    );
    expect(
      prompt,
      contains(
        'accept any non-zero failure exit code instead of hard-coding one OS-specific non-zero code',
      ),
    );
  });

  test(
    'buildPythonTestDependencyRecoveryPrompt rewrites verification toward a stdlib fallback',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-verify-cli',
        title: 'Create a test script to verify the CLI functionality',
        targetFiles: ['tests/test_ping.py'],
        validationCommand: 'python3 -m pytest tests/test_ping.py',
        notes:
            'Verify that the script can successfully ping a known host like 8.8.8.8.',
      );

      final prompt =
          ConversationPlanExecutionCoordinator.buildPythonTestDependencyRecoveryPrompt(
            task: task,
            failedCommand: 'python3 -m pytest tests/test_ping.py',
            fallbackCommand: 'python3 tests/test_ping.py',
            missingDependency: 'pytest',
          );

      expect(
        prompt,
        contains(
          'The saved verification command failed because a Python test dependency is unavailable in the current environment.',
        ),
      );
      expect(prompt, contains('Saved task ID: task-verify-cli'));
      expect(prompt, contains('Missing dependency: pytest'));
      expect(
        prompt,
        contains('Fallback verification command: python3 tests/test_ping.py'),
      );
      expect(
        prompt,
        contains(
          'Rewrite the saved verification target so it runs with the Python standard library only and exits non-zero on failure.',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not add new external dependencies or switch tasks just to recover this verification step.',
        ),
      );
      expect(
        prompt,
        contains(
          'Run the fallback verification command now after updating the saved target file.',
        ),
      );
    },
  );

  test(
    'buildPythonRuntimeDependencyRecoveryPrompt keeps implementation recovery inside saved targets',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-main',
        title: 'Implement ping CLI in main.py',
        targetFiles: ['main.py'],
        validationCommand: 'python3 main.py --help',
        notes: 'Keep the entrypoint simple.',
      );

      final prompt =
          ConversationPlanExecutionCoordinator.buildPythonRuntimeDependencyRecoveryPrompt(
            task: task,
            failedCommand: 'python3 main.py --help',
            missingDependency: 'ping3',
          );

      expect(
        prompt,
        contains(
          'The saved validation command failed because the current Python implementation depends on a missing runtime module.',
        ),
      );
      expect(prompt, contains('Saved task ID: task-main'));
      expect(prompt, contains('Missing dependency: ping3'));
      expect(
        prompt,
        contains(
          'Recover by editing only the saved target files so the same validation command works in this environment.',
        ),
      );
      expect(
        prompt,
        contains(
          'Prefer Python standard-library or subprocess-based implementations for simple CLI tasks unless the user explicitly asked for a third-party package.',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not run pip install, do not ask for package installation, and do not modify dependency manifests unless they are saved target files for this task.',
        ),
      );
      expect(
        prompt,
        contains(
          'After the fix, rerun the same saved validation command immediately.',
        ),
      );
    },
  );

  test(
    'buildFailedValidationRecoveryPrompt focuses the next turn on fixing the target file',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-failed-validation',
        title: 'Implement ping_cli.py with subprocess and argparse',
        targetFiles: ['ping_cli.py'],
        validationCommand: 'python3 ping_cli.py --help',
        notes: 'Keep the command-line entrypoint small.',
      );

      final prompt =
          ConversationPlanExecutionCoordinator.buildFailedValidationRecoveryPrompt(
            task: task,
            failedCommand: 'python3 ping_cli.py --help',
            failedValidationSummary:
                'SyntaxError: invalid syntax in ping_cli.py',
          );

      expect(
        prompt,
        contains(
          'The saved validation command already failed for the current task.',
        ),
      );
      expect(prompt, contains('Saved task ID: task-failed-validation'));
      expect(prompt, contains('Target files: ping_cli.py'));
      expect(
        prompt,
        contains(
          'Use only tools that are currently available. Do not call unsupported placeholder tools such as print.',
        ),
      );
      expect(
        prompt,
        contains(
          'If the validation failure points to a saved target file, fix only that saved target file now.',
        ),
      );
      expect(
        prompt,
        contains(
          'After the fix, rerun the same saved validation command immediately.',
        ),
      );
    },
  );

  test(
    'buildToolFailureRecoveryPrompt bounds unknown tools, malformed writes, and edit mismatch',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-2',
        title: 'Implement the YAML config loader',
        targetFiles: ['src/config_loader.py', 'tests/test_config_loader.py'],
        validationCommand: 'pytest tests/test_config_loader.py',
        notes: 'Parse the YAML host list only.',
      );

      final prompt =
          ConversationPlanExecutionCoordinator.buildToolFailureRecoveryPrompt(
            task: task,
            unavailableToolNames: const ['google', 'print'],
            editMismatchPaths: const ['src/config_loader.py'],
            malformedFileMutationPaths: const ['tests/test_config_loader.py'],
            hasMalformedFileMutationFailure: true,
          );

      expect(
        prompt,
        contains('The saved task hit a recoverable tool failure.'),
      );
      expect(
        prompt,
        contains('Do not call these unavailable tools again: google, print'),
      );
      expect(
        prompt,
        contains('These files failed with edit mismatch: src/config_loader.py'),
      );
      expect(
        prompt,
        contains(
          'Read each mismatched file before retrying edit_file and use the exact current file content as old_text.',
        ),
      );
      expect(
        prompt,
        contains(
          'These file mutations failed because required arguments were malformed: tests/test_config_loader.py',
        ),
      );
      expect(
        prompt,
        contains(
          'Retry the same file mutation with top-level path and content keys for write_file, or path plus old_text and new_text for edit_file.',
        ),
      );
      expect(
        prompt,
        contains(
          'If an edit_file call failed because old_text was missing or empty, read the current file first and reuse its exact contents as old_text.',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not wrap file arguments in malformed aliases or move path outside the arguments object.',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not switch to unrelated files, do not retry unavailable tools, and do not move to future saved tasks.',
        ),
      );
    },
  );

  test('buildEditMismatchRetryPrompt requires a direct edit retry', () {
    const task = ConversationWorkflowTask(
      id: 'task-edit-retry',
      title: 'Implement core ping functionality using subprocess',
      targetFiles: ['ping_logic.py'],
      validationCommand: 'python3 ping_logic.py 8.8.8.8',
      notes: 'Keep the retry bounded to the current file.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildEditMismatchRetryPrompt(
          task: task,
          editMismatchPaths: const ['ping_logic.py'],
        );

    expect(prompt, contains('Saved task ID: task-edit-retry'));
    expect(prompt, contains('Mismatched files: ping_logic.py'));
    expect(
      prompt,
      contains(
        'Retry edit_file now on one mismatched saved target file using the exact current file contents as old_text.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not stop after another read_file, do not restate the plan, and do not move to future saved tasks.',
      ),
    );
  });

  test('buildTaskDriftRecoveryPrompt re-anchors the saved task', () {
    const task = ConversationWorkflowTask(
      id: 'task-2',
      title: 'Implement the YAML config loader',
      targetFiles: ['src/config_loader.py', 'tests/test_config_loader.py'],
      validationCommand: 'pytest tests/test_config_loader.py',
      notes: 'Parse the YAML host list only.',
    );

    final prompt =
        ConversationPlanExecutionCoordinator.buildTaskDriftRecoveryPrompt(
          task: task,
          unrelatedTouchedPaths: const ['pyproject.toml'],
          scaffoldCommands: const ['mkdir -p live_ping_cli'],
          alreadyTouchedTargetFiles: const ['src/config_loader.py'],
          repeatedTargetFiles: const ['src/config_loader.py'],
          remainingTargetFiles: const ['tests/test_config_loader.py'],
        );

    expect(prompt, contains('Saved task drift detected.'));
    expect(prompt, contains('Saved task: Implement the YAML config loader'));
    expect(
      prompt,
      contains(
        'Only touch these target files next: src/config_loader.py, tests/test_config_loader.py',
      ),
    );
    expect(prompt, contains('Ignore these unrelated paths: pyproject.toml'));
    expect(
      prompt,
      contains('You already updated these target files: src/config_loader.py'),
    );
    expect(
      prompt,
      contains(
        'Do not rewrite these target files again unless validation fails: src/config_loader.py',
      ),
    );
    expect(prompt, contains('Stop rewriting already-covered files.'));
    expect(
      prompt,
      contains(
        'Focus on the remaining target files next: tests/test_config_loader.py',
      ),
    );
    expect(
      prompt,
      contains(
        'Finish the remaining target files before making any other edits.',
      ),
    );
    expect(
      prompt,
      contains(
        'Ignore this unrelated scaffolding command: mkdir -p live_ping_cli',
      ),
    );
    expect(
      prompt,
      contains(
        'Your next action must directly modify one of the remaining target files or run the saved validation command.',
      ),
    );
    expect(
      prompt,
      contains(
        'If every target file is already covered, run the saved validation command now instead of rewriting files.',
      ),
    );
    expect(
      prompt,
      contains(
        'Do not implement future saved tasks while recovering this task.',
      ),
    );
  });

  test(
    'buildTaskDriftRecoveryPrompt shows inferred targets from validation commands',
    () {
      const task = ConversationWorkflowTask(
        id: 'task-ping-cli',
        title: 'Implement ping CLI script',
        targetFiles: [],
        validationCommand: 'python3 ping_cli.py --help',
        notes:
            'Implement the core logic using argparse to accept a host argument.',
      );

      final prompt =
          ConversationPlanExecutionCoordinator.buildTaskDriftRecoveryPrompt(
            task: task,
            unrelatedTouchedPaths: const ['src/ping_cli.py'],
            scaffoldCommands: const [],
          );

      expect(prompt, contains('Saved task: Implement ping CLI script'));
      expect(
        prompt,
        contains('Only touch these target files next: ping_cli.py'),
      );
      expect(
        prompt,
        contains('Saved validation command: python3 ping_cli.py --help'),
      );
    },
  );

  test('validationTask prefers the active task before the pending queue', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Plan thread',
      messages: const <Message>[],
      createdAt: DateTime(2026, 4, 18, 15),
      updatedAt: DateTime(2026, 4, 18, 15, 5),
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Keep implementing',
            status: ConversationWorkflowTaskStatus.inProgress,
            validationCommand: 'flutter test',
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Next task',
            validationCommand: 'dart test',
          ),
        ],
      ),
    );

    final validationTask = ConversationPlanExecutionCoordinator.validationTask(
      conversation,
    );

    expect(validationTask?.id, 'task-1');
  });

  test('executionFocusTask prefers blocked tasks over pending tasks', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Plan thread',
      messages: const <Message>[],
      createdAt: DateTime(2026, 4, 19, 9),
      updatedAt: DateTime(2026, 4, 19, 9, 5),
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Recover the blocked implementation',
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Implement the later follow-up',
          ),
        ],
      ),
      executionProgress: const [
        ConversationExecutionTaskProgress(
          taskId: 'task-1',
          status: ConversationWorkflowTaskStatus.blocked,
          blockedReason: 'Waiting for a fix.',
        ),
      ],
    );

    final focusTask = ConversationPlanExecutionCoordinator.executionFocusTask(
      conversation,
    );

    expect(focusTask?.id, 'task-1');
  });
}
