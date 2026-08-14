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
  Future<McpToolResult> _handleBrowserAction(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final policy = BrowserToolPolicy.decision(toolCall.name);
    final gate = await _resolveToolApprovalGate(
      approvalCache,
      toolCall: toolCall,
      actionKind: toolCall.name,
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.browser,
      fullAccessEligible: true,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        approvalCache.owner,
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
    final gateExpired = _expiredApproval(toolCall.name, approvalCache);
    if (gateExpired != null) return gateExpired;
    if (gate.isDenied) {
      return _browserAutoReviewDeniedResult(toolCall, gate.deniedRationale!);
    }
    if (gate.needsManual) {
      final details = await _browserActionDetails(toolCall);
      final approved = await requestBrowserAction(
        owner: approvalCache.owner,
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
      if (!approved && _isApprovalOwnerCurrent(approvalCache.owner)) {
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
    final expired = _expiredApproval(toolCall.name, approvalCache);
    if (expired != null) return expired;
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
    required ChatTurnOwner owner,
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
    String capability = 'browser_action',
  }) {
    final completer = Completer<bool>();
    final pending = PendingBrowserAction(
      owner: owner,
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
    return _registerPendingToolApproval(
      pending,
      (s) => s.copyWith(pendingBrowserAction: pending),
      capability,
      _approvalSummary(reason, summary),
      targetSummary,
    );
  }

  bool resolveBrowserAction({required String id, required bool approved}) =>
      _completeApproval<bool, PendingBrowserAction>(id, (_) => approved);

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

extension ChatNotifierNetworkHandlers on ChatNotifier {
  Future<McpToolResult?> _enforceNetworkReadTaint(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache? approvalCache,
  ) async {
    final capability = const ToolCapabilityClassifier().classify(toolCall.name);
    final isUngatedNetworkRead =
        capability.capabilityClass == ToolCapabilityClass.networkFetch ||
        capability.capabilityClass == ToolCapabilityClass.browserControl &&
            !BrowserToolPolicy.requiresUserApproval(toolCall.name);
    if (!isUngatedNetworkRead ||
        approvalCache == null ||
        !_conversationTaintState.hasUntrustedInfluence(
          owner: approvalCache.owner,
        )) {
      return null;
    }

    final approvalArguments = _networkReadApprovalArguments(toolCall);
    final gate = await _resolveToolApprovalGate(
      approvalCache,
      toolCall: toolCall,
      actionKind: 'tainted_network_access',
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.network,
      fullAccessEligible: true,
      auditArguments: approvalArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        approvalCache.owner,
        toolCall: toolCall,
        actionKind: 'tainted_network_access',
        arguments: approvalArguments,
        path: approvalArguments['target'] as String?,
        warningTitle: 'Approve tainted network access',
        warningMessage:
            'Untrusted content influenced this outbound network request.',
      ),
    );
    final gateExpired = _expiredApproval(toolCall.name, approvalCache);
    if (gateExpired != null) return gateExpired;
    if (gate.isDenied) {
      return _networkMutationDeniedResult(
        toolCall,
        code: 'taint_policy_denied',
        message: gate.deniedRationale ?? 'Taint policy denied network access.',
      );
    }
    final approved = await requestBrowserAction(
      owner: approvalCache.owner,
      toolName: toolCall.name,
      title: 'Approve outbound network access',
      riskLabel: 'Untrusted-influence network access',
      warningMessage:
          'Remote or otherwise untrusted content influenced this request.',
      approveLabel: 'Allow once',
      summary: _networkReadSummary(toolCall, approvalArguments),
      details: _networkReadDetails(approvalArguments),
      targetSummary: 'Confirm this exact destination before continuing.',
      capability: 'tainted_network_access',
    );
    if (!approved && _isApprovalOwnerCurrent(approvalCache.owner)) {
      return _networkMutationDeniedResult(
        toolCall,
        code: 'approval_denied',
        message: 'User denied tainted network access.',
      );
    }
    return _expiredApproval(toolCall.name, approvalCache);
  }

  Future<McpToolResult> _handleNetworkMutation(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final approvalArguments = _networkMutationApprovalArguments(toolCall);
    final gate = await _resolveToolApprovalGate(
      approvalCache,
      toolCall: toolCall,
      actionKind: 'network_mutation',
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.network,
      fullAccessEligible: true,
      auditArguments: approvalArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        approvalCache.owner,
        toolCall: toolCall,
        actionKind: 'network_mutation',
        arguments: approvalArguments,
        path: approvalArguments['target'] as String?,
        reason: toolCall.arguments['reason'] as String?,
        warningTitle: 'Approve HTTP state change',
        warningMessage:
            'This request can change data or trigger an action on a remote service.',
        preview: _networkMutationBodyPreview(toolCall),
      ),
    );
    final gateExpired = _expiredApproval(toolCall.name, approvalCache);
    if (gateExpired != null) return gateExpired;
    if (gate.isDenied) {
      return _networkMutationDeniedResult(
        toolCall,
        code: 'policy_denied',
        message: gate.deniedRationale ?? 'Network mutation denied.',
      );
    }
    if (gate.needsManual) {
      final approved = await requestBrowserAction(
        owner: approvalCache.owner,
        toolName: toolCall.name,
        title: 'Approve ${_networkMutationMethod(toolCall)} request',
        riskLabel: 'High-risk network mutation',
        warningMessage:
            'This request can change remote data or trigger an external action.',
        approveLabel: 'Send request',
        summary:
            '${_networkMutationMethod(toolCall)} ${approvalArguments['target']}',
        details: _networkMutationDetails(toolCall, approvalArguments),
        targetSummary: 'Review the destination and request metadata.',
        sensitiveValuePreview: _networkMutationBodyPreview(toolCall),
        reason: toolCall.arguments['reason'] as String?,
        capability: 'network_mutation',
      );
      if (!approved && _isApprovalOwnerCurrent(approvalCache.owner)) {
        return _networkMutationDeniedResult(
          toolCall,
          code: 'approval_denied',
          message: 'User denied the network mutation.',
        );
      }
    }
    final expired = _expiredApproval(toolCall.name, approvalCache);
    if (expired != null) return expired;
    return _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: Map<String, dynamic>.unmodifiable(toolCall.arguments),
    );
  }

  Map<String, dynamic> _networkMutationApprovalArguments(
    ToolCallInfo toolCall,
  ) {
    final headers = toolCall.arguments['headers'];
    final headerNames = headers is Map
        ? (headers.keys.map((key) => key.toString()).toList()..sort())
        : const <String>[];
    final body = toolCall.arguments['body'] as String?;
    return <String, dynamic>{
      'method': _networkMutationMethod(toolCall),
      'target': _redactedNetworkTarget(toolCall.arguments['url'] as String?),
      'headerNames': headerNames,
      'bodyLength': body?.length ?? 0,
      if ((toolCall.arguments['content_type'] as String?)?.trim()
          case final contentType? when contentType.isNotEmpty)
        'contentType': contentType,
      'followRedirects':
          toolCall.arguments['follow_redirects'] as bool? ?? true,
    };
  }

  Map<String, dynamic> _networkReadApprovalArguments(ToolCallInfo toolCall) {
    if (toolCall.name.startsWith('http_')) {
      final headers = toolCall.arguments['headers'];
      final headerNames = headers is Map
          ? (headers.keys.map((key) => key.toString()).toList()..sort())
          : const <String>[];
      return <String, dynamic>{
        'operation': toolCall.name,
        'target': _redactedNetworkTarget(toolCall.arguments['url'] as String?),
        'headerNames': headerNames,
      };
    }
    return <String, dynamic>{
      'operation': toolCall.name,
      if (toolCall.arguments['url'] case final String url)
        'target': _redactedNetworkTarget(url),
    };
  }

  String _networkReadSummary(
    ToolCallInfo toolCall,
    Map<String, dynamic> approvalArguments,
  ) {
    final target = approvalArguments['target'] as String?;
    return target == null || target.isEmpty
        ? toolCall.name
        : '${toolCall.name} $target';
  }

  List<String> _networkReadDetails(Map<String, dynamic> approvalArguments) {
    final headerNames = approvalArguments['headerNames'];
    return [
      'Operation: ${approvalArguments['operation']}',
      if (approvalArguments['target'] case final String target)
        'Destination: $target',
      if (headerNames is List && headerNames.isNotEmpty)
        'Header names: ${headerNames.join(', ')}',
    ];
  }

  List<String> _networkMutationDetails(
    ToolCallInfo toolCall,
    Map<String, dynamic> approvalArguments,
  ) {
    final headerNames = approvalArguments['headerNames'] as List<String>;
    return [
      'Method: ${approvalArguments['method']}',
      'Destination: ${approvalArguments['target']}',
      'Body length: ${approvalArguments['bodyLength']} characters',
      if (approvalArguments['contentType'] case final String contentType)
        'Content type: $contentType',
      if (headerNames.isNotEmpty) 'Header names: ${headerNames.join(', ')}',
      'Follow redirects: ${approvalArguments['followRedirects']}',
    ];
  }

  String _networkMutationMethod(ToolCallInfo toolCall) =>
      toolCall.name.substring('http_'.length).toUpperCase();

  String _redactedNetworkTarget(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return value;
    final redactedQuery = {
      for (final key in uri.queryParametersAll.keys) key: '[redacted]',
    };
    return uri
        .replace(
          userInfo: '',
          queryParameters: redactedQuery.isEmpty ? null : redactedQuery,
        )
        .toString();
  }

  String? _networkMutationBodyPreview(ToolCallInfo toolCall) {
    final body = toolCall.arguments['body'] as String?;
    if (body == null || body.isEmpty) return null;
    return 'Request body withheld (${body.length} characters).';
  }

  McpToolResult _networkMutationDeniedResult(
    ToolCallInfo toolCall, {
    required String code,
    required String message,
  }) {
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({'ok': false, 'code': code, 'error': message}),
      isSuccess: false,
      errorMessage: message,
    );
  }
}
