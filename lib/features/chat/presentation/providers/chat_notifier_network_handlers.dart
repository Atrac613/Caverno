// Same-library bridge for owner-scoped HTTP mutation approval.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

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
