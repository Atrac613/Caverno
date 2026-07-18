import 'package:caverno/features/settings/data/model_metadata_parser.dart';
import 'package:caverno/features/settings/data/model_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model metadata behavior', () {
    test('prefers root context metadata before nested containers', () {
      expect(
        ModelMetadataParser.readContextWindowTokens({
          'context_length': 4096,
          'metadata': {'maxModelLen': 8192},
          'capabilities': {'n_ctx': 16384},
        }),
        4096,
      );
      expect(
        ModelMetadataParser.readContextWindowTokens({
          'metadata': {'maxModelLen': 32768},
          'capabilities': {'n_ctx': 65536},
        }),
        32768,
      );
    });

    test('coerces supported positive numeric metadata only', () {
      expect(ModelMetadataParser.parsePositiveInt(4096), 4096);
      expect(ModelMetadataParser.parsePositiveInt(4095.6), 4096);
      expect(ModelMetadataParser.parsePositiveInt(' 8192 '), 8192);
      expect(ModelMetadataParser.parsePositiveInt('8192.0'), isNull);
      expect(ModelMetadataParser.parsePositiveInt(0), isNull);
      expect(ModelMetadataParser.parsePositiveInt(-1), isNull);
      expect(ModelMetadataParser.parsePositiveInt(double.infinity), isNull);
    });

    test('normalizes LM Studio model IDs and ignores blank IDs', () {
      expect(ModelMetadataParser.normalizeModelId(null), isNull);
      expect(ModelMetadataParser.normalizeModelId('   '), isNull);
      expect(
        ModelMetadataParser.normalizeModelId('  selected-model  '),
        'selected-model',
      );

      final catalog = ModelRemoteDataSource.parseLmStudioModelCatalogResponse({
        'models': [
          {'key': '  selected-model  ', 'type': 'llm'},
          {'key': '   ', 'type': 'llm'},
          {
            'key': 'downloaded-model',
            'type': 'llm',
            'loaded_instances': [
              {'id': '  loaded-model  '},
              {'id': ''},
            ],
          },
        ],
      });

      expect(catalog.map((entry) => entry.id), [
        'downloaded-model',
        'loaded-model',
        'selected-model',
      ]);
    });

    test('prefers the selected LM Studio loaded instance context', () {
      final catalog = ModelRemoteDataSource.parseLmStudioModelCatalogResponse({
        'models': [
          {
            'key': 'downloaded-model',
            'type': 'llm',
            'max_context_length': 131072,
            'loaded_instances': [
              {
                'id': 'first-instance',
                'config': {'context_length': 4096},
              },
              {
                'id': 'selected-instance',
                'config': {'context_length': 8192},
              },
            ],
          },
        ],
      }, selectedModelId: '  selected-instance  ');
      final tokensById = {
        for (final entry in catalog) entry.id: entry.contextWindowTokens,
      };

      expect(tokensById['downloaded-model'], 8192);
      expect(tokensById['first-instance'], 4096);
      expect(tokensById['selected-instance'], 8192);
    });

    test('falls back when the selected loaded instance has no context', () {
      final loadedInstances = [
        {
          'id': 'first-instance',
          'config': {'context_length': 4096},
        },
        {'id': 'selected-instance'},
      ];
      expect(
        ModelMetadataParser.readSelectedLmStudioLoadedContext(
          loadedInstances,
          'selected-instance',
        ),
        isNull,
      );
      expect(
        ModelMetadataParser.readFirstLmStudioLoadedContext(loadedInstances),
        4096,
      );

      final catalog = ModelRemoteDataSource.parseLmStudioModelCatalogResponse({
        'models': [
          {
            'key': 'downloaded-model',
            'type': 'llm',
            'max_context_length': 131072,
            'loaded_instances': [
              {
                'id': 'first-instance',
                'config': {'context_length': 4096},
              },
              {'id': 'selected-instance'},
            ],
          },
        ],
      }, selectedModelId: 'selected-instance');
      final downloaded = catalog.singleWhere(
        (entry) => entry.id == 'downloaded-model',
      );

      expect(downloaded.contextWindowTokens, 4096);
    });

    test('returns model-level context when loaded instances are malformed', () {
      expect(
        ModelMetadataParser.readSelectedLmStudioLoadedContext({
          'id': 'not-a-list',
        }, 'not-a-list'),
        isNull,
      );
      expect(
        ModelMetadataParser.readFirstLmStudioLoadedContext('not-a-list'),
        isNull,
      );

      final catalog = ModelRemoteDataSource.parseLmStudioModelCatalogResponse({
        'models': [
          {
            'key': 'downloaded-model',
            'type': 'llm',
            'max_context_length': '32768',
            'loaded_instances': {'id': 'not-a-list'},
          },
        ],
      }, selectedModelId: 'not-a-list');

      expect(catalog.single.contextWindowTokens, 32768);
    });

    test('requires one consistent context across llama.cpp slots', () {
      expect(
        ModelRemoteDataSource.parseLlamaCppSlotsContextWindowTokens([
          {'id': 0, 'n_ctx': 16384},
          {'id': 1, 'n_ctx': 16384},
          'malformed',
        ]),
        16384,
      );
      expect(
        ModelRemoteDataSource.parseLlamaCppSlotsContextWindowTokens([
          {'id': 0, 'n_ctx': 16384},
          {'id': 1, 'n_ctx': 32768},
        ]),
        isNull,
      );
      expect(
        ModelRemoteDataSource.parseLlamaCppSlotsContextWindowTokens(
          'not-a-list',
        ),
        isNull,
      );
    });
  });
}
