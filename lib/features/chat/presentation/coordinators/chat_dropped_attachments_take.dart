import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../widgets/chat_media_drop_target.dart';
import '../widgets/composer_file_models.dart';
import '../widgets/composer_video_picker.dart';
import '../widgets/message_input.dart';
import 'chat_dropped_attachments.dart';

/// Records a drop onto [ChatDroppedAttachments] and stamps a new id.
extension ChatDroppedAttachmentsTake on ChatDroppedAttachments {
  void takeImage({
    required Uint8List bytes,
    required String mimeType,
    required String filePath,
  }) {
    image = MessageInputImageAttachment(
      id: nextId += 1,
      bytes: bytes,
      mimeType: mimeType,
      filePath: filePath,
    );
  }

  void takeVideo({required String filePath, required String mimeType}) {
    video = MessageInputVideoAttachment(
      id: nextId += 1,
      filePath: filePath,
      mimeType: mimeType,
    );
  }

  void takeFile(String filePath, {String? mimeType, Uint8List? appleBookmark}) {
    file = MessageInputFileAttachment(
      id: nextId += 1,
      filePath: filePath,
      mimeType: mimeType,
      appleBookmark: appleBookmark,
    );
  }
}

/// Wires a drop onto [dropped] and rebuilds through [takeDrop].
Widget wrapChatMediaDropTarget({
  required bool enabled,
  required bool videoEnabled,
  required ChatDroppedAttachments dropped,
  required void Function(void Function() record) takeDrop,
  required Widget child,
}) {
  return ChatMediaDropTarget(
    enabled: enabled,
    videoEnabled: videoEnabled,
    onVideoDropped: (filePath, mimeType) => takeDrop(
      () => dropped.takeVideo(filePath: filePath, mimeType: mimeType),
    ),
    onFileDropped: (filePath, {mimeType, appleBookmark}) => takeDrop(
      () => dropped.takeFile(
        filePath,
        mimeType: mimeType,
        appleBookmark: appleBookmark,
      ),
    ),
    onImageDropped: (bytes, mimeType, filePath) => takeDrop(
      () => dropped.takeImage(
        bytes: bytes,
        mimeType: mimeType,
        filePath: filePath,
      ),
    ),
    child: child,
  );
}
