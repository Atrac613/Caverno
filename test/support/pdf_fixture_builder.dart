import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Builds a multi-page PDF in memory for tests about paging and sampling.
///
/// The checked-in fixtures under test/fixtures/pdf are single-page and come
/// from outside this package on purpose; a document long enough to exercise
/// windows would be a few hundred kilobytes of filler, and what it tests is
/// our own size and page policy rather than the parser.
Future<Uint8List> buildPagedPdf({
  required int pages,
  int linesPerPage = 12,
}) async {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.courier, 10);
  for (var page = 0; page < pages; page++) {
    document.pages.add().graphics.drawString(
      List<String>.generate(
        linesPerPage,
        (line) => 'page ${page + 1} line ${line + 1}',
      ).join('\n'),
      font,
      bounds: const Rect.fromLTWH(20, 20, 560, 740),
    );
  }
  final bytes = await document.save();
  document.dispose();
  return Uint8List.fromList(bytes);
}
