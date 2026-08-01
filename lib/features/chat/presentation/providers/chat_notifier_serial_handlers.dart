// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierSerialHandlers on ChatNotifier {
  Future<McpToolResult> _handleSerialOpen(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final port = (toolCall.arguments['port'] as String?)?.trim() ?? '';
    if (port.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'port is required',
      );
    }

    final baudRate = (toolCall.arguments['baud_rate'] as num?)?.toInt() ?? 9600;
    final dataBits = (toolCall.arguments['data_bits'] as num?)?.toInt() ?? 8;
    final parity = (toolCall.arguments['parity'] as String?) ?? 'none';
    final stopBits = (toolCall.arguments['stop_bits'] as num?)?.toInt() ?? 1;
    final flowControl =
        (toolCall.arguments['flow_control'] as String?) ?? 'none';

    final cacheArguments = <String, dynamic>{
      'port': port,
      'baud_rate': baudRate,
      'data_bits': dataBits,
      'parity': parity,
      'stop_bits': stopBits,
      'flow_control': flowControl,
    };
    final cachedResult = approvalCache.lookupDenial(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) return cachedResult;

    final gate = await _resolveToolApprovalGate(
      approvalCache,
      toolCall: toolCall,
      actionKind: 'serial_open',
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.connection,
      fullAccessEligible: true,
      approvalCacheArguments: cacheArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        approvalCache.owner,
        toolCall: toolCall,
        actionKind: 'serial_open',
        arguments: cacheArguments,
        reason: toolCall.arguments['reason'] as String?,
      ),
    );
    if (gate.isDenied) {
      return approvalCache.rememberDenial(
        toolCall.name,
        cacheArguments,
        _autoReviewDeniedResult(
          toolName: toolCall.name,
          rationale: gate.deniedRationale!,
        ),
      );
    }
    if (gate.needsManual) {
      final approved = await requestSerialOpen(
        owner: approvalCache.owner,
        portName: port,
        baudRate: baudRate,
      );
      if (!approved && _isApprovalOwnerCurrent(approvalCache.owner)) {
        return approvalCache.rememberDenial(
          toolCall.name,
          cacheArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User cancelled opening serial port $port',
          ),
        );
      }
    }
    final expired = _expiredApproval(toolCall.name, approvalCache);
    if (expired != null) return expired;

    final serialPortService = ref.read(serialPortServiceProvider);
    try {
      final resultJson = await serialPortService.open(
        port,
        baudRate: baudRate,
        dataBits: dataBits,
        parity: parity,
        stopBits: stopBits,
        flowControl: flowControl,
      );
      final succeeded = !_serialResultIsError(resultJson);
      final expiredAfterOpen = await _rollbackExpiredApproval(
        toolCall.name,
        approvalCache,
        target: port,
        rollback: succeeded ? () => serialPortService.close(port) : null,
      );
      if (expiredAfterOpen != null) return expiredAfterOpen;
      final result = McpToolResult(
        toolName: toolCall.name,
        result: resultJson,
        isSuccess: succeeded,
      );
      // Cache only successful opens so a transient failure (e.g. the port is
      // momentarily busy) can be retried — re-prompting the user — rather than
      // returning a stale failure. Full access never caches, so re-opening stays
      // possible without a stale result.
      return (succeeded && !gate.bypassedApproval)
          ? approvalCache.rememberResult(toolCall.name, cacheArguments, result)
          : result;
    } catch (e) {
      appLog('[Tool] Serial open failed: $e');
      final stale = _expiredApproval(toolCall.name, approvalCache);
      if (stale != null) return stale;
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'Serial open failed: $e',
      );
    }
  }

  Future<bool> requestSerialOpen({
    required ChatTurnOwner owner,
    required String portName,
    required int baudRate,
  }) {
    final completer = Completer<bool>();
    final pending = PendingSerialOpen(
      owner: owner,
      id: const Uuid().v4(),
      portName: portName,
      baudRate: baudRate,
      completer: completer,
    );
    return _registerPendingToolApproval(
      pending,
      (s) => s.copyWith(pendingSerialOpen: pending),
      'serial_connection',
      'Open $portName at $baudRate baud',
      portName,
    );
  }

  bool resolveSerialOpen({required String id, required bool approved}) =>
      _completeApproval<bool, PendingSerialOpen>(id, (_) => approved);

  bool _serialResultIsError(String resultJson) {
    try {
      final decoded = jsonDecode(resultJson);
      return decoded is Map && decoded['error'] == true;
    } catch (_) {
      return false;
    }
  }
}
