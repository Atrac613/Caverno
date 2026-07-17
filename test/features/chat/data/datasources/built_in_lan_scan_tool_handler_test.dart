import 'dart:convert';

import 'package:caverno/core/services/lan_scan_service.dart';
import 'package:caverno/features/chat/data/datasources/built_in_lan_scan_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuiltInLanScanToolHandler', () {
    test('owns the exact ordered LAN scan family and reports availability', () {
      final unavailable = BuiltInLanScanToolHandler();
      final available = BuiltInLanScanToolHandler(
        lanScanService: _FakeLanScanService(),
      );

      expect(BuiltInLanScanToolHandler.toolNames, const [
        'lan_scan',
        'lan_get_scan_results',
      ]);
      expect(
        available.definitions.map(_definitionName),
        BuiltInLanScanToolHandler.toolNames,
      );
      expect(unavailable.isAvailable, isFalse);
      expect(available.isAvailable, isTrue);
      expect(available.handles('lan_scan'), isTrue);
      expect(available.handles('lan_get_local_info'), isFalse);

      final scanFunction = _definitionFunction(available.definitions.first);
      final scanParameters =
          scanFunction['parameters']! as Map<String, dynamic>;
      final scanProperties =
          scanParameters['properties']! as Map<String, dynamic>;
      expect(scanProperties.keys, ['subnet', 'ip_version', 'timeout', 'ports']);
      expect((scanProperties['ip_version']! as Map<String, dynamic>)['enum'], [
        'auto',
        'ipv4',
        'ipv6',
      ]);
      expect(scanParameters['required'], isEmpty);

      final resultsFunction = _definitionFunction(available.definitions.last);
      final resultsParameters =
          resultsFunction['parameters']! as Map<String, dynamic>;
      final resultsProperties =
          resultsParameters['properties']! as Map<String, dynamic>;
      expect((resultsProperties['sort_by']! as Map<String, dynamic>)['enum'], [
        'ip',
        'response_time',
        'hostname',
      ]);
      expect(resultsParameters['required'], isEmpty);
    });

    test(
      'returns the legacy unknown failure and rejects unavailable calls',
      () async {
        final available = BuiltInLanScanToolHandler(
          lanScanService: _FakeLanScanService(),
        );
        final unavailable = BuiltInLanScanToolHandler();

        final unknown = await available.execute(
          name: 'lan_get_local_info',
          arguments: const {},
        );

        expect(unknown.isSuccess, isFalse);
        expect(unknown.result, isEmpty);
        expect(
          unknown.errorMessage,
          'Unknown LAN scan tool: lan_get_local_info',
        );
        await expectLater(
          unavailable.execute(name: 'lan_scan', arguments: const {}),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('forwards defaults and preserves exact payloads', () async {
      final service = _FakeLanScanService(
        scanResult: '{"hosts_found":0}\n',
        cachedResult: '{"hosts":[]}',
      );
      final handler = BuiltInLanScanToolHandler(lanScanService: service);

      final scan = await handler.execute(name: 'lan_scan', arguments: const {});
      final cached = await handler.execute(
        name: 'lan_get_scan_results',
        arguments: const {},
      );

      expect(service.scanCalls, [
        {'subnet': null, 'ip_version': null, 'timeout_ms': 1000, 'ports': null},
      ]);
      expect(service.scanResultSorts, [null]);
      expect(scan.toolName, 'lan_scan');
      expect(scan.result, '{"hosts_found":0}\n');
      expect(scan.isSuccess, isTrue);
      expect(scan.errorMessage, isNull);
      expect(cached.result, '{"hosts":[]}');
      expect(cached.isSuccess, isTrue);
    });

    test(
      'trims and converts scan arguments without clamping or reordering',
      () async {
        final service = _FakeLanScanService();
        final handler = BuiltInLanScanToolHandler(lanScanService: service);

        final scan = await handler.execute(
          name: 'lan_scan',
          arguments: const {
            'subnet': ' fd00::/120 ',
            'ip_version': ' ipv6 ',
            'timeout': 6000.9,
            'ports': [8443.7, 22, 443.2],
          },
        );
        final cached = await handler.execute(
          name: 'lan_get_scan_results',
          arguments: const {'sort_by': 'response_time'},
        );

        expect(scan.isSuccess, isTrue);
        expect(service.scanCalls, [
          {
            'subnet': 'fd00::/120',
            'ip_version': 'ipv6',
            'timeout_ms': 6000,
            'ports': [8443, 22, 443],
          },
        ]);
        expect(cached.isSuccess, isTrue);
        expect(service.scanResultSorts, ['response_time']);
      },
    );

    test('keeps service error JSON in a successful result envelope', () async {
      final payload = jsonEncode({
        'error': true,
        'message': 'No active network interface was found.',
      });
      final handler = BuiltInLanScanToolHandler(
        lanScanService: _FakeLanScanService(scanResult: payload),
      );

      final result = await handler.execute(
        name: 'lan_scan',
        arguments: const {},
      );

      expect(result.result, payload);
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
    });

    test(
      'converts service and argument exceptions into failed results',
      () async {
        final service = _FakeLanScanService(throwOperation: 'getScanResults');
        final handler = BuiltInLanScanToolHandler(lanScanService: service);

        final serviceFailure = await handler.execute(
          name: 'lan_get_scan_results',
          arguments: const {},
        );
        final castFailure = await handler.execute(
          name: 'lan_scan',
          arguments: const {
            'ports': ['443'],
          },
        );

        expect(serviceFailure.isSuccess, isFalse);
        expect(serviceFailure.result, isEmpty);
        expect(serviceFailure.errorMessage, 'Bad state: getScanResults failed');
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

final class _FakeLanScanService extends LanScanService {
  _FakeLanScanService({
    this.scanResult = 'scan result',
    this.cachedResult = 'cached result',
    this.throwOperation,
  });

  final String scanResult;
  final String cachedResult;
  final String? throwOperation;
  final List<Map<String, dynamic>> scanCalls = [];
  final List<String?> scanResultSorts = [];

  void _maybeThrow(String operation) {
    if (throwOperation == operation) {
      throw StateError('$operation failed');
    }
  }

  @override
  Future<String> startScan({
    String? subnet,
    String? ipVersion,
    int timeoutMs = 1000,
    List<int>? ports,
  }) async {
    _maybeThrow('startScan');
    scanCalls.add({
      'subnet': subnet,
      'ip_version': ipVersion,
      'timeout_ms': timeoutMs,
      'ports': ports,
    });
    return scanResult;
  }

  @override
  String getScanResults({String? sortBy}) {
    _maybeThrow('getScanResults');
    scanResultSorts.add(sortBy);
    return cachedResult;
  }
}
