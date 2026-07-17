import 'dart:convert';

import 'package:caverno/core/services/serial_port_service.dart';
import 'package:caverno/features/chat/data/datasources/built_in_serial_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuiltInSerialToolHandler', () {
    test('owns the exact ordered family and separates platform exposure', () {
      final unavailable = BuiltInSerialToolHandler(platformSupport: () => true);
      final supported = BuiltInSerialToolHandler(
        serialPortService: _FakeSerialPortService(),
        platformSupport: () => true,
      );
      final unsupported = BuiltInSerialToolHandler(
        serialPortService: _FakeSerialPortService(),
        platformSupport: () => false,
      );

      expect(BuiltInSerialToolHandler.toolNames, const [
        'serial_list_ports',
        'serial_open',
        'serial_read',
        'serial_decode',
        'serial_write',
        'serial_close',
      ]);
      expect(
        supported.definitions.map(_definitionName),
        BuiltInSerialToolHandler.toolNames,
      );
      expect(unavailable.isAvailable, isFalse);
      expect(unavailable.canExposeDefinitions, isFalse);
      expect(supported.isAvailable, isTrue);
      expect(supported.canExposeDefinitions, isTrue);
      expect(unsupported.isAvailable, isTrue);
      expect(unsupported.canExposeDefinitions, isFalse);
      expect(supported.handles('serial_read'), isTrue);
      expect(supported.handles('serial_monitor'), isFalse);

      final openFunction = _definitionFunction(supported.definitions[1]);
      final openParameters =
          openFunction['parameters']! as Map<String, dynamic>;
      expect(openParameters['required'], ['port']);
      final openProperties =
          openParameters['properties']! as Map<String, dynamic>;
      expect((openProperties['parity']! as Map<String, dynamic>)['enum'], [
        'none',
        'odd',
        'even',
        'mark',
        'space',
      ]);

      final readFunction = _definitionFunction(supported.definitions[2]);
      final readParameters =
          readFunction['parameters']! as Map<String, dynamic>;
      expect(readParameters['required'], ['port']);
      final readProperties =
          readParameters['properties']! as Map<String, dynamic>;
      expect(readProperties.keys, [
        'port',
        'encoding',
        'max_bytes',
        'clear',
        'frame_delimiter',
        'frame_length',
        'max_frames',
        'include_stats',
      ]);
    });

    test(
      'returns direct denials and rejects unavailable known calls',
      () async {
        final service = _FakeSerialPortService();
        final available = BuiltInSerialToolHandler(serialPortService: service);
        final unavailable = BuiltInSerialToolHandler();

        final open = await available.execute(
          name: 'serial_open',
          arguments: const {'port': '/dev/cu.example'},
        );
        final unknown = await available.execute(
          name: 'serial_monitor',
          arguments: const {},
        );

        expect(open.isSuccess, isFalse);
        expect(
          open.errorMessage,
          'Serial tool serial_open must be invoked with user approval and '
          'cannot be executed directly.',
        );
        expect(unknown.isSuccess, isFalse);
        expect(
          unknown.errorMessage,
          'Serial tool serial_monitor must be invoked with user approval and '
          'cannot be executed directly.',
        );
        expect(service.totalCalls, 0);
        await expectLater(
          unavailable.execute(name: 'serial_read', arguments: const {}),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('routes directly when platform exposure is disabled', () async {
      final service = _FakeSerialPortService(listResult: 'unsupported:list');
      final handler = BuiltInSerialToolHandler(
        serialPortService: service,
        platformSupport: () => false,
      );

      final result = await handler.execute(
        name: 'serial_list_ports',
        arguments: const {},
      );

      expect(handler.canExposeDefinitions, isFalse);
      expect(result.result, 'unsupported:list');
      expect(result.isSuccess, isTrue);
      expect(service.listCalls, 1);
    });

    test('forwards direct defaults and preserves exact payloads', () async {
      final service = _FakeSerialPortService(
        listResult: 'list\n',
        readResult: 'read\n',
        decodeResult: 'decode\n',
        writeResult: 'write\n',
        closeResult: 'close\n',
      );
      final handler = BuiltInSerialToolHandler(serialPortService: service);

      final list = await handler.execute(
        name: 'serial_list_ports',
        arguments: const {'ignored': true},
      );
      final read = await handler.execute(
        name: 'serial_read',
        arguments: const {'port': ' /dev/cu.read '},
      );
      final decode = await handler.execute(
        name: 'serial_decode',
        arguments: const {},
      );
      final write = await handler.execute(
        name: 'serial_write',
        arguments: const {},
      );
      final close = await handler.execute(
        name: 'serial_close',
        arguments: const {'port': ' /dev/cu.close '},
      );

      expect(
        [list, read, decode, write, close].map((result) => result.result),
        ['list\n', 'read\n', 'decode\n', 'write\n', 'close\n'],
      );
      expect(
        [list, read, decode, write, close].every((result) => result.isSuccess),
        isTrue,
      );
      expect(service.readCalls, [
        {
          'port': '/dev/cu.read',
          'encoding': 'utf8',
          'max_bytes': null,
          'clear': true,
          'frame_delimiter_hex': null,
          'frame_length': null,
          'max_frames': 200,
          'include_stats': false,
        },
      ]);
      expect(service.decodeCalls, [
        {
          'data_hex': null,
          'port': null,
          'format': '',
          'fields': null,
          'consume': false,
        },
      ]);
      expect(service.writeCalls, [
        {'port': '', 'data': '', 'encoding': 'utf8'},
      ]);
      expect(service.closeCalls, ['/dev/cu.close']);
    });

    test('converts and forwards every explicit direct argument', () async {
      final service = _FakeSerialPortService();
      final handler = BuiltInSerialToolHandler(serialPortService: service);

      await handler.execute(
        name: 'serial_read',
        arguments: const {
          'port': ' /dev/cu.read ',
          'encoding': 'base64',
          'max_bytes': 12.9,
          'clear': false,
          'frame_delimiter': '0a',
          'frame_length': 6.8,
          'max_frames': 3.7,
          'include_stats': true,
        },
      );
      await handler.execute(
        name: 'serial_decode',
        arguments: const {
          'data': '01 02',
          'port': ' /dev/cu.decode ',
          'format': '>2B',
          'fields': ['first', 2],
          'consume': true,
        },
      );
      await handler.execute(
        name: 'serial_write',
        arguments: const {
          'port': ' /dev/cu.write ',
          'data': 'QQ==',
          'encoding': 'base64',
        },
      );

      expect(service.readCalls.single, {
        'port': '/dev/cu.read',
        'encoding': 'base64',
        'max_bytes': 12,
        'clear': false,
        'frame_delimiter_hex': '0a',
        'frame_length': 6,
        'max_frames': 3,
        'include_stats': true,
      });
      expect(service.decodeCalls.single, {
        'data_hex': '01 02',
        'port': '/dev/cu.decode',
        'format': '>2B',
        'fields': ['first', '2'],
        'consume': true,
      });
      expect(service.writeCalls.single, {
        'port': '/dev/cu.write',
        'data': 'QQ==',
        'encoding': 'base64',
      });
    });

    test('keeps service error JSON in a successful result envelope', () async {
      final payload = jsonEncode({
        'error': true,
        'message': 'Serial ports are unsupported on this platform.',
      });
      final handler = BuiltInSerialToolHandler(
        serialPortService: _FakeSerialPortService(readResult: payload),
      );

      final result = await handler.execute(
        name: 'serial_read',
        arguments: const {'port': '/dev/cu.example'},
      );

      expect(result.result, payload);
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
    });

    test(
      'converts service and argument exceptions into failed results',
      () async {
        final service = _FakeSerialPortService(throwOperation: 'write');
        final handler = BuiltInSerialToolHandler(serialPortService: service);

        final serviceFailure = await handler.execute(
          name: 'serial_write',
          arguments: const {'port': '/dev/cu.example', 'data': 'A'},
        );
        final castFailure = await handler.execute(
          name: 'serial_read',
          arguments: const {'max_bytes': '12'},
        );

        expect(serviceFailure.isSuccess, isFalse);
        expect(serviceFailure.result, isEmpty);
        expect(serviceFailure.errorMessage, 'Bad state: write failed');
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

final class _FakeSerialPortService extends SerialPortService {
  _FakeSerialPortService({
    this.listResult = 'list result',
    this.readResult = 'read result',
    this.decodeResult = 'decode result',
    this.writeResult = 'write result',
    this.closeResult = 'close result',
    this.throwOperation,
  });

  final String listResult;
  final String readResult;
  final String decodeResult;
  final String writeResult;
  final String closeResult;
  final String? throwOperation;
  int listCalls = 0;
  final List<Map<String, dynamic>> readCalls = [];
  final List<Map<String, dynamic>> decodeCalls = [];
  final List<Map<String, dynamic>> writeCalls = [];
  final List<String> closeCalls = [];

  int get totalCalls =>
      listCalls +
      readCalls.length +
      decodeCalls.length +
      writeCalls.length +
      closeCalls.length;

  void _maybeThrow(String operation) {
    if (throwOperation == operation) {
      throw StateError('$operation failed');
    }
  }

  @override
  String listPorts() {
    _maybeThrow('listPorts');
    listCalls += 1;
    return listResult;
  }

  @override
  String read(
    String portName, {
    String encoding = 'utf8',
    int? maxBytes,
    bool clear = true,
    String? frameDelimiterHex,
    int? frameLength,
    int maxFrames = 200,
    bool includeStats = false,
  }) {
    _maybeThrow('read');
    readCalls.add({
      'port': portName,
      'encoding': encoding,
      'max_bytes': maxBytes,
      'clear': clear,
      'frame_delimiter_hex': frameDelimiterHex,
      'frame_length': frameLength,
      'max_frames': maxFrames,
      'include_stats': includeStats,
    });
    return readResult;
  }

  @override
  String decode({
    String? dataHex,
    String? port,
    required String format,
    List<String>? fields,
    bool consume = false,
  }) {
    _maybeThrow('decode');
    decodeCalls.add({
      'data_hex': dataHex,
      'port': port,
      'format': format,
      'fields': fields,
      'consume': consume,
    });
    return decodeResult;
  }

  @override
  Future<String> write(
    String portName,
    String data, {
    String encoding = 'utf8',
  }) async {
    _maybeThrow('write');
    writeCalls.add({'port': portName, 'data': data, 'encoding': encoding});
    return writeResult;
  }

  @override
  Future<String> close(String portName) async {
    _maybeThrow('close');
    closeCalls.add(portName);
    return closeResult;
  }
}
