import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/anabasis_delegation_admission.dart';
import 'package:caverno/features/chat/domain/services/tool_failure_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 9);
  final done = ConversationWorkflowTask(
    id: 'done',
    title: 'Build CLI',
    status: ConversationWorkflowTaskStatus.completed,
  );
  final pending = ConversationWorkflowTask(
    id: 'tests',
    title: 'Test CLI',
    targetFiles: ['test_count_field.py'],
    validationCommand: 'python3 -m unittest',
  );
  Conversation plan(List<ConversationWorkflowTask> tasks) => Conversation(
    id: 'thread',
    title: 'CLI',
    messages: [],
    createdAt: now,
    updatedAt: now,
    workflowSpec: ConversationWorkflowSpec(tasks: tasks),
  );
  ToolCallInfo call(String? id) => ToolCallInfo(
    id: 'spawn',
    name: 'spawn_subagent',
    arguments: {'workflow_task_id': ?id},
  );
  test('completed or invented task cannot be recreated through delegation', () {
    for (final id in [null, 'done', 'invented']) {
      final result = AnabasisDelegationAdmission.prepare(
        call(id),
        isParent: true,
        conversation: plan([done, pending]),
        prompt: 'Recreate count_field.py',
      );
      expect(result.refusal, isNotNull);
      expect(
        const ToolFailureClassifier().classify(call(id), result.refusal!),
        ToolResultDisposition.approvalDenied,
      );
      expect(jsonDecode(result.refusal!.result)['ready_task_ids'], ['tests']);
    }
  });
  test(
    'empty ready queue refuses instead of falling back to freeform work',
    () {
      expect(
        AnabasisDelegationAdmission.prepare(
          call(null),
          isParent: true,
          conversation: plan([done]),
          prompt: 'Build CLI',
        ).refusal,
        isNotNull,
      );
    },
  );
  test(
    'ready task carries saved validation and file scope into child prompt',
    () {
      final result = AnabasisDelegationAdmission.prepare(
        call('tests'),
        isParent: true,
        conversation: plan([done, pending]),
        prompt: 'Write tests',
      );
      expect(result.refusal, isNull);
      expect(result.prompt, contains('python3 -m unittest'));
      expect(result.prompt, contains('test_count_field.py'));
    },
  );
  test('unmet dependencies and running tasks are refused', () {
    for (final task in [
      pending.copyWith(status: ConversationWorkflowTaskStatus.inProgress),
      pending.copyWith(
        preconditions: [
          ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.task,
            ref: 'missing',
          ),
        ],
      ),
    ]) {
      expect(
        AnabasisDelegationAdmission.prepare(
          call('tests'),
          isParent: true,
          conversation: plan([task]),
          prompt: 'Write tests',
        ).refusal,
        isNotNull,
      );
    }
  });
  test('ordinary delegation and unplanned parent remain available', () {
    expect(
      AnabasisDelegationAdmission.prepare(
        call(null),
        isParent: false,
        conversation: plan([done]),
        prompt: 'Research',
      ).refusal,
      isNull,
    );
    expect(
      AnabasisDelegationAdmission.prepare(
        call(null),
        isParent: true,
        conversation: plan([]),
        prompt: 'Research',
      ).refusal,
      isNull,
    );
    expect(
      AnabasisDelegationAdmission.prepare(
        call(null),
        isParent: true,
        conversation: null,
        prompt: 'Research',
      ).refusal,
      isNotNull,
    );
  });

  test('an admitted selection reports which saved task it bound to', () {
    // The binding has to leave the prompt and become a fact the finished child
    // carries: auditing a child against the task it was given is what ANA3
    // acceptance does, and prompt text cannot be audited.
    final admitted = AnabasisDelegationAdmission.prepare(
      call('tests'),
      isParent: true,
      conversation: plan([done, pending]),
      prompt: 'Run the suite',
    );
    expect(admitted.refusal, isNull);
    expect(admitted.workflowTaskId, 'tests');
  });

  test('every path that does not admit reports no binding', () {
    // A refusal, an unplanned parent and a child all have to say "no saved
    // task", or an unrelated child would be auditable against one.
    expect(
      AnabasisDelegationAdmission.prepare(
        call('invented'),
        isParent: true,
        conversation: plan([done, pending]),
        prompt: 'Recreate it',
      ).workflowTaskId,
      isEmpty,
    );
    expect(
      AnabasisDelegationAdmission.prepare(
        call(null),
        isParent: true,
        conversation: plan([]),
        prompt: 'Research',
      ).workflowTaskId,
      isEmpty,
    );
    expect(
      AnabasisDelegationAdmission.prepare(
        call('tests'),
        isParent: false,
        conversation: plan([done, pending]),
        prompt: 'Run the suite',
      ).workflowTaskId,
      isEmpty,
    );
  });
}
