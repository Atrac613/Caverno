import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/security/llm_endpoint_transport_policy.dart';
import '../../domain/services/model_routing/chat_request_thinking_policy.dart';
import 'anthropic_messages_client.dart';
import 'chat_request_policy_client.dart';
import 'video_content_part_client.dart';

/// The request-shaping inputs every chat client path needs.
///
/// Grouped because they always travel together: passing them one named
/// parameter at a time meant four call sites repeating the same three lines,
/// which is how `acceptsChatTemplateKwargs` came to be threaded through a file
/// already at its size budget.
typedef ChatRequestShape = ({
  String? reasoningEffort,
  bool? enableThinking,
  bool acceptsChatTemplateKwargs,
});

/// Applies the same video and thinking policy to buffered and streaming clients.
abstract final class ChatDataSourceClientFactory {
  static ChatRequestThinkingPolicy thinkingPolicy(ChatRequestShape shape) =>
      ChatRequestThinkingPolicy(
        reasoningEffort: shape.reasoningEffort,
        enableThinking: shape.enableThinking,
        acceptsChatTemplateKwargs: shape.acceptsChatTemplateKwargs,
      );

  static http.Client wrap(
    http.Client delegate,
    ChatRequestShape shape, {
    String? baseUrl,
  }) => VideoContentPartClient(
    delegate: ChatRequestPolicyClient(
      delegate: AnthropicMessagesClient.wrapIfNeeded(delegate, baseUrl),
      policy: thinkingPolicy(shape),
    ),
  );

  /// The validated, fully wrapped client the datasource talks through.
  ///
  /// Built here rather than in the datasource's initializer list so both
  /// client paths are wrapped by construction: an initializer list cannot hold
  /// a local, so the shape had to be spelled out again per path, which is the
  /// drift this class exists to prevent.
  static OpenAIClient client({
    required String? baseUrl,
    required String? apiKey,
    required ChatRequestShape shape,
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  }) => OpenAIClient.withApiKey(
    apiKey ?? ApiConstants.defaultApiKey,
    baseUrl: const LlmEndpointTransportPolicy().validate(
      baseUrl: baseUrl ?? ApiConstants.defaultBaseUrl,
      apiKey: apiKey ?? ApiConstants.defaultApiKey,
    ),
    defaultHeaders: ApiConstants.userAgentHeaders,
    httpClient: wrap(httpClient ?? http.Client(), shape, baseUrl: baseUrl),
    streamClientFactory: () => wrap(
      streamClientFactory?.call() ?? http.Client(),
      shape,
      baseUrl: baseUrl,
    ),
  );
}
