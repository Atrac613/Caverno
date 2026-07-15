// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierBleHandlers on ChatNotifier {
  Future<McpToolResult> _handleBleConnect(ToolCallInfo toolCall) async {
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
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final bleService = ref.read(bleServiceProvider);
    final scanResults = bleService.getScanResults();
    final device = scanResults.where(
      (d) => d.peripheral.uuid.toString() == deviceId,
    );
    final deviceName = device.isNotEmpty ? device.first.name : null;

    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'ble_connect',
      mode: _settings.chatApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.connection,
      fullAccessEligible: true,
      approvalCacheArguments: cacheArguments,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'ble_connect',
        arguments: cacheArguments,
        reason: toolCall.arguments['reason'] as String?,
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
      final approved = await requestBleConnect(
        deviceId: deviceId,
        deviceName: deviceName,
      );
      if (!approved) {
        return _rememberToolApprovalDenial(
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

    try {
      await bleService.connect(deviceId);
      final connectedResult = McpToolResult(
        toolName: toolCall.name,
        result: 'Connected to ${deviceName ?? deviceId}',
        isSuccess: true,
      );
      return gate.bypassedApproval
          ? connectedResult
          : _rememberToolApprovalResult(
              toolCall.name,
              cacheArguments,
              connectedResult,
            );
    } catch (e) {
      appLog('[Tool] BLE connect failed: $e');
      final failedResult = McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'BLE connect failed: $e',
      );
      return gate.bypassedApproval
          ? failedResult
          : _rememberToolApprovalResult(
              toolCall.name,
              cacheArguments,
              failedResult,
            );
    }
  }

  /// Puts a pending BLE connect request into state and returns a future
  /// that completes with `true` (approved) or `false` (denied).
  Future<bool> requestBleConnect({
    required String deviceId,
    String? deviceName,
  }) {
    final completer = Completer<bool>();
    final pending = PendingBleConnect(
      id: const Uuid().v4(),
      deviceId: deviceId,
      deviceName: deviceName,
      completer: completer,
    );
    state = state.copyWith(pendingBleConnect: pending);
    _emitRuntimeApprovalRequired(
      id: pending.id,
      capability: 'ble_connection',
      summary: 'Connect to ${deviceName ?? deviceId}',
      target: deviceId,
    );
    return completer.future;
  }

  /// Resolves a pending BLE connect dialog from the UI layer.
  void resolveBleConnect({required String id, required bool approved}) {
    final pending = state.pendingBleConnect;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingBleConnect: null);
  }
}
