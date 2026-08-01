import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/context_surgery_observation_accumulator.dart';
import 'package:caverno/features/chat/domain/services/context_surgery_observation_service.dart';
import 'package:test/test.dart';

void main() {
  group('ContextSurgeryObservationAccumulator', () {
    late ContextSurgeryObservationAccumulator accumulator;

    setUp(() {
      accumulator = ContextSurgeryObservationAccumulator();
    });

    test('an empty first update preserves the empty snapshot', () {
      final result = accumulator.apply(
        owner: _owner('owner-a', 1),
        update: ContextSurgeryObservationUpdate(),
      );

      expect(result.owner, _owner('owner-a', 1));
      expect(result.snapshot, ContextSurgeryObservationSnapshot.empty);
      expect(result.changed, isFalse);
    });

    test('partial updates preserve earlier inputs for the same owner', () {
      final owner = _owner('owner-a', 1);
      final promptResult = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(
          systemPrompt: '<repo_map>lib/main.dart</repo_map>',
        ),
      );
      final toolResult = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(
          toolResults: [_result(name: 'read_file', result: 'file contents')],
        ),
      );

      expect(promptResult.changed, isTrue);
      expect(
        toolResult.snapshot.section(ContextSurgeryBlockKind.systemPrompt),
        isNotNull,
      );
      expect(
        toolResult.snapshot.section(ContextSurgeryBlockKind.repoMap),
        isNotNull,
      );
      expect(
        toolResult.snapshot.section(ContextSurgeryBlockKind.fileReadToolResult),
        isNotNull,
      );
      expect(
        promptResult.snapshot.section(
          ContextSurgeryBlockKind.fileReadToolResult,
        ),
        isNull,
        reason: 'previous immutable snapshots must not gain later sections',
      );
    });

    test('explicit empty values clear every retained observation', () {
      final owner = _owner('owner-a', 1);
      accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(
          systemPrompt: '<repo_map>lib/main.dart</repo_map>',
          toolResults: [_result(name: 'read_file', result: 'contents')],
          toolDefinitions: [_definition('external_search')],
          mcpToolNames: const {'external_search'},
        ),
      );

      final cleared = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(
          systemPrompt: '',
          toolResults: const [],
          toolDefinitions: const [],
          mcpToolNames: const {},
        ),
      );
      final omitted = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(),
      );

      expect(cleared.snapshot, ContextSurgeryObservationSnapshot.empty);
      expect(cleared.changed, isTrue);
      expect(omitted.snapshot, ContextSurgeryObservationSnapshot.empty);
      expect(omitted.changed, isFalse);
    });

    test('changed follows projected snapshot equality', () {
      final owner = _owner('owner-a', 1);
      final first = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(systemPrompt: 'abcd'),
      );
      final equalProjection = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(systemPrompt: 'wxyz'),
      );
      final changedProjection = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(systemPrompt: 'longer'),
      );

      expect(first.changed, isTrue);
      expect(equalProjection.changed, isFalse);
      expect(changedProjection.changed, isTrue);
    });

    test('projects the exact observation service result', () {
      final owner = _owner('owner-a', 1);
      final results = [
        _result(name: 'read_file', result: 'first'),
        _result(name: 'local_execute_command', result: 'verified'),
      ];
      final definitions = [
        _definition('read_file'),
        _definition('external_search'),
      ];
      final update = ContextSurgeryObservationUpdate(
        systemPrompt: '<agents_md>Follow AGENTS.md</agents_md>',
        toolResults: results,
        toolDefinitions: definitions,
        mcpToolNames: const {'external_search'},
      );

      final actual = accumulator.apply(owner: owner, update: update).snapshot;
      final expected = ContextSurgeryObservationService.buildSnapshot(
        systemPrompt: '<agents_md>Follow AGENTS.md</agents_md>',
        toolResults: results,
        toolDefinitions: definitions,
        mcpToolNames: const {'external_search'},
      );

      expect(actual, expected);
      expect(
        actual.section(ContextSurgeryBlockKind.mcpToolSchema)?.blockCount,
        1,
      );
      expect(
        actual.section(ContextSurgeryBlockKind.systemToolSchema)?.blockCount,
        1,
      );
    });

    test('copies nested result and definition inputs defensively', () {
      final owner = _owner('owner-a', 1);
      final firstArguments = <String, dynamic>{
        'path': 'lib/a.dart',
        'metadata': <String, dynamic>{
          'parts': <Object?>['original'],
        },
      };
      final secondArguments = <String, dynamic>{'path': 'lib/a.dart'};
      final function = <String, dynamic>{
        'name': 'original_tool',
        'parameters': <String, dynamic>{
          'required': <Object?>['path'],
        },
      };
      final definition = <String, dynamic>{
        'type': 'function',
        'function': function,
      };
      final mcpNames = <String>{'original_tool'};

      final first = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(
          toolResults: [
            _result(arguments: firstArguments, result: 'older'),
            _result(arguments: secondArguments, result: 'newer'),
          ],
          toolDefinitions: [definition],
          mcpToolNames: mcpNames,
        ),
      );
      firstArguments['path'] = 'lib/changed.dart';
      (firstArguments['metadata'] as Map<String, dynamic>)['parts'] = [
        'changed',
      ];
      secondArguments['path'] = 'lib/other.dart';
      function['name'] = 'changed_tool';
      (function['parameters'] as Map<String, dynamic>)['required'] = ['other'];
      mcpNames
        ..clear()
        ..add('changed_tool');
      final rebuilt = accumulator.apply(
        owner: owner,
        update: ContextSurgeryObservationUpdate(systemPrompt: 'prompt'),
      );

      expect(first.snapshot.staleToolResultCandidateCount, 1);
      expect(rebuilt.snapshot.staleToolResultCandidateCount, 1);
      expect(
        rebuilt.snapshot.section(ContextSurgeryBlockKind.mcpToolSchema)?.label,
        'MCP tools',
      );
      expect(
        rebuilt.snapshot.section(ContextSurgeryBlockKind.systemToolSchema),
        isNull,
      );
      expect(
        () => rebuilt.snapshot.sections.add(
          const ContextSurgerySectionSummary(
            kind: ContextSurgeryBlockKind.memory,
            label: 'memory',
            blockCount: 1,
            charCount: 1,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('freezes collection inputs when the update is created', () {
      final arguments = <String, dynamic>{
        'path': 'lib/original.dart',
        'metadata': <String, dynamic>{
          'parts': <Object?>['original'],
          'flags': <Object?>['safe'],
          'labels': <String, dynamic>{'primary': 'one'},
        },
      };
      final definition = _definition('original_tool');
      final names = <String>{'original_tool'};
      final results = <ToolResultInfo>[
        _result(arguments: arguments, result: 'result'),
      ];
      final definitions = <Map<String, dynamic>>[definition];
      final update = ContextSurgeryObservationUpdate(
        toolResults: results,
        toolDefinitions: definitions,
        mcpToolNames: names,
      );

      results.clear();
      definitions.clear();
      arguments['path'] = 'lib/changed.dart';
      (arguments['metadata'] as Map<String, dynamic>)['parts'] = ['changed'];
      ((arguments['metadata'] as Map<String, dynamic>)['flags']
              as List<Object?>)
          .add('changed');
      ((arguments['metadata'] as Map<String, dynamic>)['labels']
              as Map<String, dynamic>)['secondary'] =
          'two';
      (definition['function'] as Map<String, dynamic>)['name'] = 'changed_tool';
      names
        ..clear()
        ..add('changed_tool');

      expect(update.toolResults!.single.arguments['path'], 'lib/original.dart');
      expect(
        (update.toolResults!.single.arguments['metadata']
            as Map<String, dynamic>)['parts'],
        ['original'],
      );
      expect(
        (update.toolResults!.single.arguments['metadata']
            as Map<String, dynamic>)['flags'],
        ['safe'],
      );
      expect(
        (update.toolResults!.single.arguments['metadata']
            as Map<String, dynamic>)['labels'],
        {'primary': 'one'},
      );
      expect(
        (update.toolDefinitions!.single['function']
            as Map<String, dynamic>)['name'],
        'original_tool',
      );
      expect(update.mcpToolNames, {'original_tool'});
      expect(
        () => update.toolResults!.add(_result(result: 'other')),
        throwsUnsupportedError,
      );
      expect(
        () => update.toolResults!.single.arguments['path'] = 'late',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((update.toolResults!.single.arguments['metadata']
                        as Map<String, dynamic>)['parts']
                    as List<Object?>)
                .add('late'),
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((update.toolResults!.single.arguments['metadata']
                        as Map<String, dynamic>)['flags']
                    as List<Object?>)
                .add('late'),
        throwsUnsupportedError,
      );
      expect(
        () => update.toolDefinitions!.add(_definition('other')),
        throwsUnsupportedError,
      );
      expect(
        () =>
            (update.toolDefinitions!.single['function']
                    as Map<String, dynamic>)['name'] =
                'late',
        throwsUnsupportedError,
      );
      expect(() => update.mcpToolNames!.add('other'), throwsUnsupportedError);
    });

    test('rejects non-JSON result and definition snapshots', () {
      for (final invalidValue in <Object?>[
        <Object?>{'owner-a'},
        <Object?, Object?>{7: 'owner-a'},
        double.infinity,
      ]) {
        expect(
          () => ContextSurgeryObservationUpdate(
            toolResults: [
              _result(arguments: {'invalid': invalidValue}, result: 'result'),
            ],
          ),
          throwsArgumentError,
          reason: 'result ${invalidValue.runtimeType}',
        );
        expect(
          () => ContextSurgeryObservationUpdate(
            toolDefinitions: [
              {'invalid': invalidValue},
            ],
          ),
          throwsArgumentError,
          reason: 'definition ${invalidValue.runtimeType}',
        );
      }
    });

    test('does not combine observations from two conversations', () {
      final ownerA = _owner('owner-a', 1);
      final ownerB = _owner('visible-b', 1);

      accumulator.apply(
        owner: ownerA,
        update: ContextSurgeryObservationUpdate(
          systemPrompt: '<repo_map>owner A map</repo_map>',
        ),
      );
      final ownerBResult = accumulator.apply(
        owner: ownerB,
        update: ContextSurgeryObservationUpdate(
          toolResults: [_result(name: 'read_file', result: 'owner B file')],
        ),
      );

      expect(
        ownerBResult.snapshot.section(ContextSurgeryBlockKind.repoMap),
        isNull,
      );
      expect(
        accumulator
            .snapshotFor(ownerA)
            .section(ContextSurgeryBlockKind.fileReadToolResult),
        isNull,
      );
    });

    test('does not combine generations of the same conversation', () {
      final generationOne = _owner('owner-a', 1);
      final generationTwo = _owner('owner-a', 2);

      accumulator.apply(
        owner: generationOne,
        update: ContextSurgeryObservationUpdate(
          systemPrompt: '<repo_map>generation one</repo_map>',
        ),
      );
      final generationTwoResult = accumulator.apply(
        owner: generationTwo,
        update: ContextSurgeryObservationUpdate(
          toolDefinitions: [_definition('generation_two_tool')],
        ),
      );

      expect(
        generationTwoResult.snapshot.section(ContextSurgeryBlockKind.repoMap),
        isNull,
      );
      expect(
        accumulator
            .snapshotFor(generationOne)
            .section(ContextSurgeryBlockKind.repoMap),
        isNotNull,
      );
      expect(
        accumulator
            .snapshotFor(generationOne)
            .section(ContextSurgeryBlockKind.systemToolSchema),
        isNull,
      );
    });

    test('removeOwner clears exactly one generation', () {
      final generationOne = _owner('owner-a', 1);
      final generationTwo = _owner('owner-a', 2);
      accumulator.apply(
        owner: generationOne,
        update: ContextSurgeryObservationUpdate(systemPrompt: 'one'),
      );
      accumulator.apply(
        owner: generationTwo,
        update: ContextSurgeryObservationUpdate(systemPrompt: 'two'),
      );

      expect(accumulator.removeOwner(generationOne), isTrue);
      expect(accumulator.removeOwner(generationOne), isFalse);
      expect(
        accumulator.snapshotFor(generationOne),
        ContextSurgeryObservationSnapshot.empty,
      );
      expect(accumulator.snapshotFor(generationTwo).hasData, isTrue);

      final reused = accumulator.apply(
        owner: generationOne,
        update: ContextSurgeryObservationUpdate(
          toolDefinitions: [_definition('fresh_tool')],
        ),
      );
      expect(
        reused.snapshot.section(ContextSurgeryBlockKind.systemPrompt),
        isNull,
      );
      expect(
        reused.snapshot.section(ContextSurgeryBlockKind.systemToolSchema),
        isNotNull,
      );
    });

    test('clearConversation removes every generation for only that thread', () {
      final ownerA1 = _owner('owner-a', 1);
      final ownerA2 = _owner('owner-a', 2);
      final ownerB = _owner('owner-b', 1);
      for (final owner in [ownerA1, ownerA2, ownerB]) {
        accumulator.apply(
          owner: owner,
          update: ContextSurgeryObservationUpdate(
            systemPrompt: owner.toString(),
          ),
        );
      }

      expect(accumulator.clearConversation('owner-a'), 2);
      expect(
        accumulator.snapshotFor(ownerA1),
        ContextSurgeryObservationSnapshot.empty,
      );
      expect(
        accumulator.snapshotFor(ownerA2),
        ContextSurgeryObservationSnapshot.empty,
      );
      expect(accumulator.snapshotFor(ownerB).hasData, isTrue);
      expect(accumulator.clearConversation('missing'), 0);
    });

    test('clear discards every owner snapshot', () {
      final ownerA = _owner('owner-a', 1);
      final ownerB = _owner('owner-b', 1);
      accumulator.apply(
        owner: ownerA,
        update: ContextSurgeryObservationUpdate(systemPrompt: 'a'),
      );
      accumulator.apply(
        owner: ownerB,
        update: ContextSurgeryObservationUpdate(systemPrompt: 'b'),
      );

      accumulator.clear();

      expect(
        accumulator.snapshotFor(ownerA),
        ContextSurgeryObservationSnapshot.empty,
      );
      expect(
        accumulator.snapshotFor(ownerB),
        ContextSurgeryObservationSnapshot.empty,
      );
    });
  });
}

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

ToolResultInfo _result({
  String name = 'read_file',
  Map<String, dynamic>? arguments,
  required String result,
}) => ToolResultInfo(
  id: '$name-${result.hashCode}',
  name: name,
  arguments: arguments ?? <String, dynamic>{'path': 'lib/a.dart'},
  result: result,
);

Map<String, dynamic> _definition(String name) => {
  'type': 'function',
  'function': <String, dynamic>{
    'name': name,
    'parameters': <String, dynamic>{'type': 'object'},
  },
};
