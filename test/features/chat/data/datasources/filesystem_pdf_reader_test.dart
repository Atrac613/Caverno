import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// See test/fixtures/pdf/README.md for how each fixture was produced.
String _fixturePath(String name) => 'test/fixtures/pdf/$name.pdf';

Future<Map<String, dynamic>> _read(
  String name, {
  int offset = 1,
  int? limit,
  int maxChars = 120000,
}) async {
  final raw = await FilesystemTools.readFile(
    path: _fixturePath(name),
    offset: offset,
    limit: limit,
    maxChars: maxChars,
  );
  return jsonDecode(raw) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _inspect(String name) async {
  final raw = await FilesystemTools.inspectFile(path: _fixturePath(name));
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('read_file on a PDF', () {
    test('returns extracted text with page markers', () async {
      final response = await _read('text_layer');

      expect(response['error'], isNull);
      expect(response['format'], 'pdf');
      expect(response['page_count'], 1);
      expect(response['content'], startsWith('[page 1]'));
      expect(response['content'], contains('Caverno PDF fixture'));
      expect(response['total_lines'], greaterThan(1));
      expect(response['size_bytes'], greaterThan(0));
    });

    test('reports a content hash that identifies the file', () async {
      final first = await _read('text_layer');
      final second = await _read('text_layer');
      final other = await _read('ascii_uncompressed');

      expect(first['content_hash'], isA<String>());
      expect(first['content_hash'], second['content_hash']);
      expect(first['content_hash'], isNot(other['content_hash']));
    });

    test('honors offset and limit over the extracted lines', () async {
      final whole = await _read('text_layer');
      final wholeLines = (whole['content'] as String).split('\n');

      final window = await _read('text_layer', offset: 2, limit: 1);

      expect(window['start_line'], 2);
      expect(window['line_count'], 1);
      expect(window['content'], wholeLines[1]);
      expect(window['truncated_by_limit'], isTrue);
      expect(window['total_lines'], whole['total_lines']);
    });

    test('clips to max_chars and says so', () async {
      final response = await _read('text_layer', maxChars: 12);

      expect((response['content'] as String).length, lessThanOrEqualTo(12));
      expect(response['truncated_by_chars'], isTrue);
      expect(response['truncated'], isTrue);
    });

    test('reads an uncompressed PDF that a text sniff would pass', () async {
      // The whole file is printable ASCII, so the binary classifier says
      // "text". Without the PDF check running first this would return raw
      // `%PDF` syntax as if it were a source file.
      final response = await _read('ascii_uncompressed');

      expect(response['format'], 'pdf');
      expect(response['content'], contains('Plain ASCII fixture body'));
      expect(response['content'], isNot(contains('endobj')));
    });

    test('names OCR when the document has no text layer', () async {
      final response = await _read('image_only');

      expect(response['error'], contains('scanned document'));
      expect(response['error'], contains('OCR'));
      expect(response['content'], isNull);
    });

    test('reports a password-protected document', () async {
      final response = await _read('encrypted');

      expect(response['error'], contains('password-protected'));
    });

    test('still refuses a non-PDF binary file', () async {
      final directory = Directory.systemTemp.createTempSync('caverno_bin');
      addTearDown(() => directory.deleteSync(recursive: true));
      final binary = File('${directory.path}/blob.bin')
        ..writeAsBytesSync(<int>[0x00, 0x01, 0x02, 0x00, 0xff]);

      final response =
          jsonDecode(await FilesystemTools.readFile(path: binary.path))
              as Map<String, dynamic>;

      expect(response['error'], contains('Binary files are not supported'));
    });

    test('still reads an ordinary text file unchanged', () async {
      final directory = Directory.systemTemp.createTempSync('caverno_txt');
      addTearDown(() => directory.deleteSync(recursive: true));
      final text = File('${directory.path}/notes.txt')
        ..writeAsStringSync('alpha\nbeta\n');

      final response =
          jsonDecode(await FilesystemTools.readFile(path: text.path))
              as Map<String, dynamic>;

      expect(response['content'], 'alpha\nbeta');
      expect(response['format'], isNull);
    });
  });

  group('inspect_file on a PDF', () {
    test('reports pages and samples the extracted text', () async {
      final response = await _inspect('text_layer');

      expect(response['format_hint'], 'pdf');
      expect(response['encoding'], 'pdf');
      expect(response['text_extractable'], isTrue);
      expect(response['page_count'], 1);
      expect(response['is_binary'], isNull);
      expect((response['head'] as List).first, '[page 1]');
      expect(response['tail'], isNotEmpty);
      expect(response['size_human'], isA<String>());
    });

    test('says a scanned document yields nothing', () async {
      final response = await _inspect('image_only');

      expect(response['text_extractable'], isFalse);
      expect(response['format_hint'], 'pdf');
      expect(response['error'], contains('OCR'));
    });

    test('still reports a non-PDF binary as binary', () async {
      final directory = Directory.systemTemp.createTempSync('caverno_bin2');
      addTearDown(() => directory.deleteSync(recursive: true));
      final binary = File('${directory.path}/blob.bin')
        ..writeAsBytesSync(<int>[0x00, 0x01, 0x02]);

      final response =
          jsonDecode(await FilesystemTools.inspectFile(path: binary.path))
              as Map<String, dynamic>;

      expect(response['is_binary'], isTrue);
      expect(response['encoding'], 'binary');
    });
  });
}
