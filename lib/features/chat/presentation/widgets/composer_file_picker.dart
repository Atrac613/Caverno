import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/services/attachment_storage_service.dart';
import '../../../../core/services/pdf_text_extraction_service.dart';
import '../../../../core/utils/attachment_format.dart';
import '../../../../core/utils/logger.dart';
import 'composer_file_models.dart';

export 'composer_file_models.dart';

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

  static const Set<String> _allowedMimes = {
    'application/pdf',
    'text/plain',
    'text/markdown',
    'text/csv',
    'text/tab-separated-values',
    'text/xml',
    'text/yaml',
    'application/json',
    'application/xml',
    'application/x-yaml',
    'application/yaml',
  };

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

  /// Whether a drop's declared MIME type is a document this picker will take.
  ///
  /// Used for files that arrive without an extension, such as a browser
  /// download named `download` whose type is still `application/pdf`.
  static bool acceptsMime(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return false;
    final mime = mimeType.toLowerCase().split(';').first.trim();
    if (_allowedMimes.contains(mime)) return true;
    return mime.startsWith('text/');
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
      if (result == null || result.files.isEmpty) {
        return ComposerFileChoice.none;
      }

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
    if (!attachment.alreadyDurable &&
        !acceptsPath(attachment.filePath) &&
        !acceptsMime(attachment.mimeType)) {
      return const ComposerFileChoice.notice('message.drop_file_unsupported');
    }
    var scoped = false;
    final bookmark = attachment.appleBookmark;
    try {
      if (Platform.isMacOS && bookmark != null && bookmark.isNotEmpty) {
        scoped = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
      }
      final file = File(attachment.filePath);
      return await prepare(
        sourcePath: attachment.filePath,
        originalName: file.uri.pathSegments.last,
        sizeBytes: await file.length(),
        alreadyDurable: attachment.alreadyDurable,
      );
    } catch (e) {
      appDebugPrint('Failed to attach dropped file: $e');
      return _readError();
    } finally {
      if (scoped && bookmark != null) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  /// Prepares bytes that arrived without a path, such as a clipboard paste.
  Future<ComposerFileChoice> fromBytes({
    required List<int> bytes,
    required String originalName,
  }) async {
    String? durablePath;
    try {
      durablePath = await AttachmentStorageService.persistBytes(
        bytes: Uint8List.fromList(bytes),
        originalName: originalName,
      );
      final choice = await prepare(
        sourcePath: durablePath,
        originalName: originalName,
        sizeBytes: bytes.length,
        alreadyDurable: true,
      );
      await _discardUnusedStaging(durablePath, choice);
      return choice;
    } catch (e) {
      appDebugPrint('Failed to attach pasted file: $e');
      await _deleteQuietly(durablePath);
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
    // The extractor refuses this size, and paging cannot help: the whole file
    // has to be in memory before the first page comes out.
    if (sizeBytes > PdfTextExtractionService.maxBytes) {
      return ComposerFileChoice.notice(
        'message.pdf_too_large',
        args: {
          'limit': formatAttachmentSize(PdfTextExtractionService.maxBytes),
        },
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
        PdfExtractionError.tooLarge => ComposerFileChoice.notice(
          'message.pdf_too_large',
          args: {
            'limit': formatAttachmentSize(PdfTextExtractionService.maxBytes),
          },
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

  Future<void> _discardUnusedStaging(
    String durablePath,
    ComposerFileChoice choice,
  ) async {
    if (choice.file?.isPathReference == true) return;
    await _deleteQuietly(durablePath);
  }

  Future<void> _deleteQuietly(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await File(path).delete();
    } catch (_) {}
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
      // Keep the [Attached file:] prefix so conversation deletion can collect
      // the managed copy. search_files skips binary files and would find nothing.
      return '[Attached file: $durablePath ($human)]\n'
          'This PDF is large and is available on disk at the path above. '
          'read_file extracts its text layer — call inspect_file first for the '
          'page count, then read_file with offset, limit, and start_page. Do '
          'not try to read it all at once.';
    }
    return '[Attached file: $durablePath ($human)]\n'
        'This file is large and is available on disk at the path above. '
        'Use inspect_file first, then search_files / read_file with offset '
        'and limit. Do not try to read it all at once.';
  }
}
