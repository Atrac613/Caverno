import 'package:caverno/features/settings/data/model_remote_datasource.dart';
import 'package:caverno/features/settings/domain/entities/model_catalog_entry.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('extracts explicit context window fields from raw model metadata', () {
    final catalog = ModelRemoteDataSource.parseModelCatalogResponse({
      'object': 'list',
      'data': [
        {'id': 'zeta-model', 'owned_by': 'local', 'context_length': 1000000},
        {
          'id': 'alpha-model',
          'ownedBy': 'provider',
          'metadata': {'maxModelLen': '131072'},
        },
        {
          'id': 'middle-model',
          'capabilities': {'n_ctx': 32768.0},
        },
      ],
    });

    expect(catalog, [
      const ModelCatalogEntry(
        id: 'alpha-model',
        ownedBy: 'provider',
        contextWindowTokens: 131072,
      ),
      const ModelCatalogEntry(id: 'middle-model', contextWindowTokens: 32768),
      const ModelCatalogEntry(
        id: 'zeta-model',
        ownedBy: 'local',
        contextWindowTokens: 1000000,
      ),
    ]);
  });

  test('leaves context window unknown when metadata is absent', () {
    final catalog = ModelRemoteDataSource.parseModelCatalogResponse({
      'object': 'list',
      'data': [
        {'id': 'plain-model', 'owned_by': 'local', 'max_tokens': 4096},
      ],
    });

    expect(catalog, [
      const ModelCatalogEntry(id: 'plain-model', ownedBy: 'local'),
    ]);
    expect(catalog.single.contextWindowTokens, isNull);
  });

  test('extracts LM Studio loaded instance context metadata', () {
    final catalog = ModelRemoteDataSource.parseLmStudioModelCatalogResponse({
      'models': [
        {
          'key': 'downloaded-model',
          'type': 'llm',
          'publisher': 'local',
          'max_context_length': 131072,
          'loaded_instances': [
            {
              'id': 'loaded-model',
              'config': {'context_length': 65536},
            },
          ],
        },
        {
          'key': 'embedding-model',
          'type': 'embedding',
          'max_context_length': 8192,
        },
      ],
    });

    expect(catalog, [
      const ModelCatalogEntry(
        id: 'downloaded-model',
        ownedBy: 'local',
        contextWindowTokens: 65536,
      ),
      const ModelCatalogEntry(
        id: 'loaded-model',
        ownedBy: 'local',
        contextWindowTokens: 65536,
      ),
    ]);
  });

  test('extracts llama.cpp context metadata from props and slots', () {
    expect(
      ModelRemoteDataSource.parseLlamaCppPropsContextWindowTokens({
        'default_generation_settings': {'n_ctx': 32768},
      }),
      32768,
    );
    expect(
      ModelRemoteDataSource.parseLlamaCppSlotsContextWindowTokens([
        {'id': 0, 'n_ctx': 16384},
        {'id': 1, 'n_ctx': 16384},
      ]),
      16384,
    );
  });

  test('enriches catalog with LM Studio native metadata fallback', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/v1/models') {
        return http.Response(
          '{"data":[{"id":"loaded-model","owned_by":"local"}]}',
          200,
        );
      }
      if (request.url.path == '/api/v1/models') {
        return http.Response(
          '{"models":[{"key":"downloaded-model","type":"llm",'
          '"publisher":"local","max_context_length":131072,'
          '"loaded_instances":[{"id":"loaded-model",'
          '"config":{"context_length":65536}}]}]}',
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      client: client,
    );

    final catalog = await dataSource.listModelCatalog(
      selectedModelId: 'loaded-model',
    );

    expect(catalog, [
      const ModelCatalogEntry(
        id: 'loaded-model',
        ownedBy: 'local',
        contextWindowTokens: 65536,
      ),
    ]);
    expect(requests.map((uri) => uri.toString()), [
      'http://localhost:1234/v1/models',
      'http://localhost:1234/api/v1/models',
    ]);
  });

  test('enriches catalog with llama.cpp props metadata fallback', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.path == '/v1/models') {
        return http.Response('{"data":[{"id":"local-model"}]}', 200);
      }
      if (request.url.path == '/props' &&
          request.url.queryParameters['model'] == 'local-model') {
        return http.Response(
          '{"default_generation_settings":{"n_ctx":32768}}',
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      client: client,
    );

    final catalog = await dataSource.listModelCatalog(
      selectedModelId: 'local-model',
    );

    expect(catalog, [
      const ModelCatalogEntry(id: 'local-model', contextWindowTokens: 32768),
    ]);
    expect(requests.map((uri) => uri.toString()), [
      'http://localhost:1234/v1/models',
      'http://localhost:1234/api/v1/models',
      'http://localhost:1234/props?model=local-model',
    ]);
  });

  test(
    'modelListProvider keeps the existing sorted id list behavior',
    () async {
      const config = ModelListConfig(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'no-key',
      );
      final container = ProviderContainer(
        overrides: [
          modelCatalogProvider(config).overrideWith(
            (ref) async => const [
              ModelCatalogEntry(id: 'zeta-model', contextWindowTokens: 1000000),
              ModelCatalogEntry(id: 'alpha-model', contextWindowTokens: 131072),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);

      final ids = await container.read(modelListProvider(config).future);

      expect(ids, ['alpha-model', 'zeta-model']);
    },
  );
}
