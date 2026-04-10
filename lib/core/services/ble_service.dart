import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

/// A discovered BLE device with cached advertisement data.
class BleDiscoveredDevice {
  BleDiscoveredDevice({
    required this.peripheral,
    required this.rssi,
    required this.name,
    required this.serviceUuids,
    required this.discoveredAt,
  });

  final Peripheral peripheral;
  final int rssi;
  final String? name;
  final List<String> serviceUuids;
  final DateTime discoveredAt;
}

/// A timestamped notification value from a subscribed characteristic.
class BleNotificationEntry {
  BleNotificationEntry({required this.timestamp, required this.value});

  final DateTime timestamp;
  final Uint8List value;
}

/// Manages BLE central and peripheral operations.
///
/// Central: scan, connect, discover services, read/write characteristics,
/// subscribe to notifications.
/// Peripheral: advertise, host GATT services, notify connected centrals.
class BleService {
  CentralManager? _centralManager;
  PeripheralManager? _peripheralManager;

  // Central state
  final Map<String, BleDiscoveredDevice> _scanResults = {};
  final Map<String, Peripheral> _connections = {};
  final Map<String, List<GATTService>> _discoveredServices = {};
  final Map<String, List<BleNotificationEntry>> _notificationBuffers = {};
  final Map<String, StreamSubscription<GATTCharacteristicNotifiedEventArgs>>
      _notificationSubscriptions = {};
  StreamSubscription<DiscoveredEventArgs>? _scanSubscription;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>?
      _connectionStateSubscription;
  bool _isScanning = false;
  int _scanGeneration = 0;

  // Peripheral state
  bool _isAdvertising = false;
  final List<GATTService> _hostedServices = [];
  final Map<String, Central> _connectedCentrals = {};
  final Map<String, GATTCharacteristic> _hostedCharacteristics = {};
  StreamSubscription<GATTCharacteristicReadRequestedEventArgs>?
      _readRequestSub;
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>?
      _writeRequestSub;
  StreamSubscription<GATTCharacteristicNotifyStateChangedEventArgs>?
      _notifyStateChangedSub;
  StreamSubscription<CentralConnectionStateChangedEventArgs>?
      _peripheralConnectionSub;

  // Characteristic value cache for peripheral mode read requests.
  final Map<String, Uint8List> _hostedCharacteristicValues = {};

  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;

  CentralManager get _central {
    return _centralManager ??= CentralManager();
  }

  PeripheralManager get _peripheral {
    return _peripheralManager ??= PeripheralManager();
  }

  // ---------------------------------------------------------------------------
  // Central: Scan
  // ---------------------------------------------------------------------------

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
    List<String>? serviceUuids,
  }) async {
    if (_isScanning) await stopScan();
    _scanResults.clear();

    List<UUID>? filterUuids;
    if (serviceUuids != null && serviceUuids.isNotEmpty) {
      filterUuids = serviceUuids.map(UUID.fromString).toList();
    }

    _scanSubscription = _central.discovered.listen((event) {
      final id = event.peripheral.uuid.toString();
      String? name;
      try {
        name = event.advertisement.name;
      } catch (_) {}
      final uuids =
          event.advertisement.serviceUUIDs.map((u) => u.toString()).toList();
      _scanResults[id] = BleDiscoveredDevice(
        peripheral: event.peripheral,
        rssi: event.rssi,
        name: name,
        serviceUuids: uuids,
        discoveredAt: DateTime.now(),
      );
    });

    await _central.startDiscovery(serviceUUIDs: filterUuids);
    _isScanning = true;
    final gen = ++_scanGeneration;
    appLog('[BleService] Scan started (gen=$gen)');

    // Auto-stop after timeout. Only if this scan generation is still active.
    Future.delayed(timeout, () {
      if (_isScanning && _scanGeneration == gen) stopScan();
    });
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;
    try {
      await _central.stopDiscovery();
    } catch (e) {
      appLog('[BleService] Error stopping scan: $e');
    }
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _isScanning = false;
    appLog('[BleService] Scan stopped, ${_scanResults.length} devices found');
  }

  List<BleDiscoveredDevice> getScanResults({String? sortBy}) {
    final results = _scanResults.values.toList();
    if (sortBy == 'rssi') {
      results.sort((a, b) => b.rssi.compareTo(a.rssi));
    } else if (sortBy == 'name') {
      results.sort(
        (a, b) => (a.name ?? '').compareTo(b.name ?? ''),
      );
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // Central: Connect / Disconnect
  // ---------------------------------------------------------------------------

  Future<void> connect(String deviceId) async {
    final device = _scanResults[deviceId];
    if (device == null) {
      throw StateError(
        'Device $deviceId not found in scan results. Run ble_start_scan first.',
      );
    }

    _connectionStateSubscription ??=
        _central.connectionStateChanged.listen((event) {
      final id = event.peripheral.uuid.toString();
      if (event.state == ConnectionState.disconnected) {
        _connections.remove(id);
        _discoveredServices.remove(id);
        appLog('[BleService] Device $id disconnected');
      }
    });

    await _central.connect(device.peripheral);
    _connections[deviceId] = device.peripheral;
    appLog('[BleService] Connected to $deviceId');
  }

  Future<void> disconnect(String deviceId) async {
    final peripheral = _connections[deviceId];
    if (peripheral == null) {
      throw StateError('Device $deviceId is not connected.');
    }
    await _central.disconnect(peripheral);
    _connections.remove(deviceId);
    _discoveredServices.remove(deviceId);
    appLog('[BleService] Disconnected from $deviceId');
  }

  String getConnectionState(String deviceId) {
    return _connections.containsKey(deviceId) ? 'connected' : 'disconnected';
  }

  // ---------------------------------------------------------------------------
  // Central: Discover Services
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> discoverServices(String deviceId) async {
    final peripheral = _requireConnected(deviceId);
    final services = await _central.discoverGATT(peripheral);
    _discoveredServices[deviceId] = services;

    return services.map((s) {
      return {
        'uuid': s.uuid.toString(),
        'is_primary': s.isPrimary,
        'characteristics': s.characteristics.map((c) {
          return {
            'uuid': c.uuid.toString(),
            'properties': c.properties.map((p) => p.name).toList(),
            'descriptors': c.descriptors.map((d) {
              return {'uuid': d.uuid.toString()};
            }).toList(),
          };
        }).toList(),
      };
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Central: Read / Write Characteristics
  // ---------------------------------------------------------------------------

  Future<Uint8List> readCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    // Check notification buffer first for subscribed characteristics.
    final subKey = _subscriptionKey(deviceId, serviceUuid, characteristicUuid);
    final buffer = _notificationBuffers[subKey];
    if (buffer != null && buffer.isNotEmpty) {
      return buffer.last.value;
    }

    final peripheral = _requireConnected(deviceId);
    final characteristic = _findCharacteristic(
      deviceId,
      serviceUuid,
      characteristicUuid,
    );
    return _central.readCharacteristic(peripheral, characteristic);
  }

  /// Returns buffered notification values for a subscribed characteristic.
  List<BleNotificationEntry> getNotificationBuffer(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    final key = _subscriptionKey(deviceId, serviceUuid, characteristicUuid);
    return List.unmodifiable(_notificationBuffers[key] ?? []);
  }

  Future<void> writeCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    Uint8List value, {
    GATTCharacteristicWriteType type =
        GATTCharacteristicWriteType.withResponse,
  }) async {
    final peripheral = _requireConnected(deviceId);
    final characteristic = _findCharacteristic(
      deviceId,
      serviceUuid,
      characteristicUuid,
    );
    await _central.writeCharacteristic(
      peripheral,
      characteristic,
      value: value,
      type: type,
    );
  }

  // ---------------------------------------------------------------------------
  // Central: Subscribe / Unsubscribe
  // ---------------------------------------------------------------------------

  Future<void> subscribeCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    final peripheral = _requireConnected(deviceId);
    final characteristic = _findCharacteristic(
      deviceId,
      serviceUuid,
      characteristicUuid,
    );
    final key = _subscriptionKey(deviceId, serviceUuid, characteristicUuid);
    if (_notificationSubscriptions.containsKey(key)) return;

    await _central.setCharacteristicNotifyState(
      peripheral,
      characteristic,
      state: true,
    );

    _notificationBuffers[key] = [];
    _notificationSubscriptions[key] =
        _central.characteristicNotified.listen((event) {
      if (event.peripheral.uuid.toString() == deviceId &&
          event.characteristic.uuid.toString() == characteristicUuid) {
        final buffer = _notificationBuffers[key] ??= [];
        buffer.add(
          BleNotificationEntry(timestamp: DateTime.now(), value: event.value),
        );
        // Ring buffer: keep last 10 entries.
        if (buffer.length > 10) buffer.removeAt(0);
      }
    });

    appLog('[BleService] Subscribed to $characteristicUuid on $deviceId');
  }

  Future<void> unsubscribeCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) async {
    final peripheral = _requireConnected(deviceId);
    final characteristic = _findCharacteristic(
      deviceId,
      serviceUuid,
      characteristicUuid,
    );
    final key = _subscriptionKey(deviceId, serviceUuid, characteristicUuid);

    await _central.setCharacteristicNotifyState(
      peripheral,
      characteristic,
      state: false,
    );
    await _notificationSubscriptions.remove(key)?.cancel();
    _notificationBuffers.remove(key);
    appLog('[BleService] Unsubscribed from $characteristicUuid on $deviceId');
  }

  // ---------------------------------------------------------------------------
  // Peripheral: Advertise
  // ---------------------------------------------------------------------------

  Future<void> startAdvertising({
    String? localName,
    List<String>? serviceUuids,
  }) async {
    if (_isAdvertising) await stopAdvertising();

    _setupPeripheralHandlers();

    final advertisement = Advertisement(
      name: localName,
      serviceUUIDs: serviceUuids?.map(UUID.fromString).toList() ?? [],
    );
    await _peripheral.startAdvertising(advertisement);
    _isAdvertising = true;
    appLog('[BleService] Advertising started');
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await _peripheral.stopAdvertising();
    } catch (e) {
      appLog('[BleService] Error stopping advertising: $e');
    }
    _isAdvertising = false;
    appLog('[BleService] Advertising stopped');
  }

  // ---------------------------------------------------------------------------
  // Peripheral: Add Service
  // ---------------------------------------------------------------------------

  Future<void> addService({
    required String serviceUuid,
    required List<Map<String, dynamic>> characteristics,
  }) async {
    final chars = <GATTCharacteristic>[];
    for (final charDef in characteristics) {
      final uuid = UUID.fromString(charDef['uuid'] as String);
      final rawProps = (charDef['properties'] as List?)?.cast<String>() ?? [];
      final properties = rawProps
          .map(_parseCharacteristicProperty)
          .whereType<GATTCharacteristicProperty>()
          .toList();
      final permissions = _derivePermissions(properties);

      final char = GATTCharacteristic.mutable(
        uuid: uuid,
        properties: properties,
        permissions: permissions,
        descriptors: [],
      );
      chars.add(char);
      _hostedCharacteristics[uuid.toString()] = char;

      // Initialize with provided value if present.
      if (charDef['value'] != null) {
        _hostedCharacteristicValues[uuid.toString()] =
            _decodeValue(charDef['value'] as String, charDef['encoding'] as String? ?? 'hex');
      }
    }

    final service = GATTService(
      uuid: UUID.fromString(serviceUuid),
      isPrimary: true,
      includedServices: [],
      characteristics: chars,
    );
    await _peripheral.addService(service);
    _hostedServices.add(service);
    appLog('[BleService] Service $serviceUuid added with ${chars.length} characteristics');
  }

  // ---------------------------------------------------------------------------
  // Peripheral: Update Characteristic (notify subscribers)
  // ---------------------------------------------------------------------------

  Future<void> updateCharacteristic(
    String serviceUuid,
    String characteristicUuid,
    Uint8List value,
  ) async {
    _hostedCharacteristicValues[characteristicUuid] = value;

    final char = _hostedCharacteristics[characteristicUuid];
    if (char == null) {
      throw StateError(
        'Characteristic $characteristicUuid not found in hosted services.',
      );
    }

    // Notify all connected centrals.
    for (final central in _connectedCentrals.values) {
      try {
        await _peripheral.notifyCharacteristic(central, char, value: value);
      } catch (e) {
        appLog('[BleService] Failed to notify central: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Peripheral: State
  // ---------------------------------------------------------------------------

  Map<String, dynamic> getPeripheralState() {
    return {
      'is_advertising': _isAdvertising,
      'hosted_services': _hostedServices.map((s) {
        return {
          'uuid': s.uuid.toString(),
          'characteristics': s.characteristics.map((c) {
            return {
              'uuid': c.uuid.toString(),
              'properties': c.properties.map((p) => p.name).toList(),
            };
          }).toList(),
        };
      }).toList(),
      'connected_centrals': _connectedCentrals.keys.toList(),
    };
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await stopScan();
    await stopAdvertising();

    for (final sub in _notificationSubscriptions.values) {
      await sub.cancel();
    }
    _notificationSubscriptions.clear();
    _notificationBuffers.clear();

    for (final deviceId in _connections.keys.toList()) {
      try {
        await disconnect(deviceId);
      } catch (_) {}
    }

    await _connectionStateSubscription?.cancel();
    await _readRequestSub?.cancel();
    await _writeRequestSub?.cancel();
    await _notifyStateChangedSub?.cancel();
    await _peripheralConnectionSub?.cancel();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Peripheral _requireConnected(String deviceId) {
    final peripheral = _connections[deviceId];
    if (peripheral == null) {
      throw StateError(
        'Device $deviceId is not connected. Call ble_connect first.',
      );
    }
    return peripheral;
  }

  GATTCharacteristic _findCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    final services = _discoveredServices[deviceId];
    if (services == null || services.isEmpty) {
      throw StateError(
        'No services discovered for $deviceId. '
        'Call ble_discover_services first.',
      );
    }

    final sUuid = serviceUuid.toLowerCase();
    final cUuid = characteristicUuid.toLowerCase();

    for (final service in services) {
      if (service.uuid.toString().toLowerCase() != sUuid) continue;
      for (final char in service.characteristics) {
        if (char.uuid.toString().toLowerCase() == cUuid) return char;
      }
    }
    throw StateError(
      'Characteristic $characteristicUuid not found in service $serviceUuid.',
    );
  }

  String _subscriptionKey(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) =>
      '$deviceId/$serviceUuid/$characteristicUuid';

  void _setupPeripheralHandlers() {
    if (_readRequestSub != null) return;

    _readRequestSub = _peripheral.characteristicReadRequested.listen((event) {
      final uuid = event.characteristic.uuid.toString();
      final value = _hostedCharacteristicValues[uuid] ?? Uint8List(0);
      _peripheral.respondReadRequestWithValue(event.request, value: value);
    });

    _writeRequestSub =
        _peripheral.characteristicWriteRequested.listen((event) {
      final uuid = event.characteristic.uuid.toString();
      _hostedCharacteristicValues[uuid] = event.request.value;
      _peripheral.respondWriteRequest(event.request);
    });

    try {
      _peripheralConnectionSub =
          _peripheral.connectionStateChanged.listen((event) {
        final id = event.central.uuid.toString();
        if (event.state == ConnectionState.connected) {
          _connectedCentrals[id] = event.central;
          appLog('[BleService] Central $id connected');
        } else {
          _connectedCentrals.remove(id);
          appLog('[BleService] Central $id disconnected');
        }
      });
    } on UnsupportedError {
      // connectionStateChanged not available on all platforms.
    }

    try {
      _notifyStateChangedSub =
          _peripheral.characteristicNotifyStateChanged.listen((event) {
        appLog(
          '[BleService] Notify state changed: ${event.characteristic.uuid} '
          'state=${event.state}',
        );
      });
    } on UnsupportedError {
      // Not available on all platforms.
    }
  }

  static GATTCharacteristicProperty? _parseCharacteristicProperty(String name) {
    return switch (name.toLowerCase()) {
      'read' => GATTCharacteristicProperty.read,
      'write' => GATTCharacteristicProperty.write,
      'writeWithoutResponse' ||
      'write_without_response' =>
        GATTCharacteristicProperty.writeWithoutResponse,
      'notify' => GATTCharacteristicProperty.notify,
      'indicate' => GATTCharacteristicProperty.indicate,
      _ => null,
    };
  }

  static List<GATTCharacteristicPermission> _derivePermissions(
    List<GATTCharacteristicProperty> properties,
  ) {
    final perms = <GATTCharacteristicPermission>{};
    for (final prop in properties) {
      switch (prop) {
        case GATTCharacteristicProperty.read:
          perms.add(GATTCharacteristicPermission.read);
        case GATTCharacteristicProperty.write:
        case GATTCharacteristicProperty.writeWithoutResponse:
          perms.add(GATTCharacteristicPermission.write);
        case GATTCharacteristicProperty.notify:
        case GATTCharacteristicProperty.indicate:
          perms.add(GATTCharacteristicPermission.read);
      }
    }
    return perms.toList();
  }

  static Uint8List _decodeValue(String value, String encoding) {
    return switch (encoding) {
      'utf8' => Uint8List.fromList(utf8.encode(value)),
      'base64' => base64Decode(value),
      _ => _hexDecode(value),
    };
  }

  static Uint8List _hexDecode(String hex) {
    final clean = hex.replaceAll(RegExp(r'[\s:-]'), '');
    final bytes = <int>[];
    for (var i = 0; i + 1 < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  static String encodeValue(Uint8List value, String encoding) {
    return switch (encoding) {
      'utf8' => utf8.decode(value, allowMalformed: true),
      'base64' => base64Encode(value),
      _ => value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':'),
    };
  }
}

final bleServiceProvider = Provider<BleService>((ref) {
  final service = BleService();
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
