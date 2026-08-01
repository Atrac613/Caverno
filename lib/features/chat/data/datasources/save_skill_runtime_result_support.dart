import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/save_skill_tool_contract.dart';
import 'save_skill_runtime_contract.dart';

const saveSkillUncertainBoundaryMessage =
    'The skill may have been saved; inspect the skill catalog before retrying';

int saveSkillRuntimeDispositionPriority(
  SaveSkillRuntimeDisposition? disposition,
) => switch (disposition) {
  null || SaveSkillRuntimeDisposition.completed => 0,
  SaveSkillRuntimeDisposition.rejected => 1,
  SaveSkillRuntimeDisposition.ownerExpired => 2,
  SaveSkillRuntimeDisposition.effectUncertain => 3,
  SaveSkillRuntimeDisposition.boundaryMismatch => 4,
};

McpToolResult saveSkillRuntimeFailure(String message) => McpToolResult(
  toolName: canonicalSaveSkillToolName,
  result: '',
  isSuccess: false,
  errorMessage: message,
);

SaveSkillRuntimeDisposition classifySaveSkillRuntimeResult({
  required SaveSkillRuntimeDisposition? observed,
  required McpToolResult result,
}) =>
    observed ??
    (result.isSuccess
        ? SaveSkillRuntimeDisposition.completed
        : SaveSkillRuntimeDisposition.rejected);

McpToolResult saveSkillRuntimeBoundaryFailure({
  required bool writeDispatched,
  required SaveSkillRuntimeDisposition? observed,
  required Object error,
}) {
  final uncertain =
      writeDispatched ||
      observed == SaveSkillRuntimeDisposition.effectUncertain;
  return saveSkillRuntimeFailure(
    uncertain
        ? saveSkillUncertainBoundaryMessage
        : 'Skill save boundary failed: $error',
  );
}
