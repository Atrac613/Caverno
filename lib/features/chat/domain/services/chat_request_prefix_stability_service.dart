import 'dart:convert';

import '../entities/message.dart';

class ChatRequestPrefixStabilityService {
  ChatRequestPrefixStabilityService._();

  static String buildPromptPrefixJson({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    required int stableMessageCount,
  }) {
    if (stableMessageCount < 0) {
      throw ArgumentError.value(
        stableMessageCount,
        'stableMessageCount',
        'must not be negative',
      );
    }
    final boundedMessageCount = stableMessageCount > messages.length
        ? messages.length
        : stableMessageCount;
    final prefixPayload = <String, dynamic>{
      'messages': messages
          .take(boundedMessageCount)
          .map(_messagePromptPayload)
          .toList(growable: false),
      'tools': tools ?? const <Map<String, dynamic>>[],
    };
    return jsonEncode(_normalizeJson(prefixPayload));
  }

  static int commonLeadingPromptMessageCount(
    List<Message> first,
    List<Message> second,
  ) {
    final limit = first.length < second.length ? first.length : second.length;
    var count = 0;
    while (count < limit) {
      final firstPayload = _normalizeJson(_messagePromptPayload(first[count]));
      final secondPayload = _normalizeJson(
        _messagePromptPayload(second[count]),
      );
      if (jsonEncode(firstPayload) != jsonEncode(secondPayload)) {
        break;
      }
      count += 1;
    }
    return count;
  }

  static Map<String, dynamic> _messagePromptPayload(Message message) {
    return {
      'role': message.role.name,
      'content': message.content,
      if (message.imageBase64 != null) 'imageBase64': message.imageBase64,
      if (message.imageMimeType != null) 'imageMimeType': message.imageMimeType,
    };
  }

  static Object? _normalizeJson(Object? value) {
    if (value is Map) {
      final normalized = <String, Object?>{};
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        normalized[entry.key.toString()] = _normalizeJson(entry.value);
      }
      return normalized;
    }
    if (value is Iterable) {
      return value.map(_normalizeJson).toList(growable: false);
    }
    return value;
  }
}
