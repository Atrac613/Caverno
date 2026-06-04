import 'dart:convert';

import 'package:caverno/core/services/serial_port_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SerialPortService service;

  setUp(() {
    service = SerialPortService();
  });

  Map<String, dynamic> decode(
    String data,
    String format, {
    List<String>? fields,
  }) {
    return jsonDecode(
      service.decode(dataHex: data, format: format, fields: fields),
    ) as Map<String, dynamic>;
  }

  group('SerialPortService.decode (struct)', () {
    test('little-endian uint16 (default byte order)', () {
      final r = decode('2c 01', '<H');
      expect(r['values'], [300]);
      expect(r['bytes_consumed'], 2);
      expect(r['byte_order'], 'little');
    });

    test('big-endian uint16', () {
      final r = decode('01 2c', '>H');
      expect(r['values'], [300]);
      expect(r['byte_order'], 'big');
    });

    test('signed int8 is negative', () {
      final r = decode('ff', 'b');
      expect(r['values'], [-1]);
    });

    test('float32 little-endian', () {
      final r = decode('00 00 80 3f', '<f');
      expect((r['values'] as List).first, closeTo(1.0, 1e-6));
    });

    test('multiple values with named fields', () {
      // <HHf : uint16=1, uint16=300, float32=1.0
      final r = decode(
        '01 00 2c 01 00 00 80 3f',
        '<HHf',
        fields: ['count', 'value', 'ratio'],
      );
      expect(r['values'].length, 3);
      expect(r['fields']['count'], 1);
      expect(r['fields']['value'], 300);
      expect((r['fields']['ratio'] as num).toDouble(), closeTo(1.0, 1e-6));
      expect(r['bytes_consumed'], 8);
    });

    test('repeat count expands a type', () {
      final r = decode('01 00 02 00 03 00', '<3H');
      expect(r['values'], [1, 2, 3]);
    });

    test('Ns reads a fixed-length string', () {
      final r = decode('48 65 6c 6c 6f', '5s');
      expect(r['values'], ['Hello']);
    });

    test('Nx skips pad bytes', () {
      final r = decode('ff 01 00', 'xH');
      expect(r['values'], [1]);
      expect(r['bytes_consumed'], 3);
    });

    test('non-finite float is stringified (JSON-safe)', () {
      // 0x7fc00000 (BE) is NaN as float32.
      final r = decode('7f c0 00 00', '>f');
      expect(r['values'].first, 'NaN');
    });

    test('not enough bytes returns an error', () {
      final r = decode('01', '<H');
      expect(r['error'], true);
      expect(r['message'], contains('Not enough bytes'));
    });

    test('invalid format token returns an error', () {
      final r = decode('01 02', '<Hz');
      expect(r['error'], true);
    });

    test('missing data and port returns an error', () {
      final r =
          jsonDecode(service.decode(format: '<H')) as Map<String, dynamic>;
      expect(r['error'], true);
    });
  });
}
