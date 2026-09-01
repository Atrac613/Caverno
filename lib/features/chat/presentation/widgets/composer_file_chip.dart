import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/attachment_format.dart';
import 'composer_file_models.dart';

/// The composer's chip for a staged file attachment.
///
/// Mirrors [ComposerVideoChip]: the composer holds the attachment, the chip
/// knows how to show one. The icon is the only signal that says whether the
/// model will read the text from this message or fetch it off disk, so it is
/// decided here rather than in the composer's build method.
class ComposerFileChip extends StatelessWidget {
  const ComposerFileChip({
    required this.file,
    required this.onCleared,
    super.key,
  });

  final ComposerFileAttachment file;
  final VoidCallback onCleared;

  IconData get _icon {
    if (file.isPathReference) return Icons.link;
    return file.pdfPageCount == null ? Icons.description : Icons.picture_as_pdf;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: file.isPathReference ? 'message.attached_as_path'.tr() : '',
        child: Chip(
          avatar: Icon(_icon, size: 18),
          label: Text(
            '${file.name} (${formatAttachmentSize(file.sizeBytes)})',
            overflow: TextOverflow.ellipsis,
          ),
          deleteIcon: const Icon(Icons.close, size: 18),
          onDeleted: onCleared,
        ),
      ),
    );
  }
}
