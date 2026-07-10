// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierPythonHandlers on ChatNotifier {
  Future<McpToolResult> _handlePythonScript(ToolCallInfo toolCall) async {
    final code = (toolCall.arguments['code'] as String?)?.trim() ?? '';
    if (code.isEmpty) {
      const missingCodeMessage =
          'code is required; call run_python_script again with a complete '
          'Python script in the code argument. Use caverno.inputs[0] for '
          'attached files when analyzing attachments.';
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: missingCodeMessage,
      );
    }

    // Approval is keyed on the script source only; `reason` is non-semantic.
    final cacheArguments = <String, dynamic>{'code': code};
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final reason = toolCall.arguments['reason'] as String?;

    // Stage the working directory + any image the user attached before
    // prompting, so the approval surfaces the real working directory and the
    // script can reach attachments through `caverno.inputs`.
    final inputMessage = _latestPythonInputMessage();
    final staged = await PythonInputStaging.stage(
      imageBase64: inputMessage?.imageBase64,
      imageMimeType: inputMessage?.imageMimeType,
      originalImagePath: inputMessage?.originalImagePath,
      originalImageMimeType: inputMessage?.originalImageMimeType,
    );

    // Running model-written Python with file + network access is high-risk, so
    // it goes through the same approval gate as local_execute_command.
    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'run_python_script',
      mode: _settings.codingApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.coding,
      fullAccessEligible: true,
      approvalCacheArguments: cacheArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'run_python_script',
        arguments: cacheArguments,
        workingDirectory: staged.workingDirectory,
        reason: reason,
        preview: code,
      ),
    );
    if (gate.isDenied) {
      return _rememberToolApprovalDenial(
        toolCall.name,
        cacheArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final approved = await requestFileOperation(
        operation: 'Run Python script',
        path: staged.workingDirectory,
        preview: code,
        reason: reason,
      );
      if (!approved) {
        return _rememberToolApprovalDenial(
          toolCall.name,
          cacheArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User denied Python script execution',
          ),
        );
      }
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: {
        'code': code,
        'working_directory': staged.workingDirectory,
        'inputs': staged.inputs,
        if (toolCall.arguments['timeout_seconds'] != null)
          'timeout_seconds': toolCall.arguments['timeout_seconds'],
      },
    );

    // Full access never caches so the model can iterate; approvals cache to
    // avoid re-prompting for the identical script within the same turn.
    return gate.bypassedApproval
        ? result
        : _rememberToolApprovalResult(toolCall.name, cacheArguments, result);
  }

  /// Most recent user message carrying an image attachment, if any.
  Message? _latestPythonInputMessage() {
    for (final message in state.messages.reversed) {
      if (message.role == MessageRole.user &&
          ((message.originalImagePath?.isNotEmpty ?? false) ||
              (message.imageBase64?.isNotEmpty ?? false))) {
        return message;
      }
    }
    return null;
  }
}
