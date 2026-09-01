import 'dart:typed_data';

/// A file the composer is holding, either inlined or referenced by path.
class ComposerFileAttachment {
  const ComposerFileAttachment({
    required this.name,
    required this.sizeBytes,
    this.content,
    this.durablePath,
    this.previewPath,
    this.isPdf = false,
    this.pdfPageCount,
  });

  final String name;

  /// Size of the file on disk, which for a PDF is not the size of [content].
  final int sizeBytes;

  /// Text carried in the message body, null when referenced by path instead.
  final String? content;

  /// Durable copy on disk for the platform viewer, even when the text was
  /// inlined. Set for PDFs, whose pages the app cannot render itself.
  final String? previewPath;

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

  /// The file to hand the platform viewer, or null when there is none on disk.
  String? get openablePath => durablePath ?? previewPath;
}

/// A file dropped onto the chat surface, waiting to be picked up.
///
/// Mirrors [MessageInputVideoAttachment]: the path travels, not the bytes,
/// because a dropped file is delivered by reference.
class MessageInputFileAttachment {
  const MessageInputFileAttachment({
    required this.id,
    required this.filePath,
    this.mimeType,
    this.appleBookmark,
  });

  final int id;
  final String filePath;

  final String? mimeType;

  /// macOS security-scoped bookmark for a drop outside the app container.
  final Uint8List? appleBookmark;
}
