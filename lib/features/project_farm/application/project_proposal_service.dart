import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../chat/domain/entities/coding_project.dart';
import '../../chat/domain/entities/model_usage_role.dart';
import '../data/roadmap_snapshot_repository.dart';
import '../domain/entities/project_proposal.dart';
import '../domain/entities/roadmap_snapshot.dart';
import '../domain/next_step_proposal_contract.dart';
import '../domain/roadmap_next_task_contract.dart';
import '../domain/roadmap_next_task_extractor.dart';

/// Keeps each project's next-step proposal current (FARM3 suggest mode).
///
/// Recomputes only when its input changes: the verified roadmap items, the
/// thread states, the contract version, or the model. Never polls; callers
/// refresh on a change or when the user asks.
final class ProjectProposalService {
  ProjectProposalService({
    required RoadmapSnapshotRepositoryApi repository,
    required RoadmapCompletionPort Function() complete,
    required String Function() model,
    DateTime Function()? now,
  }) : _repository = repository,
       _complete = complete,
       _model = model,
       _now = now ?? DateTime.now;

  final RoadmapSnapshotRepositoryApi _repository;
  final RoadmapCompletionPort Function() _complete;
  final String Function() _model;
  final DateTime Function() _now;

  ProjectProposal? cachedProposal(String projectId) =>
      _repository.proposalFor(projectId);

  /// Returns null when there is nothing to propose from: no snapshot, a failed
  /// one, or no verified item.
  Future<ProjectProposal?> refresh({
    required CodingProject project,
    required RoadmapSnapshot? snapshot,
    required List<ProposalThread> threads,
  }) async {
    final candidates = proposalCandidates(snapshot);
    if (candidates.isEmpty) return null;
    final input = nextStepProposalInput(
      projectName: project.name,
      candidates: candidates,
      threads: threads,
    );
    final model = _model();
    final hash = sha256
        .convert(utf8.encode('$nextStepProposalVersion|$model|$input'))
        .toString();
    final cached = _repository.proposalFor(project.id);
    if (cached != null && cached.inputHash == hash) return cached;

    ProjectProposal proposal;
    try {
      final completion = await ModelUsageRole.projectState.runWith(
        () => _complete()(
          system: nextStepProposalSystemPrompt,
          user: input,
          schemaName: 'caverno_next_step_proposal',
          schema: nextStepProposalSchema,
          maxTokens: 600,
        ),
      );
      final verified = verifyNextStepProposal(
        decodeJsonObject(completion.content),
        candidates,
      );
      proposal = verified == null
          ? ProjectProposal(
              projectId: project.id,
              inputHash: hash,
              proposedAt: _now(),
              error: 'The proposal did not name a listed roadmap item.',
            )
          : ProjectProposal(
              projectId: project.id,
              inputHash: hash,
              proposedAt: _now(),
              taskId: verified.taskId,
              taskTitle:
                  candidates
                      .where((c) => c.id == verified.taskId)
                      .firstOrNull
                      ?.title ??
                  '',
              rationale: verified.rationale,
              automatability: verified.automatability.name,
              automatabilityReason: verified.automatabilityReason,
            );
    } on Object catch (error) {
      proposal = ProjectProposal(
        projectId: project.id,
        inputHash: hash,
        proposedAt: _now(),
        error: '$error',
      );
    }
    await _repository.saveProposal(proposal);
    return proposal;
  }
}

/// The verified roadmap items a proposal may choose from.
List<ProposalCandidate> proposalCandidates(RoadmapSnapshot? snapshot) {
  if (snapshot == null || snapshot.status == RoadmapSnapshotStatus.failed) {
    return const [];
  }
  ProposalCandidate candidate(RoadmapItemSnapshot item, String status) =>
      ProposalCandidate(
        id: item.id,
        title: item.title,
        quote: item.quote,
        status: status,
      );
  final seen = <String>{};
  return [
    if (snapshot.recommended case final item? when item.verified)
      candidate(item, 'next'),
    for (final item in snapshot.current) candidate(item, 'in_progress'),
    for (final item in snapshot.blocked) candidate(item, 'blocked'),
  ].where((c) => c.id.isNotEmpty && seen.add(c.id)).toList(growable: false);
}
