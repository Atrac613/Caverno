// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierReviewInspection on ChatNotifier {
  String projectTaskVerificationContext(String conversationId) =>
      _primaryRoutes.verificationContext(conversationId)?.prompt ?? '';

  ProjectTaskReviewVerdict? takeProjectTaskReviewVerdict(ChatTurnOwner owner) =>
      _primaryRoutes.takeReviewTerminal(
        owner.interactionGeneration,
        owner.conversationId,
      );

  String? _captureProjectTaskReviewResponse({
    required ChatTurnOwner owner,
    required String response,
    required String finishReason,
    required List<ToolResultInfo> results,
  }) {
    final generation = owner.interactionGeneration;
    if (!_isCodeReview(generation) ||
        _conversationForId(owner.conversationId)?.goal?.projectTaskAutoReview !=
            true) {
      return null;
    }
    final retained = _primaryRoutes.reviewTerminal(
      generation,
      owner.conversationId,
    );
    if (retained != null) {
      return retained.response;
    }
    var verdict = ProjectTaskReviewVerdict.fromResponse(response);
    final inspection = _guardReviewInspection(
      candidateResponse: response,
      toolResults: results,
      generation: generation,
    );
    if (inspection != null) {
      verdict = verdict.incomplete(
        FinalAnswerClaimDetector.unverifiedReadOnlyInspectionNotice,
      );
    } else if (finishReason == 'length') {
      verdict = verdict.incomplete('The review response was truncated.');
    } else if (verdict.disposition == ProjectTaskReviewDisposition.clean &&
        ToolResultPromptBuilder.completionEvidence(
          results,
        ).hasBlockingEvidence) {
      verdict = verdict.incomplete(
        'The review has an unresolved verification failure.',
      );
    }
    _primaryRoutes.recordReviewTerminal(
      generation,
      owner.conversationId,
      verdict,
    );
    _turnEnd.addTransform(
      owner,
      'project_task_review_${verdict.disposition.name}',
    );
    return verdict.response;
  }

  List<String> _taskReviewInspectionPaths(int generation) =>
      const ProjectTaskReviewInspection().paths(
        conversation: _conversationForGeneration(generation),
        codeReview: _isCodeReview(generation),
        projectRoot: _turnOwnerSnapshotForGeneration(generation)?.projectRoot,
      );

  Future<bool> _startTaskReviewInspection(
    int generation,
    List<Map<String, dynamic>> tools,
  ) async {
    final paths = _taskReviewInspectionPaths(generation);
    if (paths.isEmpty) return false;
    if (!ToolDefinitionSearchService.toolNamesFromDefinitions(
      tools,
    ).contains('read_file')) {
      return _rejectTaskReviewWithoutInspection(generation);
    }
    // Use the normal owner-fenced tool route and ledger. These are harness
    // prerequisites, not model-authored calls or evidence from an earlier turn.
    await _executeToolCalls(
      [
        for (final file in paths)
          ToolCallInfo(
            id: 'farm_review_inspection_${_uuid.v4()}',
            name: 'read_file',
            arguments: {'path': file},
          ),
      ],
      assistantContent:
          'The harness is inspecting the current task files before the '
          'dedicated read-only review. Review these executed results and the '
          'task patch; failed reads leave the review incomplete.',
      selectedToolNames: ToolDefinitionSearchService.toolNamesFromDefinitions(
        tools,
      ).toSet(),
      stableToolDefinitions: tools,
      interactionGeneration: generation,
    );
    return true;
  }

  Future<bool> _rejectTaskReviewWithoutInspection(int generation) async {
    if (!_isCodeReview(generation) ||
        _conversationForGeneration(generation)?.goal?.projectTaskAutoReview !=
            true) {
      return false;
    }
    final owner = _turnOwnerForGeneration(generation);
    if (owner != null) {
      await _handleError(
        'Farm review is incomplete: current task-file inspection requires '
        'the read_file tool and a tool-capable review route.',
        owner: owner,
      );
    }
    return true;
  }

  ToolResultInfo? _guardReviewInspection({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int generation,
  }) => _claims.buildUnverifiedReadOnlyInspectionClaimToolResult(
    candidateResponse: candidateResponse,
    toolResults: toolResults,
    requiredFilePaths: _taskReviewInspectionPaths(generation),
  );

  ToolDefinitionSearchSelection _initialToolSelection(
    List<Map<String, dynamic>> tools,
  ) {
    final selection = _settings.enablePrefixStableToolLoop
        ? ToolDefinitionSearchSelection(
            toolSearchEnabled: false,
            toolDefinitions: tools,
            selectedToolNames:
                ToolDefinitionSearchService.toolNamesFromDefinitions(tools),
          )
        : ToolDefinitionSearchService.buildInitialSelection(tools);
    if (_settings.enablePrefixStableToolLoop) {
      appLog(
        '[Tool] Prefix-stable tool loop enabled; using a fixed full tool list',
      );
    }
    if (selection.toolSearchEnabled) {
      appLog(
        '[ToolSearch] Enabled dynamic tool loading. Initial tools: '
        '${ToolDefinitionSearchService.toolNamesFromDefinitions(selection.toolDefinitions).toList()}',
      );
    }
    return selection;
  }
}
