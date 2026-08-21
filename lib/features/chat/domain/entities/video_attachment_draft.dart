import 'dart:io';

import '../../../../core/utils/attachment_format.dart';

/// A video on its way to a message: picked or typed, not yet sent.
///
/// Exactly one of [path] and [url] is set: a file the person chose, or an
/// address they typed. The bytes are never carried here -- a clip is large
/// enough that reading it into memory to sit in widget state, and again into
/// the conversation's stored JSON, is the wrong shape.
class VideoAttachmentDraft {
  const VideoAttachmentDraft({
    this.path,
    this.url,
    required this.mimeType,
    required this.displayName,
    this.sizeBytes,
    this.durationMs,
  }) : assert(
         (path == null) != (url == null),
         'A video attachment is either a local file or a URL, never both',
       );

  final String? path;
  final String? url;
  final String mimeType;

  /// File name, or the URL's last segment, for the composer chip.
  final String displayName;
  final int? sizeBytes;
  final int? durationMs;

  bool get isRemote => url != null;

  /// Largest clip accepted from disk.
  ///
  /// llama.cpp caps its own fetch of a remote media URL at 10MB, so anything
  /// above this cannot be delivered by URL at all, and inlining it as a data
  /// URI would be a third larger again. Refusing early beats a request that
  /// fails after the upload.
  static const int maxFileBytes = 10 * 1024 * 1024;

  /// Above this, a clip is worth warning about before it is sent.
  ///
  /// A server expands video into frames -- llama.cpp samples 4fps by default --
  /// so fifteen seconds is already around sixty images of context.
  static const int warnAboveDurationMs = 15 * 1000;

  bool get exceedsSizeLimit =>
      !isRemote && (sizeBytes ?? 0) > maxFileBytes;

  bool get isLong => (durationMs ?? 0) > warnAboveDurationMs;

  /// Same attachment at a different location, after the file is copied
  /// somewhere durable.
  VideoAttachmentDraft copyWith({String? path}) => VideoAttachmentDraft(
    path: path ?? this.path,
    url: url,
    mimeType: mimeType,
    displayName: displayName,
    sizeBytes: sizeBytes,
    durationMs: durationMs,
  );

  /// The size limit as the composer shows it.
  static String get formattedMaxFileSize => formatAttachmentSize(maxFileBytes);

  /// Label for an attachment chip: name, size, and length when known.
  String get chipLabel => <String>[
    if (displayName.isNotEmpty) displayName,
    if ((sizeBytes ?? 0) > 0) formatAttachmentSize(sizeBytes!),
    if ((durationMs ?? 0) > 0) formatAttachmentDuration(durationMs!),
  ].join(' · ');

  static Future<int?> fileSizeOf(String path) async {
    try {
      return await File(path).length();
    } on Object {
      return null;
    }
  }
}
