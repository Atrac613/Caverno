import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/serial_connection_attempt_coordinator.dart';
import '../../domain/services/serial_connection_port.dart';
import '../../domain/services/serial_connection_tool_contract.dart';

enum SerialSessionCloseKind { closed, alreadyAbsent, sessionMismatch }

/// Minimal session-aware transport needed by the owner-bound adapter.
abstract interface class SerialSessionPort {
  Future<String> open(
    String portName, {
    required int baudRate,
    required int dataBits,
    required String parity,
    required int stopBits,
    required String flowControl,
  });

  String? sessionFingerprint(String portName);

  Future<SerialSessionCloseKind> closeIfSessionMatches(
    String portName,
    String expectedFingerprint,
  );
}

/// Adapts the desktop serial service to the owner-aware connection contract.
final class SerialPortConnectionAdapter implements SerialConnectionPort {
  const SerialPortConnectionAdapter({
    required SerialSessionPort service,
    required bool Function(ChatTurnOwner owner) ownerIsCurrent,
  }) : _service = service,
       _ownerIsCurrent = ownerIsCurrent;

  final SerialSessionPort _service;
  final bool Function(ChatTurnOwner owner) _ownerIsCurrent;

  @override
  Future<SerialConnectionResult> open(
    ChatTurnOwner owner,
    SerialConnectionRequest request,
  ) async {
    final options = request.options;
    final resultJson = await _service.open(
      request.portName,
      baudRate: options.baudRate,
      dataBits: options.dataBits,
      parity: options.parity,
      stopBits: options.stopBits,
      flowControl: options.flowControl,
    );
    final fingerprint =
        _fingerprintFromResult(resultJson) ??
        _service.sessionFingerprint(request.portName);
    return _ownerIsCurrent(owner)
        ? SerialConnectionResult.completed(
            owner: owner,
            request: request,
            resultJson: resultJson,
            sessionFingerprint: fingerprint,
          )
        : SerialConnectionResult.ownerExpired(
            owner: owner,
            request: request,
            resultJson: resultJson,
            sessionFingerprint: fingerprint,
          );
  }

  @override
  Future<SerialConnectionRollbackResult> rollbackOpen(
    SerialConnectionRollbackPermit permit,
  ) async {
    final receipt = permit.receipt;
    final identity = receipt.identity;
    final request = SerialConnectionRequest(
      toolCallId: identity.toolCallId,
      portName: identity.portName,
      options: identity.options,
    );
    final expectedFingerprint = receipt.sessionFingerprint;
    try {
      final result = await _service.closeIfSessionMatches(
        request.portName,
        expectedFingerprint,
      );
      return switch (result) {
        SerialSessionCloseKind.closed => SerialConnectionRollbackResult.closed(
          owner: identity.owner,
          request: request,
          expectedSessionFingerprint: expectedFingerprint,
        ),
        SerialSessionCloseKind.alreadyAbsent =>
          SerialConnectionRollbackResult.alreadyAbsent(
            owner: identity.owner,
            request: request,
            expectedSessionFingerprint: expectedFingerprint,
          ),
        SerialSessionCloseKind.sessionMismatch =>
          SerialConnectionRollbackResult.sessionMismatch(
            owner: identity.owner,
            request: request,
            expectedSessionFingerprint: expectedFingerprint,
          ),
      };
    } catch (error) {
      return SerialConnectionRollbackResult.failed(
        owner: identity.owner,
        request: request,
        expectedSessionFingerprint: expectedFingerprint,
        error: error,
      );
    }
  }

  String? _fingerprintFromResult(String resultJson) {
    try {
      final decoded = jsonDecode(resultJson);
      final fingerprint = decoded is Map
          ? decoded['session_fingerprint'] as String?
          : null;
      return fingerprint?.trim().isEmpty == false ? fingerprint!.trim() : null;
    } catch (_) {
      return null;
    }
  }
}
