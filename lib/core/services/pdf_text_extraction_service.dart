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

  /// Parsed fine but every page came back empty. May be a scan, a vector-only
  /// drawing, or a blank document — distinguished from [malformed] because
  /// retrying with a repaired file will not help.
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
    this.startPageIndex = 0,
    this.textTruncated = false,
    this.error,
  });

  const PdfExtractionResult.failure(PdfExtractionError error)
    : this(error: error);

  /// Page-marked text, or null when [error] is set.
  final String? text;

  /// Pages the document holds.
  final int pageCount;

  /// Pages actually represented in [text], counting from [startPageIndex].
  final int extractedPages;

  /// 0-based page where this extraction began.
  final int startPageIndex;

  /// Whether the last included page was cut to fit
  /// [PdfTextExtractionService.maxTextChars].
  ///
  /// Only ever true when that page is the first of the window: a later page
  /// that does not fit is left out whole, so [nextPage] can point at it.
  final bool textTruncated;

  final PdfExtractionError? error;

  bool get isSuccess => error == null && text != null;

  /// 1-based page to pass as `start_page` to continue a windowed read.
  ///
  /// Points at the first page this window did not deliver in full. A page cut
  /// by the character budget is not counted as delivered unless it was the
  /// only page in the window, in which case continuing past it is the only way
  /// to make progress and [textTruncated] says its tail was dropped.
  int get nextPage => startPageIndex + extractedPages + 1;

  /// Whether [text] stops short of the document's last page, or a page was cut.
  bool get truncated =>
      isSuccess &&
      (textTruncated || startPageIndex + extractedPages < pageCount);
}

/// Extracts a text layer from a PDF.
///
/// The only place in the app that knows what a PDF is. Both the chat composer
/// and the `read_file` / `inspect_file` tools go through here so a person and
/// the model see the same text for the same document.
///
/// Deliberately text-only: rendering pages to images for a vision model is a
/// different feature with a different cost, and a document with no characters
/// is reported as [PdfExtractionError.noTextLayer] rather than silently
/// yielding nothing.
abstract final class PdfTextExtractionService {
  /// Largest PDF we will parse.
  ///
  /// The parser takes the whole file as a byte buffer, so this bounds peak
  /// memory on a phone, where the file tools already halve their scan ceiling.
  static const int maxBytes = 32 * 1024 * 1024;

  /// Character budget for the joined text of one extraction window.
  ///
  /// A thousand-page export would otherwise build a string far larger than any
  /// caller can use: `read_file` clips to 120k characters and the composer
  /// inlines at most 256KB. Stopping early keeps a runaway document from
  /// costing memory nobody spends. Callers that need later pages pass
  /// [startPageIndex] (or `start_page` on `read_file`).
  static const int maxTextChars = 2 * 1024 * 1024;

  /// `%PDF-`, the header every PDF starts with.
  static const List<int> _signature = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];

  /// How far into the file the header may sit.
  ///
  /// The spec says offset zero, but files that grew a scanner or NUL preamble
  /// are common enough that every real reader scans a window instead.
  /// Printable text before the header is rejected: that is a document talking
  /// about PDFs, not a PDF.
  static const int _signatureSearchWindow = 1024;

  /// `/Encrypt`, the trailer dictionary key a password-protected PDF carries.
  static final List<int> _encryptMarker = '/Encrypt'.codeUnits;

  static final List<int> _trailerMarker = 'trailer'.codeUnits;

  /// Trailer sits near EOF. Searching the whole file would treat `/Encrypt`
  /// inside a content stream as encryption.
  static const int _encryptSearchTailBytes = 32 * 1024;

  /// Whether [prefix] begins a PDF.
  ///
  /// Matches `%PDF-` plus a version digit rather than the extension so a
  /// `report.bin` that is really a PDF still reads, and a text file someone
  /// renamed to `.pdf` does not get routed into the parser. A README that
  /// mentions the signature is not a PDF: printable bytes before the header
  /// fail the check.
  static bool looksLikePdf(List<int> prefix) {
    final index = _indexOfBytes(prefix, _signature, _signatureSearchWindow);
    if (index < 0) return false;
    final versionAt = index + _signature.length;
    if (versionAt >= prefix.length) return false;
    final version = prefix[versionAt];
    if (version < 0x30 || version > 0x39) return false;
    for (var i = 0; i < index; i++) {
      // Control bytes, spaces and DEL may precede the header; anything a
      // reader would see as text means this is a document about PDFs.
      final byte = prefix[i];
      if (byte > 0x20 && byte != 0x7F) return false;
    }
    return true;
  }

  /// Reads and extracts [file], or explains why it could not.
  ///
  /// Never throws: both callers need a value to render, and a malformed
  /// attachment is an ordinary outcome rather than an error condition.
  static Future<PdfExtractionResult> extract(
    File file, {
    int startPageIndex = 0,
    int? maxPages,
    int? maxTextChars,
  }) async {
    try {
      final length = await file.length();
      if (length > maxBytes) {
        return const PdfExtractionResult.failure(PdfExtractionError.tooLarge);
      }
      return extractBytes(
        await file.readAsBytes(),
        startPageIndex: startPageIndex,
        maxPages: maxPages,
        maxTextChars: maxTextChars,
      );
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
  static Future<PdfExtractionResult> extractBytes(
    Uint8List bytes, {
    int startPageIndex = 0,
    int? maxPages,
    int? maxTextChars,
  }) => Isolate.run(
    () => extractBytesSync(
      bytes,
      startPageIndex: startPageIndex,
      maxPages: maxPages,
      maxTextChars: maxTextChars,
    ),
  );

  /// Extracts several page windows from one buffer in a single isolate.
  ///
  /// `inspect_file` wants the first pages and the last pages of the same
  /// document. Two [extractBytes] calls would copy the whole file to two
  /// isolates and parse it twice; this copies and parses once.
  static Future<List<PdfExtractionResult>> extractWindowsBytes(
    Uint8List bytes,
    List<PdfPageWindow> windows,
  ) => Isolate.run(() => extractWindowsBytesSync(bytes, windows));

  /// The synchronous core of [extractWindowsBytes].
  static List<PdfExtractionResult> extractWindowsBytesSync(
    Uint8List bytes,
    List<PdfPageWindow> windows,
  ) {
    if (bytes.length > maxBytes) {
      return List<PdfExtractionResult>.filled(
        windows.length,
        const PdfExtractionResult.failure(PdfExtractionError.tooLarge),
      );
    }
    if (!looksLikePdf(bytes)) {
      return List<PdfExtractionResult>.filled(
        windows.length,
        const PdfExtractionResult.failure(PdfExtractionError.malformed),
      );
    }

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final opened = document;
      final pageCount = opened.pages.count;
      return windows
          .map(
            (window) => _extractPages(
              opened,
              startPageIndex: window.resolveStart(pageCount),
              maxPages: window.maxPages,
              maxTextChars: window.maxTextChars ?? maxTextChars,
            ),
          )
          .toList();
    } catch (_) {
      final failure = PdfExtractionResult.failure(
        _hasEncryptMarker(bytes)
            ? PdfExtractionError.encrypted
            : PdfExtractionError.malformed,
      );
      return List<PdfExtractionResult>.filled(windows.length, failure);
    } finally {
      document?.dispose();
    }
  }

  /// The synchronous core, exposed for tests that would rather not hop.
  static PdfExtractionResult extractBytesSync(
    Uint8List bytes, {
    int startPageIndex = 0,
    int? maxPages,
    int? maxTextChars,
  }) {
    if (bytes.length > maxBytes) {
      return const PdfExtractionResult.failure(PdfExtractionError.tooLarge);
    }
    if (!looksLikePdf(bytes)) {
      return const PdfExtractionResult.failure(PdfExtractionError.malformed);
    }

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      return _extractPages(
        document,
        startPageIndex: startPageIndex,
        maxPages: maxPages,
        maxTextChars: maxTextChars ?? PdfTextExtractionService.maxTextChars,
      );
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

  static PdfExtractionResult _extractPages(
    PdfDocument document, {
    required int startPageIndex,
    required int? maxPages,
    required int maxTextChars,
  }) {
    final pageCount = document.pages.count;
    if (pageCount <= 0) {
      return const PdfExtractionResult.failure(PdfExtractionError.noTextLayer);
    }
    if (startPageIndex < 0 || startPageIndex >= pageCount) {
      return PdfExtractionResult(
        text: '',
        pageCount: pageCount,
        extractedPages: 0,
        startPageIndex: startPageIndex.clamp(0, pageCount),
      );
    }

    final extractor = PdfTextExtractor(document);
    final buffer = StringBuffer();
    var extractedPages = 0;
    var anyText = false;
    var textTruncated = false;
    final lastExclusive = maxPages == null
        ? pageCount
        : (startPageIndex + maxPages).clamp(startPageIndex, pageCount);

    for (var index = startPageIndex; index < lastExclusive; index++) {
      // Page at a time rather than one whole-document call: it is what makes
      // the page markers below true, and it is where the budget can stop.
      final page = extractor
          .extractText(startPageIndex: index, endPageIndex: index)
          .trimRight();
      if (page.trim().isNotEmpty) anyText = true;

      final marker = '[page ${index + 1}]';
      final separator = buffer.isEmpty ? 0 : 1;
      // Room for this page's body: the budget less what is written, the
      // separating newline, the marker, and the newline after it.
      final remaining =
          maxTextChars - buffer.length - separator - marker.length - 1;

      if (page.length > remaining) {
        // A page that does not fit is left out entirely so [nextPage] points
        // at it and the caller can read it whole. Cutting it here and still
        // counting it -- what the first version did -- made the advertised
        // `start_page = next_page` continuation skip the rest of the page.
        if (extractedPages > 0) break;
        // Unless it is the first page of the window: there is no smaller
        // window to fall back to, so emit what fits and say it was cut.
        if (remaining <= 0) break;
        textTruncated = true;
      }

      final body = textTruncated ? page.substring(0, remaining) : page;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln(marker);
      if (body.isNotEmpty) buffer.writeln(body);
      extractedPages++;

      if (textTruncated) break;
    }

    if (!anyText) {
      return const PdfExtractionResult.failure(PdfExtractionError.noTextLayer);
    }
    return PdfExtractionResult(
      text: buffer.toString().trimRight(),
      pageCount: pageCount,
      extractedPages: extractedPages,
      startPageIndex: startPageIndex,
      textTruncated: textTruncated,
    );
  }

  static bool _hasEncryptMarker(List<int> bytes) {
    final tailStart = bytes.length > _encryptSearchTailBytes
        ? bytes.length - _encryptSearchTailBytes
        : 0;
    final tailLength = bytes.length - tailStart;
    final trailerAt = _lastIndexOfBytes(
      bytes,
      _trailerMarker,
      start: tailStart,
      length: tailLength,
    );
    if (trailerAt >= 0) {
      return _indexOfBytes(
            bytes.sublist(trailerAt),
            _encryptMarker,
            bytes.length - trailerAt,
          ) >=
          0;
    }
    return _indexOfBytes(
          bytes.sublist(tailStart),
          _encryptMarker,
          tailLength,
        ) >=
        0;
  }

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
      if (_matchAt(haystack, needle, start)) return start;
    }
    return -1;
  }

  static int _lastIndexOfBytes(
    List<int> haystack,
    List<int> needle, {
    required int start,
    required int length,
  }) {
    final end = (start + length).clamp(0, haystack.length);
    for (var i = end - needle.length; i >= start; i--) {
      if (_matchAt(haystack, needle, i)) return i;
    }
    return -1;
  }

  static bool _matchAt(List<int> haystack, List<int> needle, int start) {
    for (var offset = 0; offset < needle.length; offset++) {
      if (haystack[start + offset] != needle[offset]) return false;
    }
    return true;
  }
}

/// One page range to pull out of a document.
class PdfPageWindow {
  const PdfPageWindow({
    this.startPageIndex = 0,
    this.maxPages,
    this.maxTextChars,
    this.fromEnd = false,
  });

  /// 0-based first page, or ignored when [fromEnd] is set.
  final int startPageIndex;

  final int? maxPages;
  final int? maxTextChars;

  /// Whether the window is the document's last [maxPages] pages.
  ///
  /// A caller outside the isolate does not know the page count yet, so the
  /// alternative is a second parse just to find out where the tail begins.
  final bool fromEnd;

  /// Where this window starts once [pageCount] is known.
  int resolveStart(int pageCount) {
    if (!fromEnd) return startPageIndex;
    final pages = maxPages ?? pageCount;
    final start = pageCount - pages;
    return start < 0 ? 0 : start;
  }
}
