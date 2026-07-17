import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart'
    show GATTCharacteristicWriteType;

import '../../../../core/services/ble_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'ble_tools.dart';
import 'mcp_tool_result_normalizer.dart';

/// Exposes and executes the built-in Bluetooth Low Energy tool family.
final class BuiltInBleToolHandler {
  BuiltInBleToolHandler({BleService? bleService}) : _bleService = bleService;

  static const List<String> toolNames = <String>[
    'ble_start_scan',
    'ble_stop_scan',
    'ble_get_scan_results',
    'ble_connect',
    'ble_disconnect',
    'ble_discover_services',
    'ble_read_characteristic',
    'ble_write_characteristic',
    'ble_subscribe_characteristic',
    'ble_unsubscribe_characteristic',
    'ble_get_connection_state',
    'ble_start_advertising',
    'ble_stop_advertising',
    'ble_add_service',
    'ble_update_characteristic',
    'ble_get_peripheral_state',
  ];

  static const Set<String> _toolNameSet = <String>{...toolNames};
  static final RegExp _hexSeparatorChars = RegExp(r'[\s:-]');

  final BleService? _bleService;

  bool get isAvailable => _bleService != null;

  List<Map<String, dynamic>> get definitions => BleTools.allTools;

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown BLE tool');
    }
    final ble = _bleService;
    if (ble == null) {
      throw StateError('BLE service is unavailable');
    }

    try {
      switch (name) {
        case 'ble_start_scan':
          final timeout = ((arguments['timeout'] as num?)?.toInt() ?? 10).clamp(
            1,
            60,
          );
          final serviceUuids = (arguments['service_uuids'] as List?)
              ?.cast<String>();
          await ble.startScan(
            timeout: Duration(seconds: timeout),
            serviceUuids: serviceUuids,
          );
          return _success(
            name,
            'Scan started (${timeout}s timeout). '
            'Use ble_get_scan_results to see discovered devices.',
          );

        case 'ble_stop_scan':
          await ble.stopScan();
          return _success(
            name,
            'Scan stopped. ${ble.getScanResults().length} devices found.',
          );

        case 'ble_get_scan_results':
          final sortBy = arguments['sort_by'] as String?;
          final results = ble.getScanResults(sortBy: sortBy);
          if (results.isEmpty) {
            return _success(
              name,
              'No devices found. Try ble_start_scan first.',
            );
          }
          final buffer = StringBuffer();
          buffer.writeln('Found ${results.length} device(s):');
          for (final device in results) {
            buffer.writeln(
              '- device_id: ${device.peripheral.uuid}  '
              'name: ${device.name ?? "(unknown)"}  '
              'rssi: ${device.rssi} dBm  '
              'services: ${device.serviceUuids.isEmpty ? "none" : device.serviceUuids.join(", ")}',
            );
          }
          return _success(name, buffer.toString());

        case 'ble_connect':
          return _failure(
            name,
            'ble_connect must be handled by ChatNotifier (internal error)',
          );

        case 'ble_disconnect':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty) {
            return _missingParam(name, 'device_id');
          }
          await ble.disconnect(deviceId);
          return _success(name, 'Disconnected from $deviceId');

        case 'ble_discover_services':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty) {
            return _missingParam(name, 'device_id');
          }
          final services = await ble.discoverServices(deviceId);
          return _success(name, jsonEncode(services));

        case 'ble_read_characteristic':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final characteristicUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'hex';
          if (deviceId.isEmpty ||
              serviceUuid.isEmpty ||
              characteristicUuid.isEmpty) {
            return _missingParam(
              name,
              'device_id, service_uuid, characteristic_uuid',
            );
          }
          final value = await ble.readCharacteristic(
            deviceId,
            serviceUuid,
            characteristicUuid,
          );
          final encoded = BleService.encodeValue(value, encoding);
          final notifications = ble.getNotificationBuffer(
            deviceId,
            serviceUuid,
            characteristicUuid,
          );
          final buffer = StringBuffer();
          buffer.writeln('value ($encoding): $encoded');
          if (notifications.isNotEmpty) {
            buffer.writeln(
              'notification_buffer (${notifications.length} entries):',
            );
            for (final entry in notifications) {
              buffer.writeln(
                '  ${entry.timestamp.toIso8601String()}: '
                '${BleService.encodeValue(entry.value, encoding)}',
              );
            }
          }
          return _success(name, buffer.toString());

        case 'ble_write_characteristic':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final characteristicUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          final rawValue = (arguments['value'] as String?)?.trim() ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'hex';
          final writeTypeName =
              (arguments['write_type'] as String?) ?? 'withResponse';
          if (deviceId.isEmpty ||
              serviceUuid.isEmpty ||
              characteristicUuid.isEmpty ||
              rawValue.isEmpty) {
            return _missingParam(
              name,
              'device_id, service_uuid, characteristic_uuid, value',
            );
          }
          final writeType = writeTypeName == 'withoutResponse'
              ? GATTCharacteristicWriteType.withoutResponse
              : GATTCharacteristicWriteType.withResponse;
          final valueBytes = _decodeValueForWrite(rawValue, encoding);
          await ble.writeCharacteristic(
            deviceId,
            serviceUuid,
            characteristicUuid,
            valueBytes,
            type: writeType,
          );
          return _success(
            name,
            'Written ${valueBytes.length} bytes to $characteristicUuid',
          );

        case 'ble_subscribe_characteristic':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final characteristicUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty ||
              serviceUuid.isEmpty ||
              characteristicUuid.isEmpty) {
            return _missingParam(
              name,
              'device_id, service_uuid, characteristic_uuid',
            );
          }
          await ble.subscribeCharacteristic(
            deviceId,
            serviceUuid,
            characteristicUuid,
          );
          return _success(
            name,
            'Subscribed to notifications on $characteristicUuid. '
            'Use ble_read_characteristic to get latest values.',
          );

        case 'ble_unsubscribe_characteristic':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final characteristicUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty ||
              serviceUuid.isEmpty ||
              characteristicUuid.isEmpty) {
            return _missingParam(
              name,
              'device_id, service_uuid, characteristic_uuid',
            );
          }
          await ble.unsubscribeCharacteristic(
            deviceId,
            serviceUuid,
            characteristicUuid,
          );
          return _success(name, 'Unsubscribed from $characteristicUuid');

        case 'ble_get_connection_state':
          final deviceId = (arguments['device_id'] as String?)?.trim() ?? '';
          if (deviceId.isEmpty) {
            return _missingParam(name, 'device_id');
          }
          final state = ble.getConnectionState(deviceId);
          return _success(name, 'Device $deviceId: $state');

        case 'ble_start_advertising':
          final localName = arguments['local_name'] as String?;
          final serviceUuids = (arguments['service_uuids'] as List?)
              ?.cast<String>();
          await ble.startAdvertising(
            localName: localName,
            serviceUuids: serviceUuids,
          );
          return _success(name, 'Advertising started');

        case 'ble_stop_advertising':
          await ble.stopAdvertising();
          return _success(name, 'Advertising stopped');

        case 'ble_add_service':
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final characteristics =
              (arguments['characteristics'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          if (serviceUuid.isEmpty || characteristics.isEmpty) {
            return _missingParam(name, 'service_uuid, characteristics');
          }
          await ble.addService(
            serviceUuid: serviceUuid,
            characteristics: characteristics,
          );
          return _success(
            name,
            'Service $serviceUuid added with '
            '${characteristics.length} characteristic(s)',
          );

        case 'ble_update_characteristic':
          final serviceUuid =
              (arguments['service_uuid'] as String?)?.trim() ?? '';
          final characteristicUuid =
              (arguments['characteristic_uuid'] as String?)?.trim() ?? '';
          final rawValue = (arguments['value'] as String?)?.trim() ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'hex';
          if (serviceUuid.isEmpty ||
              characteristicUuid.isEmpty ||
              rawValue.isEmpty) {
            return _missingParam(
              name,
              'service_uuid, characteristic_uuid, value',
            );
          }
          final bytes = _decodeValueForWrite(rawValue, encoding);
          await ble.updateCharacteristic(
            serviceUuid,
            characteristicUuid,
            bytes,
          );
          return _success(
            name,
            'Characteristic $characteristicUuid updated and '
            'subscribers notified',
          );

        case 'ble_get_peripheral_state':
          return _success(name, jsonEncode(ble.getPeripheralState()));
      }
      throw StateError('Unhandled BLE tool: $name');
    } catch (error) {
      appLog('[McpToolService] BLE tool error ($name): $error');
      return _failure(name, error.toString());
    }
  }

  static McpToolResult _success(String toolName, String result) {
    return McpToolResultNormalizer.success(toolName: toolName, result: result);
  }

  static McpToolResult _failure(String toolName, String errorMessage) {
    return McpToolResultNormalizer.failure(
      toolName: toolName,
      errorMessage: errorMessage,
    );
  }

  static McpToolResult _missingParam(String toolName, String params) {
    return _failure(toolName, '$params required');
  }

  static Uint8List _decodeValueForWrite(String value, String encoding) {
    return switch (encoding) {
      'utf8' => Uint8List.fromList(utf8.encode(value)),
      'base64' => base64Decode(value),
      _ => _hexDecodeValue(value),
    };
  }

  static Uint8List _hexDecodeValue(String hex) {
    final clean = hex.replaceAll(_hexSeparatorChars, '');
    final bytes = <int>[];
    for (var i = 0; i + 1 < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
}
