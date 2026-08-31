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
    if (loaded.error != null) return loaded.error;
    final bytes = loaded.bytes!;

    final extraction = await PdfTextExtractionService.extractBytes(
      bytes,
      startPageIndex: startPage - 1,
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
    if (loaded.errorPayload != null) return loaded.errorPayload;
    final bytes = loaded.bytes!;
    final sizeBytes = bytes.length;

    final head = await PdfTextExtractionService.extractBytes(
      bytes,
      startPageIndex: 0,
      maxPages: _inspectHeadPages,
    );
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

    var tail = const <String>[];
    final tailStart = head.pageCount - _inspectTailPages;
    if (tailLimit > 0 && tailStart >= _inspectHeadPages) {
      final tailExtraction = await PdfTextExtractionService.extractBytes(
        bytes,
        startPageIndex: tailStart,
        maxPages: _inspectTailPages,
      );
      if (tailExtraction.isSuccess) {
        final tailLines = _splitLines(tailExtraction.text!);
        tail = tailLines.length <= tailLimit
            ? tailLines.map(FilesystemOverviewFormat.clipLine).toList()
            : tailLines
                  .skip(tailLines.length - tailLimit)
                  .map(FilesystemOverviewFormat.clipLine)
                  .toList();
      }
    } else if (tailLimit > 0) {
      tail = headLines.length <= tailLimit
          ? headLines.map(FilesystemOverviewFormat.clipLine).toList()
          : headLines
                .skip(headLines.length - tailLimit)
                .map(FilesystemOverviewFormat.clipLine)
                .toList();
    }

    return jsonEncode({
      'path': absolutePath,
      'size_bytes': sizeBytes,
      'size_human': FilesystemOverviewFormat.formatBytes(sizeBytes),
      'total_lines': headLines.length,
      'encoding': 'pdf',
      'format_hint': 'pdf',
      'text_extractable': true,
      'page_count': head.pageCount,
      'head': sampledHead,
      if (tailLimit > 0) 'tail': tail,
      if (head.pageCount > _inspectHeadPages) 'pages_sampled': true,
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

  static Future<
    ({
      Uint8List? bytes,
      FirstPartyToolExecutionResult? error,
      String? errorPayload,
    })
  >
  _readBounded(File file, String absolutePath) async {
    try {
      final length = await file.length();
      if (length > PdfTextExtractionService.maxBytes) {
        final message = jsonEncode({
          'error': describeError(PdfExtractionError.tooLarge),
          'path': absolutePath,
        });
        return (
          bytes: null,
          error: FirstPartyToolExecutionResult.payloadOnly(message),
          errorPayload: jsonEncode({
            'error': describeError(PdfExtractionError.tooLarge),
            'path': absolutePath,
            'size_bytes': length,
            'size_human': FilesystemOverviewFormat.formatBytes(length),
            'format_hint': 'pdf',
            'text_extractable': false,
          }),
        );
      }
      return (bytes: await file.readAsBytes(), error: null, errorPayload: null);
    } on FileSystemException {
      final message = jsonEncode({
        'error': describeError(PdfExtractionError.malformed),
        'path': absolutePath,
      });
      return (
        bytes: null,
        error: FirstPartyToolExecutionResult.payloadOnly(message),
        errorPayload: message,
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
