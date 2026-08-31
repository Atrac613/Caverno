import 'dart:io';
import 'dart:typed_data';

import 'package:caverno/core/services/pdf_text_extraction_service.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('rejects text that merely has a .pdf name', () {
      expect(
        PdfTextExtractionService.looksLikePdf('hello, world'.codeUnits),
        isFalse,
      );
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
}
