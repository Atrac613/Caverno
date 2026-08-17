import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Actions available from the composer's "+" attachments menu.
enum ComposerAttachmentAction { image, file }

/// The composer's "+" button: picks an image or a file to send with the
/// message. It leads the action row because it adds content, ahead of the
/// chips that only describe how the message gets answered.
class ComposerAttachmentButton extends StatelessWidget {
  const ComposerAttachmentButton({
    super.key,
    required this.onPickImage,
    required this.onPickFile,
  });

  final VoidCallback onPickImage;
  final VoidCallback onPickFile;

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
      ],
    );
  }
}
