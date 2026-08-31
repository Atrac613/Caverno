import '../widgets/composer_file_models.dart';
import '../widgets/composer_video_picker.dart';
import '../widgets/message_input.dart';

/// The most recent file dropped onto the chat surface, per kind.
///
/// The composer picks these up in `didUpdateWidget`. Each attachment carries
/// a monotonic id so two drops of the same path are not collapsed.
class ChatDroppedAttachments {
  MessageInputImageAttachment? image;
  MessageInputVideoAttachment? video;
  MessageInputFileAttachment? file;

  int nextId = 0;
}
