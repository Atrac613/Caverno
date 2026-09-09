import 'dart:convert';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

/// Startup listing decode for persisted conversation payloads.
///
/// Full `Conversation.fromJson` walks every message, checkpoint, and turn
/// diff. That work belongs on the conversation that is actually opened, not
/// on the 400+ row sidebar list. This codec keeps identity, titles, workspace
/// routing, and plan/goal flags while dropping the heavy arrays.
final class ConversationListingCodec {
  const ConversationListingCodec();

  /// Marker id for a one-row placeholder so an unopened conversation with
  /// messages is not treated as empty (fresh-thread reuse checks
  /// `messages.isEmpty`).
  static const stubMessageId = '__caverno_listing_stub__';

  /// True when [messages] is the listing placeholder, not a real transcript.
  static bool isListingStub(List<Message> messages) {
    return messages.length == 1 && messages.single.id == stubMessageId;
  }

  Conversation? decode({
    required String listingJson,
    required int messageCount,
  }) {
    try {
      final data = jsonDecode(listingJson);
      if (data is! Map<String, dynamic>) {
        return null;
      }
      data['messages'] = const <Map<String, dynamic>>[];
      data['checkpoints'] = const <Map<String, dynamic>>[];
      data['turnDiffs'] = const <Map<String, dynamic>>[];
      final conversation = Conversation.fromJson(data);
      if (messageCount <= 0) {
        return conversation;
      }
      return conversation.copyWith(
        messages: [
          Message(
            id: stubMessageId,
            content: '',
            role: MessageRole.user,
            timestamp: conversation.createdAt,
          ),
        ],
      );
    } catch (error) {
      appLog('[ConversationListingCodec] Failed to parse listing: $error');
      return null;
    }
  }

  /// Drops message bodies in Dart when SQLite `json_remove` is unavailable.
  Conversation? decodeFromFullPayload(String payload) {
    try {
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final messages = data['messages'];
      final messageCount = messages is List ? messages.length : 0;
      data.remove('messages');
      data.remove('checkpoints');
      data.remove('turnDiffs');
      return decode(listingJson: jsonEncode(data), messageCount: messageCount);
    } catch (error) {
      appLog('[ConversationListingCodec] Failed to strip full payload: $error');
      return null;
    }
  }
}
