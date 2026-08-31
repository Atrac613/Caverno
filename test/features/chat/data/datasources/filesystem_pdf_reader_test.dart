import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/filesystem_pdf_reader.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/pdf_fixture_builder.dart';

/// See test/fixtures/pdf/README.md for how each fixture was produced.
String _fixturePath(String name) => 'test/fixtures/pdf/$name.pdf';

Future<Map<String, dynamic>> _read(
  String name, {
  int offset = 1,
  int? limit,
  int maxChars = 120000,
  int startPage = 1,
}) async {
  final raw = await FilesystemTools.readFile(
    path: _fixturePath(name),
    offset: offset,
    limit: limit,
    maxChars: maxChars,
    startPage: startPage,
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

    test('clips to max_chars without counting omitted lines', () {
      final selection = FilesystemPdfReader.selectLines(
        text: 'alpha\nbeta\ngamma',
        offset: 1,
        limit: 10,
        maxChars: 3,
      );

      expect(selection.content, 'alp');
      expect(selection.lineCount, 1);
      expect(selection.truncatedByChars, isTrue);
      expect(selection.totalLines, 3);
    });

    test('clips to max_chars and says so', () async {
      final response = await _read('text_layer', maxChars: 12);

      expect((response['content'] as String).length, lessThanOrEqualTo(12));
      expect(response['truncated_by_chars'], isTrue);
      expect(response['truncated'], isTrue);
    });

    test('start_page extracts from a later page', () async {
      final directory = Directory.systemTemp.createTempSync(
        'caverno_pdf_pages',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/pages.pdf';
      File(path).writeAsBytesSync(await buildPagedPdf(pages: 3));

      final late =
          jsonDecode(await FilesystemTools.readFile(path: path, startPage: 3))
              as Map<String, dynamic>;

      expect(late['error'], isNull);
      expect(late['start_page'], 3);
      expect(late['content'], contains('[page 3]'));
      expect(late['content'], contains('page 3 line 1'));
      expect(late['content'], isNot(contains('[page 1]')));
    });

    test('rejects start_page past the end of the document', () async {
      final response = await _read('text_layer', startPage: 2);

      expect(response['error'], contains('past the end'));
      expect(response['page_count'], 1);
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

      expect(response['error'], contains('no extractable text'));
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

  test(
    'a text file that mentions the PDF signature still reads as text',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'caverno_pdf_mention',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final notes = File('${directory.path}/notes.md')
        ..writeAsStringSync('The %PDF-1.7 signature identifies PDFs.\n');

      final response =
          jsonDecode(await FilesystemTools.readFile(path: notes.path))
              as Map<String, dynamic>;

      expect(response['error'], isNull);
      expect(response['format'], isNull);
      expect(response['content'], contains('The %PDF-1.7 signature'));
    },
  );


  group('a PDF longer than the inspect sample', () {
    late Directory workspace;
    late File file;

    setUp(() async {
      workspace = Directory.systemTemp.createTempSync('caverno_pdf_paging');
      file = File('${workspace.path}/paged.pdf')
        ..writeAsBytesSync(await buildPagedPdf(pages: 20));
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('inspect_file never passes its sample off as the total', () async {
      final inspect =
          jsonDecode(await FilesystemTools.inspectFile(path: file.path))
              as Map<String, dynamic>;
      final read = jsonDecode(await FilesystemTools.readFile(path: file.path))
          as Map<String, dynamic>;

      // Reporting the sampled line count as `total_lines` told a model
      // planning offset/limit reads that this document held 41 lines when
      // read_file returns hundreds.
      expect(inspect['total_lines'], isNull);
      expect(inspect['sampled_lines'], isA<int>());
      expect(inspect['pages_sampled'], isTrue);
      expect(inspect['page_count'], 20);
      expect(inspect['sampled_lines'], lessThan(read['total_lines'] as int));
    });

    test('inspect_file samples the last pages, not the first again', () async {
      final inspect =
          jsonDecode(await FilesystemTools.inspectFile(path: file.path))
              as Map<String, dynamic>;

      expect((inspect['head'] as List).first, '[page 1]');
      expect((inspect['tail'] as List).join('\n'), contains('page 20'));
    });

    test('read_file pages from start_page', () async {
      final second = jsonDecode(
            await FilesystemTools.readFile(path: file.path, startPage: 19),
          )
          as Map<String, dynamic>;

      expect(second['start_page'], 19);
      expect(second['content'], startsWith('[page 19]'));
      expect(second['content'], contains('page 20 line 1'));
      expect(second['page_count'], 20);
    });

    test('read_file rejects a start_page past the end', () async {
      final response = jsonDecode(
            await FilesystemTools.readFile(path: file.path, startPage: 99),
          )
          as Map<String, dynamic>;

      expect(response['error'], contains('past the end'));
      expect(response['page_count'], 20);
    });
  });

  test('inspect_file reports a real total when it sampled everything',
      () async {
    final inspect =
        jsonDecode(await FilesystemTools.inspectFile(path: _fixturePath('text_layer')))
            as Map<String, dynamic>;

    expect(inspect['total_lines'], isA<int>());
    expect(inspect['sampled_lines'], isNull);
    expect(inspect['pages_sampled'], isNull);
  });
}
