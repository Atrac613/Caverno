import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_approved_repair_task_adapter.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_objective_continuation_policy.dart';
import 'package:caverno/features/maintenance/presentation/providers/ll37_approved_repair_task_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = Ll37ApprovedRepairTaskAdapter();

  test('builds one stable LL13 request without mutating the source', () {
    final source = _sourceTask();
    final before = source.toJson();

    final first = adapter.review(
      continuation: _continuation(),
      sourceTask: source,
    );
    final reordered = adapter.review(
      continuation: _continuation(gaps: _gaps().reversed.toList()),
      sourceTask: source,
    );

    expect(first.status, Ll37ApprovedRepairTaskStatus.ready);
    expect(first.spec!.assignmentId, reordered.spec!.assignmentId);
    expect(first.spec!.assignmentId, startsWith('ll37-repair-'));
    expect(first.spec!.sourceTaskId, source.id);
    expect(first.spec!.baseBranch, source.branchName);
    expect(first.spec!.branchPrefix, 'feature/ll37-repair-');
    expect(first.spec!.prompt, _continuation().repairNudge);
    expect(first.spec!.verificationCommand, source.verificationCommand);
    expect(first.spec!.objectiveAcceptanceCriteria, ['The flag is true.']);
    expect(source.toJson(), before);
  });

  test('suppresses a duplicate stable assignment', () {
    final ready = adapter.review(
      continuation: _continuation(),
      sourceTask: _sourceTask(),
    );

    final duplicate = adapter.review(
      continuation: _continuation(),
      sourceTask: _sourceTask(),
      existingTaskIds: [ready.spec!.assignmentId],
    );

    expect(duplicate.status, Ll37ApprovedRepairTaskStatus.alreadyQueued);
    expect(duplicate.canQueue, isFalse);
    expect(duplicate.spec, isNull);
  });

  test('maps every frozen field into the existing LL13 launcher request', () {
    final approved = adapter.review(
      continuation: _continuation(),
      sourceTask: _sourceTask(),
    );

    final request = ll37ApprovedRepairTaskLaunchRequest(approved.spec!);

    expect(request.assignmentId, approved.spec!.assignmentId);
    expect(request.title, approved.spec!.title);
    expect(request.prompt, approved.spec!.prompt);
    expect(request.codingProjectId, approved.spec!.codingProjectId);
    expect(request.baseBranch, approved.spec!.baseBranch);
    expect(request.branchPrefix, approved.spec!.branchPrefix);
    expect(request.checkpointLineageId, approved.spec!.checkpointLineageId);
    expect(request.endpointId, approved.spec!.endpointId);
    expect(request.verificationCommand, approved.spec!.verificationCommand);
    expect(
      request.objectiveAcceptanceCriteria,
      approved.spec!.objectiveAcceptanceCriteria,
    );
  });

  test('fails closed for source identity and contract drift', () {
    final source = _sourceTask();
    final cases =
        <({Ll37ObjectiveContinuationReview review, WorktreeAgentTask? task})>[
          (
            review: _continuation(candidateId: 'worktree-agent:other'),
            task: source,
          ),
          (
            review: _continuation(objective: 'Different objective.'),
            task: source,
          ),
          (
            review: _continuation(criteria: const ['Different criterion.']),
            task: source,
          ),
          (review: _continuation(), task: null),
          (
            review: _continuation(),
            task: source.copyWith(status: WorktreeAgentTaskStatus.running),
          ),
          (
            review: _continuation(),
            task: source.copyWith(verifiedGreen: false),
          ),
          (review: _continuation(), task: source.copyWith(codingProjectId: '')),
          (review: _continuation(), task: source.copyWith(branchName: '')),
          (
            review: _continuation(),
            task: source.copyWith(verificationCommand: ''),
          ),
        ];

    for (final item in cases) {
      final result = adapter.review(
        continuation: item.review,
        sourceTask: item.task,
      );
      expect(result.status, Ll37ApprovedRepairTaskStatus.ineligible);
      expect(result.canQueue, isFalse);
    }
  });

  test('rejects a result that is not a reviewed repair packet', () {
    final result = adapter.review(
      continuation: Ll37ObjectiveContinuationReview(
        status: Ll37ObjectiveContinuationStatus.userDecisionRequired,
        candidateId: 'worktree-agent:task-1',
        objective: 'Set the feature flag.',
        acceptanceCriteria: const ['The flag is true.'],
        gaps: const [],
        detail: 'User decision required.',
      ),
      sourceTask: _sourceTask(),
    );

    expect(result.status, Ll37ApprovedRepairTaskStatus.ineligible);
  });
}

WorktreeAgentTask _sourceTask() => WorktreeAgentTask(
  id: 'task-1',
  status: WorktreeAgentTaskStatus.completed,
  title: 'Enable the feature flag',
  prompt: 'Set the feature flag.',
  codingProjectId: 'project-1',
  baseBranch: 'main',
  branchName: 'feature/source-task',
  worktreePath: '/tmp/source-task',
  checkpointLineageId: 'checkpoint-1',
  endpointId: 'mesh-1',
  verificationCommand: 'dart test',
  objectiveAcceptanceCriteria: const ['The flag is true.'],
  createdAt: DateTime.utc(2026, 8, 13),
  updatedAt: DateTime.utc(2026, 8, 13, 1),
  finishedAt: DateTime.utc(2026, 8, 13, 1),
  verifiedGreen: true,
);

Ll37ObjectiveContinuationReview _continuation({
  String candidateId = 'worktree-agent:task-1',
  String objective = 'Set the feature flag.',
  List<String> criteria = const ['The flag is true.'],
  List<Ll37ObjectiveContinuationGap>? gaps,
}) => Ll37ObjectiveContinuationReview(
  status: Ll37ObjectiveContinuationStatus.repairReview,
  candidateId: candidateId,
  objective: objective,
  acceptanceCriteria: criteria,
  gaps: gaps ?? _gaps(),
  detail: 'Review the repair.',
  repairNudge: 'Frozen repair packet.',
);

List<Ll37ObjectiveContinuationGap> _gaps() => const [
  Ll37ObjectiveContinuationGap(
    id: 'll37-gap-b',
    kind: 'unmet_criterion',
    location: 'config.json',
    detail: 'The flag is false.',
  ),
  Ll37ObjectiveContinuationGap(
    id: 'll37-gap-a',
    kind: 'verification_failure',
    location: 'verification',
    detail: 'The behavior check failed.',
  ),
];
