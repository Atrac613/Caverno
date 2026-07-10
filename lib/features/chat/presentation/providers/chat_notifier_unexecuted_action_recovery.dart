// Same-library extension on [ChatNotifier]: delegates unexecuted-action and
// final-answer claim detection to the domain detector while keeping stateful
// application in the notifier.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierUnexecutedActionRecovery on ChatNotifier {
  String _messageContentWithVerificationClaimNotice(String content) {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation?.workspaceMode != WorkspaceMode.coding) {
      return content;
    }
    final assessment = _codingVerificationClaimGuard.assess(
      candidateResponse: content,
      toolResults: [
        ..._latestCompletedToolResults,
        ..._latestContentToolResults,
      ],
    );
    if (!assessment.hasMismatch) {
      return content;
    }
    final notice = assessment.buildNotice();
    if (content.contains(notice)) {
      return content;
    }
    _appliedTurnTransforms.add('verification_claim_notice');
    return '${content.trimRight()}\n\n$notice';
  }

  String _messageContentWithUnwrittenFileClaimNotice(String content) {
    final conversationsState = ref.read(conversationsNotifierProvider);
    final conversation = conversationsState.currentConversation;
    if (conversation == null ||
        conversation.workspaceMode != WorkspaceMode.coding) {
      return content;
    }
    final projectRoot = _getEffectiveCodingProject()?.rootPath.trim();
    if (projectRoot == null || projectRoot.isEmpty) {
      return content;
    }
    final assessment = _unwrittenFileClaimGuard.assess(
      candidateResponse: content,
      toolResults: [
        ..._latestCompletedToolResults,
        ..._latestContentToolResults,
      ],
      projectRoot: projectRoot,
    );
    if (!assessment.hasClaims) {
      return content;
    }
    final notice = assessment.buildNotice();
    if (content.contains(notice)) {
      return content;
    }
    _appliedTurnTransforms.add('unwritten_file_claim_notice');
    return '${content.trimRight()}\n\n$notice';
  }

  ToolResultInfo? _buildUnexecutedSkippedBrowserActionToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required int interactionGeneration,
  }) {
    return _finalAnswerClaimDetector
        .buildUnexecutedSkippedBrowserActionToolResult(
          candidateResponse: candidateResponse,
          batchToolResults: batchToolResults,
          latestUserContent: _latestUserContentForGeneration(
            interactionGeneration,
          ),
        );
  }

  ToolResultInfo? _buildUnexecutedFileSideEffectToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) {
    return _finalAnswerClaimDetector.buildUnexecutedFileSideEffectToolResult(
      candidateResponse: candidateResponse,
      toolResults: toolResults,
      latestUserContent: _latestUserContentForGeneration(interactionGeneration),
    );
  }

  ToolResultInfo? _buildUnexecutedCommandActionToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) {
    return _finalAnswerClaimDetector.buildUnexecutedCommandActionToolResult(
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
  }

  ToolResultInfo? _buildUnverifiedReadOnlyInspectionClaimToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    return _finalAnswerClaimDetector
        .buildUnverifiedReadOnlyInspectionClaimToolResult(
          candidateResponse: candidateResponse,
          toolResults: toolResults,
        );
  }

  @visibleForTesting
  ToolResultInfo? buildUnverifiedReadOnlyInspectionClaimToolResultForTest({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    return _buildUnverifiedReadOnlyInspectionClaimToolResult(
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
  }

  @visibleForTesting
  bool looksLikeCompletedReadOnlyInspectionClaimForTest(String content) {
    return _looksLikeCompletedReadOnlyInspectionClaim(content);
  }

  @visibleForTesting
  bool hasSuccessfulReadOnlyInspectionResultForTest(
    List<ToolResultInfo> toolResults,
  ) {
    return _hasSuccessfulReadOnlyInspectionResult(toolResults);
  }

  bool _hasSuccessfulFileSideEffectResult(List<ToolResultInfo> toolResults) {
    return _finalAnswerClaimDetector.hasSuccessfulFileSideEffectResult(
      toolResults,
    );
  }

  bool _hasSuccessfulReadOnlyInspectionResult(
    List<ToolResultInfo> toolResults,
  ) {
    return _finalAnswerClaimDetector.hasSuccessfulReadOnlyInspectionResult(
      toolResults,
    );
  }

  String _clipForDiagnostic(String value, {int maxLength = 240}) {
    return _finalAnswerClaimDetector.clipForDiagnostic(
      value,
      maxLength: maxLength,
    );
  }

  bool _looksLikeCompletedReadOnlyInspectionClaim(String content) {
    return _finalAnswerClaimDetector.looksLikeCompletedReadOnlyInspectionClaim(
      content,
    );
  }

  Set<String> _browserToolNamesFromDefinitions(
    List<Map<String, dynamic>> toolDefinitions,
  ) {
    return _finalAnswerClaimDetector.browserToolNamesFromDefinitions(
      toolDefinitions,
    );
  }

  bool _looksLikeBrowserActionRequest(String text) {
    return _finalAnswerClaimDetector.looksLikeBrowserActionRequest(text);
  }

  String _browserActionToolNameForText(String text) {
    return _finalAnswerClaimDetector.browserActionToolNameForText(text);
  }

  String _messageContentWithUnexecutedCommandActionNotice(
    String content,
    String notice,
  ) {
    return _finalAnswerClaimDetector
        .messageContentWithUnexecutedCommandActionNotice(
          content,
          notice: notice,
        );
  }

  String _messageContentWithPrependedClaimCorrectionNotice(
    String content,
    String notice,
  ) {
    return _finalAnswerClaimDetector
        .messageContentWithPrependedClaimCorrectionNotice(content, notice);
  }

  String _messageContentWithUnverifiedReadOnlyInspectionNotice(
    String content,
    String notice,
  ) {
    return _finalAnswerClaimDetector
        .messageContentWithUnverifiedReadOnlyInspectionNotice(
          content,
          notice: notice,
        );
  }

  bool _looksLikeUnsupportedFileSideEffectClaim(
    String content, {
    required List<ToolResultInfo> toolResults,
  }) {
    return _finalAnswerClaimDetector.looksLikeUnsupportedFileSideEffectClaim(
      content,
      toolResults: toolResults,
    );
  }

  bool _hasUnexecutedFileSideEffectResult(List<ToolResultInfo> toolResults) {
    return _finalAnswerClaimDetector.hasUnexecutedFileSideEffectResult(
      toolResults,
    );
  }

  bool _hasUnexecutedCommandActionResult(List<ToolResultInfo> toolResults) {
    return _finalAnswerClaimDetector.hasUnexecutedCommandActionResult(
      toolResults,
    );
  }

  bool _hasUnverifiedReadOnlyInspectionClaimResult(
    List<ToolResultInfo> toolResults,
  ) {
    return _finalAnswerClaimDetector.hasUnverifiedReadOnlyInspectionClaimResult(
      toolResults,
    );
  }

  bool _hasSuccessfulCommandExecutionResult(List<ToolResultInfo> toolResults) {
    return _finalAnswerClaimDetector.hasSuccessfulCommandExecutionResult(
      toolResults,
    );
  }

  bool _looksLikeCommandSuccessClaim(String content) {
    return _finalAnswerClaimDetector.looksLikeCommandSuccessClaim(content);
  }

  bool _looksLikeUnsupportedCommandExecutionAction(String content) {
    return _finalAnswerClaimDetector.looksLikeUnsupportedCommandExecutionAction(
      content,
    );
  }

  bool _looksLikeFutureCommandExecutionAction(String content) {
    return _finalAnswerClaimDetector.looksLikeFutureCommandExecutionAction(
      content,
    );
  }

  bool _looksLikeCompletedCommandExecutionClaim(String content) {
    return _finalAnswerClaimDetector.looksLikeCompletedCommandExecutionClaim(
      content,
    );
  }

  bool _looksLikeFutureFileSideEffectAction(String content) {
    return _finalAnswerClaimDetector.looksLikeFutureFileSideEffectAction(
      content,
    );
  }

  bool _containsCjkFutureActionMarker(String value, {int startIndex = 0}) {
    return _finalAnswerClaimDetector.containsCjkFutureActionMarker(
      value,
      startIndex: startIndex,
    );
  }
}
