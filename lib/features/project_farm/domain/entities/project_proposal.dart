import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_proposal.freezed.dart';
part 'project_proposal.g.dart';

/// The orchestrator's cached next-step proposal for one project (FARM3).
///
/// Advice, not authority: nothing starts without the user's Start work.
/// [inputHash] covers the roadmap items, thread states, contract version, and
/// model, so a proposal is recomputed only when one of them changes.
@freezed
abstract class ProjectProposal with _$ProjectProposal {
  const factory ProjectProposal({
    required String projectId,
    required String inputHash,
    required DateTime proposedAt,

    /// Empty when the orchestrator proposed starting nothing, or failed.
    @Default('') String taskId,
    @Default('') String taskTitle,
    @Default('') String rationale,

    /// `unattended` or `needsHuman`; empty when there is no proposal.
    @Default('') String automatability,
    @Default('') String automatabilityReason,
    String? error,
  }) = _ProjectProposal;

  factory ProjectProposal.fromJson(Map<String, dynamic> json) =>
      _$ProjectProposalFromJson(json);
}
