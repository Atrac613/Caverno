// Same-library extension on [ChatNotifier]: terminal tool-response
// acceptance delegates to a pure policy service while preserving existing
// private call sites during the decomposition.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierTerminalToolResponsePolicy on ChatNotifier {
  ToolTerminalResponsePolicy get _terminalToolResponsePolicy =>
      ToolTerminalResponsePolicy(
        looksLikeUnexecutedToolRequest: _looksLikeUnexecutedToolRequest,
        looksLikePlanOnlyFinalToolAnswer: _looksLikePlanOnlyFinalToolAnswer,
        looksLikePendingToolActionResponse: _looksLikePendingToolActionResponse,
        looksLikeStructuredToolRequest: _looksLikeStructuredToolRequest,
        isFileMutationToolName: _isFileMutationToolName,
        isSuccessfulFileMutationToolResult: _isSuccessfulFileMutationToolResult,
        toolResultPayloadPath: _toolResultPayloadPath,
        containsAnyCodeUnitSequence: _containsAnyCodeUnitSequence,
        containsCjkBlockerMarker: _containsCjkBlockerMarker,
        containsCjkMissingEvidenceMarker: _containsCjkMissingEvidenceMarker,
      );

  int _hiddenAssistantEvidenceScore(String response) {
    return _terminalToolResponsePolicy.hiddenAssistantEvidenceScore(response);
  }

  bool _shouldAcceptRecoveryFinalTextResponse(String response) {
    return _terminalToolResponsePolicy.shouldAcceptRecoveryFinalTextResponse(
      response,
    );
  }

  bool _shouldAcceptTerminalToolRoleFinalTextResponse(String response) {
    return _terminalToolResponsePolicy
        .shouldAcceptTerminalToolRoleFinalTextResponse(response);
  }

  bool _shouldAcceptTerminalFileMutationFinalTextResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _terminalToolResponsePolicy
        .shouldAcceptTerminalFileMutationFinalTextResponse(
          response,
          toolResults,
        );
  }

  bool _shouldAcceptTerminalBrowserSaveDataResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _terminalToolResponsePolicy
        .shouldAcceptTerminalBrowserSaveDataResponse(response, toolResults);
  }

  String _normalizeTerminalBrowserSaveDataResponse(String response) {
    return _terminalToolResponsePolicy.normalizeTerminalBrowserSaveDataResponse(
      response,
    );
  }

  bool _containsFileMutationCompletionMarker(String response) {
    return _terminalToolResponsePolicy.containsFileMutationCompletionMarker(
      response,
    );
  }

  bool _shouldAcceptTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _terminalToolResponsePolicy
        .shouldAcceptTerminalSkillToolRoleResponse(response, toolResults);
  }

  bool _shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
    String response,
    List<ToolResultInfo> toolResults,
    List<ToolCallInfo> followUpToolCalls,
  ) {
    return _terminalToolResponsePolicy
        .shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
          response,
          toolResults,
          followUpToolCalls,
        );
  }

  bool _looksLikeSkillContinuationWorkIntent(String response) {
    return _terminalToolResponsePolicy.looksLikeSkillContinuationWorkIntent(
      response,
    );
  }

  String _normalizeTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _terminalToolResponsePolicy.normalizeTerminalSkillToolRoleResponse(
      response,
      toolResults,
    );
  }

  bool _hasSuccessfulLoadSkillResult(List<ToolResultInfo> toolResults) {
    return _terminalToolResponsePolicy.hasSuccessfulLoadSkillResult(
      toolResults,
    );
  }

  bool _toolResultLooksSuccessfulForFinalAnswer(String result) {
    return _terminalToolResponsePolicy.toolResultLooksSuccessfulForFinalAnswer(
      result,
    );
  }

  bool _shouldAcceptTerminalToolRoleBlockerResponse(String response) {
    return _terminalToolResponsePolicy
        .shouldAcceptTerminalToolRoleBlockerResponse(response);
  }
}
