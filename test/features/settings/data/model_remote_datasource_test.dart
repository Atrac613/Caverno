import 'package:caverno/features/settings/data/model_remote_datasource.dart';
import 'package:caverno/core/constants/api_constants.dart';
import 'package:caverno/features/settings/domain/entities/local_model_lifecycle.dart';
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

  test('parses LM Studio managed model lifecycle state and metadata hints', () {
    final catalog =
        ModelRemoteDataSource.parseLmStudioManagedModelCatalogResponse({
          'models': [
            {
              'type': 'llm',
              'publisher': 'google',
              'key': 'google/gemma-4-26b-a4b',
              'params_string': '26B-A4B',
              'selected_variant': 'google/gemma-4-26b-a4b@q4_k_m',
              'quantization': {'name': 'Q4_K_M'},
              'loaded_instances': [
                {
                  'id': 'google/gemma-4-26b-a4b',
                  'config': {'context_length': 4096},
                },
              ],
            },
            {
              'type': 'llm',
              'publisher': 'deepseek',
              'key': 'deepseek-r1',
              'max_context_length': 131072,
              'loaded_instances': [],
            },
            {'type': 'embedding', 'publisher': 'gaianet', 'key': 'nomic-embed'},
          ],
        });

    expect(catalog.supported, isTrue);
    expect(catalog.models, [
      const LocalManagedModel(
        id: 'deepseek-r1',
        state: LocalModelLifecycleState.unloaded,
        statusValue: 'unloaded',
        ownedBy: 'deepseek',
        contextWindowTokens: 131072,
      ),
      const LocalManagedModel(
        id: 'google/gemma-4-26b-a4b',
        state: LocalModelLifecycleState.loaded,
        statusValue: 'loaded',
        ownedBy: 'google',
        contextWindowTokens: 4096,
        metadataHints: ['26B-A4B', 'google/gemma-4-26b-a4b@q4_k_m', 'Q4_K_M'],
      ),
    ]);
  });

  test('parses Ollama managed model lifecycle state and show metadata', () {
    final catalog =
        ModelRemoteDataSource.parseOllamaManagedModelCatalogResponse(
          tagsJson: {
            'models': [
              {
                'name': 'llama3.2:latest',
                'model': 'llama3.2:latest',
                'details': {
                  'family': 'llama',
                  'parameter_size': '3.2B',
                  'quantization_level': 'Q4_K_M',
                },
              },
              {
                'name': 'example/qwen2.5-coder:7b',
                'model': 'example/qwen2.5-coder:7b',
                'details': {
                  'family': 'qwen2',
                  'parameter_size': '7.6B',
                  'quantization_level': 'Q5_K_M',
                },
              },
            ],
          },
          runningJson: {
            'models': [
              {
                'name': 'llama3.2:latest',
                'model': 'llama3.2:latest',
                'context_length': 8192,
              },
            ],
          },
          showDetailsByModel: {
            'example/qwen2.5-coder:7b': {
              'parameters': 'temperature 0.7\nnum_ctx 32768',
              'model_info': {'qwen2.context_length': 32768},
              'details': {'format': 'gguf'},
            },
          },
        );

    expect(catalog.supported, isTrue);
    expect(catalog.models, [
      const LocalManagedModel(
        id: 'example/qwen2.5-coder:7b',
        state: LocalModelLifecycleState.unloaded,
        statusValue: 'unloaded',
        ownedBy: 'example',
        contextWindowTokens: 32768,
        metadataHints: [
          '7.6B',
          'Q5_K_M',
          'qwen2',
          'temperature 0.7\nnum_ctx 32768',
          'gguf',
        ],
      ),
      const LocalManagedModel(
        id: 'llama3.2:latest',
        state: LocalModelLifecycleState.loaded,
        statusValue: 'loaded',
        contextWindowTokens: 8192,
        metadataHints: ['3.2B', 'Q4_K_M', 'llama'],
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

  test('parses llama.cpp router managed model lifecycle state', () {
    final catalog =
        ModelRemoteDataSource.parseLlamaCppManagedModelCatalogResponse({
          'data': [
            {
              'id': 'zeta-model',
              'path': '/models/zeta.gguf',
              'owned_by': 'llamacpp',
              'status': {
                'value': 'loaded',
                'args': ['llama-server', '-ctx', '4096'],
              },
              'metadata': {'n_ctx': 4096},
            },
            {
              'id': 'alpha-model',
              'status': {'value': 'unloaded', 'failed': true, 'exit_code': 1},
            },
            {'id': 'middle-model', 'status': 'sleeping'},
          ],
        });

    expect(catalog.supported, isTrue);
    expect(catalog.models, [
      const LocalManagedModel(
        id: 'alpha-model',
        state: LocalModelLifecycleState.unloaded,
        statusValue: 'unloaded',
        failed: true,
        exitCode: 1,
      ),
      const LocalManagedModel(
        id: 'middle-model',
        state: LocalModelLifecycleState.sleeping,
        statusValue: 'sleeping',
      ),
      const LocalManagedModel(
        id: 'zeta-model',
        state: LocalModelLifecycleState.loaded,
        statusValue: 'loaded',
        path: '/models/zeta.gguf',
        ownedBy: 'llamacpp',
        contextWindowTokens: 4096,
        commandArguments: ['llama-server', '-ctx', '4096'],
      ),
    ]);
  });

  test(
    'uses NVIDIA NIM cloud catalog fallback when models route is unsupported',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/v1/models') {
          return http.Response('Not found', 404);
        }
        return http.Response('Unexpected request', 500);
      });

      final dataSource = ModelRemoteDataSource(
        baseUrl: '${ApiConstants.nvidiaNimBaseUrl}/',
        apiKey: 'nvapi-test-key',
        client: client,
      );

      final catalog = await dataSource.listModelCatalog();

      expect(
        catalog,
        contains(
          const ModelCatalogEntry(
            id: ApiConstants.nvidiaNimDefaultModel,
            ownedBy: 'nvidia',
          ),
        ),
      );
      expect(
        catalog,
        contains(
          const ModelCatalogEntry(id: 'openai/gpt-oss-120b', ownedBy: 'openai'),
        ),
      );
      expect(requests.map((uri) => uri.toString()), [
        'https://integrate.api.nvidia.com/v1/models',
      ]);
    },
  );

  test('does not use NVIDIA NIM catalog fallback without an API key', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('Not found', 404);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: ApiConstants.nvidiaNimBaseUrl,
      apiKey: ApiConstants.defaultApiKey,
      client: client,
    );

    await expectLater(dataSource.listModelCatalog(), throwsException);
    expect(requests.map((uri) => uri.toString()), [
      'https://integrate.api.nvidia.com/v1/models',
    ]);
  });

  test('does not mask NVIDIA NIM authorization failures', () async {
    final client = MockClient((request) async {
      return http.Response('Unauthorized', 401);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: ApiConstants.nvidiaNimBaseUrl,
      apiKey: 'nvapi-test-key',
      client: client,
    );

    await expectLater(dataSource.listModelCatalog(), throwsException);
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

  test('lists llama.cpp router managed models at native root', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers['Authorization'], 'Bearer no-key');
      return http.Response(
        '{"data":[{"id":"local-model","status":{"value":"loading"}}]}',
        200,
      );
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      client: client,
    );

    final catalog = await dataSource.listLlamaCppManagedModels(refresh: true);

    expect(catalog.supported, isTrue);
    expect(catalog.models, [
      const LocalManagedModel(
        id: 'local-model',
        state: LocalModelLifecycleState.loading,
        statusValue: 'loading',
      ),
    ]);
    expect(
      requests.single.url.toString(),
      'http://localhost:1234/models?reload=1',
    );
  });

  test(
    'lists managed models through the provider-neutral lifecycle API',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          '{"data":[{"id":"local-model","status":{"value":"loaded"}}]}',
          200,
        );
      });

      final dataSource = ModelRemoteDataSource(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'no-key',
        client: client,
      );

      final catalog = await dataSource.listManagedModels(refresh: true);

      expect(catalog.supported, isTrue);
      expect(catalog.models.single.id, 'local-model');
      expect(
        requests.single.url.toString(),
        'http://localhost:1234/models?reload=1',
      );
    },
  );

  test(
    'lists LM Studio managed models when llama.cpp router is unsupported',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/models') {
          return http.Response('not found', 404);
        }
        if (request.url.path == '/api/v1/models') {
          return http.Response(
            '{"models":[{"type":"llm","key":"lmstudio-model",'
            '"loaded_instances":[]}]}',
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final dataSource = ModelRemoteDataSource(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'no-key',
        client: client,
      );

      final catalog = await dataSource.listManagedModels();

      expect(catalog.supported, isTrue);
      expect(catalog.models.single.id, 'lmstudio-model');
      expect(requests.map((request) => request.url.path).toList(), [
        '/models',
        '/api/v1/models',
      ]);
    },
  );

  test(
    'lists Ollama managed models when earlier providers are unsupported',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/models') {
          return http.Response('not found', 404);
        }
        if (request.url.path == '/api/v1/models') {
          return http.Response('not found', 404);
        }
        if (request.url.path == '/api/tags') {
          return http.Response(
            '{"models":[{"name":"llama3.2:latest","model":"llama3.2:latest",'
            '"details":{"parameter_size":"3.2B","quantization_level":"Q4_K_M"}}]}',
            200,
          );
        }
        if (request.url.path == '/api/ps') {
          return http.Response(
            '{"models":[{"name":"llama3.2:latest",'
            '"model":"llama3.2:latest","context_length":8192}]}',
            200,
          );
        }
        if (request.url.path == '/api/show') {
          expect(request.body, '{"model":"llama3.2:latest"}');
          return http.Response(
            '{"model_info":{"llama.context_length":8192}}',
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final dataSource = ModelRemoteDataSource(
        baseUrl: 'http://localhost:11434/v1',
        apiKey: 'no-key',
        client: client,
      );

      final catalog = await dataSource.listManagedModels();

      expect(catalog.supported, isTrue);
      expect(catalog.models.single.id, 'llama3.2:latest');
      expect(catalog.models.single.state, LocalModelLifecycleState.loaded);
      expect(catalog.models.single.contextWindowTokens, 8192);
      expect(requests.map((request) => request.url.path).toList(), [
        '/models',
        '/api/v1/models',
        '/api/tags',
        '/api/ps',
        '/api/show',
      ]);
    },
  );

  test('loads managed models with model payload', () async {
    late http.Request recordedRequest;
    final client = MockClient((request) async {
      recordedRequest = request;
      return http.Response('{"success":true}', 200);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      client: client,
    );

    final result = await dataSource.loadManagedModel('local-model');

    expect(result.supported, isTrue);
    expect(result.succeeded, isTrue);
    expect(recordedRequest.method, 'POST');
    expect(recordedRequest.url.toString(), 'http://localhost:1234/models/load');
    expect(recordedRequest.headers['Content-Type'], 'application/json');
    expect(recordedRequest.body, '{"model":"local-model"}');
  });

  test('loads LM Studio models when llama.cpp router is unsupported', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/models/load') {
        return http.Response('not found', 404);
      }
      if (request.url.path == '/api/v1/models/load') {
        return http.Response('{"status":"loaded"}', 200);
      }
      return http.Response('not found', 404);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      client: client,
    );

    final result = await dataSource.loadManagedModel('lmstudio-model');

    expect(result.supported, isTrue);
    expect(result.succeeded, isTrue);
    expect(requests.map((request) => request.url.path).toList(), [
      '/models/load',
      '/api/v1/models/load',
    ]);
    expect(requests.last.body, '{"model":"lmstudio-model"}');
  });

  test('loads Ollama models when earlier providers are unsupported', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/models/load') {
        return http.Response('not found', 404);
      }
      if (request.url.path == '/api/v1/models/load') {
        return http.Response('not found', 404);
      }
      if (request.url.path == '/api/generate') {
        return http.Response(
          '{"model":"llama3.2:latest","response":"","done":true}',
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:11434/api',
      apiKey: 'no-key',
      client: client,
    );

    final result = await dataSource.loadManagedModel('llama3.2:latest');

    expect(result.supported, isTrue);
    expect(result.succeeded, isTrue);
    expect(requests.map((request) => request.url.path).toList(), [
      '/models/load',
      '/api/v1/models/load',
      '/api/generate',
    ]);
    expect(
      requests.last.body,
      '{"model":"llama3.2:latest","prompt":"","stream":false}',
    );
  });

  test(
    'unload returns no-op message when lifecycle endpoint is unsupported',
    () async {
      final client = MockClient((request) async {
        return http.Response(
          '{"error":{"message":"This server does not support models."}}',
          501,
        );
      });

      final dataSource = ModelRemoteDataSource(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'no-key',
        client: client,
      );

      final result = await dataSource.unloadManagedModel('local-model');

      expect(result.supported, isFalse);
      expect(result.succeeded, isFalse);
      expect(result.statusCode, 501);
      expect(result.message, contains('router mode'));
    },
  );

  test('unloads LM Studio instances with instance_id payload', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/models/unload') {
        return http.Response('not found', 404);
      }
      if (request.url.path == '/api/v1/models/unload') {
        return http.Response('{"instance_id":"lmstudio-model"}', 200);
      }
      return http.Response('not found', 404);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      client: client,
    );

    final result = await dataSource.unloadManagedModel('lmstudio-model');

    expect(result.supported, isTrue);
    expect(result.succeeded, isTrue);
    expect(requests.map((request) => request.url.path).toList(), [
      '/models/unload',
      '/api/v1/models/unload',
    ]);
    expect(requests.last.body, '{"instance_id":"lmstudio-model"}');
  });

  test('unloads Ollama models with keep alive zero payload', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/models/unload') {
        return http.Response('not found', 404);
      }
      if (request.url.path == '/api/v1/models/unload') {
        return http.Response('not found', 404);
      }
      if (request.url.path == '/api/generate') {
        return http.Response(
          '{"model":"llama3.2:latest","response":"","done":true,'
          '"done_reason":"unload"}',
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:11434/v1',
      apiKey: 'no-key',
      client: client,
    );

    final result = await dataSource.unloadManagedModel('llama3.2:latest');

    expect(result.supported, isTrue);
    expect(result.succeeded, isTrue);
    expect(requests.map((request) => request.url.path).toList(), [
      '/models/unload',
      '/api/v1/models/unload',
      '/api/generate',
    ]);
    expect(
      requests.last.body,
      '{"model":"llama3.2:latest","prompt":"","stream":false,"keep_alive":0}',
    );
  });

  test('pulls Ollama models with non-streaming payload', () async {
    late http.Request recordedRequest;
    final client = MockClient((request) async {
      recordedRequest = request;
      return http.Response('{"status":"success"}', 200);
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:11434/v1',
      apiKey: 'no-key',
      client: client,
    );

    final result = await dataSource.pullOllamaModel('llama3.2:latest');

    expect(result.supported, isTrue);
    expect(result.succeeded, isTrue);
    expect(recordedRequest.url.toString(), 'http://localhost:11434/api/pull');
    expect(recordedRequest.body, '{"model":"llama3.2:latest","stream":false}');
  });

  test('load surfaces llama.cpp router error messages', () async {
    final client = MockClient((request) async {
      return http.Response(
        '{"error":{"message":"model validation failed"}}',
        400,
      );
    });

    final dataSource = ModelRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      client: client,
    );

    final result = await dataSource.loadManagedModel('missing-model');

    expect(result.supported, isTrue);
    expect(result.succeeded, isFalse);
    expect(result.statusCode, 400);
    expect(result.message, 'model validation failed');
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
