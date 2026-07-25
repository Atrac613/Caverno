import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/model_catalog_entry.dart';
import 'package:caverno/features/settings/presentation/providers/model_context_window_resolver.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _probeRef = Provider<Ref>((ref) => ref);

AppSettings _settings({
  String model = 'executor-model',
  LlmProvider provider = LlmProvider.openAiCompatible,
}) {
  return AppSettings.defaults().copyWith(
    llmProvider: provider,
    baseUrl: 'http://localhost:1234/v1',
    apiKey: 'no-key',
    model: model,
  );
}

ModelListConfig _configFor(AppSettings settings) => ModelListConfig(
  baseUrl: settings.baseUrl,
  apiKey: settings.apiKey,
  selectedModelId: settings.effectiveModel,
);

ProviderContainer _container({
  required AppSettings settings,
  required Future<List<ModelCatalogEntry>> Function() catalog,
}) {
  return ProviderContainer(
    overrides: [
      modelCatalogProvider(
        _configFor(settings),
      ).overrideWith((ref) => catalog()),
    ],
  );
}

void main() {
  test('resolves the advertised context window for the active model', () async {
    final settings = _settings();
    final container = _container(
      settings: settings,
      catalog: () async => const [
        ModelCatalogEntry(id: 'other-model', contextWindowTokens: 8192),
        ModelCatalogEntry(id: 'executor-model', contextWindowTokens: 32768),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await resolveUsableContextTokens(container.read(_probeRef), settings),
      32768,
    );
  });

  test('stays unmeasured when the endpoint advertises no window', () async {
    final settings = _settings();
    final container = _container(
      settings: settings,
      catalog: () async => const [ModelCatalogEntry(id: 'executor-model')],
    );
    addTearDown(container.dispose);

    expect(
      await resolveUsableContextTokens(container.read(_probeRef), settings),
      0,
    );
  });

  test('a failing catalog fetch never fails the probe', () async {
    final settings = _settings();
    final container = _container(
      settings: settings,
      catalog: () async => throw Exception('endpoint unreachable'),
    );
    addTearDown(container.dispose);

    expect(
      await resolveUsableContextTokens(container.read(_probeRef), settings),
      0,
      reason: 'an unreachable endpoint must not block capability probing',
    );
  });

  test('skips the catalog for the Apple Foundation Models provider', () async {
    final settings = _settings(provider: LlmProvider.appleFoundationModels);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await resolveUsableContextTokens(container.read(_probeRef), settings),
      0,
      reason: 'the on-device provider has no model catalog to query',
    );
  });
}
