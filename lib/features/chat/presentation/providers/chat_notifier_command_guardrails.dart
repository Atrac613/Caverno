// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierCommandGuardrails on ChatNotifier {
  McpToolResult? _buildGitTagFormatInspectionGuardResult(
    ToolCallInfo toolCall, {
    required List<ToolResultInfo> executedToolResults,
  }) {
    if (toolCall.name != 'git_execute_command') {
      return null;
    }
    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final command = GitTools.normalizeCommand(
      (resolvedArguments['command'] as String?)?.trim() ?? '',
    );
    if (GitTools.firstShellControlOperator(command) != null) {
      return null;
    }
    if (!_isGitTagCreationCommand(command)) {
      return null;
    }
    final workingDirectory =
        (resolvedArguments['working_directory'] as String?)?.trim() ?? '';
    final hasTagFormatInspection = executedToolResults.any(
      (toolResult) => _isSuccessfulGitTagFormatInspection(
        toolResult,
        workingDirectory: workingDirectory,
      ),
    );
    if (hasTagFormatInspection) {
      return null;
    }

    final payload = jsonEncode({
      'error':
          'Git tag creation requires inspecting existing tag names in this '
          'turn before creating a new tag.',
      'code': 'git_tag_format_inspection_required',
      'command': 'git $command',
      'working_directory': workingDirectory,
      'required_action':
          'Run git_execute_command with "tag --list" or '
          '"for-each-ref refs/tags --format=%(refname:short)" first, then '
          'choose a new tag name that matches the existing repository format.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'Inspect existing git tag names before creating a new tag.',
    );
  }

  McpToolResult? _buildTimedOutCommandRetryGuardResult(
    ToolCallInfo toolCall, {
    required List<ToolResultInfo> executedToolResults,
  }) {
    if (!_isCommandExecutionTool(toolCall.name) ||
        _isReadOnlyCommandExecutionToolCall(toolCall)) {
      return null;
    }
    final command = _toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return null;
    }
    final normalizedCommand = _normalizeToolCommandForComparison(command);
    final matchingTimedOutResult = executedToolResults.reversed
        .where(
          (result) =>
              _isCommandExecutionTool(result.name) &&
              _toolResultTimedOut(result) &&
              _toolResultCommandMatches(
                result,
                normalizedCommand: normalizedCommand,
              ),
        )
        .firstOrNull;
    if (matchingTimedOutResult == null) {
      return null;
    }

    final payload = jsonEncode({
      'error':
          'The same command already timed out. Automatic retry is blocked '
          'because the previous process may still be running or may have '
          'partially completed side effects.',
      'code': 'command_retry_after_timeout_blocked',
      'command': command,
      'previous_error': _toolResultErrorText(matchingTimedOutResult),
      'required_action':
          'Ask the user before retrying, or verify the previous process state '
          'with a read-only inspection command first.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: true,
    );
  }

  McpToolResult? _buildProductionReleaseApprovalGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required int interactionGeneration,
  }) {
    if (!_isProductionReleaseCommandToolCall(toolCall)) {
      return null;
    }
    if (_hasExplicitProductionReleaseApproval(interactionGeneration)) {
      return null;
    }

    final command = _toolCommandArgument(toolCall.arguments) ?? '';
    final payload = jsonEncode({
      'ok': false,
      'code': 'production_release_explicit_approval_required',
      'error':
          'A production release command was blocked because the latest user '
          'message or ask_user_question answer did not explicitly approve '
          'production release execution.',
      'command': command,
      if ((currentAssistantContent ?? '').trim().isNotEmpty)
        'assistant_intent': _clipForDiagnostic(currentAssistantContent!.trim()),
      'required_action':
          'Ask the user to explicitly approve the production release command '
          'after any dry run, then retry only after that user approval.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: true,
    );
  }

  McpToolResult? _buildCodingCommandPreflightGuardResult(
    ToolCallInfo toolCall,
  ) {
    final toolName = toolCall.name.trim().toLowerCase();
    if (toolName != 'local_execute_command' && toolName != 'process_start') {
      return null;
    }
    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final command = LocalShellTools.normalizeCommand(
      (resolvedArguments['command'] as String?)?.trim() ?? '',
    );
    final workingDirectory =
        (resolvedArguments['working_directory'] as String?)?.trim() ?? '';
    final issue = CodingCommandOutputGuardrailService.detectPreflightIssue(
      toolName: toolCall.name,
      command: command,
      workingDirectory: workingDirectory,
    );
    if (issue == null) {
      return null;
    }

    final payload = jsonEncode({
      'ok': false,
      ...issue.toJson(),
      'required_action': issue.instruction,
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: issue.summary,
    );
  }

  McpToolResult? _buildModifiedSavedValidationCommandGuardResult(
    ToolCallInfo toolCall,
  ) {
    if (!_isCommandExecutionTool(toolCall.name)) {
      return null;
    }
    final validationCommand = _currentSavedValidationCommandForToolLoop();
    if (validationCommand == null) {
      return null;
    }
    final command = _toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return null;
    }
    final normalizedCommand = _normalizeToolCommandForComparison(command);
    final normalizedValidationCommand = _normalizeToolCommandForComparison(
      validationCommand,
    );
    if (normalizedCommand == normalizedValidationCommand) {
      return null;
    }
    if (!_looksLikeModifiedSavedValidationCommand(
      command: command,
      validationCommand: validationCommand,
      normalizedCommand: normalizedCommand,
      normalizedValidationCommand: normalizedValidationCommand,
    )) {
      return null;
    }

    final payload = jsonEncode({
      'ok': false,
      'code': 'saved_validation_command_modified',
      'error':
          'A saved validation command was blocked because it was modified '
          'before execution.',
      'saved_validation_command': validationCommand,
      'attempted_command': command,
      'required_action':
          'Run the saved validation command exactly as saved, without '
          'wrappers, shell operators, extra echo commands, or fallback '
          'branches.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'Run the saved validation command exactly as saved.',
    );
  }

  McpToolResult? _buildSavedTaskTargetScopeGuardResult(ToolCallInfo toolCall) {
    final toolName = toolCall.name.trim().toLowerCase();
    if (toolName != 'write_file' && toolName != 'edit_file') {
      return null;
    }
    final task = _currentSavedTaskForToolLoop();
    if (task == null || task.targetFiles.isEmpty) {
      return null;
    }
    final path = _toolPathFromArguments(toolCall.arguments);
    if (path == null) {
      return null;
    }
    if (_savedTaskTargetAllowsPath(path: path, targetFiles: task.targetFiles)) {
      return null;
    }

    final payload = jsonEncode({
      'ok': false,
      'code': 'saved_task_target_scope_violation',
      'error':
          'A file mutation was blocked because it targeted a file outside '
          'the active saved task target files.',
      'task_id': task.id,
      'task_title': task.title,
      'attempted_path': path,
      'allowed_target_files': task.targetFiles,
      'required_action':
          'Modify only the active saved task target files, or finish the '
          'current saved task before starting work on another file.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'File mutation is outside the active saved task targets.',
    );
  }

  McpToolResult? _buildUnexecutedFileMutationBeforeCommandGuardResult(
    ToolCallInfo toolCall, {
    required String? currentAssistantContent,
    required List<ToolCallInfo> pendingToolCalls,
    required List<ToolResultInfo> executedToolResults,
  }) {
    if (!_isCommandExecutionTool(toolCall.name) ||
        _isReadOnlyCommandExecutionToolCall(toolCall)) {
      return null;
    }
    if (pendingToolCalls.any((pendingToolCall) {
      return pendingToolCall.id != toolCall.id &&
          _isFileMutationToolName(pendingToolCall.name);
    })) {
      return null;
    }
    if (_hasSuccessfulFileSideEffectResult(executedToolResults)) {
      return null;
    }

    final candidate = currentAssistantContent?.trim() ?? '';
    if (!_looksLikeFutureFileSideEffectAction(candidate)) {
      return null;
    }

    final blockedCommand = _toolCommandArgument(toolCall.arguments);
    final payloadMap = <String, Object?>{
      'ok': false,
      'code': 'unexecuted_file_save',
      'error':
          'A command was blocked because the assistant claimed a local file '
          'would be changed, but no successful write_file, edit_file, or '
          'rollback_last_file_change result is available for that claimed '
          'mutation.',
      'missing_tool': 'edit_file',
      'blocked_tool': toolCall.name,
      'claimedResponse': _clipForDiagnostic(candidate),
      'required_action':
          'Use write_file or edit_file to perform the claimed file mutation '
          'before running the command, or explain that the command remains '
          'blocked because the file change was not executed.',
    };
    if (blockedCommand != null) {
      payloadMap['blocked_command'] = blockedCommand;
    }
    final payload = jsonEncode(payloadMap);
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: true,
    );
  }

  bool _looksLikeModifiedSavedValidationCommand({
    required String command,
    required String validationCommand,
    required String normalizedCommand,
    required String normalizedValidationCommand,
  }) {
    if (normalizedCommand.startsWith(normalizedValidationCommand)) {
      final suffix = normalizedCommand
          .substring(normalizedValidationCommand.length)
          .trimLeft();
      if (suffix.startsWith('&&') ||
          suffix.startsWith('||') ||
          suffix.startsWith(';') ||
          suffix.startsWith('|')) {
        return true;
      }
    }
    return _looksLikePathResolvedSavedValidationCommand(
      command: command,
      validationCommand: validationCommand,
    );
  }

  bool _looksLikePathResolvedSavedValidationCommand({
    required String command,
    required String validationCommand,
  }) {
    final attemptedArgs = _simpleCommandSegmentArgs(command);
    final validationArgs = _simpleCommandSegmentArgs(validationCommand);
    final attemptedPathIndex = _savedValidationPathArgumentIndex(attemptedArgs);
    final validationPathIndex = _savedValidationPathArgumentIndex(
      validationArgs,
    );
    if (attemptedPathIndex == null ||
        validationPathIndex == null ||
        attemptedPathIndex != validationPathIndex ||
        attemptedArgs.length != validationArgs.length) {
      return false;
    }
    for (var index = 0; index < validationArgs.length; index += 1) {
      if (index == validationPathIndex) {
        continue;
      }
      if (attemptedArgs[index] != validationArgs[index]) {
        return false;
      }
    }
    final attemptedPath = _normalizeSavedTaskScopePath(
      attemptedArgs[attemptedPathIndex],
    );
    final validationPath = _normalizeSavedTaskScopePath(
      validationArgs[validationPathIndex],
    );
    return attemptedPath != null &&
        validationPath != null &&
        attemptedPath == validationPath;
  }

  List<String> _simpleCommandSegmentArgs(String command) {
    final args = GitTools.splitArgs(command.trim());
    final controlIndex = args.indexWhere(_isShellControlArgument);
    return controlIndex == -1 ? args : args.take(controlIndex).toList();
  }

  bool _isShellControlArgument(String value) {
    return value == '&&' || value == '||' || value == ';' || value == '|';
  }

  int? _savedValidationPathArgumentIndex(List<String> args) {
    if (args.length < 2) {
      return null;
    }
    final executable = args.first.split('/').last.toLowerCase();
    if (executable == 'cat' && args.length == 2) {
      return 1;
    }
    if (executable == 'ls' && args.length == 2) {
      return 1;
    }
    if (executable == 'test' && args.length == 3 && args[1] == '-f') {
      return 2;
    }
    if (executable == 'grep' && args.length >= 3) {
      return args.length - 1;
    }
    return null;
  }

  ConversationWorkflowTask? _currentSavedTaskForToolLoop() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null) {
      return null;
    }
    return ConversationPlanExecutionCoordinator.validationTask(conversation) ??
        ConversationPlanExecutionCoordinator.executionFocusTask(conversation);
  }

  bool _savedTaskTargetAllowsPath({
    required String path,
    required List<String> targetFiles,
  }) {
    final normalizedPath = _normalizeSavedTaskScopePath(path);
    if (normalizedPath == null) {
      return true;
    }
    for (final targetFile in targetFiles) {
      final target = targetFile.trim();
      if (target.isEmpty) {
        continue;
      }
      final normalizedTarget = _normalizeSavedTaskScopePath(target);
      if (normalizedTarget == null) {
        continue;
      }
      if (normalizedPath == normalizedTarget) {
        return true;
      }
      if ((target.endsWith('/') || target.endsWith('\\')) &&
          normalizedPath.startsWith('$normalizedTarget/')) {
        return true;
      }
    }
    return false;
  }

  String? _normalizeSavedTaskScopePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final resolved = FilesystemTools.resolvePath(
      trimmed,
      defaultRoot: _getActiveProjectRootPath(),
    );
    var normalized = (resolved ?? trimmed).replaceAll('\\', '/').trim();
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }

  bool _isGitTagCreationCommand(String command) {
    final args = GitTools.splitArgs(command);
    if (args.isEmpty || args.first != 'tag') {
      return false;
    }
    if (GitTools.isReadOnly(command)) {
      return false;
    }
    return !args.any((arg) => arg == '-d' || arg == '--delete');
  }

  bool _isSuccessfulGitTagFormatInspection(
    ToolResultInfo toolResult, {
    required String workingDirectory,
  }) {
    if (toolResult.name != 'git_execute_command') {
      return false;
    }
    final command = GitTools.normalizeCommand(
      (toolResult.arguments['command'] as String?)?.trim() ?? '',
    );
    if (!_isGitTagFormatInspectionCommand(command)) {
      return false;
    }
    final decoded = _decodeJsonObject(toolResult.result);
    if (decoded == null || decoded['exit_code'] != 0) {
      return false;
    }
    final resultWorkingDirectory = decoded['working_directory'];
    return workingDirectory.isEmpty ||
        resultWorkingDirectory is! String ||
        resultWorkingDirectory == workingDirectory;
  }

  bool _isGitTagFormatInspectionCommand(String command) {
    final args = GitTools.splitArgs(command);
    if (args.isEmpty) {
      return false;
    }
    if (args.first == 'tag' && GitTools.isReadOnly(command)) {
      return true;
    }
    if (args.first == 'for-each-ref' &&
        args.any((arg) => arg == 'refs/tags' || arg.startsWith('refs/tags/'))) {
      return true;
    }
    if (args.first == 'show-ref' && args.contains('--tags')) {
      return true;
    }
    return false;
  }

  bool _shouldRequestToolLoopExhaustionRecovery({
    required List<ToolCallInfo> pendingToolCalls,
    required List<ToolResultInfo> currentToolResults,
  }) {
    return _toolLoopRecoveryPolicy.shouldRequestExhaustionRecovery(
      pendingToolCalls: pendingToolCalls,
      currentToolResults: currentToolResults,
      isWriteGitCommandToolCall: _isWriteGitCommandToolCall,
    );
  }

  bool _isProductionReleaseCommandToolCall(ToolCallInfo toolCall) {
    final toolName = toolCall.name.trim().toLowerCase();
    if (toolName != 'local_execute_command' && toolName != 'process_start') {
      return false;
    }
    if (_isReadOnlyCommandExecutionToolCall(toolCall)) {
      return false;
    }
    final command = _toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return false;
    }
    return _looksLikeProductionReleaseCommand(command);
  }

  bool _looksLikeProductionReleaseCommand(String command) {
    final args = GitTools.splitArgs(command);
    if (args.isEmpty) {
      return false;
    }
    if (args.any((arg) {
      final normalized = arg.trim().toLowerCase();
      return normalized == '--dry-run' ||
          normalized == '-n' ||
          normalized == '--help' ||
          normalized == '-h';
    })) {
      return false;
    }
    const releaseScripts = {
      'release_ios_macos.sh',
      'build_macos_sparkle_release.sh',
      'publish_macos_sparkle_release.sh',
    };
    return args.any((arg) {
      final normalized = arg.trim().toLowerCase();
      if (normalized.isEmpty || normalized.startsWith('-')) {
        return false;
      }
      final basename = normalized.split('/').last;
      return releaseScripts.contains(basename);
    });
  }

  bool _latestUserExplicitlyApprovedProductionRelease() {
    for (var index = state.messages.length - 1; index >= 0; index -= 1) {
      final message = state.messages[index];
      if (message.role != MessageRole.user) {
        continue;
      }
      final content = message.content.trim();
      if (content.isEmpty) {
        continue;
      }
      if (_looksLikeExplicitProductionReleaseApproval(content)) {
        return true;
      }
      return _looksLikeAffirmativeReleaseApprovalAnswer(content) &&
          _previousAssistantAskedForProductionReleaseApproval(index);
    }
    return false;
  }

  bool _previousAssistantAskedForProductionReleaseApproval(int beforeIndex) {
    for (var index = beforeIndex - 1; index >= 0; index -= 1) {
      final message = state.messages[index];
      final content = message.content.trim();
      if (content.isEmpty) {
        continue;
      }
      if (message.role == MessageRole.assistant) {
        return _looksLikeProductionReleaseApprovalPrompt(content);
      }
      if (message.role == MessageRole.user) {
        return false;
      }
    }
    return false;
  }

  bool _hasExplicitProductionReleaseApproval(int interactionGeneration) {
    if (_latestUserExplicitlyApprovedProductionRelease()) {
      return true;
    }
    return _askUserQuestionTurnCache.anyResult(
      interactionGeneration,
      _answerGrantsProductionReleaseApproval,
    );
  }

  bool _answerGrantsProductionReleaseApproval(McpToolResult answerResult) {
    if (!answerResult.isSuccess) {
      return false;
    }
    final decoded = _decodeJsonObject(answerResult.result);
    if (decoded == null || decoded['status'] != 'answered') {
      return false;
    }

    String questionText = '';
    final answerEvidence = <String>[];
    void addEvidence(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        answerEvidence.add(value.trim());
      }
    }

    final questionValue = decoded['question'];
    if (questionValue is String && questionValue.trim().isNotEmpty) {
      questionText = questionValue.trim();
    }
    addEvidence(decoded['answer']);
    addEvidence(decoded['other']);
    final selected = decoded['selected'];
    if (selected is List) {
      for (final option in selected) {
        if (option is Map) {
          addEvidence(option['label']);
          addEvidence(option['description']);
          addEvidence(option['preview']);
        } else {
          addEvidence(option);
        }
      }
    }

    if (answerEvidence.isEmpty) {
      return false;
    }
    if (answerEvidence.any(_looksLikeExplicitProductionReleaseApproval)) {
      return true;
    }
    if (!_looksLikeExplicitProductionReleaseApproval(questionText)) {
      return false;
    }
    return answerEvidence.any(_looksLikeAffirmativeReleaseApprovalAnswer);
  }

  bool _looksLikeExplicitProductionReleaseApproval(String content) {
    final lowerContent = content.toLowerCase();
    if (RegExp(r'^\s*(release|ship)\b').hasMatch(lowerContent)) {
      return true;
    }
    if (!_mentionsProductionRelease(content)) {
      return false;
    }
    return _containsAny(lowerContent, const [
          'run',
          'execute',
          'start',
          'publish',
          'upload',
          'ship',
          'production',
          'prod',
          'go ahead',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x5b9f, 0x884c],
          [0x9032, 0x3081],
          [0x516c, 0x958b],
          [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9],
          [0x672c, 0x756a],
          [0x3057, 0x3066],
          [0x304a, 0x9858, 0x3044],
          [0x3084, 0x3063, 0x3066],
        ]);
  }

  bool _looksLikeProductionReleaseApprovalPrompt(String content) {
    if (!_mentionsProductionRelease(content)) {
      return false;
    }
    final lowerContent = content.toLowerCase();
    final asksForApproval =
        _containsAny(lowerContent, const [
          'approve',
          'approval',
          'confirm',
          'permission',
          'authorize',
          'run',
          'execute',
          'proceed',
        ]) ||
        content.contains('?') ||
        content.contains(String.fromCharCode(0xff1f)) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x627f, 0x8a8d],
          [0x8a31, 0x53ef],
          [0x5b9f, 0x884c],
          [0x9032, 0x3081],
          [0x3057, 0x307e, 0x3059, 0x304b],
        ]);
    if (!asksForApproval) {
      return false;
    }
    return _containsAny(lowerContent, const [
          'production',
          'prod',
          'command',
          'release',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x672c, 0x756a],
          [0x30b3, 0x30de, 0x30f3, 0x30c9],
          [0x30ea, 0x30ea, 0x30fc, 0x30b9],
        ]);
  }

  bool _mentionsProductionRelease(String content) {
    final lowerContent = content.toLowerCase();
    return _containsAny(lowerContent, const [
          'release',
          'publish',
          'upload',
          'app store connect',
          'sparkle',
          's3',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x30ea, 0x30ea, 0x30fc, 0x30b9],
          [0x672c, 0x756a],
          [0x516c, 0x958b],
          [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9],
        ]);
  }

  bool _looksLikeAffirmativeReleaseApprovalAnswer(String content) {
    final lowerContent = content.toLowerCase();
    if (_containsAny(lowerContent, const [
      'do not',
      "don't",
      'dont',
      'no',
      'cancel',
      'decline',
      'deny',
      'reject',
      'skip',
      'stop',
      'block',
      'not release',
      'not now',
    ])) {
      return false;
    }
    return _containsAny(lowerContent, const [
          'approve',
          'approved',
          'yes',
          'go ahead',
          'proceed',
          'run',
          'execute',
          'release',
          'ship',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x627f, 0x8a8d],
          [0x306f, 0x3044],
          [0x9032, 0x3081],
          [0x5b9f, 0x884c],
          [0x516c, 0x958b],
          [0x672c, 0x756a],
          [0x304a, 0x9858, 0x3044],
          [0x3084, 0x3063, 0x3066],
        ]);
  }

  bool _shouldBlockToolCallsForUserConfirmation({
    required String? currentAssistantContent,
    required List<ToolCallInfo> toolCalls,
  }) {
    final candidate = currentAssistantContent?.trim() ?? '';
    if (!_looksLikeGitWriteConfirmationQuestion(candidate)) {
      return false;
    }
    return toolCalls.any(_isWriteGitCommandToolCall);
  }

  bool _isWriteGitCommandToolCall(ToolCallInfo toolCall) {
    if (toolCall.name.trim().toLowerCase() != 'git_execute_command') {
      return false;
    }
    final command = _toolCommandArgument(toolCall.arguments);
    return command != null && !GitTools.isReadOnly(command);
  }

  bool _looksLikeGitWriteConfirmationQuestion(String content) {
    if (content.isEmpty || content.length > 1200) {
      return false;
    }
    final lowerContent = content.toLowerCase();
    final hasQuestionMarker =
        lowerContent.contains('?') ||
        content.contains(String.fromCharCode(0xff1f)) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x3057, 0x307e, 0x3059, 0x304b],
          [0x3057, 0x3066, 0x3082, 0x3044, 0x3044, 0x3067, 0x3059, 0x304b],
          [0x3057, 0x3066, 0x3088, 0x3044, 0x3067, 0x3059, 0x304b],
        ]);
    if (!hasQuestionMarker) {
      return false;
    }
    if (RegExp(
      r'\b(commit|stage|staging|push|reset|checkout|merge|rebase)\b',
    ).hasMatch(lowerContent)) {
      return true;
    }
    if (_containsAny(lowerContent, const ['git add', 'git commit'])) {
      return true;
    }
    return _containsAnyCodeUnitSequence(content, const [
      [0x30b3, 0x30df, 0x30c3, 0x30c8],
      [0x30b9, 0x30c6, 0x30fc, 0x30b8],
      [0x30d7, 0x30c3, 0x30b7, 0x30e5],
      [0x30ea, 0x30bb, 0x30c3, 0x30c8],
      [0x30c1, 0x30a7, 0x30c3, 0x30af, 0x30a2, 0x30a6, 0x30c8],
      [0x30de, 0x30fc, 0x30b8],
      [0x30ea, 0x30d9, 0x30fc, 0x30b9],
    ]);
  }

  bool _containsCommandExecutionContext(String content) {
    final lowerContent = content.toLowerCase();
    if (_containsAny(lowerContent, const [
      'local command',
      'command line',
      'shell command',
      'local_execute_command',
      'run_tests',
      'git_execute_command',
      'dry run',
      'dry-run',
      'release script',
      'tool/release_',
      'flutter test',
      'flutter analyze',
      'flutter build',
      'dart test',
      'git commit',
      'git add',
      'git push',
      'xcodebuild',
      'app store connect',
      'build/ios',
      'ipa',
      'bash ',
    ])) {
      return true;
    }
    return _containsAnyCodeUnitSequence(content, const [
      [0x30d3, 0x30eb, 0x30c9],
      [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9],
      [0x30ea, 0x30ea, 0x30fc, 0x30b9],
      [0x30d7, 0x30ed, 0x30bb, 0x30b9],
      [0x30b3, 0x30de, 0x30f3, 0x30c9],
      [0x30b3, 0x30df, 0x30c3, 0x30c8],
      [0x30b9, 0x30c6, 0x30fc, 0x30b8],
      [0x30d7, 0x30c3, 0x30b7, 0x30e5],
      [0x691c, 0x8a3c],
      [0x5b9f, 0x884c],
    ]);
  }

  bool _looksLikeCommandExecutionQuestion(String content) {
    final lowerContent = content.toLowerCase();
    if (_containsAny(lowerContent, const [
      'should i run',
      'shall i run',
      'do you want me to run',
      'would you like me to run',
      'can i run',
      'run it?',
      'execute it?',
    ])) {
      return true;
    }
    final hasQuestionMark =
        lowerContent.contains('?') ||
        content.contains(String.fromCharCode(0xff1f));
    return hasQuestionMark &&
        _containsAnyCodeUnitSequence(content, const [
          [0x5b9f, 0x884c, 0x3057, 0x307e, 0x3059, 0x304b],
          [0x30b3, 0x30df, 0x30c3, 0x30c8, 0x3057, 0x307e, 0x3059, 0x304b],
          [0x30b9, 0x30c6, 0x30fc, 0x30b8, 0x3057, 0x307e, 0x3059, 0x304b],
          [0x30d7, 0x30c3, 0x30b7, 0x30e5, 0x3057, 0x307e, 0x3059, 0x304b],
        ]);
  }

  bool _containsCjkFutureCommandExecutionAction(String value) {
    final hasAction = _containsAnyCodeUnitSequence(value, const [
      [0x5b9f, 0x884c, 0x3057, 0x307e, 0x3059],
      [0x8d70, 0x3089, 0x305b, 0x307e, 0x3059],
      [0x958b, 0x59cb, 0x3057, 0x307e, 0x3059],
      [0x958b, 0x59cb, 0x3057, 0x307e, 0x3057, 0x305f],
      [0x30b3, 0x30df, 0x30c3, 0x30c8, 0x3057, 0x307e, 0x3059],
      [0x30b9, 0x30c6, 0x30fc, 0x30b8, 0x3057, 0x307e, 0x3059],
      [0x30d7, 0x30c3, 0x30b7, 0x30e5, 0x3057, 0x307e, 0x3059],
    ]);
    if (!hasAction) {
      return false;
    }
    return _containsAnyCodeUnitSequence(value, const [
      [0x30c9, 0x30e9, 0x30a4, 0x30e9, 0x30f3],
      [0x30ed, 0x30fc, 0x30ab, 0x30eb, 0x30b3, 0x30de, 0x30f3, 0x30c9],
      [0x30b3, 0x30de, 0x30f3, 0x30c9],
      [0x30b3, 0x30df, 0x30c3, 0x30c8],
      [0x30b9, 0x30c6, 0x30fc, 0x30b8],
      [0x30d7, 0x30c3, 0x30b7, 0x30e5],
      [0x691c, 0x8a3c],
      [0x30c6, 0x30b9, 0x30c8],
      [0x9759, 0x7684, 0x89e3, 0x6790],
      [0x89e3, 0x6790],
      [0x30ea, 0x30ea, 0x30fc, 0x30b9],
      [0x672c, 0x756a],
      [0x30b9, 0x30af, 0x30ea, 0x30d7, 0x30c8],
    ]);
  }
}
