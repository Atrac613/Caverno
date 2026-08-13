import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../chat/domain/entities/worktree_agent_task.dart';
import 'll37_objective_continuation_policy.dart';

enum Ll37ApprovedRepairTaskStatus { ready, ineligible, alreadyQueued }

class Ll37ApprovedRepairTaskSpec {
  Ll37ApprovedRepairTaskSpec({
    required this.assignmentId,
    required this.sourceTaskId,
    required this.title,
    required this.prompt,
    required this.codingProjectId,
    required this.baseBranch,
    required this.branchPrefix,
    required this.checkpointLineageId,
    required this.endpointId,
    required this.verificationCommand,
    required List<String> objectiveAcceptanceCriteria,
  }) : objectiveAcceptanceCriteria = List.unmodifiable(
         objectiveAcceptanceCriteria,
       );

  final String assignmentId;
  final String sourceTaskId;
  final String title;
  final String prompt;
  final String codingProjectId;
  final String baseBranch;
  final String branchPrefix;
  final String checkpointLineageId;
  final String endpointId;
  final String verificationCommand;
  final List<String> objectiveAcceptanceCriteria;
}

class Ll37ApprovedRepairTaskReview {
  const Ll37ApprovedRepairTaskReview({
    required this.status,
    required this.detail,
    this.spec,
  });

  final Ll37ApprovedRepairTaskStatus status;
  final String detail;
  final Ll37ApprovedRepairTaskSpec? spec;

  bool get canQueue =>
      status == Ll37ApprovedRepairTaskStatus.ready && spec != null;
}

/// Validates a reviewed LL37 packet before it can enter the LL13 queue path.
class Ll37ApprovedRepairTaskAdapter {
  const Ll37ApprovedRepairTaskAdapter();

  static const branchPrefix = 'feature/ll37-repair-';
  static const _candidatePrefix = 'worktree-agent:';

  Ll37ApprovedRepairTaskReview review({
    required Ll37ObjectiveContinuationReview continuation,
    required WorktreeAgentTask? sourceTask,
    Iterable<String> existingTaskIds = const [],
  }) {
    if (!continuation.canCopyRepairNudge || continuation.gaps.isEmpty) {
      return const Ll37ApprovedRepairTaskReview(
        status: Ll37ApprovedRepairTaskStatus.ineligible,
        detail: 'The LL37 result does not contain a reviewed repair packet.',
      );
    }
    if (sourceTask == null ||
        continuation.candidateId !=
            '$_candidatePrefix${sourceTask.id.trim()}') {
      return const Ll37ApprovedRepairTaskReview(
        status: Ll37ApprovedRepairTaskStatus.ineligible,
        detail: 'The completed LL13 source task could not be matched.',
      );
    }
    final objective = _contractText(sourceTask.prompt);
    final criteria = sourceTask.objectiveAcceptanceCriteria
        .map(_contractText)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final reviewedCriteria = continuation.acceptanceCriteria
        .map(_contractText)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final codingProjectId = sourceTask.codingProjectId.trim();
    final sourceBranch = sourceTask.branchName.trim();
    final verificationCommand = sourceTask.verificationCommand.trim();
    if (sourceTask.status != WorktreeAgentTaskStatus.completed ||
        !sourceTask.verifiedGreen ||
        objective.isEmpty ||
        objective != _contractText(continuation.objective) ||
        !_sameOrdered(criteria, reviewedCriteria) ||
        codingProjectId.isEmpty ||
        sourceBranch.isEmpty ||
        verificationCommand.isEmpty) {
      return const Ll37ApprovedRepairTaskReview(
        status: Ll37ApprovedRepairTaskStatus.ineligible,
        detail: 'The LL13 source task no longer matches the frozen contract.',
      );
    }

    final gapIds = continuation.gaps.map((gap) => gap.id.trim()).toList()
      ..sort();
    if (gapIds.any((id) => id.isEmpty)) {
      return const Ll37ApprovedRepairTaskReview(
        status: Ll37ApprovedRepairTaskStatus.ineligible,
        detail: 'The reviewed packet contains an invalid gap identity.',
      );
    }
    final assignmentId = _assignmentId(
      candidateId: continuation.candidateId,
      objective: objective,
      criteria: criteria,
      gapIds: gapIds,
    );
    final existingIds = existingTaskIds.map((id) => id.trim()).toSet();
    if (existingIds.contains(assignmentId)) {
      return Ll37ApprovedRepairTaskReview(
        status: Ll37ApprovedRepairTaskStatus.alreadyQueued,
        detail: 'Repair task $assignmentId is already registered.',
      );
    }
    final sourceTitle = sourceTask.title.trim();
    return Ll37ApprovedRepairTaskReview(
      status: Ll37ApprovedRepairTaskStatus.ready,
      detail: 'The reviewed packet is ready for explicit LL13 queue approval.',
      spec: Ll37ApprovedRepairTaskSpec(
        assignmentId: assignmentId,
        sourceTaskId: sourceTask.id.trim(),
        title:
            'Repair LL37 gaps: '
            '${sourceTitle.isEmpty ? sourceTask.id.trim() : sourceTitle}',
        prompt: continuation.repairNudge!,
        codingProjectId: codingProjectId,
        baseBranch: sourceBranch,
        branchPrefix: branchPrefix,
        checkpointLineageId: sourceTask.checkpointLineageId.trim(),
        endpointId: sourceTask.endpointId.trim(),
        verificationCommand: verificationCommand,
        objectiveAcceptanceCriteria: criteria,
      ),
    );
  }

  String _assignmentId({
    required String candidateId,
    required String objective,
    required List<String> criteria,
    required List<String> gapIds,
  }) {
    final payload = jsonEncode({
      'candidateId': candidateId.trim(),
      'objective': objective,
      'acceptanceCriteria': criteria,
      'gapIds': gapIds,
    });
    final digest = sha256.convert(utf8.encode(payload)).toString();
    return 'll37-repair-${digest.substring(0, 16)}';
  }

  bool _sameOrdered(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  String _contractText(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
