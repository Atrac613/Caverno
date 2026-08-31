import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/services/attachment_storage_service.dart';
import '../../../../core/services/pdf_text_extraction_service.dart';
import '../../../../core/utils/attachment_format.dart';
import '../../../../core/utils/logger.dart';

/// A file dropped onto the chat surface, waiting to be picked up.
///
/// Mirrors [MessageInputVideoAttachment]: the path travels, not the bytes,
/// because a dropped file is delivered by reference and reading it in the drop
/// handler would only buy a copy in memory.
class MessageInputFileAttachment {
  const MessageInputFileAttachment({required this.id, required this.filePath});

  final int id;
  final String filePath;
}

/// A file the composer is holding, either inlined or referenced by path.
class ComposerFileAttachment {
  const ComposerFileAttachment({
    required this.name,
    required this.sizeBytes,
    this.content,
    this.durablePath,
    this.isPdf = false,
    this.pdfPageCount,
  });

  final String name;

  /// Size of the file on disk, which for a PDF is not the size of [content].
  final int sizeBytes;

  /// Text carried in the message body, null when referenced by path instead.
  final String? content;

  /// Durable copy the model reads with the file tools, null when inlined.
  final String? durablePath;

  /// Whether the source file is a PDF.
  ///
  /// Carried rather than inferred from [name]: the picker decides from the
  /// file's header, so a PDF with a misleading extension still gets PDF
  /// advice, and a `.pdf` that is really text does not.
  final bool isPdf;

  /// Pages the source PDF had, null when referenced by path or not a PDF.
  final int? pdfPageCount;

  bool get isPathReference => durablePath != null;
}

/// What choosing a file produced, and what the person should be told.
///
/// Follows [ComposerVideoChoice]: the two travel together because a rejected
/// file yields no attachment and one message, and holding a `BuildContext`
/// here would make the whole picker untestable.
class ComposerFileChoice {
  const ComposerFileChoice({this.file, this.noticeKey, this.noticeArgs});

  const ComposerFileChoice.notice(String key, {Map<String, String>? args})
    : this(noticeKey: key, noticeArgs: args);

  static const ComposerFileChoice none = ComposerFileChoice();

  final ComposerFileAttachment? file;

  /// Translation key for a message to surface, or null when there is nothing
  /// to say. Kept as a key so this stays a plain object with no context.
  final String? noticeKey;
  final Map<String, String>? noticeArgs;

  String? get notice =>
      noticeKey?.tr(namedArgs: noticeArgs ?? const <String, String>{});
}

/// Chooses a file for the composer, from the picker, a drop, or the clipboard.
///
/// Separate from the composer because none of it is about the composer: it is
/// a file dialog, a size policy and PDF extraction, and keeping it here means
/// the composer holds only the resulting attachment.
class ComposerFilePicker {
  const ComposerFilePicker();

  /// Extensions the file dialog offers, and the gate a drop has to pass.
  ///
  /// Everything here is text the model can read directly, plus PDF, whose text
  /// layer this class extracts.
  static const List<String> allowedExtensions = <String>[
    'csv', 'txt', 'json', 'md', //
    'log', 'jsonl', 'ndjson', 'tsv', 'xml', 'yaml', 'yml',
    'pdf',
  ];

  /// Files at or below this size are inlined into the message text. Larger
  /// ones are copied to a durable path and referenced by path so the model can
  /// analyze them with the file tools without bloating the context window.
  ///
  /// For a PDF this is measured against the *extracted text*, not the file: a
  /// four-megabyte scan of a report is often twenty kilobytes of prose, and
  /// making the person's PDF wait on a tool round-trip for that would be a
  /// worse answer for no saving.
  static const int inlineMaxBytes = 256 * 1024;

  /// How much of a file to read when deciding whether it is a PDF.
  static const int _signatureSniffBytes = 1024;

  /// Whether a dropped or pasted path is one this picker will take.
  static bool acceptsPath(String path) {
    final lower = path.toLowerCase();
    return allowedExtensions.any((extension) => lower.endsWith('.$extension'));
  }

  /// Opens the file dialog and prepares whatever the person chose.
  Future<ComposerFileChoice> pick() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        // Fetch the path (available on mobile too) instead of loading the whole
        // file into memory — large files must never be read fully here.
        withData: false,
      );
      if (result == null || result.files.isEmpty) return ComposerFileChoice.none;

      final picked = result.files.first;
      final sourcePath = picked.path;
      if (sourcePath == null) return _readError();
      return await prepare(
        sourcePath: sourcePath,
        originalName: picked.name,
        sizeBytes: picked.size,
      );
    } catch (e) {
      appDebugPrint('Failed to pick file: $e');
      return _readError();
    }
  }

  /// Prepares a file the person dropped onto the chat surface.
  Future<ComposerFileChoice> fromDroppedFile(
    MessageInputFileAttachment attachment,
  ) async {
    if (!acceptsPath(attachment.filePath)) {
      return const ComposerFileChoice.notice('message.drop_file_unsupported');
    }
    try {
      final file = File(attachment.filePath);
      return await prepare(
        sourcePath: attachment.filePath,
        originalName: file.uri.pathSegments.last,
        sizeBytes: await file.length(),
      );
    } catch (e) {
      appDebugPrint('Failed to attach dropped file: $e');
      return _readError();
    }
  }

  /// Prepares bytes that arrived without a path, such as a clipboard paste.
  Future<ComposerFileChoice> fromBytes({
    required List<int> bytes,
    required String originalName,
  }) async {
    try {
      final durablePath = await AttachmentStorageService.persistBytes(
        bytes: Uint8List.fromList(bytes),
        originalName: originalName,
      );
      return await prepare(
        sourcePath: durablePath,
        originalName: originalName,
        sizeBytes: bytes.length,
        alreadyDurable: true,
      );
    } catch (e) {
      appDebugPrint('Failed to attach pasted file: $e');
      return _readError();
    }
  }

  /// Decides how one file should reach the model.
  ///
  /// [alreadyDurable] says [sourcePath] is already inside the attachments
  /// directory, so a path reference can point at it instead of copying twice.
  Future<ComposerFileChoice> prepare({
    required String sourcePath,
    required String originalName,
    required int sizeBytes,
    bool alreadyDurable = false,
  }) async {
    final file = File(sourcePath);
    if (await _looksLikePdf(file)) {
      return _preparePdf(
        file: file,
        originalName: originalName,
        sizeBytes: sizeBytes,
        alreadyDurable: alreadyDurable,
      );
    }

    if (sizeBytes > inlineMaxBytes) {
      return _asPathReference(
        sourcePath: sourcePath,
        originalName: originalName,
        sizeBytes: sizeBytes,
        alreadyDurable: alreadyDurable,
        isPdf: false,
      );
    }

    try {
      final content = utf8.decode(await file.readAsBytes());
      return ComposerFileChoice(
        file: ComposerFileAttachment(
          name: originalName,
          sizeBytes: sizeBytes,
          content: content,
        ),
      );
    } on FormatException {
      return _readError();
    } on FileSystemException {
      return _readError();
    }
  }

  Future<ComposerFileChoice> _preparePdf({
    required File file,
    required String originalName,
    required int sizeBytes,
    required bool alreadyDurable,
  }) async {
    // Above the extractor's memory bound nothing can be inlined, so hand the
    // model the path: read_file parses PDFs and applies the same bound with
    // paging behind it.
    if (sizeBytes > PdfTextExtractionService.maxBytes) {
      return _asPathReference(
        sourcePath: file.path,
        originalName: originalName,
        sizeBytes: sizeBytes,
        alreadyDurable: alreadyDurable,
        isPdf: true,
      );
    }

    final extraction = await PdfTextExtractionService.extract(file);
    final error = extraction.error;
    if (error != null) {
      return switch (error) {
        PdfExtractionError.noTextLayer => const ComposerFileChoice.notice(
          'message.pdf_no_text_layer',
        ),
        PdfExtractionError.encrypted => const ComposerFileChoice.notice(
          'message.pdf_encrypted',
        ),
        PdfExtractionError.malformed => const ComposerFileChoice.notice(
          'message.pdf_read_error',
        ),
        // Only reachable if the file grew between the check above and the
        // read; the path reference stays a correct answer either way.
        PdfExtractionError.tooLarge => await _asPathReference(
          sourcePath: file.path,
          originalName: originalName,
          sizeBytes: sizeBytes,
          alreadyDurable: alreadyDurable,
          isPdf: true,
        ),
      };
    }

    final text = extraction.text!;
    if (utf8.encode(text).length > inlineMaxBytes) {
      return _asPathReference(
        sourcePath: file.path,
        originalName: originalName,
        sizeBytes: sizeBytes,
        alreadyDurable: alreadyDurable,
        isPdf: true,
      );
    }

    return ComposerFileChoice(
      file: ComposerFileAttachment(
        name: originalName,
        sizeBytes: sizeBytes,
        content: text,
        isPdf: true,
        pdfPageCount: extraction.pageCount,
      ),
    );
  }

  Future<ComposerFileChoice> _asPathReference({
    required String sourcePath,
    required String originalName,
    required int sizeBytes,
    required bool alreadyDurable,
    required bool isPdf,
  }) async {
    try {
      final durablePath = alreadyDurable
          ? sourcePath
          : await AttachmentStorageService.persist(
              sourcePath: sourcePath,
              originalName: originalName,
            );
      return ComposerFileChoice(
        file: ComposerFileAttachment(
          name: originalName,
          sizeBytes: sizeBytes,
          durablePath: durablePath,
          isPdf: isPdf,
        ),
      );
    } catch (e) {
      appDebugPrint('Failed to persist attachment: $e');
      return _readError();
    }
  }

  Future<bool> _looksLikePdf(File file) async {
    try {
      final prefix = <int>[];
      await for (final chunk in file.openRead(0, _signatureSniffBytes)) {
        prefix.addAll(chunk);
      }
      return PdfTextExtractionService.looksLikePdf(prefix);
    } on FileSystemException {
      return false;
    }
  }

  ComposerFileChoice _readError() =>
      const ComposerFileChoice.notice('message.file_read_error');

  /// The block an attachment contributes to the outgoing message.
  ///
  /// Lives beside the picker rather than in the composer's send path so the
  /// wording the model actually receives is testable without a widget.
  static String composeMessageBlock(ComposerFileAttachment file) {
    final durablePath = file.durablePath;
    if (durablePath == null) {
      final label = file.pdfPageCount == null
          ? '[File: ${file.name}]'
          : '[File: ${file.name} (PDF, ${file.pdfPageCount} pages)]';
      return '$label\n${file.content}';
    }

    final human = formatAttachmentSize(file.sizeBytes);
    if (file.isPdf) {
      // Deliberately does not offer search_files: it skips binary files, so a
      // grep over a PDF silently finds nothing.
      return '[Attached PDF: $durablePath ($human)]\n'
          'This PDF is large and is available on disk at the path above. '
          'read_file extracts its text layer — call inspect_file first for the '
          'page count, then read_file with offset and limit. Do not try to '
          'read it all at once.';
    }
    return '[Attached file: $durablePath ($human)]\n'
        'This file is large and is available on disk at the path above. '
        'Use inspect_file first, then search_files / read_file with offset '
        'and limit. Do not try to read it all at once.';
  }
}
