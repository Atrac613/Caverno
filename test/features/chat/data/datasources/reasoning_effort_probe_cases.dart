part of 'chat_data_datasources_tiny_test.dart';

void _runReasoningEffortProbe() {
  const candidates = ['low', 'medium', 'high', 'xhigh'];

  Future<(ReasoningEffortProbeResult, List<Map<String, dynamic>>)> probe({
    required String model,
    required int Function(Map<String, dynamic> body) statusFor,
    bool acceptsChatTemplateKwargs = false,
  }) async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      bodies.add(body);
      return http.Response('{}', statusFor(body));
    });
    final result = await const ReasoningEffortProbe().run(
      baseUrl: 'http://192.168.100.241:1234/v1',
      apiKey: 'no-key',
      model: model,
      acceptsChatTemplateKwargs: acceptsChatTemplateKwargs,
      candidates: candidates,
      client: client,
    );
    return (result, bodies);
  }

  String? templateEffort(Map<String, dynamic> body) =>
      (body['chat_template_kwargs'] as Map?)?['reasoning_effort'] as String?;

  test('reads a template vocabulary from 400s, as the app sends it', () async {
    // qwen3.8-27b-exl3, measured 2026-09-24: its template raises on `high`.
    final (result, bodies) = await probe(
      model: 'qwen3.8-27b-exl3',
      acceptsChatTemplateKwargs: true,
      statusFor: (body) => templateEffort(body) == 'high' ? 400 : 200,
    );

    expect(result.outcome, ReasoningEffortProbeResult.validatedOutcome);
    expect(result.accepted, ['low', 'medium', 'xhigh']);
    expect(bodies.map(templateEffort), [null, ...candidates]);
    expect(
      bodies.map((body) => body['max_tokens']),
      everyElement(1),
      reason: 'the policy thinking floor must not turn probes into generations',
    );
  });

  test('claims nothing when no effort is refused', () async {
    final (result, _) = await probe(
      model: 'gpt-compatible',
      statusFor: (_) => 200,
    );

    expect(result.outcome, ReasoningEffortProbeResult.unvalidatedOutcome);
    expect(result.accepted, isNull);
  });

  test('a refused baseline makes a candidate 400 meaningless', () async {
    final (result, bodies) = await probe(
      model: 'gpt-compatible',
      statusFor: (_) => 400,
    );

    expect(result.isConclusive, isFalse);
    expect(bodies, hasLength(1));
  });

  test(
    'a non-400 failure stops the probe instead of reading as a no',
    () async {
      final (result, _) = await probe(
        model: 'gpt-compatible',
        statusFor: (body) => body['reasoning_effort'] == 'medium' ? 503 : 200,
      );

      expect(result.isConclusive, isFalse);
      expect(result.accepted, isNull);
    },
  );
}
