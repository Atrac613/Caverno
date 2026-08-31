import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Why a PDF could not be turned into text.
///
/// Kept as an enum rather than a message so both call sites (the composer and
/// the file tools) can phrase the same cause in their own register: the
/// composer needs a localized snackbar, the tools need English JSON the model
/// reads.
enum PdfExtractionError {
  /// Above [PdfTextExtractionService.maxBytes]. The parser works from a whole
  /// in-memory buffer, so this is a memory bound, not a policy one.
  tooLarge,

  /// Password-protected. Caverno never prompts for one; the person can decrypt
  /// the file and attach it again.
  encrypted,

  /// Parsed fine but every page came back empty — a scanned document whose
  /// pages are images. Distinguished from [malformed] because the remedy is
  /// completely different (OCR, not a repaired file).
  noTextLayer,

  /// Truncated, corrupt, or not a PDF at all.
  malformed,
}

/// The outcome of one extraction attempt.
class PdfExtractionResult {
  const PdfExtractionResult({
    this.text,
    this.pageCount = 0,
    this.extractedPages = 0,
    this.error,
  });

  const PdfExtractionResult.failure(PdfExtractionError error)
    : this(error: error);

  /// Page-marked text, or null when [error] is set.
  final String? text;

  /// Pages the document holds.
  final int pageCount;

  /// Pages actually represented in [text]. Lower than [pageCount] only when
  /// the character budget ran out part way through.
  final int extractedPages;

  final PdfExtractionError? error;

  bool get isSuccess => error == null && text != null;

  /// Whether [text] stops short of the document's last page.
  bool get truncated => isSuccess && extractedPages < pageCount;
}

/// Extracts a text layer from a PDF.
///
/// The only place in the app that knows what a PDF is. Both the chat composer
/// and the `read_file` / `inspect_file` tools go through here so a person and
/// the model see the same text for the same document.
///
/// Deliberately text-only: rendering pages to images for a vision model is a
/// different feature with a different cost, and a scanned PDF is reported as
/// [PdfExtractionError.noTextLayer] rather than silently yielding nothing.
abstract final class PdfTextExtractionService {
  /// Largest PDF we will parse.
  ///
  /// The parser takes the whole file as a byte buffer, so this bounds peak
  /// memory on a phone, where the file tools already halve their scan ceiling.
  static const int maxBytes = 32 * 1024 * 1024;

  /// Character budget for the joined text of one document.
  ///
  /// A thousand-page export would otherwise build a string far larger than any
  /// caller can use: `read_file` clips to 120k characters and the composer
  /// inlines at most 256KB. Stopping early keeps a runaway document from
  /// costing memory nobody spends.
  static const int maxTextChars = 2 * 1024 * 1024;

  /// `%PDF-`, the header every PDF starts with.
  static const List<int> _signature = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];

  /// How far into the file the header may sit.
  ///
  /// The spec says offset zero, but files that grew a mail or scanner preamble
  /// are common enough that every real reader scans a window instead.
  static const int _signatureSearchWindow = 1024;

  /// `/Encrypt`, the trailer entry a password-protected PDF carries.
  static final List<int> _encryptMarker = '/Encrypt'.codeUnits;

  /// Whether [prefix] begins a PDF.
  ///
  /// Matches the header bytes rather than the extension so a `report.bin` that
  /// is really a PDF still reads, and a text file someone renamed to `.pdf`
  /// does not get routed into the parser.
  static bool looksLikePdf(List<int> prefix) =>
      _indexOfBytes(prefix, _signature, _signatureSearchWindow) >= 0;

  /// Reads and extracts [file], or explains why it could not.
  ///
  /// Never throws: both callers need a value to render, and a malformed
  /// attachment is an ordinary outcome rather than an error condition.
  static Future<PdfExtractionResult> extract(File file) async {
    try {
      final length = await file.length();
      if (length > maxBytes) {
        return const PdfExtractionResult.failure(PdfExtractionError.tooLarge);
      }
      return extractBytes(await file.readAsBytes());
    } on FileSystemException {
      return const PdfExtractionResult.failure(PdfExtractionError.malformed);
    }
  }

  /// Extracts [bytes] on a background isolate.
  ///
  /// Parsing a few hundred pages is seconds of pure CPU. On the main isolate
  /// that would freeze the composer mid-attachment and stall the tool loop's
  /// event loop, so the work is handed off even though the payload has to be
  /// copied to get there.
  static Future<PdfExtractionResult> extractBytes(Uint8List bytes) =>
      Isolate.run(() => extractBytesSync(bytes));

  /// The synchronous core, exposed for tests that would rather not hop.
  static PdfExtractionResult extractBytesSync(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      return const PdfExtractionResult.failure(PdfExtractionError.tooLarge);
    }
    if (!looksLikePdf(bytes)) {
      return const PdfExtractionResult.failure(PdfExtractionError.malformed);
    }

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      return _extractPages(document);
    } catch (_) {
      // The parser reports a wrong password and a corrupt xref table with the
      // same exception type, so the file itself decides which one this was:
      // only an encrypted document carries an /Encrypt trailer entry.
      return PdfExtractionResult.failure(
        _hasEncryptMarker(bytes)
            ? PdfExtractionError.encrypted
            : PdfExtractionError.malformed,
      );
    } finally {
      document?.dispose();
    }
  }

  static PdfExtractionResult _extractPages(PdfDocument document) {
    final pageCount = document.pages.count;
    final extractor = PdfTextExtractor(document);
    final buffer = StringBuffer();
    var extractedPages = 0;
    var anyText = false;

    for (var index = 0; index < pageCount; index++) {
      // Page at a time rather than one whole-document call: it is what makes
      // the page markers below true, and it is where the budget can stop.
      final page = extractor
          .extractText(startPageIndex: index, endPageIndex: index)
          .trimRight();
      if (page.trim().isNotEmpty) anyText = true;

      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('[page ${index + 1}]');
      if (page.isNotEmpty) buffer.writeln(page);
      extractedPages++;

      if (buffer.length >= maxTextChars) break;
    }

    if (!anyText) {
      return const PdfExtractionResult.failure(PdfExtractionError.noTextLayer);
    }
    return PdfExtractionResult(
      text: buffer.toString().trimRight(),
      pageCount: pageCount,
      extractedPages: extractedPages,
    );
  }

  static bool _hasEncryptMarker(List<int> bytes) =>
      _indexOfBytes(bytes, _encryptMarker, bytes.length) >= 0;

  /// First index of [needle] in [haystack], searching at most [searchLimit]
  /// starting positions. Hand-rolled because the payload is bytes, not a
  /// string, and decoding a binary file to search it would defeat the point.
  static int _indexOfBytes(
    List<int> haystack,
    List<int> needle,
    int searchLimit,
  ) {
    final last = (searchLimit < haystack.length ? searchLimit : haystack.length)
        .clamp(0, haystack.length);
    for (var start = 0; start + needle.length <= last; start++) {
      var matched = true;
      for (var offset = 0; offset < needle.length; offset++) {
        if (haystack[start + offset] != needle[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) return start;
    }
    return -1;
  }
}
