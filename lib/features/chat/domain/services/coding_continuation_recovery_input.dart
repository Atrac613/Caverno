import 'immutable_json_snapshot.dart';

/// What [CodingContinuationRecoveryPolicy.recoveryCode] decides from.
/// [candidateResponse] is the raw response, reasoning included.
final class CodingContinuationRecoveryInput {
  CodingContinuationRecoveryInput({
    required this.candidateResponse,
    required List<Map<String, dynamic>> toolDefinitions,
    required this.owningTurnLatestUserText,
    required this.requireContinuationRequest,
    required this.isCodingWorkspaceOrMode,
    required this.hasPendingAutoContinueWorkflow,
    required this.saveSkillCompletedInGeneration,
    required this.acceptsTerminalToolRoleBlockerResponse,
    required this.bracketedToolRequestName,
    this.isProjectTaskTurn = false,
    this.reasoningOnlyRecoveryUsed = false,
  }) : toolDefinitions = List<Map<String, dynamic>>.unmodifiable(
         toolDefinitions.map(ImmutableJsonSnapshot.freezeMap),
       );

  final String candidateResponse;
  final List<Map<String, dynamic>> toolDefinitions;
  final String owningTurnLatestUserText;
  final bool requireContinuationRequest;
  final bool isCodingWorkspaceOrMode;
  final bool hasPendingAutoContinueWorkflow;
  final bool saveSkillCompletedInGeneration;
  final bool acceptsTerminalToolRoleBlockerResponse;
  final String? bracketedToolRequestName;

  /// A farm project-task turn, settled by a structured marker: prose recovery
  /// does not apply to it (see PrimaryTurnPurpose.projectTaskStep).
  final bool isProjectTaskTurn;

  /// Whether this turn already had its one reasoning-only stop recovery.
  final bool reasoningOnlyRecoveryUsed;
}
