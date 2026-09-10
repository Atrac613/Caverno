import 'package:http/http.dart' as http;

import '../../domain/services/qwen38_request_thinking_policy.dart';
import 'qwen38_request_policy_client.dart';
import 'video_content_part_client.dart';

/// Builds the HTTP client stack every chat request path shares.
///
/// Both the buffered and the streaming client are wrapped: video parts are
/// written into the JSON body, so a stream path left unwrapped would silently
/// drop the attachment and answer blind. Thinking has to be decided the same
/// way on both, and by the policy the datasource reads back afterwards, so all
/// three are built here rather than repeated at three call sites that can
/// drift apart one parameter at a time.
abstract final class ChatDataSourceClientFactory {
  static Qwen38RequestThinkingPolicy thinkingPolicy({
    String? reasoningEffort,
    bool? enableThinking,
  }) => Qwen38RequestThinkingPolicy(
    reasoningEffort: reasoningEffort,
    enableThinking: enableThinking,
  );

  static http.Client wrap(
    http.Client delegate, {
    String? reasoningEffort,
    bool? enableThinking,
  }) => VideoContentPartClient(
    delegate: Qwen38RequestPolicyClient(
      delegate: delegate,
      policy: thinkingPolicy(
        reasoningEffort: reasoningEffort,
        enableThinking: enableThinking,
      ),
    ),
  );
}
