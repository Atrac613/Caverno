// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierBleHandlers on ChatNotifier {
  Future<McpToolResult> _handleBleConnect(
    ToolCallInfo toolCall,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final deviceId = (toolCall.arguments['device_id'] as String?)?.trim() ?? '';
    if (deviceId.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'device_id is required',
      );
    }

    final cacheArguments = <String, dynamic>{'device_id': deviceId};
    final cachedResult = approvalCache.lookupDenial(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) return cachedResult;

    final bleService = ref.read(bleServiceProvider);
    final scanResults = bleService.getScanResults();
    final device = scanResults.where(
      (d) => d.peripheral.uuid.toString() == deviceId,
    );
    final deviceName = device.isNotEmpty ? device.first.name : null;

    final gate = await _resolveToolApprovalGate(
      approvalCache,
      toolCall: toolCall,
      actionKind: 'ble_connect',
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.connection,
      fullAccessEligible: true,
      approvalCacheArguments: cacheArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        approvalCache.owner,
        toolCall: toolCall,
        actionKind: 'ble_connect',
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
      final approved = await requestBleConnect(
        owner: approvalCache.owner,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      if (!approved && _isApprovalOwnerCurrent(approvalCache.owner)) {
        return approvalCache.rememberDenial(
          toolCall.name,
          cacheArguments,
          McpToolResult(
            toolName: toolCall.name,
            result: '',
            isSuccess: false,
            errorMessage: 'User cancelled BLE connection',
          ),
        );
      }
    }
    final expired = _expiredApproval(toolCall.name, approvalCache);
    if (expired != null) return expired;

    final attemptOutcome = await _bleConnectAttempts.connect(
      owner: approvalCache.owner,
      deviceId: deviceId,
      service: bleService,
      ownerIsCurrent: _isApprovalOwnerCurrent,
      onRollbackError: (error) {
        appLog(
          '[Tool] Failed to roll back expired BLE attempt '
          '${approvalCache.owner} for $deviceId: $error',
        );
      },
    );
    if (attemptOutcome.kind == BleConnectAttemptOutcomeKind.ownerExpired) {
      return approvalTurnExpiredResult(toolCall.name);
    }
    final result = switch (attemptOutcome.kind) {
      BleConnectAttemptOutcomeKind.connected => McpToolResult(
        toolName: toolCall.name,
        result: 'Connected to ${deviceName ?? deviceId}',
        isSuccess: true,
      ),
      BleConnectAttemptOutcomeKind.failed => McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'BLE connect failed: ${attemptOutcome.error}',
      ),
      BleConnectAttemptOutcomeKind.ownerExpired => throw StateError(
        'Expired BLE attempts return before result construction.',
      ),
    };
    if (attemptOutcome.kind == BleConnectAttemptOutcomeKind.failed) {
      appLog('[Tool] BLE connect failed: ${attemptOutcome.error}');
    }
    return gate.bypassedApproval
        ? result
        : approvalCache.rememberResult(toolCall.name, cacheArguments, result);
  }

  Future<bool> requestBleConnect({
    required ChatTurnOwner owner,
    required String deviceId,
    String? deviceName,
  }) {
    final completer = Completer<bool>();
    final pending = PendingBleConnect(
      owner: owner,
      id: const Uuid().v4(),
      deviceId: deviceId,
      deviceName: deviceName,
      completer: completer,
    );
    return _registerPendingToolApproval(
      pending,
      (s) => s.copyWith(pendingBleConnect: pending),
      'ble_connection',
      'Connect to ${deviceName ?? deviceId}',
      deviceId,
    );
  }

  bool resolveBleConnect({required String id, required bool approved}) =>
      _completeApproval<bool, PendingBleConnect>(id, (_) => approved);
}
