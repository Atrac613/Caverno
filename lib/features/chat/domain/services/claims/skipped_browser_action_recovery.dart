import '../../entities/tool_call_info.dart';
import '../tool_definition_search_service.dart';
import 'final_answer_claim_detector.dart';

/// Decides snapshot recovery and follow-up repair without executing browser tools.
final class SkippedBrowserActionRecovery {
  const SkippedBrowserActionRecovery();

  static const _claims = FinalAnswerClaimDetector();

  ToolCallInfo? resolve({
    required bool hasToolCalls,
    required Set<String> disabledToolNames,
    required List<Map<String, dynamic>> availableTools,
    required String latestUserContent,
    required DateTime Function() now,
  }) {
    if (hasToolCalls || disabledToolNames.contains('browser_snapshot')) {
      return null;
    }
    final names = ToolDefinitionSearchService.toolNamesFromDefinitions(
      availableTools,
    ).toSet();
    if (!names.contains('browser_snapshot')) {
      return null;
    }
    if (!_claims.looksLikeBrowserActionRequest(latestUserContent)) {
      return null;
    }
    return ToolCallInfo(
      id: 'recovered_browser_snapshot_${now().microsecondsSinceEpoch}',
      name: 'browser_snapshot',
      arguments: const {'max_elements': 80},
    );
  }

  bool shouldRepairAfterSnapshot({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required String latestUserContent,
  }) {
    if (candidateResponse.trim().isEmpty) {
      return false;
    }
    if (!_claims.hasRecoveredBrowserSnapshot(batchToolResults)) {
      return false;
    }
    return _claims.looksLikeBrowserActionRequest(latestUserContent);
  }
}
