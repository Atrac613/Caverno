import 'dart:convert';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/services/task_acceptance_decision.dart';
import 'package:flutter_test/flutter_test.dart';

const _decisions = TaskAcceptanceDecisionService();

Conversation _conversation({
  String taskId = 'task-1',
  String validationCommand = 'dart test',
  String lastValidationCommand = '',
}) => Conversation(
  id: 'conversation-1',
  title: 'Plan thread',
  messages: const <Message>[],
  createdAt: DateTime(2026, 9, 13),
  updatedAt: DateTime(2026, 9, 13),
  workspaceMode: WorkspaceMode.coding,
  projectId: 'project-1',
  workflowStage: ConversationWorkflowStage.implement,
  workflowSpec: ConversationWorkflowSpec(
    tasks: [
      ConversationWorkflowTask(
        id: taskId,
        title: 'Read the spec',
        validationCommand: validationCommand,
        status: ConversationWorkflowTaskStatus.completed,
      ),
    ],
  ),
  executionProgress: [
    if (lastValidationCommand.isNotEmpty)
      ConversationExecutionTaskProgress(
        taskId: taskId,
        status: ConversationWorkflowTaskStatus.completed,
        lastValidationCommand: lastValidationCommand,
      ),
  ],
);

SubagentTask _child({
  String workflowTaskId = 'task-1',
  String resultSummary = 'The spec lists add, list, done and delete.',
}) => SubagentTask(
  id: 'child-1',
  conversationId: 'conversation-1',
  interactionGeneration: 1,
  status: SubagentTaskStatus.completed,
  description: 'Read the spec',
  workflowTaskId: workflowTaskId,
  resultSummary: resultSummary,
);

String _code(TaskAcceptanceDecision decision) {
  final refusal = decision as TaskAcceptanceRefusal;
  return (jsonDecode(refusal.result.result) as Map)['code'] as String;
}

TaskAcceptanceDecision _decide({
  bool isParentTurn = true,
  Conversation? conversation,
  String taskId = 'task-1',
  String rationale = 'The child read the spec and the commands match.',
  List<SubagentTask>? children,
}) => _decisions.decide(
  toolName: 'accept_task',
  isParentTurn: isParentTurn,
  conversation: conversation ?? _conversation(),
  taskId: taskId,
  rationale: rationale,
  childrenForConversation: children ?? [_child()],
);

void main() {
  // The order is behaviour: a non-parent learns nothing about the plan, an
  // unknown id is answered with the ids that exist, and the audit runs last
  // because it is the only ground that depends on what a child did.
  test('a child may not grade its own work', () {
    expect(_code(_decide(isParentTurn: false)), 'acceptance_not_parent');
  });

  test('an unknown id is answered with the ids that exist', () {
    final decision = _decide(taskId: 'not-a-task');
    expect(_code(decision), 'acceptance_unknown_task');
    expect(
      (jsonDecode((decision as TaskAcceptanceRefusal).result.result)
          as Map)['known_task_ids'],
      ['task-1'],
    );
  });

  test('an acceptance without a reason records nothing', () {
    expect(_code(_decide(rationale: '  ')), 'acceptance_rationale_missing');
  });

  test('nothing delegated means nothing to accept on', () {
    expect(
      _code(_decide(children: const [])),
      'acceptance_no_delegated_result',
    );
    expect(
      _code(_decide(children: [_child(workflowTaskId: 'other-task')])),
      'acceptance_no_delegated_result',
      reason: 'A child bound to another task is not this task\'s evidence.',
    );
  });

  test('a child that reported nothing leaves a level outstanding', () {
    final decision = _decide(children: [_child(resultSummary: '')]);
    expect(_code(decision), 'acceptance_levels_outstanding');
    expect(
      (jsonDecode((decision as TaskAcceptanceRefusal).result.result)
          as Map)['outstanding'],
      contains('evidence'),
    );
  });

  test('an admitted child with a summary yields the contract to write', () {
    final decision =
        _decide(
              conversation: _conversation(lastValidationCommand: 'dart test'),
            )
            as TaskAcceptanceContract;

    expect(decision.task.id, 'task-1');
    expect(decision.evidence, ['dart test', 'child summary recorded']);
  });

  test('the success and write-failure payloads keep their shapes', () {
    final contract = _decide() as TaskAcceptanceContract;

    expect(
      jsonDecode(_decisions.accepted('accept_task', contract).result),
      containsPair('accepted_task_id', 'task-1'),
    );
    expect(
      jsonDecode(_decisions.writeFailed('accept_task').result),
      containsPair('code', 'acceptance_write_failed'),
    );
  });
}
