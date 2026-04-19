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
}
