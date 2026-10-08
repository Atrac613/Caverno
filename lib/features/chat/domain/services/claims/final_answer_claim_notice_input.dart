import '../../entities/tool_call_info.dart';
import '../immutable_json_snapshot.dart';
import '../tool_loop/tool_outcome_snapshot.dart';

/// Immutable owner-scoped evidence used to annotate one final answer.
final class FinalAnswerClaimNoticeInput {
  FinalAnswerClaimNoticeInput({
    required this.isCodingWorkspaceOrMode,
    required this.candidateContent,
    required List<ToolResultInfo> toolResults,
    required List<String> executedCommands,
    required String? projectRoot,
    required this.offersCommandExecution,
  }) : toolResults = List<ToolResultInfo>.unmodifiable(
         toolResults.map(_freezeToolResult),
       ),
       executedCommands = List<String>.unmodifiable(executedCommands),
       projectRoot = projectRoot?.trim();

  final bool isCodingWorkspaceOrMode;
  final String candidateContent;
  final List<ToolResultInfo> toolResults;
  final List<String> executedCommands;
  final String? projectRoot;
  final bool offersCommandExecution;

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) {
    return ToolResultInfo(
      id: result.id,
      name: result.name,
      arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
      result: result.result,
      outcome: ToolOutcomeSnapshot.freeze(result.outcome),
    );
  }
}
