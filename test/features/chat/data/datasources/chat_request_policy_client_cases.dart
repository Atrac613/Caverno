part of 'chat_data_datasources_tiny_test.dart';

/// Records the body the policy client actually put on the wire.
class _RecordingClient extends http.BaseClient {
  String? sentBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sentBody = (request as http.Request).body;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}

void _runChatRequestPolicyClient() {
  test(
    'explicit thinking reaches streaming and non-streaming requests',
    () async {
      for (final stream in [true, false]) {
        for (final enabled in [true, false]) {
          final delegate = _RecordingClient();
          final client = ChatRequestPolicyClient(
            delegate: delegate,
            policy: ChatRequestThinkingPolicy(
              enableThinking: enabled,
              acceptsChatTemplateKwargs: true,
            ),
          );
          final request = http.Request(
            'POST',
            Uri.parse('http://localhost/v1/chat/completions'),
          )..body = jsonEncode({'model': 'custom-model', 'stream': stream});
          await client.send(request);
          final body = jsonDecode(delegate.sentBody!) as Map<String, dynamic>;
          expect(body['chat_template_kwargs'], {'enable_thinking': enabled});
          expect(body['stream'], stream);
          client.close();
        }
      }
    },
  );

  test(
    'explicit thinking stays off the wire for an endpoint not opted in',
    () async {
      final delegate = _RecordingClient();
      final client = ChatRequestPolicyClient(
        delegate: delegate,
        policy: const ChatRequestThinkingPolicy(enableThinking: true),
      );
      final request = http.Request(
        'POST',
        Uri.parse('https://api.example.com/v1/chat/completions'),
      )..body = jsonEncode({'model': 'gpt-6-luna', 'stream': true});
      await client.send(request);
      final body = jsonDecode(delegate.sentBody!) as Map<String, dynamic>;
      expect(body.containsKey('chat_template_kwargs'), isFalse);
      expect(body.containsKey('enable_thinking'), isFalse);
      client.close();
    },
  );

  Future<Map<String, dynamic>> sendUnder(ModelUsageRole role) async {
    final delegate = _RecordingClient();
    final client = ChatRequestPolicyClient(
      delegate: delegate,
      // Opted in because suppression is now decided by the role plus the
      // endpoint's opt-in, with no model name in it. What this case proves is
      // unchanged: that the role survives the zone hop into the http client.
      policy: const ChatRequestThinkingPolicy(
        reasoningEffort: 'medium',
        acceptsChatTemplateKwargs: true,
      ),
    );
    final request =
        http.Request(
            'POST',
            Uri.parse('http://192.168.100.241:1234/v1/chat/completions'),
          )
          ..body = jsonEncode({
            'model': ApiConstants.qwen38VisionModel,
            'max_tokens': 1200,
            'reasoning_effort': 'medium',
          });

    await role.runWith(() => client.send(request));
    return jsonDecode(delegate.sentBody!) as Map<String, dynamic>;
  }

  test(
    'a memory-extraction request reaches the wire without thinking',
    () async {
      final body = await sendUnder(ModelUsageRole.memoryExtraction);

      expect(
        (body['chat_template_kwargs'] as Map)['enable_thinking'],
        isFalse,
        reason: 'the role must survive the zone hop into the http client',
      );
      expect(body['max_tokens'], 1200);
    },
  );

  test('a chat request keeps its thinking budget', () async {
    final body = await sendUnder(ModelUsageRole.chat);

    expect((body['chat_template_kwargs'] as Map)['enable_thinking'], isTrue);
    expect(
      body['max_tokens'],
      ChatRequestThinkingPolicy.mediumMinimumMaxTokens,
    );
  });

  Future<Map<String, dynamic>> sendEffortRequest(String? wireEffort) async {
    final delegate = _RecordingClient();
    final client = ChatRequestPolicyClient(
      delegate: delegate,
      policy: const ChatRequestThinkingPolicy(reasoningEffort: 'high'),
    );
    final request =
        http.Request(
            'POST',
            Uri.parse('http://192.168.100.241:1234/v1/chat/completions'),
          )
          ..body = jsonEncode({
            'model': 'qwen3.8-27b-exl3',
            'reasoning_effort': ?wireEffort,
          });
    await client.send(request);
    client.close();
    return jsonDecode(delegate.sentBody!) as Map<String, dynamic>;
  }

  test('the template effort follows the effort the request carries', () async {
    final body = await sendEffortRequest('high');

    expect((body['chat_template_kwargs'] as Map)['reasoning_effort'], 'high');
  });

  test(
    'a retry without reasoning_effort drops it from the template too',
    () async {
      // qwen3.8-27b-exl3's template 400s on `high`. The datasource retries
      // without the top-level field; had the kwargs kept the configured
      // effort, the retry would have been rejected identically.
      final body = await sendEffortRequest(null);

      expect(
        (body['chat_template_kwargs'] as Map).containsKey('reasoning_effort'),
        isFalse,
      );
      expect(body.containsKey('reasoning_effort'), isFalse);
    },
  );

  test('the reasoning log line reports the controls as sent', () {
    expect(
      ChatRequestPolicyClient.reasoningControlsLogLine({
        'enable_thinking': true,
        'max_tokens': 1536,
        'chat_template_kwargs': {
          'enable_thinking': true,
          'reasoning_effort': 'xhigh',
        },
      }),
      '[LLM] reasoning: thinking=on, effort=xhigh (chat_template_kwargs), '
      'max_tokens=1536',
    );
    expect(
      ChatRequestPolicyClient.reasoningControlsLogLine({
        'reasoning_effort': 'high',
      }),
      '[LLM] reasoning: thinking=default, effort=high (top-level), '
      'max_tokens=default',
    );
    expect(
      ChatRequestPolicyClient.reasoningControlsLogLine({
        'max_tokens': 512,
        'chat_template_kwargs': {'enable_thinking': false},
      }),
      '[LLM] reasoning: thinking=off, effort=default, max_tokens=512',
    );
  });
}
