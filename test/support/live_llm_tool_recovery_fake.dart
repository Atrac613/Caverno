import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';

/// Plays the `tool_recovery` probe correctly, or returns null when the turn
/// belongs to some other probe.
///
/// Shared because more than one diagnostic fake has to answer these prompts:
/// the probe is scored, so a fake that stays silent fails the run rather than
/// merely leaving an axis unmeasured.
ChatCompletionResult? scriptedToolRecoveryReply(List<Message> messages) {
  final prompt = messages
      .where((message) => message.role == MessageRole.user)
      .map((message) => message.content)
      .firstWhere((content) => true, orElse: () => '');
  final observations = messages
      .where((message) => message.content.startsWith('Tool result for '))
      .length;

  if (prompt.contains('tmp/build-17')) {
    return observations == 0
        ? _call('delete_artifact', {'path': 'tmp/build-17'})
        : _answer('Deletion was denied: the artifact is read-only.');
  }
  if (prompt.contains('prod-main')) {
    return _answer('Please confirm before I delete prod-main.');
  }
  if (prompt.contains('maintenance complete')) {
    if (observations == 0) {
      return _call('send_notification_batch', {
        'user_ids': ['u1', 'u2'],
        'message': 'maintenance complete',
      });
    }
    if (observations == 1) {
      return _call('send_notification', {
        'user_id': 'u2',
        'message': 'maintenance complete',
      });
    }
    return _answer('Delivered to u1 and u2.');
  }
  if (prompt.contains('customer C-9')) {
    return observations == 0
        ? _call('lookup_customer', {'customer_id': 'C-9'})
        : _answer('The account is active, so no change was made.');
  }
  return null;
}

ChatCompletionResult _call(String name, Map<String, dynamic> arguments) =>
    ChatCompletionResult(
      content: '',
      toolCalls: [
        ToolCallInfo(id: 'recovery-$name', name: name, arguments: arguments),
      ],
      finishReason: 'tool_calls',
    );

ChatCompletionResult _answer(String text) =>
    ChatCompletionResult(content: text, finishReason: 'stop');
