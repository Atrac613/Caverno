import 'dart:convert';

import 'package:caverno/core/constants/api_constants.dart';
import 'package:caverno/features/chat/data/datasources/qwen38_request_policy_client.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/services/qwen38_request_thinking_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Records the body the policy client actually put on the wire.
class _RecordingClient extends http.BaseClient {
  String? sentBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sentBody = (request as http.Request).body;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}

void main() {
  Future<Map<String, dynamic>> sendUnder(ModelUsageRole role) async {
    final delegate = _RecordingClient();
    final client = Qwen38RequestPolicyClient(
      delegate: delegate,
      policy: const Qwen38RequestThinkingPolicy(reasoningEffort: 'medium'),
    );
    final request =
        http.Request(
            'POST',
            Uri.parse('http://192.168.100.241:1234/v1/chat/completions'),
          )
          ..body = jsonEncode({
            'model': ApiConstants.qwen38VisionModel,
            'max_tokens': 1200,
          });

    await role.runWith(() => client.send(request));
    return jsonDecode(delegate.sentBody!) as Map<String, dynamic>;
  }

  test('a memory-extraction request reaches the wire without thinking', () async {
    final body = await sendUnder(ModelUsageRole.memoryExtraction);

    expect(
      (body['chat_template_kwargs'] as Map)['enable_thinking'],
      isFalse,
      reason: 'the role must survive the zone hop into the http client',
    );
    expect(body['max_tokens'], 1200);
  });

  test('a chat request keeps its thinking budget', () async {
    final body = await sendUnder(ModelUsageRole.chat);

    expect((body['chat_template_kwargs'] as Map)['enable_thinking'], isTrue);
    expect(
      body['max_tokens'],
      Qwen38RequestThinkingPolicy.mediumMinimumMaxTokens,
    );
  });
}
