import '../../../../core/services/serial_port_service.dart';
import 'serial_port_connection_adapter.dart';

/// Exposes [SerialPortService] through the narrow session-aware transport API.
final class SerialPortServiceSessionPort implements SerialSessionPort {
  const SerialPortServiceSessionPort(this._service);

  final SerialPortService _service;

  @override
  Future<String> open(
    String portName, {
    required int baudRate,
    required int dataBits,
    required String parity,
    required int stopBits,
    required String flowControl,
  }) {
    return _service.open(
      portName,
      baudRate: baudRate,
      dataBits: dataBits,
      parity: parity,
      stopBits: stopBits,
      flowControl: flowControl,
    );
  }

  @override
  String? sessionFingerprint(String portName) {
    return _service.sessionFingerprint(portName);
  }

  @override
  Future<SerialSessionCloseKind> closeIfSessionMatches(
    String portName,
    String expectedFingerprint,
  ) async {
    final result = await _service.closeIfSessionMatches(
      portName,
      expectedFingerprint,
    );
    return switch (result) {
      SerialPortConditionalCloseKind.closed => SerialSessionCloseKind.closed,
      SerialPortConditionalCloseKind.alreadyAbsent =>
        SerialSessionCloseKind.alreadyAbsent,
      SerialPortConditionalCloseKind.sessionMismatch =>
        SerialSessionCloseKind.sessionMismatch,
    };
  }
}
