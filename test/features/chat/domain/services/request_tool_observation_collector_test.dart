import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/request_tool_observation_collector.dart';
import 'package:test/test.dart';

const _collector = RequestToolObservationCollector();

Map<String, dynamic> _definition(
  String name, {
  String description = 'Tool definition',
}) {
  return <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'description': description,
      'parameters': <String, dynamic>{
        'type': 'object',
        'required': <String>['query'],
      },
    },
  };
}

RequestToolCatalogSnapshot _catalog({
  McpConnectionStatus connectionStatus = McpConnectionStatus.connected,
  List<Map<String, dynamic>>? definitions,
  List<Map<String, dynamic>>? externalDescriptors,
}) {
  return RequestToolCatalogSnapshot(
    connectionStatus: connectionStatus,
    toolDefinitions:
        definitions ?? [_definition('read_file'), _definition('remote_search')],
    externalToolDescriptors:
        externalDescriptors ?? [_definition('remote_search')],
  );
}

RequestToolObservationInput _input({
  RequestToolCatalogSnapshot? catalog,
  bool includeCatalog = true,
  bool hasToolNamesOverride = false,
  Iterable<String> effectiveToolNames = const <String>[],
  bool mcpEnabled = true,
  bool hasTemporalReferenceContext = false,
}) {
  return RequestToolObservationInput(
    catalog: includeCatalog ? (catalog ?? _catalog()) : null,
    hasToolNamesOverride: hasToolNamesOverride,
    effectiveToolNames: effectiveToolNames,
    mcpEnabled: mcpEnabled,
    hasTemporalReferenceContext: hasTemporalReferenceContext,
  );
}

List<Object?> _definitionNames(RequestToolObservation observation) {
  return observation.definitions
      .map((definition) => (definition['function'] as Map)['name'])
      .toList();
}

void main() {
  group('observation enablement', () {
    test('returns empty observations without a catalog snapshot', () {
      final observation = _collector.collect(
        _input(
          includeCatalog: false,
          hasToolNamesOverride: true,
          effectiveToolNames: const ['read_file'],
          hasTemporalReferenceContext: true,
        ),
      );

      expect(observation.definitions, isEmpty);
      expect(observation.mcpNames, isEmpty);
    });

    test(
      'returns empty observations when every activation source is absent',
      () {
        final observation = _collector.collect(
          _input(
            hasToolNamesOverride: false,
            mcpEnabled: false,
            hasTemporalReferenceContext: false,
          ),
        );

        expect(observation.definitions, isEmpty);
        expect(observation.mcpNames, isEmpty);
      },
    );

    test('accepts each activation source independently', () {
      final cases =
          <
            ({
              String name,
              bool hasOverride,
              bool mcpEnabled,
              bool hasTemporalContext,
              List<String> effectiveNames,
              List<String> expectedDefinitions,
            })
          >[
            (
              name: 'override presence',
              hasOverride: true,
              mcpEnabled: false,
              hasTemporalContext: false,
              effectiveNames: const ['read_file'],
              expectedDefinitions: const ['read_file'],
            ),
            (
              name: 'MCP enabled',
              hasOverride: false,
              mcpEnabled: true,
              hasTemporalContext: false,
              effectiveNames: const [],
              expectedDefinitions: const ['read_file', 'remote_search'],
            ),
            (
              name: 'temporal context presence',
              hasOverride: false,
              mcpEnabled: false,
              hasTemporalContext: true,
              effectiveNames: const [],
              expectedDefinitions: const ['read_file', 'remote_search'],
            ),
          ];

      for (final testCase in cases) {
        final observation = _collector.collect(
          _input(
            hasToolNamesOverride: testCase.hasOverride,
            effectiveToolNames: testCase.effectiveNames,
            mcpEnabled: testCase.mcpEnabled,
            hasTemporalReferenceContext: testCase.hasTemporalContext,
          ),
        );

        expect(
          _definitionNames(observation),
          testCase.expectedDefinitions,
          reason: testCase.name,
        );
      }
    });
  });

  group('override observation', () {
    test(
      'observes the full catalog without advertising plan-drafting tools',
      () {
        final advertisedNames = <String>[];

        final observation = _collector.collect(
          _input(
            hasToolNamesOverride: false,
            effectiveToolNames: advertisedNames,
          ),
        );

        expect(_definitionNames(observation), ['read_file', 'remote_search']);
        expect(advertisedNames, isEmpty);
      },
    );

    test('preserves the full catalog shape when no override is present', () {
      final malformedFunction = <String, dynamic>{'function': 'malformed'};
      final missingFunction = <String, dynamic>{'unexpected': true};

      final observation = _collector.collect(
        _input(
          catalog: _catalog(
            definitions: [
              malformedFunction,
              _definition('read_file'),
              missingFunction,
            ],
          ),
          hasToolNamesOverride: false,
        ),
      );

      expect(observation.definitions, hasLength(3));
      expect(observation.definitions[0]['function'], 'malformed');
      expect(
        (observation.definitions[1]['function'] as Map)['name'],
        'read_file',
      );
      expect(observation.definitions[2]['unexpected'], isTrue);
    });

    test(
      'treats an empty override as present and filters every definition',
      () {
        final observation = _collector.collect(
          _input(
            hasToolNamesOverride: true,
            effectiveToolNames: const [],
            mcpEnabled: false,
          ),
        );

        expect(observation.definitions, isEmpty);
        expect(observation.mcpNames, {'remote_search'});
      },
    );

    test(
      'filters exact names while preserving definition order and duplicates',
      () {
        final catalog = _catalog(
          definitions: [
            _definition('beta', description: 'first beta'),
            <String, dynamic>{'function': 'malformed'},
            _definition('alpha'),
            <String, dynamic>{
              'function': <String, dynamic>{'name': 7},
            },
            _definition('beta', description: 'second beta'),
            _definition('gamma'),
            _definition(''),
          ],
        );

        final observation = _collector.collect(
          _input(
            catalog: catalog,
            hasToolNamesOverride: true,
            effectiveToolNames: const ['alpha', 'beta', ''],
          ),
        );

        expect(_definitionNames(observation), ['beta', 'alpha', 'beta', '']);
        expect(
          (observation.definitions.first['function'] as Map)['description'],
          'first beta',
        );
        expect(
          (observation.definitions[2]['function'] as Map)['description'],
          'second beta',
        );
      },
    );

    test('uses exact case-sensitive names without normalization', () {
      final observation = _collector.collect(
        _input(
          catalog: _catalog(
            definitions: [_definition('read_file'), _definition(' Read_File ')],
          ),
          hasToolNamesOverride: true,
          effectiveToolNames: const ['read_file'],
        ),
      );

      expect(_definitionNames(observation), ['read_file']);
    });
  });

  group('external MCP names', () {
    test('collects valid connected names in first-seen order', () {
      final catalog = _catalog(
        externalDescriptors: [
          _definition('remote_b'),
          <String, dynamic>{'function': <Object?>[]},
          _definition(''),
          _definition('remote_a'),
          _definition('remote_b'),
          <String, dynamic>{
            'function': <String, dynamic>{'name': 9},
          },
          _definition(' '),
        ],
      );

      final observation = _collector.collect(_input(catalog: catalog));

      expect(observation.mcpNames.toList(), ['remote_b', 'remote_a', ' ']);
    });

    test('returns no external names for every non-connected status', () {
      for (final status in [
        McpConnectionStatus.disconnected,
        McpConnectionStatus.connecting,
        McpConnectionStatus.error,
      ]) {
        final observation = _collector.collect(
          _input(catalog: _catalog(connectionStatus: status)),
        );

        expect(observation.mcpNames, isEmpty, reason: status.name);
      }
    });

    test('does not filter connected names with the definition override', () {
      final observation = _collector.collect(
        _input(
          catalog: _catalog(
            definitions: [_definition('remote_a'), _definition('remote_b')],
            externalDescriptors: [
              _definition('remote_a'),
              _definition('remote_b'),
            ],
          ),
          hasToolNamesOverride: true,
          effectiveToolNames: const ['remote_a'],
          mcpEnabled: false,
        ),
      );

      expect(_definitionNames(observation), ['remote_a']);
      expect(observation.mcpNames.toList(), ['remote_a', 'remote_b']);
    });
  });

  group('request-owner isolation', () {
    test('retains no observation between sequential owner snapshots', () {
      final ownerA = _input(
        catalog: _catalog(
          definitions: [_definition('owner_a'), _definition('shared')],
          externalDescriptors: [_definition('owner_a_remote')],
        ),
        hasToolNamesOverride: true,
        effectiveToolNames: const ['owner_a'],
        mcpEnabled: false,
      );
      final ownerB = _input(
        catalog: _catalog(
          definitions: [_definition('owner_b'), _definition('shared')],
          externalDescriptors: [_definition('owner_b_remote')],
        ),
        hasToolNamesOverride: true,
        effectiveToolNames: const ['owner_b'],
        mcpEnabled: false,
      );

      final firstOwnerAObservation = _collector.collect(ownerA);
      final inactiveObservation = _collector.collect(
        _input(
          catalog: _catalog(
            definitions: [_definition('poison')],
            externalDescriptors: [_definition('poison_remote')],
          ),
          hasToolNamesOverride: false,
          mcpEnabled: false,
          hasTemporalReferenceContext: false,
        ),
      );
      final ownerBObservation = _collector.collect(ownerB);
      final secondOwnerAObservation = _collector.collect(ownerA);

      expect(_definitionNames(firstOwnerAObservation), ['owner_a']);
      expect(firstOwnerAObservation.mcpNames, {'owner_a_remote'});
      expect(inactiveObservation.definitions, isEmpty);
      expect(inactiveObservation.mcpNames, isEmpty);
      expect(_definitionNames(ownerBObservation), ['owner_b']);
      expect(ownerBObservation.mcpNames, {'owner_b_remote'});
      expect(_definitionNames(secondOwnerAObservation), ['owner_a']);
      expect(secondOwnerAObservation.mcpNames, {'owner_a_remote'});
    });
  });

  group('immutable snapshots', () {
    test('freezes source definitions, descriptors, and effective names', () {
      final requiredNames = <String>['query'];
      final rawMetadata = <String, dynamic>{
        'primary': <Object?>['stable'],
      };
      final rawTags = <String>['stable'];
      final function = <String, dynamic>{
        'name': 'read_file',
        'parameters': <String, dynamic>{'required': requiredNames},
      };
      final definition = <String, dynamic>{
        'type': 'function',
        'function': function,
        'raw_metadata': rawMetadata,
        'raw_tags': rawTags,
      };
      final descriptorFunction = <String, dynamic>{'name': 'remote_search'};
      final descriptor = <String, dynamic>{'function': descriptorFunction};
      final definitions = <Map<String, dynamic>>[definition];
      final descriptors = <Map<String, dynamic>>[descriptor];
      final effectiveNames = <String>['read_file'];
      final catalog = RequestToolCatalogSnapshot(
        connectionStatus: McpConnectionStatus.connected,
        toolDefinitions: definitions,
        externalToolDescriptors: descriptors,
      );
      final input = _input(
        catalog: catalog,
        hasToolNamesOverride: true,
        effectiveToolNames: effectiveNames,
      );

      definitions.clear();
      descriptors.clear();
      function['name'] = 'changed';
      descriptorFunction['name'] = 'changed_remote';
      requiredNames.add('path');
      (rawMetadata['primary']! as List<Object?>).add('changed');
      rawTags.add('changed');
      effectiveNames
        ..clear()
        ..add('changed');

      final observation = _collector.collect(input);

      expect(_definitionNames(observation), ['read_file']);
      expect(observation.mcpNames, {'remote_search'});
      expect(
        (((observation.definitions.single['function'] as Map)['parameters']
                as Map)['required']
            as List),
        ['query'],
      );
      expect(
        (observation.definitions.single['raw_metadata'] as Map)['primary'],
        ['stable'],
      );
      expect(observation.definitions.single['raw_tags'], ['stable']);
      expect(input.effectiveToolNames, ['read_file']);
    });

    test('rejects non-JSON catalog values', () {
      for (final invalidValue in <Object?>[
        <Object?>{'owner-a'},
        <Object?, Object?>{7: 'owner-a'},
        double.nan,
      ]) {
        expect(
          () => RequestToolCatalogSnapshot(
            connectionStatus: McpConnectionStatus.connected,
            toolDefinitions: [
              {'invalid': invalidValue},
            ],
            externalToolDescriptors: const [],
          ),
          throwsArgumentError,
          reason: invalidValue.runtimeType.toString(),
        );
      }
    });

    test('exposes only unmodifiable observation collections', () {
      final observation = _collector.collect(_input());

      expect(
        () => observation.definitions.add(_definition('write_file')),
        throwsUnsupportedError,
      );
      expect(
        () => observation.definitions.first['type'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () =>
            (((observation.definitions.first['function'] as Map)['parameters']
                        as Map)['required']
                    as List)
                .add('path'),
        throwsUnsupportedError,
      );
      expect(
        () => observation.mcpNames.add('changed_remote'),
        throwsUnsupportedError,
      );
    });
  });
}
