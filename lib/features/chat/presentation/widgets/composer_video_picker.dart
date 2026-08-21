import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/video_attachment_draft.dart';

/// A video dropped onto the chat surface, waiting to be picked up.
///
/// Carries the path rather than bytes for the same reason
/// [VideoAttachmentDraft] does: the file is delivered by reference.
class MessageInputVideoAttachment {
  const MessageInputVideoAttachment({
    required this.id,
    required this.filePath,
    required this.mimeType,
  });

  final int id;
  final String filePath;
  final String mimeType;
}

/// What choosing a video produced, and what the person should be told.
///
/// The two travel together because the interesting cases are both at once:
/// a clip that is too large yields no attachment and one message, while a long
/// one yields both.
class ComposerVideoChoice {
  const ComposerVideoChoice({this.video, this.noticeKey, this.noticeArgs});

  static const ComposerVideoChoice none = ComposerVideoChoice();

  final VideoAttachmentDraft? video;

  /// Translation key for a message to surface, or null when there is nothing
  /// to say. Kept as a key so this stays a plain object with no BuildContext.
  final String? noticeKey;
  final Map<String, String>? noticeArgs;

  String? get notice =>
      noticeKey?.tr(namedArgs: noticeArgs ?? const <String, String>{});
}

/// Chooses a video for the composer, from disk, the gallery, or a typed URL.
///
/// Separate from the composer because none of it is about the composer: it is
/// platform plumbing plus one dialog, and keeping it here means the composer
/// holds only the resulting draft.
class ComposerVideoPicker {
  const ComposerVideoPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker;

  final ImagePicker? _imagePicker;

  /// Picks a video with whichever chooser the platform actually has.
  ///
  /// Deliberately not routed through the composer's file picker: that path
  /// allow-lists text extensions and inlines small files into the message
  /// body, neither of which a video survives.
  Future<ComposerVideoChoice> pick() async {
    try {
      final picked = Platform.isIOS || Platform.isAndroid
          ? await _pickFromGallery()
          : await _pickFromDisk();
      return validate(picked);
    } catch (e) {
      debugPrint('Failed to pick video: $e');
      return ComposerVideoChoice.none;
    }
  }

  /// Asks for a video URL the model endpoint can fetch on its own.
  Future<ComposerVideoChoice> promptForUrl(BuildContext context) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => const _VideoUrlDialog(),
    );
    final trimmed = entered?.trim() ?? '';
    if (trimmed.isEmpty) return ComposerVideoChoice.none;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return const ComposerVideoChoice(noticeKey: 'message.video_url_invalid');
    }
    return ComposerVideoChoice(
      video: VideoAttachmentDraft(
        url: trimmed,
        mimeType: mimeTypeFor(parsed.path),
        displayName: parsed.pathSegments.isEmpty
            ? parsed.host
            : parsed.pathSegments.last,
      ),
    );
  }

  /// Turns a dropped file into a draft, applying the same limits as a pick.
  Future<ComposerVideoChoice> fromDroppedFile(
    MessageInputVideoAttachment attachment,
  ) async {
    return validate(
      VideoAttachmentDraft(
        path: attachment.filePath,
        mimeType: attachment.mimeType,
        displayName: attachment.filePath.split(Platform.pathSeparator).last,
        sizeBytes: await VideoAttachmentDraft.fileSizeOf(attachment.filePath),
      ),
    );
  }

  /// Applies the size limit and the long-clip warning.
  @visibleForTesting
  ComposerVideoChoice validate(VideoAttachmentDraft? video) {
    if (video == null) return ComposerVideoChoice.none;
    if (video.exceedsSizeLimit) {
      return ComposerVideoChoice(
        noticeKey: 'message.video_too_large',
        noticeArgs: <String, String>{
          'limit': VideoAttachmentDraft.formattedMaxFileSize,
        },
      );
    }
    return ComposerVideoChoice(
      video: video,
      noticeKey: video.isLong ? 'message.video_long_warning' : null,
    );
  }

  Future<VideoAttachmentDraft?> _pickFromGallery() async {
    final picker = _imagePicker ?? ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return null;
    return VideoAttachmentDraft(
      path: picked.path,
      mimeType: picked.mimeType ?? mimeTypeFor(picked.path),
      displayName: picked.name.isNotEmpty ? picked.name : picked.path,
      sizeBytes: await VideoAttachmentDraft.fileSizeOf(picked.path),
    );
  }

  Future<VideoAttachmentDraft?> _pickFromDisk() async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    final picked = result?.files.singleOrNull;
    final path = picked?.path;
    if (picked == null || path == null) return null;
    return VideoAttachmentDraft(
      path: path,
      mimeType: mimeTypeFor(path),
      displayName: picked.name.isNotEmpty ? picked.name : path,
      sizeBytes: picked.size,
    );
  }

  static String mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.avi')) return 'video/x-msvideo';
    return 'video/mp4';
  }
}

class _VideoUrlDialog extends StatefulWidget {
  const _VideoUrlDialog();

  @override
  State<_VideoUrlDialog> createState() => _VideoUrlDialogState();
}

class _VideoUrlDialogState extends State<_VideoUrlDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('message.attach_video_url'.tr()),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'https://example.com/clip.mp4',
          helperText: 'message.attach_video_url_helper'.tr(),
          helperMaxLines: 3,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(onPressed: _submit, child: Text('common.ok'.tr())),
      ],
    );
  }
}

/// The composer's chip for a video that is about to be sent.
///
/// A chip, not a player: the composer says what is about to go out, and
/// playback belongs to the app the clip came from.
class ComposerVideoChip extends StatelessWidget {
  const ComposerVideoChip({
    required this.video,
    required this.onCleared,
    super.key,
  });

  final VideoAttachmentDraft video;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: Icon(video.isRemote ? Icons.link : Icons.movie, size: 18),
          label: Text(video.chipLabel, overflow: TextOverflow.ellipsis),
          deleteIcon: const Icon(Icons.close, size: 18),
          onDeleted: onCleared,
        ),
      ),
    );
  }
}
