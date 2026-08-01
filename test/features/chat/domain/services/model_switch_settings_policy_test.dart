import 'package:caverno/features/chat/domain/services/model_switch_settings_policy.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:test/test.dart';

const _policy = ModelSwitchSettingsPolicy();

AppSettings _settings({
  LlmProvider provider = LlmProvider.openAiCompatible,
  String baseUrl = 'http://localhost:1234/v1',
  String model = 'model-a',
  String apiKey = 'secret',
  bool demoMode = false,
  ReasoningEffortPreference reasoningEffort =
      ReasoningEffortPreference.automatic,
  bool enableLlmSessionLogs = true,
}) => AppSettings.defaults().copyWith(
  llmProvider: provider,
  baseUrl: baseUrl,
  model: model,
  apiKey: apiKey,
  demoMode: demoMode,
  reasoningEffort: reasoningEffort,
  enableLlmSessionLogs: enableLlmSessionLogs,
);

void main() {
  group('ModelSwitchSettingsPolicy route identity', () {
    test('returns exact unchanged OpenAI-compatible route IDs', () {
      final settings = _settings();

      final result = _policy.compare(previous: settings, next: settings);

      expect(
        result.previousRouteId,
        'openAiCompatible|http://localhost:1234/v1|model-a',
      );
      expect(result.nextRouteId, result.previousRouteId);
      expect(result.routeChanged, isFalse);
      expect(result.previousPrimaryModelForPreparation, isNull);
      expect(result.shouldRebuildDataSource, isFalse);
    });

    test('normalizes route URL and model whitespace exactly', () {
      final previous = _settings(
        baseUrl: '  HTTPS://Example.COM/V1/  ',
        model: '  Model-A  ',
      );
      final next = _settings(
        baseUrl: 'https://example.com/v1/',
        model: 'Model-A',
      );

      final result = _policy.compare(previous: previous, next: next);

      expect(
        result.previousRouteId,
        'openAiCompatible|https://example.com/v1/|Model-A',
      );
      expect(result.nextRouteId, result.previousRouteId);
      expect(result.routeChanged, isFalse);
      expect(result.shouldRebuildDataSource, isTrue);
    });

    test('preserves model case in route identity', () {
      final result = _policy.compare(
        previous: _settings(model: 'Model-A'),
        next: _settings(model: 'model-a'),
      );

      expect(
        result.previousRouteId,
        'openAiCompatible|http://localhost:1234/v1|Model-A',
      );
      expect(
        result.nextRouteId,
        'openAiCompatible|http://localhost:1234/v1|model-a',
      );
      expect(result.routeChanged, isTrue);
    });

    test('uses the exact Apple route independent of URL and model', () {
      final result = _policy.compare(
        previous: _settings(
          provider: LlmProvider.appleFoundationModels,
          baseUrl: 'http://unused-a',
          model: 'ignored-a',
        ),
        next: _settings(
          provider: LlmProvider.appleFoundationModels,
          baseUrl: 'http://unused-b',
          model: 'ignored-b',
        ),
      );

      expect(
        result.previousRouteId,
        'appleFoundationModels|apple-foundation-models://local|'
        'apple-foundation-models',
      );
      expect(result.nextRouteId, result.previousRouteId);
      expect(result.routeChanged, isFalse);
      expect(result.previousPrimaryModelForPreparation, isNull);
      expect(result.shouldRebuildDataSource, isTrue);
    });

    test('reports exact IDs for provider transitions', () {
      final result = _policy.compare(
        previous: _settings(),
        next: _settings(provider: LlmProvider.appleFoundationModels),
      );

      expect(
        result.previousRouteId,
        'openAiCompatible|http://localhost:1234/v1|model-a',
      );
      expect(
        result.nextRouteId,
        'appleFoundationModels|apple-foundation-models://local|'
        'apple-foundation-models',
      );
      expect(result.routeChanged, isTrue);
      expect(result.previousPrimaryModelForPreparation, isNull);
      expect(result.shouldRebuildDataSource, isTrue);
    });
  });

  group('ModelSwitchSettingsPolicy previous model preparation', () {
    test(
      'returns the trimmed previous model for a compatible model change',
      () {
        final result = _policy.compare(
          previous: _settings(model: '  model-a  '),
          next: _settings(model: ' model-b '),
        );

        expect(result.routeChanged, isTrue);
        expect(result.previousPrimaryModelForPreparation, 'model-a');
        expect(result.shouldRebuildDataSource, isFalse);
      },
    );

    test('allows raw URL and credential whitespace differences', () {
      final result = _policy.compare(
        previous: _settings(
          baseUrl: '  http://localhost:1234/v1  ',
          model: 'model-a',
          apiKey: '  secret  ',
        ),
        next: _settings(
          baseUrl: 'http://localhost:1234/v1',
          model: 'model-b',
          apiKey: 'secret',
        ),
      );

      expect(result.routeChanged, isTrue);
      expect(result.previousPrimaryModelForPreparation, 'model-a');
      expect(result.shouldRebuildDataSource, isTrue);
    });

    test('preserves every exclusion gate', () {
      final compatiblePrevious = _settings(model: 'model-a');
      final compatibleNext = _settings(model: 'model-b');
      final cases = <({String label, AppSettings previous, AppSettings next})>[
        (
          label: 'previous provider',
          previous: compatiblePrevious.copyWith(
            llmProvider: LlmProvider.appleFoundationModels,
          ),
          next: compatibleNext,
        ),
        (
          label: 'next provider',
          previous: compatiblePrevious,
          next: compatibleNext.copyWith(
            llmProvider: LlmProvider.appleFoundationModels,
          ),
        ),
        (
          label: 'previous demo',
          previous: compatiblePrevious.copyWith(demoMode: true),
          next: compatibleNext,
        ),
        (
          label: 'next demo',
          previous: compatiblePrevious,
          next: compatibleNext.copyWith(demoMode: true),
        ),
        (
          label: 'base URL',
          previous: compatiblePrevious,
          next: compatibleNext.copyWith(baseUrl: 'http://other-host:1234/v1'),
        ),
        (
          label: 'base URL case',
          previous: compatiblePrevious.copyWith(
            baseUrl: 'HTTP://LOCALHOST:1234/v1',
          ),
          next: compatibleNext,
        ),
        (
          label: 'API key',
          previous: compatiblePrevious,
          next: compatibleNext.copyWith(apiKey: 'other-secret'),
        ),
        (
          label: 'API key case',
          previous: compatiblePrevious,
          next: compatibleNext.copyWith(apiKey: 'SECRET'),
        ),
      ];

      for (final testCase in cases) {
        final result = _policy.compare(
          previous: testCase.previous,
          next: testCase.next,
        );

        expect(
          result.previousPrimaryModelForPreparation,
          isNull,
          reason: testCase.label,
        );
      }
    });

    test('rejects empty and unchanged normalized previous models', () {
      final cases = <({String label, AppSettings previous, AppSettings next})>[
        (
          label: 'empty previous',
          previous: _settings(model: '   '),
          next: _settings(model: 'model-b'),
        ),
        (
          label: 'same normalized model',
          previous: _settings(model: ' model-a '),
          next: _settings(model: 'model-a'),
        ),
      ];

      for (final testCase in cases) {
        final result = _policy.compare(
          previous: testCase.previous,
          next: testCase.next,
        );

        expect(
          result.previousPrimaryModelForPreparation,
          isNull,
          reason: testCase.label,
        );
      }
    });

    test('returns the previous model when the next model is empty', () {
      final result = _policy.compare(
        previous: _settings(model: 'model-a'),
        next: _settings(model: '   '),
      );

      expect(result.routeChanged, isTrue);
      expect(result.previousPrimaryModelForPreparation, 'model-a');
      expect(result.shouldRebuildDataSource, isFalse);
    });
  });

  group('ModelSwitchSettingsPolicy data-source rebuild matrix', () {
    test('rebuilds for each exact data-source field independently', () {
      final base = _settings();
      final cases =
          <
            ({
              String label,
              AppSettings previous,
              AppSettings next,
              bool routeChanged,
            })
          >[
            (
              label: 'demo enabled',
              previous: base,
              next: base.copyWith(demoMode: true),
              routeChanged: false,
            ),
            (
              label: 'demo disabled',
              previous: base.copyWith(demoMode: true),
              next: base,
              routeChanged: false,
            ),
            (
              label: 'provider',
              previous: base,
              next: base.copyWith(
                llmProvider: LlmProvider.appleFoundationModels,
              ),
              routeChanged: true,
            ),
            (
              label: 'base URL',
              previous: base,
              next: base.copyWith(baseUrl: 'http://other-host:1234/v1'),
              routeChanged: true,
            ),
            (
              label: 'API key',
              previous: base,
              next: base.copyWith(apiKey: 'other-secret'),
              routeChanged: false,
            ),
            (
              label: 'reasoning effort',
              previous: base,
              next: base.copyWith(
                reasoningEffort: ReasoningEffortPreference.low,
              ),
              routeChanged: false,
            ),
            (
              label: 'session logs',
              previous: base,
              next: base.copyWith(enableLlmSessionLogs: false),
              routeChanged: false,
            ),
          ];

      for (final testCase in cases) {
        final result = _policy.compare(
          previous: testCase.previous,
          next: testCase.next,
        );

        expect(result.shouldRebuildDataSource, isTrue, reason: testCase.label);
        expect(
          result.routeChanged,
          testCase.routeChanged,
          reason: testCase.label,
        );
      }
    });

    test('uses raw URL and API-key equality for rebuild decisions', () {
      final baseUrlWhitespace = _policy.compare(
        previous: _settings(baseUrl: ' http://localhost:1234/v1 '),
        next: _settings(baseUrl: 'http://localhost:1234/v1'),
      );
      final apiKeyWhitespace = _policy.compare(
        previous: _settings(apiKey: ' secret '),
        next: _settings(apiKey: 'secret'),
      );

      expect(baseUrlWhitespace.routeChanged, isFalse);
      expect(baseUrlWhitespace.shouldRebuildDataSource, isTrue);
      expect(apiKeyWhitespace.routeChanged, isFalse);
      expect(apiKeyWhitespace.shouldRebuildDataSource, isTrue);
    });

    test('does not rebuild for model or unrelated settings changes', () {
      final base = _settings();
      final cases =
          <
            ({
              String label,
              AppSettings next,
              bool routeChanged,
              String? previousModel,
            })
          >[
            (
              label: 'model',
              next: base.copyWith(model: 'model-b'),
              routeChanged: true,
              previousModel: 'model-a',
            ),
            (
              label: 'model whitespace',
              next: base.copyWith(model: ' model-a '),
              routeChanged: false,
              previousModel: null,
            ),
            (
              label: 'temperature',
              next: base.copyWith(temperature: 0.1),
              routeChanged: false,
              previousModel: null,
            ),
            (
              label: 'max tokens',
              next: base.copyWith(maxTokens: 2048),
              routeChanged: false,
              previousModel: null,
            ),
            (
              label: 'role model',
              next: base.copyWith(memoryExtractionModel: 'small-model'),
              routeChanged: false,
              previousModel: null,
            ),
            (
              label: 'MCP',
              next: base.copyWith(mcpEnabled: !base.mcpEnabled),
              routeChanged: false,
              previousModel: null,
            ),
            (
              label: 'active endpoint metadata',
              next: base.copyWith(activeLlmEndpointId: 'secondary'),
              routeChanged: false,
              previousModel: null,
            ),
          ];

      for (final testCase in cases) {
        final result = _policy.compare(previous: base, next: testCase.next);

        expect(result.shouldRebuildDataSource, isFalse, reason: testCase.label);
        expect(
          result.routeChanged,
          testCase.routeChanged,
          reason: testCase.label,
        );
        expect(
          result.previousPrimaryModelForPreparation,
          testCase.previousModel,
          reason: testCase.label,
        );
      }
    });

    test('keeps demo transitions out of route identity and preparation', () {
      final enabled = _policy.compare(
        previous: _settings(demoMode: false),
        next: _settings(demoMode: true),
      );
      final disabled = _policy.compare(
        previous: _settings(demoMode: true),
        next: _settings(demoMode: false),
      );

      for (final result in [enabled, disabled]) {
        expect(result.routeChanged, isFalse);
        expect(result.previousPrimaryModelForPreparation, isNull);
        expect(result.shouldRebuildDataSource, isTrue);
      }
    });
  });
}
