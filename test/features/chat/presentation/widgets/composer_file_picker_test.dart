import 'dart:io';
import 'dart:ui';

import 'package:caverno/features/chat/presentation/widgets/composer_file_picker.dart';
import 'package:caverno/features/chat/presentation/widgets/composer_file_submission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// See test/fixtures/pdf/README.md for how each fixture was produced.
String _fixturePath(String name) => 'test/fixtures/pdf/$name.pdf';

void main() {
  const picker = ComposerFilePicker();
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('caverno_composer_file');
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  /// Runs the picker's policy without the durable copy, which needs a platform
  /// directory this test has no business standing up.
  Future<ComposerFileChoice> prepare(File file) async => picker.prepare(
    sourcePath: file.path,
    originalName: file.uri.pathSegments.last,
    sizeBytes: file.lengthSync(),
    alreadyDurable: true,
  );

  group('acceptsPath', () {
    test('takes the text formats and PDF', () {
      expect(ComposerFilePicker.acceptsPath('/tmp/notes.md'), isTrue);
      expect(ComposerFilePicker.acceptsPath('/tmp/export.CSV'), isTrue);
      expect(ComposerFilePicker.acceptsPath('/tmp/report.pdf'), isTrue);
    });

    test('takes a PDF MIME type even without an extension', () {
      expect(ComposerFilePicker.acceptsMime('application/pdf'), isTrue);
      expect(
        ComposerFilePicker.acceptsMime('text/plain; charset=utf-8'),
        isTrue,
      );
      expect(ComposerFilePicker.acceptsMime('image/png'), isFalse);
    });

    test('refuses everything else', () {
      expect(ComposerFilePicker.acceptsPath('/tmp/photo.png'), isFalse);
      expect(ComposerFilePicker.acceptsPath('/tmp/archive.zip'), isFalse);
      expect(ComposerFilePicker.acceptsPath('/tmp/noextension'), isFalse);
    });
  });

  group('text files', () {
    test('inlines a small one', () async {
      final file = File('${workspace.path}/notes.txt')
        ..writeAsStringSync('alpha\nbeta');

      final choice = await prepare(file);

      expect(choice.notice, isNull);
      expect(choice.file!.content, 'alpha\nbeta');
      expect(choice.file!.isPathReference, isFalse);
      expect(choice.file!.pdfPageCount, isNull);
    });

    test('references a large one by path', () async {
      final file = File('${workspace.path}/big.log')
        ..writeAsStringSync('x' * (ComposerFilePicker.inlineMaxBytes + 1));

      final choice = await prepare(file);

      expect(choice.file!.isPathReference, isTrue);
      expect(choice.file!.content, isNull);
      expect(choice.file!.durablePath, file.path);
    });

    test('reports a file that is not valid UTF-8', () async {
      final file = File('${workspace.path}/blob.txt')
        ..writeAsBytesSync(<int>[0xC3, 0x28, 0xA0]);

      final choice = await prepare(file);

      expect(choice.file, isNull);
      expect(choice.noticeKey, 'message.file_read_error');
    });
  });

  group('PDFs', () {
    test('inlines the extracted text and records the page count', () async {
      final choice = await prepare(File(_fixturePath('text_layer')));

      expect(choice.notice, isNull);
      expect(choice.file!.pdfPageCount, 1);
      expect(choice.file!.isPathReference, isFalse);
      expect(choice.file!.content, contains('Caverno PDF fixture'));
      expect(
        choice.file!.sizeBytes,
        File(_fixturePath('text_layer')).lengthSync(),
      );
    });

    test('recognises one whose bytes look like text', () async {
      final choice = await prepare(File(_fixturePath('ascii_uncompressed')));

      expect(choice.file!.pdfPageCount, 1);
      expect(choice.file!.content, contains('Plain ASCII fixture body'));
      expect(choice.file!.content, isNot(contains('endobj')));
    });

    test('names OCR for a scanned document and attaches nothing', () async {
      final choice = await prepare(File(_fixturePath('image_only')));

      expect(choice.file, isNull);
      expect(choice.noticeKey, 'message.pdf_no_text_layer');
    });

    test('reports a password-protected document', () async {
      final choice = await prepare(File(_fixturePath('encrypted')));

      expect(choice.file, isNull);
      expect(choice.noticeKey, 'message.pdf_encrypted');
    });

    test('refuses a PDF above the extractor memory bound', () async {
      final choice = await picker.prepare(
        sourcePath: _fixturePath('text_layer'),
        originalName: 'huge.pdf',
        sizeBytes: 33 * 1024 * 1024,
        alreadyDurable: true,
      );

      expect(choice.file, isNull);
      expect(choice.noticeKey, 'message.pdf_too_large');
    });

    test('reports a corrupt document', () async {
      final source = File(_fixturePath('text_layer')).readAsBytesSync();
      final file = File('${workspace.path}/truncated.pdf')
        ..writeAsBytesSync(source.sublist(0, 400));

      final choice = await prepare(file);

      expect(choice.file, isNull);
      expect(choice.noticeKey, 'message.pdf_read_error');
    });

    test('references one by path when its text will not fit inline', () async {
      final file = File('${workspace.path}/long.pdf')
        ..writeAsBytesSync(await _buildWordyPdf(pages: 200));

      final choice = await prepare(file);

      expect(choice.file!.isPathReference, isTrue);
      expect(choice.file!.content, isNull);
      // The advice in the message body has to say read_file, and it reads
      // this flag rather than the extension.
      expect(choice.file!.isPdf, isTrue);
    });
  });

  group('composeMessageBlock', () {
    test('labels an inlined text file', () {
      const file = ComposerFileAttachment(
        name: 'notes.txt',
        sizeBytes: 10,
        content: 'alpha',
      );

      expect(
        ComposerFilePicker.composeMessageBlock(file),
        '[File: notes.txt]\nalpha',
      );
    });

    test('labels an inlined PDF with its page count', () {
      const file = ComposerFileAttachment(
        name: 'report.pdf',
        sizeBytes: 2048,
        content: '[page 1]\nbody',
        pdfPageCount: 3,
      );

      expect(
        ComposerFilePicker.composeMessageBlock(file),
        '[File: report.pdf (PDF, 3 pages)]\n[page 1]\nbody',
      );
    });

    test('points a large PDF at read_file, never search_files', () {
      const file = ComposerFileAttachment(
        name: 'huge.pdf',
        sizeBytes: 40 * 1024 * 1024,
        durablePath: '/attachments/huge.pdf',
        isPdf: true,
      );

      final block = ComposerFilePicker.composeMessageBlock(file);

      expect(block, startsWith('[Attached file: /attachments/huge.pdf'));
      expect(block, contains('PDF'));
      expect(block, contains('read_file'));
      expect(block, contains('inspect_file'));
      expect(block, isNot(contains('search_files')));
    });

    test('keeps the original wording for a large text file', () {
      const file = ComposerFileAttachment(
        name: 'huge.log',
        sizeBytes: 1024 * 1024,
        durablePath: '/attachments/huge.log',
      );

      final block = ComposerFilePicker.composeMessageBlock(file);

      expect(block, startsWith('[Attached file: /attachments/huge.log'));
      expect(block, contains('search_files'));
    });

    test('keeps PDF text out of the visible attachment summary', () {
      const file = ComposerFileAttachment(
        name: 'report.pdf',
        sizeBytes: 2048,
        content: '[page 1]\nprivate body',
        isPdf: true,
        pdfPageCount: 3,
      );

      expect(
        ComposerFileSubmission.compose(file: file, userText: '').visibleContent,
        '[File: report.pdf (PDF, 3 pages, 2.0 KB)]',
      );
      expect(
        ComposerFileSubmission.compose(file: file, userText: '').visibleContent,
        isNot(contains('private body')),
      );

      final submission = ComposerFileSubmission.compose(
        file: file,
        userText: 'Summarize it.',
      );
      // The person's words lead the bubble, and the conversation title is
      // taken from the head of this string.
      expect(
        submission.visibleContent,
        'Summarize it.\n\n[File: report.pdf (PDF, 3 pages, 2.0 KB)]',
      );
      expect(submission.visibleContent, isNot(contains('private body')));
      // The model still reads the document before the instruction.
      expect(submission.modelContent, contains('[page 1]\nprivate body'));
      expect(submission.modelContent, endsWith('\n\nSummarize it.'));
    });

    test('an attachment with no question is just the header', () {
      const file = ComposerFileAttachment(
        name: 'notes.txt',
        sizeBytes: 12,
        content: 'alpha',
      );

      final submission = ComposerFileSubmission.compose(
        file: file,
        userText: '',
      );

      expect(submission.visibleContent, '[File: notes.txt (12 B)]');
    });
  });
}

/// Builds a PDF whose extracted text exceeds the inline budget.
///
/// Written here rather than checked in: the fixture would be a few hundred
/// kilobytes of filler, and what it exercises is the size policy, not the
/// parser.
Future<List<int>> _buildWordyPdf({required int pages}) async {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.courier, 9);
  final paragraph = List<String>.filled(
    100,
    'lorem ipsum dolor sit amet',
  ).join(' ');
  for (var page = 0; page < pages; page++) {
    document.pages.add().graphics.drawString(
      paragraph,
      font,
      bounds: const Rect.fromLTWH(20, 20, 560, 740),
    );
  }
  final bytes = await document.save();
  document.dispose();
  return bytes;
}
