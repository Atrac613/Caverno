// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// Handlers for the built-in browser tools. Sensitive actions (fill, click,
/// submit, eval, save) route through [_handleBrowserAction]; read/observe
/// actions run without approval.
///
/// The chat-mode permission setting ([AppSettings.chatApprovalMode]) decides
/// how sensitive actions are gated:
/// - default: prompt the user for one-tap approval (the original behavior);
/// - auto-review: the configured LLM endpoint allows/denies each action;
/// - full access: actions run automatically without a prompt. This powers
///   hands-off browser automation (e.g. clicking through a multi-step flow).
///
/// Unlike the macOS computer-use handler, this deliberately does NOT cache
/// results by (name, arguments): repeated identical browser actions (e.g.
/// clicking a "Next" button) must re-execute, so we only gate on approval.
extension ChatNotifierBrowserHandlers on ChatNotifier {
  Future<McpToolResult> _handleBrowserAction(ToolCallInfo toolCall) async {
    final policy = BrowserToolPolicy.decision(toolCall.name);
    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: toolCall.name,
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.browser,
      fullAccessEligible: true,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: toolCall.name,
        // Sanitized args: raw secret-bearing fields are dropped; a masked
        // preview rides along in `preview` instead (see _browserReviewArguments).
        arguments: _browserReviewArguments(toolCall),
        reason: toolCall.arguments['reason'] as String?,
        warningMessage: policy.warningMessage,
        preview: _browserSensitiveValuePreview(toolCall),
      ),
    );
    if (gate.isDenied) {
      return _browserAutoReviewDeniedResult(toolCall, gate.deniedRationale!);
    }
    if (gate.needsManual) {
      final details = await _browserActionDetails(toolCall);
      final approved = await requestBrowserAction(
        toolName: toolCall.name,
        title: policy.title,
        riskLabel: policy.riskLabel,
        warningMessage: policy.warningMessage,
        approveLabel: policy.approveLabel,
        summary: _describeBrowserAction(toolCall),
        details: details,
        targetSummary: _browserActionTargetSummary(toolCall),
        sensitiveValuePreview: _browserSensitiveValuePreview(toolCall),
        reason: toolCall.arguments['reason'] as String?,
      );
      if (!approved) {
        return McpToolResult(
          toolName: toolCall.name,
          result: jsonEncode({
            'ok': false,
            'code': 'approval_denied',
            'error': 'User denied the browser action.',
            'nextAction':
                'Ask the user for explicit approval before retrying this browser action.',
          }),
          isSuccess: false,
          errorMessage: 'User denied browser action.',
        );
      }
    }
    return _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
  }

  Future<McpToolResult> _handleBrowserActionWithoutApproval(
    ToolCallInfo toolCall,
  ) {
    return _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
  }

  /// Builds the argument map sent to the auto-reviewer. Raw secret-bearing
  /// fields (`value`, `script`, `data`) are dropped so credentials are never
  /// forwarded to the review endpoint; a masked/truncated preview is carried in
  /// the request's `preview` field instead. The page host (never the full URL,
  /// which may carry credentials) is added for context.
  Map<String, dynamic> _browserReviewArguments(ToolCallInfo toolCall) {
    const omittedKeys = {'value', 'script', 'data'};
    final sanitized = <String, dynamic>{
      for (final entry in toolCall.arguments.entries)
        if (!omittedKeys.contains(entry.key)) entry.key: entry.value,
    };
    final url = ref.read(browserSessionServiceProvider).currentUrl;
    final host = url == null ? null : Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) {
      sanitized['pageHost'] = host;
    }
    return sanitized;
  }

  McpToolResult _browserAutoReviewDeniedResult(
    ToolCallInfo toolCall,
    String rationale,
  ) {
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': 'auto_review_denied',
        'error': 'Auto-review denied this browser action. $rationale',
        'nextAction':
            'Ask the user for explicit approval before retrying this browser action.',
      }),
      isSuccess: false,
      errorMessage: 'Auto-review denied: $rationale',
    );
  }

  Future<bool> requestBrowserAction({
    required String toolName,
    required String title,
    required String riskLabel,
    required String warningMessage,
    required String approveLabel,
    required String summary,
    required List<String> details,
    String? targetSummary,
    String? sensitiveValuePreview,
    String? reason,
  }) {
    final completer = Completer<bool>();
    final pending = PendingBrowserAction(
      id: const Uuid().v4(),
      toolName: toolName,
      title: title,
      riskLabel: riskLabel,
      warningMessage: warningMessage,
      approveLabel: approveLabel,
      summary: summary,
      details: details,
      targetSummary: targetSummary,
      sensitiveValuePreview: sensitiveValuePreview,
      reason: reason,
      completer: completer,
    );
    state = state.copyWith(pendingBrowserAction: pending);
    _emitRuntimeApprovalRequired(
      id: pending.id,
      capability: 'browser_action',
      summary: reason?.trim().isNotEmpty == true ? reason!.trim() : summary,
      target: targetSummary,
    );
    return completer.future;
  }

  void resolveBrowserAction({required String id, required bool approved}) {
    final pending = state.pendingBrowserAction;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingBrowserAction: null);
  }

  String _describeBrowserAction(ToolCallInfo toolCall) {
    final args = toolCall.arguments;
    return switch (toolCall.name) {
      'browser_fill' =>
        'Fill ${_browserTargetLabel(args)} with ${_browserSensitiveValuePreview(toolCall) ?? 'a value'}',
      'browser_click' => 'Click ${_browserTargetLabel(args)}',
      'browser_submit' =>
        (args['selector'] as String?)?.isNotEmpty ?? false
            ? 'Submit the form containing ${args['selector']}'
            : 'Submit the current form',
      'browser_eval' =>
        'Run JavaScript in the page (${((args['script'] as String?) ?? '').length} chars)',
      'browser_save_data' => 'Save data to ${args['filename'] ?? 'a file'}',
      _ => toolCall.name,
    };
  }

  String _browserTargetLabel(Map<String, dynamic> args) {
    if (args['ref'] != null) return 'element #${args['ref']}';
    final selector = (args['selector'] as String?)?.trim();
    if (selector != null && selector.isNotEmpty) return 'selector "$selector"';
    return 'the target element';
  }

  Future<List<String>> _browserActionDetails(ToolCallInfo toolCall) async {
    final args = toolCall.arguments;
    final details = <String>['Tool: ${toolCall.name}'];
    switch (toolCall.name) {
      case 'browser_fill':
      case 'browser_click':
        if (args['ref'] != null) details.add('Target ref: ${args['ref']}');
        if ((args['selector'] as String?)?.isNotEmpty ?? false) {
          details.add('Selector: ${args['selector']}');
        }
      case 'browser_submit':
        if ((args['selector'] as String?)?.isNotEmpty ?? false) {
          details.add('Form selector: ${args['selector']}');
        }
      case 'browser_save_data':
        final target = await ref
            .read(browserSessionServiceProvider)
            .resolveSaveTarget(
              filename: (args['filename'] as String?) ?? 'browser_data',
              format: (args['format'] as String?) ?? 'json',
              destination: args['destination'] as String?,
            );
        details.add('Destination: ${target.destination.label}');
        if (target.destinationChanged) {
          details.add('Requested destination: ${target.requestedDestination}');
        }
        details.add('Requested file: ${target.requestedFilename}');
        details.add('Final file: ${target.filename}');
        details.add('Save location: ${target.directory.path}');
        details.add('Full path: ${target.path}');
        details.add(
          'Size: ${((args['data'] as String?) ?? '').length} characters',
        );
      case 'browser_eval':
        details.add(
          'Script length: ${((args['script'] as String?) ?? '').length} characters',
        );
    }
    final reason = args['reason'] as String?;
    if (reason != null && reason.trim().isNotEmpty) {
      details.add('Model reason: ${reason.trim()}');
    }
    // Show only the host (never the full URL, which may carry credentials).
    final url = ref.read(browserSessionServiceProvider).currentUrl;
    final host = url == null ? null : Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) {
      details.add('Page: $host');
    }
    return details;
  }

  String? _browserActionTargetSummary(ToolCallInfo toolCall) {
    return switch (toolCall.name) {
      'browser_fill' || 'browser_click' =>
        'Review the target ${_browserTargetLabel(toolCall.arguments)} before approving.',
      'browser_save_data' => 'A file will be written to your device.',
      'browser_eval' => 'Arbitrary JavaScript will run in the current page.',
      _ => null,
    };
  }

  /// Builds a preview for the approval sheet. Credential-like fills are masked;
  /// `browser_eval` shows the (truncated) script so the user can vet it.
  String? _browserSensitiveValuePreview(ToolCallInfo toolCall) {
    if (toolCall.name == 'browser_eval') {
      final script = (toolCall.arguments['script'] as String?) ?? '';
      return script.length > 400 ? '${script.substring(0, 400)}…' : script;
    }
    if (toolCall.name != 'browser_fill') return null;
    final value = (toolCall.arguments['value'] as String?) ?? '';
    if (value.isEmpty) return '(empty)';
    if (_browserLooksLikeSecret(toolCall.arguments)) {
      return '${'•' * value.length.clamp(0, 32)} (${value.length} chars, hidden)';
    }
    return value.length > 80 ? '${value.substring(0, 80)}…' : value;
  }

  bool _browserLooksLikeSecret(Map<String, dynamic> args) {
    final selector = ((args['selector'] as String?) ?? '').toLowerCase();
    return selector.contains('pass') ||
        selector.contains('pwd') ||
        selector.contains('secret') ||
        selector.contains('otp') ||
        selector.contains('token');
  }
}
