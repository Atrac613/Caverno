import 'dart:io';
import 'dart:typed_data';

import 'package:caverno/core/services/pdf_text_extraction_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pdf_fixture_builder.dart';

/// Fixtures are checked in rather than generated: see
/// test/fixtures/pdf/README.md for how each one was produced and why two of
/// the three deliberately come from outside this package.
File _fixture(String name) => File('test/fixtures/pdf/$name.pdf');

void main() {
  group('looksLikePdf', () {
    test('accepts a real PDF header', () {
      final bytes = _fixture('text_layer').readAsBytesSync();
      expect(PdfTextExtractionService.looksLikePdf(bytes), isTrue);
    });

    test('accepts a header behind a preamble', () {
      final bytes = Uint8List.fromList(<int>[
        ...List<int>.filled(64, 0x20),
        ...'%PDF-1.7'.codeUnits,
      ]);
      expect(PdfTextExtractionService.looksLikePdf(bytes), isTrue);
    });

    test('rejects a header mentioned in a text preamble', () {
      expect(
        PdfTextExtractionService.looksLikePdf(
          'The %PDF-1.7 signature identifies PDFs'.codeUnits,
        ),
        isFalse,
      );
    });

    test('rejects a header without a version digit', () {
      expect(PdfTextExtractionService.looksLikePdf('%PDF-'.codeUnits), isFalse);
    });

    test('rejects a header past the search window', () {
      final bytes = Uint8List.fromList(<int>[
        ...List<int>.filled(2048, 0x20),
        ...'%PDF-1.7'.codeUnits,
      ]);
      expect(PdfTextExtractionService.looksLikePdf(bytes), isFalse);
    });
  });

  group('extract', () {
    test('returns page-marked text for a PDF with a text layer', () async {
      final result = await PdfTextExtractionService.extract(
        _fixture('text_layer'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.error, isNull);
      expect(result.pageCount, 1);
      expect(result.extractedPages, 1);
      expect(result.truncated, isFalse);
      expect(result.text, startsWith('[page 1]'));
      expect(result.text, contains('Caverno PDF fixture'));
      expect(result.text, contains('quick brown fox'));
    });

    test('reports a scanned document as noTextLayer', () async {
      final result = await PdfTextExtractionService.extract(
        _fixture('image_only'),
      );

      expect(result.error, PdfExtractionError.noTextLayer);
      expect(result.text, isNull);
      expect(result.isSuccess, isFalse);
    });

    test('caps a page that exceeds the character budget', () {
      final bytes = _fixture('text_layer').readAsBytesSync();

      final result = PdfTextExtractionService.extractBytesSync(
        Uint8List.fromList(bytes),
        maxTextChars: 24,
      );

      expect(result.isSuccess, isTrue);
      expect(result.truncated, isTrue);
      expect(result.textTruncated, isTrue);
      expect(result.text!.length, lessThanOrEqualTo(24));
    });

    test('reports a password-protected document as encrypted', () async {
      final result = await PdfTextExtractionService.extract(
        _fixture('encrypted'),
      );

      expect(result.error, PdfExtractionError.encrypted);
    });

    test('reports a truncated PDF as malformed, not encrypted', () async {
      final bytes = _fixture('text_layer').readAsBytesSync();

      final result = await PdfTextExtractionService.extractBytes(
        Uint8List.sublistView(bytes, 0, 400),
      );

      expect(result.error, PdfExtractionError.malformed);
    });

    test('reports non-PDF bytes as malformed', () async {
      final result = await PdfTextExtractionService.extractBytes(
        Uint8List.fromList('not a document at all'.codeUnits),
      );

      expect(result.error, PdfExtractionError.malformed);
    });

    test('reports a missing file as malformed', () async {
      final result = await PdfTextExtractionService.extract(
        File('test/fixtures/pdf/does_not_exist.pdf'),
      );

      expect(result.error, PdfExtractionError.malformed);
    });

    test('refuses a file above the memory bound before reading it', () async {
      final directory = Directory.systemTemp.createTempSync('caverno_pdf');
      addTearDown(() => directory.deleteSync(recursive: true));
      final oversized = File('${directory.path}/big.pdf')
        ..writeAsBytesSync(
          Uint8List(PdfTextExtractionService.maxBytes + 1),
          flush: true,
        );

      final result = await PdfTextExtractionService.extract(oversized);

      expect(result.error, PdfExtractionError.tooLarge);
    });
  });

  group('page windows', () {
    test('leaves out a page that does not fit and points next_page at it',
        () async {
      final bytes = await buildPagedPdf(pages: 4);
      final whole = PdfTextExtractionService.extractBytesSync(bytes);
      final wholeLength = whole.text!.length;

      // A budget that fits the first pages but not the last one.
      final result = PdfTextExtractionService.extractBytesSync(
        bytes,
        maxTextChars: wholeLength - 20,
      );

      expect(result.isSuccess, isTrue);
      expect(result.truncated, isTrue);
      expect(result.textTruncated, isFalse, reason: 'no page was cut in half');
      expect(result.extractedPages, lessThan(4));
      // The dropped page is the one to continue from: counting it as
      // extracted made the advertised continuation skip its text entirely.
      expect(result.nextPage, result.extractedPages + 1);
      expect(result.text, contains('[page ${result.extractedPages}]'));
      expect(result.text, isNot(contains('[page ${result.nextPage}]')));
    });

    test('continuing from next_page loses nothing', () async {
      final bytes = await buildPagedPdf(pages: 4);
      final whole = PdfTextExtractionService.extractBytesSync(bytes);
      final first = PdfTextExtractionService.extractBytesSync(
        bytes,
        maxTextChars: whole.text!.length - 20,
      );

      final rest = PdfTextExtractionService.extractBytesSync(
        bytes,
        startPageIndex: first.nextPage - 1,
      );

      for (var page = 1; page <= 4; page++) {
        final marker = '[page $page]';
        expect(
          first.text!.contains(marker) || rest.text!.contains(marker),
          isTrue,
          reason: 'page $page fell between the two windows',
        );
      }
      expect(rest.text, contains('page 4 line 1'));
    });

    test('cuts the first page only when nothing else can be dropped',
        () async {
      final bytes = await buildPagedPdf(pages: 2);

      final result = PdfTextExtractionService.extractBytesSync(
        bytes,
        maxTextChars: 40,
      );

      expect(result.isSuccess, isTrue);
      expect(result.extractedPages, 1);
      expect(result.textTruncated, isTrue);
      expect(result.text, startsWith('[page 1]'));
    });

    test('maxPages bounds the window', () async {
      final bytes = await buildPagedPdf(pages: 5);

      final result = PdfTextExtractionService.extractBytesSync(
        bytes,
        startPageIndex: 1,
        maxPages: 2,
      );

      expect(result.pageCount, 5);
      expect(result.extractedPages, 2);
      expect(result.startPageIndex, 1);
      expect(result.text, contains('[page 2]'));
      expect(result.text, contains('[page 3]'));
      expect(result.text, isNot(contains('[page 4]')));
      expect(result.nextPage, 4);
    });
  });

  group('extractWindowsBytes', () {
    test('returns head and tail from one parse', () async {
      final bytes = await buildPagedPdf(pages: 8);

      final windows = await PdfTextExtractionService.extractWindowsBytes(
        bytes,
        const [
          PdfPageWindow(maxPages: 3),
          PdfPageWindow(maxPages: 2, fromEnd: true),
        ],
      );

      expect(windows, hasLength(2));
      expect(windows.first.text, startsWith('[page 1]'));
      expect(windows.first.extractedPages, 3);
      expect(windows.last.startPageIndex, 6);
      expect(windows.last.text, contains('[page 7]'));
      expect(windows.last.text, contains('[page 8]'));
    });

    test('reports the same failure for every window', () async {
      final windows = await PdfTextExtractionService.extractWindowsBytes(
        Uint8List.fromList('not a pdf'.codeUnits),
        const [PdfPageWindow(), PdfPageWindow(fromEnd: true)],
      );

      expect(
        windows.map((window) => window.error),
        everyElement(PdfExtractionError.malformed),
      );
    });
  });
}
