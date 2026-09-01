import 'dart:convert';
import 'dart:io';

import '../../../../core/services/attachment_storage_service.dart';
import '../../../../core/services/pdf_text_extraction_service.dart';
import '../../../../core/utils/attachment_format.dart';
import '../../../../core/utils/logger.dart';
import 'composer_file_picker.dart';

/// What the composer does with a PDF, kept apart from the picker's generic
/// size policy: extracting text, deciding whether the result fits inline, and
/// keeping a copy on disk so the person can still open the document itself.
Future<ComposerFileChoice> preparePdfAttachment({
  required ComposerFilePicker picker,
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
  if (utf8.encode(text).length > ComposerFilePicker.inlineMaxBytes) {
    return picker.asPathReference(
      sourcePath: file.path,
      originalName: originalName,
      sizeBytes: sizeBytes,
      alreadyDurable: alreadyDurable,
      isPdf: true,
    );
  }

  // Kept on disk even though the text is inlined: the app cannot render PDF
  // pages, so the only way to show the person the document itself is to hand
  // the file to the platform viewer.
  return ComposerFileChoice(
    file: ComposerFileAttachment(
      name: originalName,
      sizeBytes: sizeBytes,
      content: text,
      previewPath: await _preservedCopy(
        sourcePath: file.path,
        originalName: originalName,
        alreadyDurable: alreadyDurable,
      ),
      isPdf: true,
      pdfPageCount: extraction.pageCount,
    ),
  );
}

/// A copy of [sourcePath] that outlives the picker's temporary directory.
///
/// Returns null rather than failing the attachment: a PDF whose text was
/// extracted is still worth sending when only the preview copy could not be
/// written.
Future<String?> _preservedCopy({
  required String sourcePath,
  required String originalName,
  required bool alreadyDurable,
}) async {
  if (alreadyDurable) return sourcePath;
  try {
    return await AttachmentStorageService.persist(
      sourcePath: sourcePath,
      originalName: originalName,
    );
  } catch (e) {
    appDebugPrint('Failed to keep a preview copy of the attachment: $e');
    return null;
  }
}
