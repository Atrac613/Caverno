import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Actions available from the composer's "+" attachments menu.
enum ComposerAttachmentAction { image, file, video, videoUrl }

/// The composer's "+" button: picks an image or a file to send with the
/// message. It leads the action row because it adds content, ahead of the
/// chips that only describe how the message gets answered.
class ComposerAttachmentButton extends StatelessWidget {
  const ComposerAttachmentButton({
    super.key,
    required this.onPickImage,
    required this.onPickFile,
    this.onPickVideo,
    this.onEnterVideoUrl,
    this.videoEnabled = false,
  });

  final VoidCallback onPickImage;
  final VoidCallback onPickFile;
  final VoidCallback? onPickVideo;
  final VoidCallback? onEnterVideoUrl;

  /// Whether the endpoint in use accepts video.
  ///
  /// The video entries are hidden rather than disabled: a greyed-out row
  /// invites the person to work out why, and the reason lives in a settings
  /// screen they are not currently looking at.
  final bool videoEnabled;

  bool get _showVideo =>
      videoEnabled && (onPickVideo != null || onEnterVideoUrl != null);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ComposerAttachmentAction>(
      tooltip: 'message.attachments'.tr(),
      icon: const Icon(Icons.add),
      onSelected: (action) {
        switch (action) {
          case ComposerAttachmentAction.image:
            onPickImage();
          case ComposerAttachmentAction.file:
            onPickFile();
          case ComposerAttachmentAction.video:
            onPickVideo?.call();
          case ComposerAttachmentAction.videoUrl:
            onEnterVideoUrl?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<ComposerAttachmentAction>(
          value: ComposerAttachmentAction.image,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.image),
            title: Text('message.attach_image'.tr()),
          ),
        ),
        PopupMenuItem<ComposerAttachmentAction>(
          value: ComposerAttachmentAction.file,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.attach_file),
            title: Text('message.attach_file'.tr()),
          ),
        ),
        if (_showVideo && onPickVideo != null)
          PopupMenuItem<ComposerAttachmentAction>(
            value: ComposerAttachmentAction.video,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.movie),
              title: Text('message.attach_video'.tr()),
            ),
          ),
        if (_showVideo && onEnterVideoUrl != null)
          PopupMenuItem<ComposerAttachmentAction>(
            value: ComposerAttachmentAction.videoUrl,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link),
              title: Text('message.attach_video_url'.tr()),
            ),
          ),
      ],
    );
  }
}
