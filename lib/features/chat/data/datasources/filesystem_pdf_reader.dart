import 'dart:convert';
import 'dart:io';

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
  }) async {
    if (!PdfTextExtractionService.looksLikePdf(prefix)) return null;

    final extraction = await PdfTextExtractionService.extract(file);
    if (!extraction.isSuccess) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error': describeError(extraction.error!),
          'path': absolutePath,
        }),
      );
    }

    final sizeBytes = await file.length();
    final selection = selectLines(
      text: extraction.text!,
      offset: offset,
      limit: limit,
      maxChars: maxChars,
    );
    // Hashes the raw PDF, not the extracted text: the question this answers is
    // "is this the same file I read before", and two documents can render the
    // same characters. Safe to publish because the hash is only read by the
    // tool-loop digest and the result summary -- edit_file's precondition
    // fingerprints a text snapshot of its own and never consults this one.
    final contentHash = await _contentHash(file, sizeBytes);

    final response = <String, dynamic>{
      'path': absolutePath,
      'content': selection.content,
      'content_hash': ?contentHash,
      'size_bytes': sizeBytes,
      'format': 'pdf',
      'page_count': extraction.pageCount,
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
  static Future<String?> inspectFile({
    required File file,
    required String absolutePath,
    required List<int> prefix,
    required int headLimit,
    required int tailLimit,
  }) async {
    if (!PdfTextExtractionService.looksLikePdf(prefix)) return null;

    final sizeBytes = await file.length();
    final extraction = await PdfTextExtractionService.extract(file);
    if (!extraction.isSuccess) {
      return jsonEncode({
        'error': describeError(extraction.error!),
        'path': absolutePath,
        'size_bytes': sizeBytes,
        'size_human': FilesystemOverviewFormat.formatBytes(sizeBytes),
        'format_hint': 'pdf',
        'text_extractable': false,
      });
    }

    final lines = _splitLines(extraction.text!);
    final head = lines
        .take(headLimit)
        .map(FilesystemOverviewFormat.clipLine)
        .toList();
    final tail = tailLimit <= 0
        ? const <String>[]
        : lines
              .skip(lines.length > tailLimit ? lines.length - tailLimit : 0)
              .map(FilesystemOverviewFormat.clipLine)
              .toList();

    return jsonEncode({
      'path': absolutePath,
      'size_bytes': sizeBytes,
      'size_human': FilesystemOverviewFormat.formatBytes(sizeBytes),
      'total_lines': lines.length,
      'encoding': 'pdf',
      'format_hint': 'pdf',
      'text_extractable': true,
      'page_count': extraction.pageCount,
      'head': head,
      if (tailLimit > 0) 'tail': tail,
      if (extraction.truncated) 'pages_truncated': true,
      if (extraction.truncated) 'pages_extracted': extraction.extractedPages,
    });
  }

  /// English prose for the model, one cause per line of remedy.
  ///
  /// The scanned-document case names OCR on purpose: told only that reading
  /// failed, a model will answer from the filename instead of stopping.
  static String describeError(PdfExtractionError error) => switch (error) {
    PdfExtractionError.tooLarge =>
      'PDF is too large to extract text from (limit '
          '${FilesystemOverviewFormat.formatBytes(PdfTextExtractionService.maxBytes)}).',
    PdfExtractionError.encrypted =>
      'PDF is password-protected and cannot be opened.',
    PdfExtractionError.noTextLayer =>
      'PDF has no extractable text layer, so it is a scanned document. '
          'Reading it would require OCR, which is not available. Do not '
          'describe its contents.',
    PdfExtractionError.malformed =>
      'PDF could not be parsed; the file is truncated or corrupt.',
  };

  static Future<String?> _contentHash(File file, int sizeBytes) async {
    try {
      return sha256.convert(await file.readAsBytes()).toString();
    } catch (_) {
      // Absent means unknown, never unchanged.
      return null;
    }
  }

  static List<String> _splitLines(String text) =>
      const LineSplitter().convert(text);

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
      if (!truncatedByChars) {
        final separator = selectedLineCount == 0 ? 0 : 1;
        final projected = charsCollected + separator + line.length;
        if (projected > maxChars) {
          final remaining = maxChars - charsCollected - separator;
          if (remaining > 0) {
            if (selectedLineCount > 0) buffer.write('\n');
            buffer.write(line.substring(0, remaining));
            charsCollected += separator + remaining;
          }
          truncatedByChars = true;
        } else {
          if (selectedLineCount > 0) buffer.write('\n');
          buffer.write(line);
          charsCollected = projected;
        }
      }
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
