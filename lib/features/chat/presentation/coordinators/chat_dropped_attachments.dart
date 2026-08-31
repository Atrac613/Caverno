import 'dart:typed_data';

import '../widgets/composer_file_picker.dart';
import '../widgets/composer_video_picker.dart';
import '../widgets/message_input.dart';

/// The most recent file dropped onto the chat surface, per kind.
///
/// The composer picks these up in `didUpdateWidget`, which is why each one
/// carries a monotonic id: two drops of the same path are two attachments, and
/// without the id the second would look like the first and be ignored. Holding
/// all three together keeps the page's own state to a single field and keeps
/// the counters next to the values they stamp.
class ChatDroppedAttachments {
  MessageInputImageAttachment? image;
  MessageInputVideoAttachment? video;
  MessageInputFileAttachment? file;

  int _nextId = 0;

  void takeImage({
    required Uint8List bytes,
    required String mimeType,
    required String filePath,
  }) {
    image = MessageInputImageAttachment(
      id: ++_nextId,
      bytes: bytes,
      mimeType: mimeType,
      filePath: filePath,
    );
  }

  void takeVideo({required String filePath, required String mimeType}) {
    video = MessageInputVideoAttachment(
      id: ++_nextId,
      filePath: filePath,
      mimeType: mimeType,
    );
  }

  void takeFile(String filePath) {
    file = MessageInputFileAttachment(id: ++_nextId, filePath: filePath);
  }
}
