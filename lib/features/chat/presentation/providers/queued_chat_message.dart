import '../../../project_farm/domain/entities/project_task_commit_scope.dart';
import '../../domain/entities/video_attachment_draft.dart';
import 'chat_state.dart' show ChatInteractionOrigin;
import 'primary_turn_purpose.dart';

class QueuedChatMessage {
  const QueuedChatMessage({
    required this.id,
    required this.content,
    this.modelContent,
    this.attachmentPath,
    required this.imageBase64,
    required this.imageMimeType,
    required this.languageCode,
    required this.isVoiceMode,
    required this.bypassPlanMode,
    this.originalImagePath,
    this.originalImageMimeType,
    this.video,
    this.origin = ChatInteractionOrigin.local,
    this.remoteDeviceId,
    this.conversationId,
    this.purpose = PrimaryTurnPurpose.conversation,
    this.projectTaskCommitScope,
  });

  final String? conversationId;
  final PrimaryTurnPurpose purpose;
  final ProjectTaskCommitScope? projectTaskCommitScope;
  final String id;
  final String content;
  final String? modelContent;
  final String? attachmentPath;
  final String? imageBase64;
  final String? imageMimeType;
  final String? originalImagePath;
  final String? originalImageMimeType;
  final VideoAttachmentDraft? video;
  final String languageCode;
  final bool isVoiceMode;
  final bool bypassPlanMode;
  final ChatInteractionOrigin origin;
  final String? remoteDeviceId;
  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;
  bool get hasVideo => video != null;
  // One field tuple keeps equality and hashing aligned as queued context grows.
  Object get _equalityValues => (
    id,
    content,
    modelContent,
    attachmentPath,
    imageBase64,
    imageMimeType,
    originalImagePath,
    originalImageMimeType,
    video,
    languageCode,
    isVoiceMode,
    bypassPlanMode,
    origin,
    remoteDeviceId,
    conversationId,
    purpose,
    projectTaskCommitScope,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueuedChatMessage && _equalityValues == other._equalityValues;
  @override
  int get hashCode => _equalityValues.hashCode;
}
