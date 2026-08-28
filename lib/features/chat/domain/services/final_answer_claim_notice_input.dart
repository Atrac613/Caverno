import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';

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
      outcome: _freezeOutcome(result.outcome),
    );
  }

  /// Carries the structured outcome across the freeze.
  ///
  /// Dropping it here left every claim check inside this applicator reading
  /// prose even where `ToolOutcome` already held the answer, and the loss was
  /// invisible because each consumer has a text fallback: the typed mutation
  /// path in `UnwrittenFileClaimGuard`, its no-op-mutation check (so a
  /// byte-identical write counted as a change), and the whole structured
  /// test-count path in `CodingVerificationClaimGuard`, which returns early on
  /// a null outcome and therefore never ran here at all.
  ///
  /// `ToolOutcome` and the value classes it holds are immutable apart from the
  /// mutation list's own identity, so only that needs wrapping to keep the
  /// freeze contract.
  static ToolOutcome? _freezeOutcome(ToolOutcome? outcome) {
    if (outcome == null) return null;
    return ToolOutcome(
      exitCode: outcome.exitCode,
      processState: outcome.processState,
      fileMutations: List<ToolFileMutation>.unmodifiable(outcome.fileMutations),
      readOutcome: outcome.readOutcome,
      testOutcome: outcome.testOutcome,
      fileChanged: outcome.fileChanged,
      contentHash: outcome.contentHash,
      diagnosticCount: outcome.diagnosticCount,
      diagnosticErrorCount: outcome.diagnosticErrorCount,
      diagnosticWarningCount: outcome.diagnosticWarningCount,
      testPassedCount: outcome.testPassedCount,
      testFailedCount: outcome.testFailedCount,
      testSkippedCount: outcome.testSkippedCount,
    );
  }
}
