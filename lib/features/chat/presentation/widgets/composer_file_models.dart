import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';

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
