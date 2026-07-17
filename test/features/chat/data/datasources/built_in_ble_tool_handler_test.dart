import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:caverno/core/services/ble_service.dart';
import 'package:caverno/features/chat/data/datasources/built_in_ble_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuiltInBleToolHandler', () {
    test('owns the exact ordered BLE family and reports availability', () {
      final unavailable = BuiltInBleToolHandler();
      final available = BuiltInBleToolHandler(bleService: _FakeBleService());

      expect(BuiltInBleToolHandler.toolNames, const [
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
      ]);
      expect(
        available.definitions.map(_definitionName),
        BuiltInBleToolHandler.toolNames,
      );
      expect(unavailable.isAvailable, isFalse);
      expect(available.isAvailable, isTrue);
      expect(available.handles('ble_read_characteristic'), isTrue);
      expect(available.handles('bluetooth_read'), isFalse);

      final connect = available.definitions.firstWhere(
        (definition) => _definitionName(definition) == 'ble_connect',
      );
      final function = connect['function']! as Map<String, dynamic>;
      final parameters = function['parameters']! as Map<String, dynamic>;
      expect(function['description'], contains('Requires user confirmation'));
      expect(parameters['required'], ['device_id']);
    });

    test('rejects unknown names and unavailable direct execution', () async {
      final available = BuiltInBleToolHandler(bleService: _FakeBleService());
      final unavailable = BuiltInBleToolHandler();

      await expectLater(
        available.execute(name: 'bluetooth_read', arguments: const {}),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        unavailable.execute(name: 'ble_stop_scan', arguments: const {}),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'normalizes scan defaults and clamps without hardware access',
      () async {
        final service = _FakeBleService();
        final handler = BuiltInBleToolHandler(bleService: service);

        final defaultResult = await handler.execute(
          name: 'ble_start_scan',
          arguments: const {},
        );
        expect(service.scanTimeout, const Duration(seconds: 10));
        expect(service.scanServiceUuids, isNull);
        expect(
          defaultResult.result,
          'Scan started (10s timeout). '
          'Use ble_get_scan_results to see discovered devices.',
        );

        final clampedResult = await handler.execute(
          name: 'ble_start_scan',
          arguments: const {
            'timeout': 99,
            'service_uuids': ['180D', '180F'],
          },
        );
        expect(service.scanTimeout, const Duration(seconds: 60));
        expect(service.scanServiceUuids, ['180D', '180F']);
        expect(clampedResult.result, startsWith('Scan started (60s timeout).'));

        await handler.execute(
          name: 'ble_start_scan',
          arguments: const {'timeout': -3},
        );
        expect(service.scanTimeout, const Duration(seconds: 1));
      },
    );

    test('preserves empty and populated scan result formatting', () async {
      final service = _FakeBleService();
      final handler = BuiltInBleToolHandler(bleService: service);

      final empty = await handler.execute(
        name: 'ble_get_scan_results',
        arguments: const {'sort_by': 'rssi'},
      );
      expect(empty.result, 'No devices found. Try ble_start_scan first.');
      expect(service.scanSortBy, 'rssi');

      final knownUuid = UUID.fromString('12345678-1234-5678-1234-567812345678');
      service.scanResults = [
        BleDiscoveredDevice(
          peripheral: _FakePeripheral(knownUuid),
          rssi: -42,
          name: 'Sensor',
          serviceUuids: const ['180D', '180F'],
          discoveredAt: DateTime.utc(2026),
        ),
        BleDiscoveredDevice(
          peripheral: _FakePeripheral(UUID.short(0x180d)),
          rssi: -70,
          name: null,
          serviceUuids: const [],
          discoveredAt: DateTime.utc(2026),
        ),
      ];
      final populated = await handler.execute(
        name: 'ble_get_scan_results',
        arguments: const {'sort_by': 'name'},
      );

      expect(service.scanSortBy, 'name');
      expect(
        populated.result,
        'Found 2 device(s):\n'
        '- device_id: $knownUuid  name: Sensor  rssi: -42 dBm  '
        'services: 180D, 180F\n'
        '- device_id: ${UUID.short(0x180d)}  name: (unknown)  '
        'rssi: -70 dBm  services: none\n',
      );

      final stopped = await handler.execute(
        name: 'ble_stop_scan',
        arguments: const {},
      );
      expect(service.stopScanCalls, 1);
      expect(stopped.result, 'Scan stopped. 2 devices found.');
    });

    test(
      'keeps connection approval and required argument failures local',
      () async {
        final service = _FakeBleService();
        final handler = BuiltInBleToolHandler(bleService: service);

        final connect = await handler.execute(
          name: 'ble_connect',
          arguments: const {'device_id': 'device'},
        );
        expect(connect.isSuccess, isFalse);
        expect(
          connect.errorMessage,
          'ble_connect must be handled by ChatNotifier (internal error)',
        );

        const cases = <(String, String)>[
          ('ble_disconnect', 'device_id required'),
          ('ble_discover_services', 'device_id required'),
          (
            'ble_read_characteristic',
            'device_id, service_uuid, characteristic_uuid required',
          ),
          (
            'ble_write_characteristic',
            'device_id, service_uuid, characteristic_uuid, value required',
          ),
          (
            'ble_subscribe_characteristic',
            'device_id, service_uuid, characteristic_uuid required',
          ),
          (
            'ble_unsubscribe_characteristic',
            'device_id, service_uuid, characteristic_uuid required',
          ),
          ('ble_get_connection_state', 'device_id required'),
          ('ble_add_service', 'service_uuid, characteristics required'),
          (
            'ble_update_characteristic',
            'service_uuid, characteristic_uuid, value required',
          ),
        ];
        for (final testCase in cases) {
          final result = await handler.execute(
            name: testCase.$1,
            arguments: const {},
          );
          expect(result.isSuccess, isFalse, reason: testCase.$1);
          expect(result.result, isEmpty, reason: testCase.$1);
          expect(result.errorMessage, testCase.$2, reason: testCase.$1);
        }
      },
    );

    test(
      'preserves central operation outputs and notification formatting',
      () async {
        final service = _FakeBleService(
          discoveredServices: const [
            {'uuid': '180D', 'is_primary': true},
          ],
          readValue: Uint8List.fromList([0x48, 0x69]),
          notifications: [
            BleNotificationEntry(
              timestamp: DateTime.utc(2026, 7, 17, 1, 2, 3),
              value: Uint8List.fromList([0x4f, 0x4b]),
            ),
          ],
        );
        final handler = BuiltInBleToolHandler(bleService: service);

        final disconnected = await handler.execute(
          name: 'ble_disconnect',
          arguments: const {'device_id': ' device-1 '},
        );
        final discovered = await handler.execute(
          name: 'ble_discover_services',
          arguments: const {'device_id': 'device-1'},
        );
        final read = await handler.execute(
          name: 'ble_read_characteristic',
          arguments: const {
            'device_id': 'device-1',
            'service_uuid': '180D',
            'characteristic_uuid': '2A37',
            'encoding': 'utf8',
          },
        );
        final state = await handler.execute(
          name: 'ble_get_connection_state',
          arguments: const {'device_id': 'device-1'},
        );

        expect(service.disconnectedDeviceIds, ['device-1']);
        expect(disconnected.result, 'Disconnected from device-1');
        expect(jsonDecode(discovered.result), service.discoveredServices);
        expect(
          read.result,
          'value (utf8): Hi\n'
          'notification_buffer (1 entries):\n'
          '  2026-07-17T01:02:03.000Z: OK\n',
        );
        expect(service.readCalls.single, ('device-1', '180D', '2A37'));
        expect(service.notificationCalls.single, ('device-1', '180D', '2A37'));
        expect(state.result, 'Device device-1: connected');
      },
    );

    test('preserves value encodings and characteristic write types', () async {
      final service = _FakeBleService();
      final handler = BuiltInBleToolHandler(bleService: service);

      for (final arguments in const [
        {
          'device_id': 'device',
          'service_uuid': 'service',
          'characteristic_uuid': 'hex-char',
          'value': 'aa:bb-c',
          'encoding': 'hex',
          'write_type': 'withoutResponse',
        },
        {
          'device_id': 'device',
          'service_uuid': 'service',
          'characteristic_uuid': 'utf8-char',
          'value': 'é',
          'encoding': 'utf8',
        },
        {
          'device_id': 'device',
          'service_uuid': 'service',
          'characteristic_uuid': 'base64-char',
          'value': 'AQID',
          'encoding': 'base64',
          'write_type': 'unexpected',
        },
      ]) {
        final result = await handler.execute(
          name: 'ble_write_characteristic',
          arguments: arguments,
        );
        expect(result.isSuccess, isTrue);
      }

      expect(service.writeCalls[0].value, [0xaa, 0xbb]);
      expect(
        service.writeCalls[0].type,
        GATTCharacteristicWriteType.withoutResponse,
      );
      expect(service.writeCalls[1].value, utf8.encode('é'));
      expect(
        service.writeCalls[1].type,
        GATTCharacteristicWriteType.withResponse,
      );
      expect(service.writeCalls[2].value, [1, 2, 3]);
      expect(
        service.writeCalls[2].type,
        GATTCharacteristicWriteType.withResponse,
      );
    });

    test('preserves subscription and peripheral operation contracts', () async {
      final service = _FakeBleService(
        peripheralState: const {
          'is_advertising': true,
          'hosted_services': [],
          'connected_centrals': [],
        },
      );
      final handler = BuiltInBleToolHandler(bleService: service);
      const characteristicArgs = {
        'device_id': 'device',
        'service_uuid': 'service',
        'characteristic_uuid': 'characteristic',
      };

      final subscribed = await handler.execute(
        name: 'ble_subscribe_characteristic',
        arguments: characteristicArgs,
      );
      final unsubscribed = await handler.execute(
        name: 'ble_unsubscribe_characteristic',
        arguments: characteristicArgs,
      );
      final advertising = await handler.execute(
        name: 'ble_start_advertising',
        arguments: const {
          'local_name': ' Caverno ',
          'service_uuids': ['180D'],
        },
      );
      final stopped = await handler.execute(
        name: 'ble_stop_advertising',
        arguments: const {},
      );
      final added = await handler.execute(
        name: 'ble_add_service',
        arguments: const {
          'service_uuid': ' service ',
          'characteristics': [
            {
              'uuid': 'characteristic',
              'properties': ['read'],
            },
          ],
        },
      );
      final updated = await handler.execute(
        name: 'ble_update_characteristic',
        arguments: const {
          'service_uuid': 'service',
          'characteristic_uuid': 'characteristic',
          'value': '41',
        },
      );
      final state = await handler.execute(
        name: 'ble_get_peripheral_state',
        arguments: const {},
      );

      expect(
        subscribed.result,
        'Subscribed to notifications on characteristic. '
        'Use ble_read_characteristic to get latest values.',
      );
      expect(unsubscribed.result, 'Unsubscribed from characteristic');
      expect(service.subscribeCalls, [('device', 'service', 'characteristic')]);
      expect(service.unsubscribeCalls, [
        ('device', 'service', 'characteristic'),
      ]);
      expect(service.advertisingLocalName, ' Caverno ');
      expect(service.advertisingServiceUuids, ['180D']);
      expect(advertising.result, 'Advertising started');
      expect(service.stopAdvertisingCalls, 1);
      expect(stopped.result, 'Advertising stopped');
      expect(service.addedServiceUuid, 'service');
      expect(service.addedCharacteristics, hasLength(1));
      expect(added.result, 'Service service added with 1 characteristic(s)');
      expect(service.updateCalls.single.value, [0x41]);
      expect(
        updated.result,
        'Characteristic characteristic updated and subscribers notified',
      );
      expect(jsonDecode(state.result), service.peripheralState);
    });

    test(
      'converts service and argument exceptions into failed results',
      () async {
        final service = _FakeBleService(throwOperation: 'disconnect');
        final handler = BuiltInBleToolHandler(bleService: service);

        final serviceFailure = await handler.execute(
          name: 'ble_disconnect',
          arguments: const {'device_id': 'device'},
        );
        final castFailure = await handler.execute(
          name: 'ble_start_scan',
          arguments: const {
            'service_uuids': [1],
          },
        );

        expect(serviceFailure.isSuccess, isFalse);
        expect(serviceFailure.result, isEmpty);
        expect(serviceFailure.errorMessage, 'Bad state: disconnect failed');
        expect(castFailure.isSuccess, isFalse);
        expect(castFailure.errorMessage, contains('is not a subtype of type'));
      },
    );
  });
}

String _definitionName(Map<String, dynamic> definition) {
  final function = definition['function']! as Map<String, dynamic>;
  return function['name']! as String;
}

final class _FakePeripheral implements Peripheral {
  _FakePeripheral(this.uuid);

  @override
  final UUID uuid;
}

final class _FakeBleService extends BleService {
  _FakeBleService({
    this.discoveredServices = const [],
    Uint8List? readValue,
    this.notifications = const [],
    this.peripheralState = const {},
    this.throwOperation,
  }) : readValue = readValue ?? Uint8List(0);

  Duration? scanTimeout;
  List<String>? scanServiceUuids;
  String? scanSortBy;
  List<BleDiscoveredDevice> scanResults = [];
  int stopScanCalls = 0;
  final List<String> disconnectedDeviceIds = [];
  final List<Map<String, dynamic>> discoveredServices;
  final List<(String, String, String)> readCalls = [];
  final List<(String, String, String)> notificationCalls = [];
  final Uint8List readValue;
  final List<BleNotificationEntry> notifications;
  final List<
    ({
      String deviceId,
      String serviceUuid,
      String characteristicUuid,
      List<int> value,
      GATTCharacteristicWriteType type,
    })
  >
  writeCalls = [];
  final List<(String, String, String)> subscribeCalls = [];
  final List<(String, String, String)> unsubscribeCalls = [];
  String connectionState = 'connected';
  String? advertisingLocalName;
  List<String>? advertisingServiceUuids;
  int stopAdvertisingCalls = 0;
  String? addedServiceUuid;
  List<Map<String, dynamic>>? addedCharacteristics;
  final List<({String serviceUuid, String characteristicUuid, List<int> value})>
  updateCalls = [];
  final Map<String, dynamic> peripheralState;
  final String? throwOperation;

  void _maybeThrow(String operation) {
    if (throwOperation == operation) {
      throw StateError('$operation failed');
    }
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
    List<String>? serviceUuids,
  }) async {
    _maybeThrow('startScan');
    scanTimeout = timeout;
    scanServiceUuids = serviceUuids?.toList();
  }

  @override
  Future<void> stopScan() async {
    _maybeThrow('stopScan');
    stopScanCalls += 1;
  }

  @override
  List<BleDiscoveredDevice> getScanResults({String? sortBy}) {
    _maybeThrow('getScanResults');
    scanSortBy = sortBy;
    return scanResults;
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _maybeThrow('disconnect');
    disconnectedDeviceIds.add(deviceId);
  }

  @override
  Future<List<Map<String, dynamic>>> discoverServices(String deviceId) async {
    _maybeThrow('discoverServices');
    return discoveredServices;
  }

  @override
  Future<Uint8List> readCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    _maybeThrow('readCharacteristic');
    readCalls.add((deviceId, serviceUuid, characteristicUuid));
    return readValue;
  }

  @override
  List<BleNotificationEntry> getNotificationBuffer(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    _maybeThrow('getNotificationBuffer');
    notificationCalls.add((deviceId, serviceUuid, characteristicUuid));
    return notifications;
  }

  @override
  Future<void> writeCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    GATTCharacteristicWriteType type = GATTCharacteristicWriteType.withResponse,
  }) async {
    _maybeThrow('writeCharacteristic');
    writeCalls.add((
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value.toList(),
      type: type,
    ));
  }

  @override
  Future<void> subscribeCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    _maybeThrow('subscribeCharacteristic');
    subscribeCalls.add((deviceId, serviceUuid, characteristicUuid));
  }

  @override
  Future<void> unsubscribeCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    _maybeThrow('unsubscribeCharacteristic');
    unsubscribeCalls.add((deviceId, serviceUuid, characteristicUuid));
  }

  @override
  String getConnectionState(String deviceId) {
    _maybeThrow('getConnectionState');
    return connectionState;
  }

  @override
  Future<void> startAdvertising({
    String? localName,
    List<String>? serviceUuids,
  }) async {
    _maybeThrow('startAdvertising');
    advertisingLocalName = localName;
    advertisingServiceUuids = serviceUuids;
  }

  @override
  Future<void> stopAdvertising() async {
    _maybeThrow('stopAdvertising');
    stopAdvertisingCalls += 1;
  }

  @override
  Future<void> addService({
    required String serviceUuid,
    required List<Map<String, dynamic>> characteristics,
  }) async {
    _maybeThrow('addService');
    addedServiceUuid = serviceUuid;
    addedCharacteristics = characteristics;
  }

  @override
  Future<void> updateCharacteristic(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value,
  ) async {
    _maybeThrow('updateCharacteristic');
    updateCalls.add((
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      value: value.toList(),
    ));
  }

  @override
  Map<String, dynamic> getPeripheralState() {
    _maybeThrow('getPeripheralState');
    return peripheralState;
  }
}
