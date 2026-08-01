// ChatNotifier decomposition collaborator: browser-tool-handler

import 'dart:convert';

import '../../../../core/services/browser_tool_policy.dart';
import '../entities/mcp_tool_entity.dart';
import 'browser_session_ownership_coordinator.dart';
import 'browser_tool_contract.dart';

export 'browser_tool_contract.dart';

/// Classifies, approves, presents, and executes built-in browser tools.
final class BrowserToolHandler {
  const BrowserToolHandler({
    required BrowserExecutionPort executionPort,
    required BrowserApprovalPort approvalPort,
    required BrowserObservationPort observationPort,
    required BrowserSessionOwnershipCoordinator sessionCoordinator,
  }) : _executionPort = executionPort,
       _approvalPort = approvalPort,
       _observationPort = observationPort,
       _sessionCoordinator = sessionCoordinator;

  final BrowserExecutionPort _executionPort;
  final BrowserApprovalPort _approvalPort;
  final BrowserObservationPort _observationPort;
  final BrowserSessionOwnershipCoordinator _sessionCoordinator;

  Future<McpToolResult> handle(BrowserToolRequest request) {
    return _runInSession(
      request,
      (lease) => BrowserToolPolicy.requiresUserApproval(request.toolName)
          ? _handleSensitiveAction(request, lease)
          : _execute(request, lease),
    );
  }

  Future<McpToolResult> handleWithoutApproval(BrowserToolRequest request) {
    return _runInSession(request, (lease) => _execute(request, lease));
  }

  Future<McpToolResult> _runInSession(
    BrowserToolRequest request,
    Future<McpToolResult> Function(BrowserSessionLease lease) action,
  ) async {
    final operation = request.operation;
    final acquisition = _sessionCoordinator.acquire(
      operation,
      _sessionCoordinator.captureSessionEpoch(),
    );
    final lease = acquisition.lease;
    if (lease == null) {
      return acquisition.kind == BrowserSessionLeaseAcquisitionKind.busy
          ? _failure(
              request.toolName,
              'browser_busy',
              'Another browser operation is still active.',
            )
          : _expiredResult(request.toolName);
    }
    try {
      final result = _requireToolResult(
        request,
        await action(lease),
        'Browser scoped result',
      );
      return _leaseCurrent(lease) ? result : _expiredResult(request.toolName);
    } finally {
      if (!_sessionCoordinator.release(
        operation,
        lease.sessionEpoch,
        lease.token,
      )) {
        _sessionCoordinator.settleInvalidatedLease(lease);
      }
    }
  }

  Future<McpToolResult> _handleSensitiveAction(
    BrowserToolRequest request,
    BrowserSessionLease lease,
  ) async {
    final operation = request.operation;
    final policy = BrowserToolPolicy.decision(request.toolName);
    final preview = sensitiveValuePreview(request);
    final gateResult = await _approvalPort.resolveGate(
      operation,
      BrowserApprovalGateRequest(
        toolRequest: request,
        policy: policy,
        buildReviewArguments: () {
          _requireCurrent(lease);
          final page = _observationPort.currentPage(operation);
          _requireOperation(
            page.operation,
            operation,
            'Browser page observation',
          );
          return reviewArguments(request, page.currentUrl);
        },
        sensitiveValuePreview: preview,
      ),
    );
    _requireOperation(gateResult.operation, operation, 'Browser approval gate');
    final gate = gateResult.decision;
    final gateStop = _approvalStop(request, lease);
    if (gateStop != null) return gateStop;
    if (gate.isDenied) {
      return autoReviewDeniedResult(request.toolName, gate.deniedRationale!);
    }
    if (gate.needsManual) {
      final details = await actionDetails(request, lease);
      final detailsStop = _approvalStop(request, lease);
      if (detailsStop != null) return detailsStop;
      final manualResult = await _approvalPort.requestManualApproval(
        operation,
        BrowserManualApprovalRequest(
          toolRequest: request,
          policy: policy,
          summary: describeAction(request),
          details: details,
          targetSummary: actionTargetSummary(request),
          sensitiveValuePreview: preview,
        ),
      );
      _requireOperation(
        manualResult.operation,
        operation,
        'Browser manual approval',
      );
      final manualStop = _approvalStop(request, lease);
      if (manualStop != null) return manualStop;
      if (!manualResult.approved) {
        return _manualApprovalDeniedResult(request.toolName);
      }
    }
    return _execute(request, lease);
  }

  Map<String, dynamic> reviewArguments(
    BrowserToolRequest request,
    String? currentUrl,
  ) {
    const omittedKeys = {'value', 'script', 'data'};
    final sanitized = <String, dynamic>{
      for (final entry in request.arguments.entries)
        if (!omittedKeys.contains(entry.key)) entry.key: entry.value,
    };
    final host = currentUrl == null ? null : Uri.tryParse(currentUrl)?.host;
    if (host != null && host.isNotEmpty) {
      sanitized['pageHost'] = host;
    }
    return freezeBrowserToolMap(sanitized);
  }

  McpToolResult autoReviewDeniedResult(String toolName, String rationale) {
    return McpToolResult(
      toolName: toolName,
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

  String describeAction(BrowserToolRequest request) {
    final args = request.arguments;
    return switch (request.toolName) {
      'browser_fill' =>
        'Fill ${targetLabel(args)} with ${sensitiveValuePreview(request) ?? 'a value'}',
      'browser_click' => 'Click ${targetLabel(args)}',
      'browser_submit' =>
        (args['selector'] as String?)?.isNotEmpty ?? false
            ? 'Submit the form containing ${args['selector']}'
            : 'Submit the current form',
      'browser_eval' =>
        'Run JavaScript in the page (${((args['script'] as String?) ?? '').length} chars)',
      'browser_save_data' => 'Save data to ${args['filename'] ?? 'a file'}',
      _ => request.toolName,
    };
  }

  String targetLabel(Map<String, dynamic> arguments) {
    if (arguments['ref'] != null) {
      return 'element #${arguments['ref']}';
    }
    final selector = (arguments['selector'] as String?)?.trim();
    if (selector != null && selector.isNotEmpty) {
      return 'selector "$selector"';
    }
    return 'the target element';
  }

  Future<List<String>> actionDetails(
    BrowserToolRequest request, [
    BrowserSessionLease? lease,
  ]) async {
    final operation = request.operation;
    final args = request.arguments;
    final details = <String>['Tool: ${request.toolName}'];
    switch (request.toolName) {
      case 'browser_fill':
      case 'browser_click':
        if (args['ref'] != null) {
          details.add('Target ref: ${args['ref']}');
        }
        if ((args['selector'] as String?)?.isNotEmpty ?? false) {
          details.add('Selector: ${args['selector']}');
        }
      case 'browser_submit':
        if ((args['selector'] as String?)?.isNotEmpty ?? false) {
          details.add('Form selector: ${args['selector']}');
        }
      case 'browser_save_data':
        final target = await _observationPort.resolveSaveTarget(
          operation,
          BrowserSaveTargetRequest(
            filename: (args['filename'] as String?) ?? 'browser_data',
            format: (args['format'] as String?) ?? 'json',
            destination: args['destination'] as String?,
          ),
        );
        _requireOperation(
          target.operation,
          operation,
          'Browser save target observation',
        );
        if (lease != null) _requireCurrent(lease);
        details.add('Destination: ${target.destinationLabel}');
        if (target.destinationChanged) {
          details.add('Requested destination: ${target.requestedDestination}');
        }
        details
          ..add('Requested file: ${target.requestedFilename}')
          ..add('Final file: ${target.filename}')
          ..add('Save location: ${target.directoryPath}')
          ..add('Full path: ${target.path}')
          ..add('Size: ${((args['data'] as String?) ?? '').length} characters');
      case 'browser_eval':
        details.add(
          'Script length: ${((args['script'] as String?) ?? '').length} characters',
        );
    }
    final reason = args['reason'] as String?;
    if (reason != null && reason.trim().isNotEmpty) {
      details.add('Model reason: ${reason.trim()}');
    }
    if (lease != null) _requireCurrent(lease);
    final page = _observationPort.currentPage(operation);
    _requireOperation(page.operation, operation, 'Browser page observation');
    final host = page.currentUrl == null
        ? null
        : Uri.tryParse(page.currentUrl!)?.host;
    if (host != null && host.isNotEmpty) {
      details.add('Page: $host');
    }
    return List<String>.unmodifiable(details);
  }

  String? actionTargetSummary(BrowserToolRequest request) {
    return switch (request.toolName) {
      'browser_fill' || 'browser_click' =>
        'Review the target ${targetLabel(request.arguments)} before approving.',
      'browser_save_data' => 'A file will be written to your device.',
      'browser_eval' => 'Arbitrary JavaScript will run in the current page.',
      _ => null,
    };
  }

  String? sensitiveValuePreview(BrowserToolRequest request) {
    if (request.toolName == 'browser_eval') {
      final script = (request.arguments['script'] as String?) ?? '';
      return script.length > 400 ? '${script.substring(0, 400)}…' : script;
    }
    if (request.toolName != 'browser_fill') {
      return null;
    }
    final value = (request.arguments['value'] as String?) ?? '';
    if (value.isEmpty) {
      return '(empty)';
    }
    if (looksLikeSecret(request.arguments)) {
      return '${'•' * value.length.clamp(0, 32)} (${value.length} chars, hidden)';
    }
    return value.length > 80 ? '${value.substring(0, 80)}…' : value;
  }

  bool looksLikeSecret(Map<String, dynamic> arguments) {
    final selector = ((arguments['selector'] as String?) ?? '').toLowerCase();
    return selector.contains('pass') ||
        selector.contains('pwd') ||
        selector.contains('secret') ||
        selector.contains('otp') ||
        selector.contains('token');
  }

  Future<McpToolResult> _execute(
    BrowserToolRequest request,
    BrowserSessionLease lease,
  ) async {
    final permit = _sessionCoordinator.authorizeEffect(lease);
    if (permit == null) {
      return _expiredResult(request.toolName);
    }
    final response = await _executionPort.execute(
      request.operation,
      BrowserExecutionRequest(
        operation: request.operation,
        arguments: request.arguments,
      ),
      permit,
    );
    _requireOperation(
      response.operation,
      request.operation,
      'Browser execution',
    );
    final result = _requireToolResult(
      request,
      response.result,
      'Browser execution',
    );
    if (!_sessionCoordinator.acceptEffect(lease, permit)) {
      return _expiredResult(request.toolName);
    }
    return result;
  }

  McpToolResult? _approvalStop(
    BrowserToolRequest request,
    BrowserSessionLease lease,
  ) {
    final expired = _approvalPort.expiredResult(request.operation);
    if (expired != null) {
      return _requireToolResult(request, expired, 'Browser expiry');
    }
    return _leaseCurrent(lease) &&
            _approvalPort.isOperationCurrent(request.operation)
        ? null
        : _expiredResult(request.toolName);
  }

  bool _leaseCurrent(BrowserSessionLease lease) {
    return _sessionCoordinator.isLeaseCurrent(
      lease.operation,
      lease.sessionEpoch,
      lease.token,
    );
  }

  void _requireCurrent(BrowserSessionLease lease) {
    if (!_leaseCurrent(lease) ||
        !_approvalPort.isOperationCurrent(lease.operation)) {
      throw StateError('Browser operation is no longer current.');
    }
  }

  McpToolResult _requireToolResult(
    BrowserToolRequest request,
    McpToolResult result,
    String source,
  ) {
    if (result.toolName != request.toolName) {
      throw StateError('$source tool name mismatch.');
    }
    return result;
  }

  McpToolResult _expiredResult(String toolName) {
    return _failure(
      toolName,
      'turn_expired',
      'The browser operation expired before completion.',
    );
  }

  McpToolResult _failure(String toolName, String code, String message) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({'ok': false, 'code': code, 'error': message}),
      isSuccess: false,
      errorMessage: message,
    );
  }

  McpToolResult _manualApprovalDeniedResult(String toolName) {
    return McpToolResult(
      toolName: toolName,
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

  void _requireOperation(
    BrowserSessionOperationIdentity actual,
    BrowserSessionOperationIdentity expected,
    String source,
  ) {
    if (actual != expected) {
      throw StateError('$source operation mismatch.');
    }
  }
}
