import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/pro_reasoning_candidate_endpoint_resolver.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  const resolver = ProReasoningCandidateEndpointResolver();

  test('anchors the selected endpoint and preserves peer models', () {
    final targets = resolver.resolve(
      settings: _settings(),
      selectedEndpointOnly: false,
    );

    expect(targets.map((target) => target.endpointId), [
      'xai',
      'local',
      'peer',
    ]);
    expect(targets.map((target) => target.model), [
      'grok-role-model',
      'local-model',
      'peer-model',
    ]);
  });

  test('restricts candidates to the selected endpoint when requested', () {
    final targets = resolver.resolve(
      settings: _settings(),
      selectedEndpointOnly: true,
    );

    expect(targets, hasLength(1));
    expect(targets.single.endpointId, 'xai');
    expect(targets.single.model, 'grok-role-model');
  });

  test('falls back to the primary endpoint for a stale selection', () {
    final targets = resolver.resolve(
      settings: _settings().copyWith(
        proReasoningEndpointId: 'missing',
        proReasoningModel: '',
      ),
      selectedEndpointOnly: true,
    );

    expect(targets, hasLength(1));
    expect(targets.single.endpointId, 'local');
    expect(targets.single.model, 'local-model');
  });

  test('deduplicates endpoints by normalized base URL', () {
    final settings = _settings();
    final targets = resolver.resolve(
      settings: settings.copyWith(
        llmEndpoints: [
          ...settings.llmEndpoints,
          const LlmEndpoint(
            id: 'duplicate-xai',
            baseUrl: 'https://api.x.ai/v1/',
            apiKey: 'xai-key',
            model: 'duplicate-model',
          ),
        ],
      ),
      selectedEndpointOnly: false,
    );

    expect(
      targets.where((target) => target.baseUrl == 'https://api.x.ai/v1'),
      hasLength(1),
    );
  });

  test('supports legacy settings without registered endpoints', () {
    const settings = AppSettings(
      baseUrl: 'http://localhost:1234/v1',
      model: 'legacy-model',
      apiKey: 'no-key',
      temperature: 0.7,
      maxTokens: 4096,
      proReasoningModel: 'legacy-reasoning-model',
    );

    final targets = resolver.resolve(
      settings: settings,
      selectedEndpointOnly: false,
    );

    expect(targets, hasLength(1));
    expect(targets.single.endpointId, AppSettings.seededLlmEndpointId);
    expect(targets.single.model, 'legacy-reasoning-model');
  });
}

AppSettings _settings() => const AppSettings(
  baseUrl: 'http://localhost:1234/v1',
  model: 'local-model',
  apiKey: 'no-key',
  temperature: 0.7,
  maxTokens: 4096,
  llmEndpoints: [
    LlmEndpoint(
      id: 'local',
      label: 'Local',
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      model: 'local-model',
    ),
    LlmEndpoint(
      id: 'xai',
      label: 'x.ai',
      baseUrl: 'https://api.x.ai/v1',
      apiKey: 'xai-key',
      model: 'grok-endpoint-model',
    ),
    LlmEndpoint(
      id: 'peer',
      label: 'Peer',
      baseUrl: 'http://peer:1234/v1',
      apiKey: 'no-key',
      model: 'peer-model',
    ),
  ],
  activeLlmEndpointId: 'local',
  proReasoningEndpointId: 'xai',
  proReasoningModel: 'grok-role-model',
);
