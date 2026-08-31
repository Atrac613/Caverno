import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';

import '../../../../core/services/pdf_text_extraction_service.dart';
import 'filesystem_overview_format.dart';
import 'first_party_tool_execution_result.dart';

/// The PDF branch of `read_file` and `inspect_file`.
///
/// Both tools classify their input as binary before doing anything else and
/// stop there. A PDF reaches this class from inside that branch and gets a
/// second chance: parsed for its text layer, it answers in the same shape a
/// text file would, so `offset` / `limit` / `max_chars` keep working and the
/// model needs no new tool to read one.
///
/// Every entry point returns null for a file that is not a PDF, which leaves
/// the callers' original "binary files are not supported" error in place.
abstract final class FilesystemPdfReader {
  /// Same ceiling the text `read_file` path uses: a hash that needs the whole
  /// file in memory is skipped above it. The PDF path already holds [bytes],
  /// so this is "do not publish a hash", not "do not re-read".
  static const int maxContentHashBytes = 8 * 1024 * 1024;

  /// Pages `inspect_file` extracts from each end. Enough to fill the head/tail
  /// line samples without parsing a thousand-page middle.
  static const int _inspectHeadPages = 3;
  static const int _inspectTailPages = 2;

  /// How much more text than one response carries the extractor may build.
  ///
  /// `offset` pages *within* an extraction window, so the window has to hold
  /// more than the window's first `max_chars`. Eight times leaves room for a
  /// deep offset while cutting the extractor's default budget by half on a
  /// default read, instead of building two megabytes and discarding 94% of it.
  static const int _extractionBudgetFactor = 8;

  static int _extractionBudget(int maxChars) => (maxChars *
          _extractionBudgetFactor)
      .clamp(maxChars, PdfTextExtractionService.maxTextChars);

  /// `read_file` over a PDF's text layer, or null when [file] is not one.
  ///
  /// [prefix] is the sample the caller already sniffed to classify the file's
  /// encoding, reused here so deciding "PDF?" costs no extra read. The header
  /// is checked before the caller's binary verdict on purpose: an uncompressed
  /// PDF is entirely printable ASCII, so a text classifier passes it and the
  /// tool would otherwise stream the raw `%PDF` syntax back to the model.
  static Future<FirstPartyToolExecutionResult?> readFileResult({
    required File file,
    required String absolutePath,
    required List<int> prefix,
    required int offset,
    required int? limit,
    required int maxChars,
    int startPage = 1,
  }) async {
    if (!PdfTextExtractionService.looksLikePdf(prefix)) return null;
    if (startPage < 1) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error': 'start_page must be greater than or equal to 1',
          'path': absolutePath,
        }),
      );
    }

    final loaded = await _readBounded(file, absolutePath);
    if (loaded.readError case final error?) {
      return FirstPartyToolExecutionResult.payloadOnly(error);
    }
    final bytes = loaded.bytes!;

    final extraction = await PdfTextExtractionService.extractBytes(
      bytes,
      startPageIndex: startPage - 1,
      maxTextChars: _extractionBudget(maxChars),
    );
    if (!extraction.isSuccess) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error': describeError(extraction.error!),
          'path': absolutePath,
        }),
      );
    }
    if (startPage > extraction.pageCount) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error': 'start_page is past the end of the document.',
          'path': absolutePath,
          'page_count': extraction.pageCount,
        }),
      );
    }

    final sizeBytes = bytes.length;
    final selection = selectLines(
      text: extraction.text!,
      offset: offset,
      limit: limit,
      maxChars: maxChars,
    );
    // Hashes the raw PDF, not the extracted text: the question this answers is
    // "is this the same file I read before", and two documents can render the
    // same characters. Uses the buffer we already hold so a concurrent rewrite
    // cannot pair text from A with a hash of B.
    final contentHash = _contentHash(bytes);

    final response = <String, dynamic>{
      'path': absolutePath,
      'content': selection.content,
      'content_hash': ?contentHash,
      'size_bytes': sizeBytes,
      'format': 'pdf',
      'page_count': extraction.pageCount,
      'start_page': startPage,
      'start_line': selection.startLine,
      'line_count': selection.lineCount,
      'total_lines': selection.totalLines,
      if (offset > 1) 'offset': offset,
      'limit': ?limit,
      if (selection.truncatedByChars ||
          selection.truncatedByLimit ||
          extraction.truncated)
        'truncated': true,
      if (selection.truncatedByChars) 'truncated_by_chars': true,
      if (selection.truncatedByLimit) 'truncated_by_limit': true,
      // total_lines counts the extraction window, which is the whole document
      // unless paging cut it short. Say so rather than let a windowed count
      // read like the file total the text path reports.
      if (extraction.truncated) 'total_lines_is_estimate': true,
      if (extraction.truncated) 'pages_truncated': true,
      if (extraction.truncated) 'pages_extracted': extraction.extractedPages,
      if (extraction.truncated) 'next_page': extraction.nextPage,
    };

    return FirstPartyToolExecutionResult(
      result: jsonEncode(response),
      outcome: contentHash == null
          ? null
          : ToolOutcome(
              readOutcome: ToolReadOutcome(
                path: absolutePath,
                contentHash: contentHash,
                byteSize: sizeBytes,
                lineCount: selection.totalLines,
              ),
            ),
    );
  }

  /// `inspect_file` over a PDF, or null when [file] is not one.
  ///
  /// Deliberately omits `is_binary` instead of answering it: a PDF is a binary
  /// container whose text is readable, and either value alone would send the
  /// model the wrong way. `format_hint` and `page_count` say what it needs.
  ///
  /// Samples the first and last pages rather than extracting the whole
  /// document, so the call stays an overview even on a long export.
  static Future<String?> inspectFile({
    required File file,
    required String absolutePath,
    required List<int> prefix,
    required int headLimit,
    required int tailLimit,
  }) async {
    if (!PdfTextExtractionService.looksLikePdf(prefix)) return null;

    final loaded = await _readBounded(file, absolutePath);
    if (loaded.inspectError case final error?) return error;
    final bytes = loaded.bytes!;
    final sizeBytes = bytes.length;

    // Both windows come out of one isolate run so a 30 MB document is copied
    // and parsed once rather than twice for five sampled pages.
    final windows = await PdfTextExtractionService.extractWindowsBytes(bytes, [
      const PdfPageWindow(maxPages: _inspectHeadPages),
      const PdfPageWindow(maxPages: _inspectTailPages, fromEnd: true),
    ]);
    final head = windows.first;
    if (!head.isSuccess) {
      return jsonEncode({
        'error': describeError(head.error!),
        'path': absolutePath,
        'size_bytes': sizeBytes,
        'size_human': FilesystemOverviewFormat.formatBytes(sizeBytes),
        'format_hint': 'pdf',
        'text_extractable': false,
      });
    }

    final headLines = _splitLines(head.text!);
    final sampledHead = headLines
        .take(headLimit)
        .map(FilesystemOverviewFormat.clipLine)
        .toList();

    // The tail window only earns its own lines when it sits past the head;
    // on a short document the two overlap and the head already holds them.
    final tailWindow = windows.last;
    final tailLines =
        tailWindow.isSuccess && tailWindow.startPageIndex >= _inspectHeadPages
        ? _splitLines(tailWindow.text!)
        : headLines;
    final tail = tailLimit <= 0
        ? const <String>[]
        : tailLines
              .skip(
                tailLines.length > tailLimit ? tailLines.length - tailLimit : 0,
              )
              .map(FilesystemOverviewFormat.clipLine)
              .toList();
    final sampledWholeDocument = head.pageCount <= _inspectHeadPages;

    return jsonEncode({
      'path': absolutePath,
      'size_bytes': sizeBytes,
      'size_human': FilesystemOverviewFormat.formatBytes(sizeBytes),
      // Only a document that fit entirely in the head window can report a
      // real total. Reporting the sample's line count as `total_lines` told a
      // model planning offset/limit reads that a 20-page PDF held 41 lines
      // when read_file returns 279, so the count is named for what it is.
      if (sampledWholeDocument) 'total_lines': headLines.length,
      if (!sampledWholeDocument) 'sampled_lines': headLines.length,
      'encoding': 'pdf',
      'format_hint': 'pdf',
      'text_extractable': true,
      'page_count': head.pageCount,
      'head': sampledHead,
      if (tailLimit > 0) 'tail': tail,
      if (!sampledWholeDocument) 'pages_sampled': true,
    });
  }

  /// English prose for the model, one cause per line of remedy.
  ///
  /// The empty-text case names OCR as one possibility: told only that reading
  /// failed, a model will answer from the filename instead of stopping.
  static String describeError(PdfExtractionError error) => switch (error) {
    PdfExtractionError.tooLarge =>
      'PDF is too large to extract text from (limit '
          '${FilesystemOverviewFormat.formatBytes(PdfTextExtractionService.maxBytes)}).',
    PdfExtractionError.encrypted =>
      'PDF is password-protected and cannot be opened.',
    PdfExtractionError.noTextLayer =>
      'PDF has no extractable text. It may be scanned, image-only, or blank. '
          'OCR is not available. Do not describe its contents.',
    PdfExtractionError.malformed =>
      'PDF could not be parsed; the file is truncated or corrupt.',
  };

  static String? _contentHash(Uint8List bytes) {
    if (bytes.length > maxContentHashBytes) return null;
    return sha256.convert(bytes).toString();
  }

  static List<String> _splitLines(String text) =>
      const LineSplitter().convert(text);

  /// Reads [file] whole, or explains why it will not.
  ///
  /// `read_file` wants the bare error and `inspect_file` wants the overview
  /// fields around it, so the failure carries both shapes built from one
  /// message rather than two encodings that can drift apart.
  static Future<_BoundedPdfBytes> _readBounded(
    File file,
    String absolutePath,
  ) async {
    try {
      final length = await file.length();
      if (length <= PdfTextExtractionService.maxBytes) {
        return _BoundedPdfBytes.loaded(await file.readAsBytes());
      }
      return _BoundedPdfBytes.failure(
        error: describeError(PdfExtractionError.tooLarge),
        absolutePath: absolutePath,
        sizeBytes: length,
      );
    } on FileSystemException {
      return _BoundedPdfBytes.failure(
        error: describeError(PdfExtractionError.malformed),
        absolutePath: absolutePath,
      );
    }
  }

  /// Line window over already-extracted text.
  ///
  /// The text-file path streams this out of a file with a byte ceiling and a
  /// carry buffer; none of that applies here, because the extractor has
  /// already bounded the document in memory.
  static PdfLineSelection selectLines({
    required String text,
    required int offset,
    required int? limit,
    required int maxChars,
  }) {
    final lines = _splitLines(text);
    final totalLines = lines.length;
    final startIndex = offset - 1;
    final endIndexExclusive = limit == null
        ? totalLines
        : (startIndex + limit).clamp(0, totalLines);

    final buffer = StringBuffer();
    var selectedLineCount = 0;
    var charsCollected = 0;
    var truncatedByChars = false;

    for (var index = startIndex; index < endIndexExclusive; index++) {
      if (index < 0 || index >= totalLines) break;
      final line = lines[index];
      final separator = selectedLineCount == 0 ? 0 : 1;
      final projected = charsCollected + separator + line.length;
      if (projected > maxChars) {
        final remaining = maxChars - charsCollected - separator;
        if (remaining > 0) {
          if (selectedLineCount > 0) buffer.write('\n');
          buffer.write(line.substring(0, remaining));
          selectedLineCount += 1;
        }
        truncatedByChars = true;
        break;
      }
      if (selectedLineCount > 0) buffer.write('\n');
      buffer.write(line);
      charsCollected = projected;
      selectedLineCount += 1;
    }

    return PdfLineSelection(
      content: buffer.toString(),
      startLine: totalLines == 0 ? 0 : offset,
      lineCount: selectedLineCount,
      totalLines: totalLines,
      truncatedByLimit: limit != null && totalLines > startIndex + limit,
      truncatedByChars: truncatedByChars,
    );
  }
}

/// A PDF's bytes, or the two renderings of why they could not be read.
class _BoundedPdfBytes {
  const _BoundedPdfBytes._({this.bytes, this.readError, this.inspectError});

  factory _BoundedPdfBytes.loaded(Uint8List bytes) =>
      _BoundedPdfBytes._(bytes: bytes);

  factory _BoundedPdfBytes.failure({
    required String error,
    required String absolutePath,
    int? sizeBytes,
  }) => _BoundedPdfBytes._(
    readError: jsonEncode({'error': error, 'path': absolutePath}),
    inspectError: jsonEncode({
      'error': error,
      'path': absolutePath,
      'size_bytes': ?sizeBytes,
      if (sizeBytes != null)
        'size_human': FilesystemOverviewFormat.formatBytes(sizeBytes),
      'format_hint': 'pdf',
      'text_extractable': false,
    }),
  );

  final Uint8List? bytes;

  /// `read_file`'s payload: the cause and the path, nothing else.
  final String? readError;

  /// `inspect_file`'s payload: the same cause inside the overview fields.
  final String? inspectError;
}

/// One line window taken out of a PDF's extracted text.
class PdfLineSelection {
  const PdfLineSelection({
    required this.content,
    required this.startLine,
    required this.lineCount,
    required this.totalLines,
    required this.truncatedByLimit,
    required this.truncatedByChars,
  });

  final String content;
  final int startLine, lineCount, totalLines;
  final bool truncatedByLimit, truncatedByChars;
}
