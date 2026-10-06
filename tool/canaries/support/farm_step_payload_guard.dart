import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';

/// The fixture lives outside repository ancestors and uses fresh empty stores.
/// Fail before HTTP if a request contains a user-home or repository context.
void guardFarmStepPayload(
  List<Message> messages, {
  List<ToolResultInfo> results = const [],
  String? assistantContent,
  List<Map<String, dynamic>>? tools,
}) {
  final text = [
    ...messages.map((message) => message.content),
    ...results.map(
      (result) => '${jsonEncode(result.arguments)}\n${result.result}',
    ),
    assistantContent ?? '',
    jsonEncode(tools),
  ].join('\n');
  for (final forbidden in [
    '/Users/',
    'Caverno agent guide',
    '.caverno/session_logs/',
  ]) {
    if (text.contains(forbidden)) {
      throw StateError(
        'Farm canary payload contains non-fixture context: $forbidden',
      );
    }
  }
}
