import '../entities/tool_call_info.dart';
import 'coding/coding_continuation_recovery_policy.dart';
import 'tool_definition_search_service.dart';

/// Selects the parent's delegation recovery without widening other turns.
final class TurnFinalizationDelegationRecovery {
  const TurnFinalizationDelegationRecovery();

  bool pending({
    required bool isParentTurn,
    required String response,
    required List<ToolResultInfo> completedResults,
  }) =>
      isParentTurn &&
      !completedResults.any((result) => result.name == 'spawn_subagent') &&
      const CodingContinuationRecoveryPolicy().looksLikeUnexecutedDelegation(
        response,
      );

  ({
    List<Map<String, dynamic>> tools,
    Set<String> selectedNames,
    bool toolSearchEnabled,
    String? forcedCode,
  })
  selectTools({
    required List<Map<String, dynamic>> allTools,
    required bool prefixStable,
    required bool pendingDelegation,
  }) {
    if (pendingDelegation) {
      final delegationTools = allTools
          .where(
            (definition) =>
                ToolDefinitionSearchService.toolNameFromDefinition(
                  definition,
                ) ==
                'spawn_subagent',
          )
          .toList(growable: false);
      if (delegationTools.isNotEmpty) {
        return (
          tools: delegationTools,
          selectedNames: const {'spawn_subagent'},
          toolSearchEnabled: false,
          forcedCode: 'unexecuted_delegation',
        );
      }
    }
    final selection = prefixStable
        ? ToolDefinitionSearchSelection(
            toolSearchEnabled: false,
            toolDefinitions: allTools,
            selectedToolNames:
                ToolDefinitionSearchService.toolNamesFromDefinitions(allTools),
          )
        : ToolDefinitionSearchService.buildInitialSelection(allTools);
    return (
      tools: selection.toolDefinitions,
      selectedNames: selection.selectedToolNames,
      toolSearchEnabled: selection.toolSearchEnabled,
      forcedCode: null,
    );
  }
}
