import 'dart:convert';

import 'package:caverno/core/services/wifi_service.dart';
import 'package:caverno/features/chat/data/datasources/built_in_wifi_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuiltInWifiToolHandler', () {
    test('owns the exact ordered WiFi family and reports availability', () {
      final unavailable = BuiltInWifiToolHandler();
      final available = BuiltInWifiToolHandler(wifiService: _FakeWifiService());

      expect(BuiltInWifiToolHandler.toolNames, const [
        'wifi_scan',
        'wifi_get_scan_results',
        'wifi_get_connection_info',
      ]);
      expect(
        available.definitions.map(_definitionName),
        BuiltInWifiToolHandler.toolNames,
      );
      expect(unavailable.isAvailable, isFalse);
      expect(available.isAvailable, isTrue);
      expect(available.handles('wifi_scan'), isTrue);
      expect(available.handles('get_wifi_health'), isFalse);

      final scanFunction = _definitionFunction(available.definitions.first);
      final scanParameters =
          scanFunction['parameters']! as Map<String, dynamic>;
      expect(scanParameters['properties'], isEmpty);

      final resultsFunction = _definitionFunction(available.definitions[1]);
      final resultsParameters =
          resultsFunction['parameters']! as Map<String, dynamic>;
      final resultsProperties =
          resultsParameters['properties']! as Map<String, dynamic>;
      final sortBy = resultsProperties['sort_by']! as Map<String, dynamic>;
      expect(sortBy['enum'], ['signal', 'ssid']);
      expect(resultsParameters['required'], isEmpty);
    });

    test('rejects unknown names and unavailable direct execution', () async {
      final available = BuiltInWifiToolHandler(wifiService: _FakeWifiService());
      final unavailable = BuiltInWifiToolHandler();

      await expectLater(
        available.execute(name: 'get_wifi_health', arguments: const {}),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        unavailable.execute(name: 'wifi_scan', arguments: const {}),
        throwsA(isA<StateError>()),
      );
    });

    test('forwards all operations and preserves exact payloads', () async {
      final service = _FakeWifiService(
        scanResult: '{"scan":"complete"}\n',
        cachedResult: '[{"ssid":"Lab"}]',
        connectionResult: '{"ssid":"Lab","ip":"192.0.2.1"}',
      );
      final handler = BuiltInWifiToolHandler(wifiService: service);

      final scan = await handler.execute(
        name: 'wifi_scan',
        arguments: const {'ignored': true},
      );
      final defaultResults = await handler.execute(
        name: 'wifi_get_scan_results',
        arguments: const {},
      );
      final sortedResults = await handler.execute(
        name: 'wifi_get_scan_results',
        arguments: const {'sort_by': 'ssid'},
      );
      final connection = await handler.execute(
        name: 'wifi_get_connection_info',
        arguments: const {'ignored': true},
      );

      expect(service.scanCalls, 1);
      expect(service.scanResultSorts, [null, 'ssid']);
      expect(service.connectionInfoCalls, 1);
      expect(scan.toolName, 'wifi_scan');
      expect(scan.result, '{"scan":"complete"}\n');
      expect(scan.isSuccess, isTrue);
      expect(defaultResults.result, '[{"ssid":"Lab"}]');
      expect(defaultResults.isSuccess, isTrue);
      expect(sortedResults.result, '[{"ssid":"Lab"}]');
      expect(sortedResults.isSuccess, isTrue);
      expect(connection.result, '{"ssid":"Lab","ip":"192.0.2.1"}');
      expect(connection.isSuccess, isTrue);
    });

    test('keeps service error JSON in a successful result envelope', () async {
      final payload = jsonEncode({
        'error': true,
        'message': 'WiFi scanning is not supported on macos.',
      });
      final handler = BuiltInWifiToolHandler(
        wifiService: _FakeWifiService(scanResult: payload),
      );

      final result = await handler.execute(
        name: 'wifi_scan',
        arguments: const {},
      );

      expect(result.result, payload);
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
    });

    test(
      'converts service and argument exceptions into failed results',
      () async {
        final service = _FakeWifiService(throwOperation: 'getConnectionInfo');
        final handler = BuiltInWifiToolHandler(wifiService: service);

        final serviceFailure = await handler.execute(
          name: 'wifi_get_connection_info',
          arguments: const {},
        );
        final castFailure = await handler.execute(
          name: 'wifi_get_scan_results',
          arguments: const {'sort_by': 7},
        );

        expect(serviceFailure.isSuccess, isFalse);
        expect(serviceFailure.result, isEmpty);
        expect(
          serviceFailure.errorMessage,
          'Bad state: getConnectionInfo failed',
        );
        expect(castFailure.isSuccess, isFalse);
        expect(castFailure.result, isEmpty);
        expect(castFailure.errorMessage, contains('is not a subtype of type'));
      },
    );
  });
}

String _definitionName(Map<String, dynamic> definition) {
  return _definitionFunction(definition)['name']! as String;
}

Map<String, dynamic> _definitionFunction(Map<String, dynamic> definition) {
  return definition['function']! as Map<String, dynamic>;
}

final class _FakeWifiService extends WifiService {
  _FakeWifiService({
    this.scanResult = 'scan result',
    this.cachedResult = 'cached result',
    this.connectionResult = 'connection result',
    this.throwOperation,
  });

  final String scanResult;
  final String cachedResult;
  final String connectionResult;
  final String? throwOperation;
  int scanCalls = 0;
  final List<String?> scanResultSorts = [];
  int connectionInfoCalls = 0;

  void _maybeThrow(String operation) {
    if (throwOperation == operation) {
      throw StateError('$operation failed');
    }
  }

  @override
  Future<String> startScan() async {
    _maybeThrow('startScan');
    scanCalls += 1;
    return scanResult;
  }

  @override
  String getScanResults({String? sortBy}) {
    _maybeThrow('getScanResults');
    scanResultSorts.add(sortBy);
    return cachedResult;
  }

  @override
  Future<String> getConnectionInfo() async {
    _maybeThrow('getConnectionInfo');
    connectionInfoCalls += 1;
    return connectionResult;
  }
}
