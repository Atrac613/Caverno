import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_execution_guardrails.dart';

void main() {
  test('assessTaskDrift flags scaffolding replay fixture as drift', () {
    final fixture = jsonDecode(
          File(
            'test/fixtures/plan_mode_ping_cli_execution_stall_replay.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
    final task = ConversationWorkflowTask.fromJson(
      fixture['task'] as Map<String, dynamic>,
    );
    final toolResults = (fixture['toolResults'] as List<dynamic>)
        .map(
          (item) => item as Map<String, dynamic>,
        )
        .map(
          (item) => ToolResultInfo(
            id: item['id'] as String,
            name: item['name'] as String,
            arguments: item['arguments'] as Map<String, dynamic>,
            result: item['result'] as String,
          ),
        )
        .toList(growable: false);

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
}
