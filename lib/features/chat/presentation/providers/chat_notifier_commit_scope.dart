// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierCommitScope on ChatNotifier {
  Future<ChatTurnOwner?> sendProjectTaskCommit(
    String prompt,
    ProjectTaskCommitScope scope, {
    required PrimaryTurnPurpose purpose,
    String languageCode = 'en',
  }) {
    if (purpose != PrimaryTurnPurpose.projectTaskCommitPreparation &&
        purpose != PrimaryTurnPurpose.projectTaskCommit) {
      throw ArgumentError(
        'A task commit scope requires a preparation or commit purpose.',
      );
    }
    return ProjectTaskCommitScope.enqueue(
      scope,
      () => sendMessage(
        prompt,
        languageCode: languageCode,
        bypassPlanMode: true,
        purpose: purpose,
      ),
    );
  }

  bool _hasCommitScope(int generation) =>
      _primaryRoutes.isProjectTaskCommit(generation) ||
      _primaryRoutes.isProjectTaskCommitPreparation(generation);

  Set<String>? _commitScopeToolNames(int generation) {
    if (!_hasCommitScope(generation)) return null;
    return {
      'read_file',
      'inspect_file',
      'list_directory',
      'find_files',
      'search_files',
      'git_execute_command',
      if (_primaryRoutes.isProjectTaskCommitPreparation(generation)) ...{
        'write_file',
        'edit_file',
      },
    };
  }

  McpToolResult _commitScopeFailure(String name, String reason) =>
      McpToolResult(
        toolName: name,
        isSuccess: false,
        result: jsonEncode({
          'ok': false,
          'code': 'project_task_commit_precondition_failed',
          ...ToolResultOrigin.refusal.marker,
          'error': reason,
        }),
        errorMessage: reason,
      );

  McpToolResult? _enforceCommitScopeTool(ToolCallInfo call, int? generation) {
    if (generation == null || !_hasCommitScope(generation)) return null;
    final scope = _primaryRoutes.commitScope(generation);
    final owner = _turnOwnerForGeneration(generation);
    final root = _projectRootForGeneration(generation);
    if (scope == null ||
        root == null ||
        scope.conversationId != owner?.conversationId ||
        scope.resolve(root) != scope.projectRoot) {
      return _commitScopeFailure(
        call.name,
        'Native task commit scope is unavailable for this owner.',
      );
    }
    if (!_commitScopeToolNames(generation)!.contains(call.name)) {
      return _commitScopeFailure(
        call.name,
        'This tool cannot run in task commit preparation or execution.',
      );
    }
    final preparing = _primaryRoutes.isProjectTaskCommitPreparation(generation);
    if (call.name == 'write_file' || call.name == 'edit_file') {
      final raw = call.arguments['path'] ?? call.arguments['file_path'];
      if (!preparing ||
          raw is! String ||
          scope.resolve(raw) != scope.roadmapPath) {
        return _commitScopeFailure(
          call.name,
          'Only the cited roadmap may be edited during commit preparation.',
        );
      }
    }
    if (call.name != 'git_execute_command') return null;
    final rawCommand = call.arguments['command'];
    final command = rawCommand is String ? rawCommand : '';
    final args = GitTools.splitArgs(GitTools.normalizeCommand(command));
    final workingDirectory = call.arguments['working_directory'] ?? '.';
    if (workingDirectory is! String ||
        scope.resolve(workingDirectory) != scope.projectRoot ||
        args.isEmpty ||
        GitTools.firstShellControlOperator(command) != null) {
      return _commitScopeFailure(
        call.name,
        'The Git command must use this task repository without shell operators.',
      );
    }
    if (GitTools.isReadOnly(command)) return null;
    final stageOnly =
        preparing &&
        args.length > 2 &&
        args[0] == 'add' &&
        args[1] == '--' &&
        args.skip(2).every((file) => scope.paths.contains(scope.resolve(file)));
    final commitOnly =
        !preparing &&
        scope.prepared != null &&
        args.length >= 5 &&
        args.first == 'commit' &&
        args.length.isOdd &&
        [
          for (var i = 1; i < args.length; i += 2) args[i],
        ].every((flag) => flag == '-m');
    return stageOnly || commitOnly
        ? null
        : _commitScopeFailure(
            call.name,
            preparing
                ? 'Prepare the roadmap and named task files first; commits are forbidden in this turn.'
                : 'Only a new commit of the accepted index is permitted; edits, staging and history changes are forbidden.',
          );
  }

  Future<McpToolResult?> _recheckTaskCommitBeforeExecution(
    ToolCallInfo call,
    OwnerToolApprovalCache cache,
  ) async {
    final generation = cache.owner.interactionGeneration;
    if (!_primaryRoutes.isProjectTaskCommit(generation)) return null;
    final scope = _primaryRoutes.commitScope(generation);
    if (scope == null) {
      return _commitScopeFailure(
        call.name,
        'Native commit preparation is missing.',
      );
    }
    final now = await const ProjectTaskCommitReader().read(scope);
    final problem = now == null
        ? 'Prepared commit state could not be read.'
        : scope.commitProblem(now);
    return problem == null ? null : _commitScopeFailure(call.name, problem);
  }

  Future<McpToolResult> _dispatchToolCall(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
    String? projectRoot,
  }) async {
    final approvalCache = _approvalCacheForGeneration(interactionGeneration);
    if (interactionGeneration != null && approvalCache == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    final commitFailure = _enforceCommitScopeTool(
      toolCall,
      interactionGeneration,
    );
    if (commitFailure != null) return commitFailure;
    return TurnProjectRoot.runScoped(
      projectRoot == null
          ? _turnProjectRootFor(interactionGeneration)
          : TurnProjectRoot(projectRoot),
      () => TurnGeneration.runScoped(
        interactionGeneration,
        () => TurnThread.runScoped(
          interactionGeneration == null
              ? null
              : _activeResponseConversationIdForGeneration(
                  interactionGeneration,
                ),
          () => ChatToolDispatcher(
            enforcePlanningPolicy: (toolCall) =>
                _enforcePlanningToolPolicy(toolCall, interactionGeneration),
            enforceNetworkReadTaint: (toolCall) =>
                _enforceNetworkReadTaint(toolCall, approvalCache),
            handleComputerUseAction: _ownerComputerUseHandler(approvalCache),
            handleComputerUseObservation:
                _handleComputerUseActionWithoutApproval,
            handleBrowserAction: _ownerBrowserActionHandler(approvalCache),
            handleBrowserObservation: _handleBrowserActionWithoutApproval,
            handleNetworkMutation: _ownerNetworkMutationHandler(approvalCache),
            handlerRegistry: _buildToolHandlerRegistry(
              interactionGeneration: interactionGeneration,
              approvalCache: approvalCache,
              projectRoot: projectRoot,
            ),
            executeFallbackTool: (toolCall) => _mcpToolService!.executeTool(
              name: toolCall.name,
              arguments: toolCall.arguments,
            ),
            validateArguments: _mcpToolService?.checkToolArguments,
          ).dispatch(toolCall),
        ),
      ),
    );
  }
}
