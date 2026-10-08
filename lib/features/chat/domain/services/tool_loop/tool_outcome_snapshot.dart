import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

/// Retains typed execution facts while isolating mutable list identities.
abstract final class ToolOutcomeSnapshot {
  static ToolOutcome? freeze(ToolOutcome? outcome) {
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
