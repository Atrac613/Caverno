// Same-library extension on [ChatNotifier]: terminal tool-response
// acceptance delegates to a pure policy service while preserving existing
// private call sites during the decomposition.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierTerminalToolResponsePolicy on ChatNotifier {
  ToolTerminalResponsePolicy get _terminalToolResponsePolicy =>
      ToolTerminalResponsePolicy(
        looksLikeUnexecutedToolRequest:
            const UnexecutedFinalAnswerToolRequestPolicy()
                .looksLikeUnexecutedToolRequest,
        looksLikePlanOnlyFinalToolAnswer:
            const UnexecutedFinalAnswerToolRequestPolicy()
                .looksLikePlanOnlyFinalToolAnswer,
        looksLikePendingToolActionResponse: _looksLikePendingToolActionResponse,
        looksLikeStructuredToolRequest:
            const UnexecutedFinalAnswerToolRequestPolicy()
                .looksLikeStructuredToolRequest,
        containsAnyCodeUnitSequence: CodeUnitTextScan.containsAny,
        containsCjkBlockerMarker: _containsCjkBlockerMarker,
        containsCjkMissingEvidenceMarker: _containsCjkMissingEvidenceMarker,
      );

  bool _shouldAcceptTerminalToolRoleFinalTextResponse(
    String response, [
    List<ToolResultInfo> toolResults = const [],
  ]) => _terminalToolResponsePolicy.shouldAcceptTerminalLoopFinalText(
    response,
    toolResults,
  );

  bool _shouldAcceptTerminalFileMutationFinalTextResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) => _terminalToolResponsePolicy
      .shouldAcceptTerminalFileMutationFinalTextResponse(response, toolResults);

  bool _shouldAcceptTerminalBrowserSaveDataResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) => _terminalToolResponsePolicy.shouldAcceptTerminalBrowserSaveDataResponse(
    response,
    toolResults,
  );

  bool _shouldAcceptTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) => _terminalToolResponsePolicy.shouldAcceptTerminalSkillToolRoleResponse(
    response,
    toolResults,
  );

  bool _shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
    String response,
    List<ToolResultInfo> toolResults,
    List<ToolCallInfo> followUpToolCalls,
  ) => _terminalToolResponsePolicy
      .shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
        response,
        toolResults,
        followUpToolCalls,
      );

  bool _shouldAcceptTerminalToolRoleBlockerResponse(String response) =>
      _terminalToolResponsePolicy.shouldAcceptTerminalToolRoleBlockerResponse(
        response,
      );
}
