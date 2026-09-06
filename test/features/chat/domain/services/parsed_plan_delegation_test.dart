import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_projector.dart';
import 'package:caverno/features/chat/domain/services/task_delegation_brief_builder.dart';
import 'package:caverno/features/chat/domain/services/task_proposal_parser.dart';
import 'package:caverno/features/chat/domain/services/workflow_task_proposal_quality_service.dart';

const _dependency = 'Inspect the JSONL schema';
const _implementation = 'Implement the JSONL counter';
const _premise = 'Existing records have stable UUIDs';

Conversation _parsedPlan({
  bool completed = false,
  bool verified = false,
  bool confirmed = true,
  bool duplicateTitle = false,
}) {
  // Use production UUID generation: the model cannot know those ids when
  // writing the proposal, so its references must survive as human text.
  final parser = TaskProposalParser(
    qualityService: WorkflowTaskProposalQualityService(),
  );
  final proposal = parser.parse(
    jsonEncode({
      'tasks': [
        {
          'title': _dependency,
          'validationCommand': 'dart test test/schema_test.dart',
        },
        if (duplicateTitle) {'title': 'Inspect the archive format'},
        {
          'title': _implementation,
          'targetFiles': ['lib/jsonl_counter.dart'],
          'preconditions': [
            {'kind': 'task', 'ref': _dependency},
            {'kind': 'assumption', 'ref': _premise},
          ],
        },
      ],
    }),
  );
  expect(proposal, isNotNull);
  final tasks = proposal!.tasks.toList();
  if (duplicateTitle) {
    // The parser deduplicates titles. Model ambiguity introduced by a later
    // plan edit while retaining the generated ids and parsed references.
    expect(tasks, hasLength(3));
    tasks[1] = tasks[1].copyWith(title: _dependency);
  }
  expect(tasks.first.id, isNot(_dependency));
  expect(tasks.last.preconditions.map((edge) => edge.ref), [
    _dependency,
    _premise,
  ]);
  const provenance = ConversationContractProvenanceService();
  return Conversation(
    id: 'parsed-plan',
    messages: const [],
    title: 'Count JSONL records',
    createdAt: DateTime(2026, 9, 5),
    updatedAt: DateTime(2026, 9, 5),
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: ConversationWorkflowSpec(
      goal: 'Count JSONL records',
      constraints: const [_premise],
      tasks: tasks,
      provenance: [
        ConversationContractItemProvenance(
          itemId: provenance.itemId(
            kind: ConversationContractItemKind.constraint,
            value: _premise,
          ),
          kind: ConversationContractItemKind.constraint,
          assumption: true,
          material: true,
          confirmed: confirmed,
        ),
      ],
    ),
    executionProgress: [
      ConversationExecutionTaskProgress(
        taskId: tasks.first.id,
        status: completed
            ? ConversationWorkflowTaskStatus.completed
            : ConversationWorkflowTaskStatus.inProgress,
        validationStatus: verified
            ? ConversationExecutionValidationStatus.passed
            : ConversationExecutionValidationStatus.unknown,
      ),
    ],
  );
}

void main() {
  const projector = ExecutionSnapshotProjector();
  const builder = TaskDelegationBriefBuilder();

  test('parsed references unlock the queue only after verified completion', () {
    final running = _parsedPlan();
    final unverified = _parsedPlan(completed: true);
    for (final plan in [running, unverified]) {
      expect(builder.candidates(plan), isEmpty);
      expect(projector.project(plan).delegatableTasks, isEmpty);
      expect(
        projector.project(plan).waitingTasks.join('\n'),
        contains(_implementation),
      );
    }

    final ready = _parsedPlan(completed: true, verified: true);
    final brief = builder.candidates(ready).single;
    expect(brief.task.title, _implementation);
    expect(brief.premises, [_premise]);
    expect(brief.runner, TaskDelegationRunner.worktree);
    final snapshot = projector.project(ready);
    expect(snapshot.waitingTasks, isEmpty);
    expect(snapshot.delegatableTasks.single, contains(_implementation));
    expect(snapshot.delegatableTasks.single, contains(_premise));
    expect(snapshot.completedTaskCount, 1);
  });

  test('unconfirmed text premise excludes the parsed dependent task', () {
    final plan = _parsedPlan(completed: true, verified: true, confirmed: false);
    expect(builder.candidates(plan), isEmpty);
    expect(projector.project(plan).delegatableTasks, isEmpty);
    expect(projector.project(plan).waitingTasks.join('\n'), contains(_premise));
  });

  test(
    'a later ambiguous title edit never unlocks the parsed dependent task',
    () {
      final plan = _parsedPlan(
        completed: true,
        verified: true,
        duplicateTitle: true,
      );
      expect(
        builder.candidates(plan).map((brief) => brief.task.title),
        isNot(contains(_implementation)),
      );
      expect(
        projector.project(plan).delegatableTasks.join('\n'),
        isNot(contains(_implementation)),
      );
      expect(
        projector.project(plan).waitingTasks.join('\n'),
        contains(_implementation),
      );
    },
  );
}
