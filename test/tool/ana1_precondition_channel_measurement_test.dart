import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:test/test.dart';

import '../../tool/ana1_precondition_channel_measurement.dart';

/// The verdict for each shape is fixed here before any number is believed.
///
/// ANA0's own measurement was published three times with a defect each time,
/// every one found by reading raw responses rather than by reasoning about the
/// counts. The two that decide whether a number is honest — an unparseable
/// response and a response that talks about ordering without writing an edge —
/// must not be scored as "a model that wrote no edges".
String _proposal({required List<Map<String, dynamic>> tasks}) {
  return jsonEncode({'tasks': tasks});
}

ChannelObservation _score(
  ChannelArm arm,
  String raw, {
  String scenarioId = 'sync-after-audit',
  Set<String> contract = const <String>{},
}) {
  return scoreChannelResponse(
    scenarioId: scenarioId,
    arm: arm,
    repeat: 1,
    rawContent: raw,
    contractReferences: contract,
  );
}

void main() {
  group('the title channel', () {
    test('reads one edge per bracket group', () {
      final observation = _score(
        ChannelArm.title,
        _proposal(
          tasks: [
            {'title': 'Audit the local data model'},
            {
              'title':
                  'Write the sync engine [requires: task: Audit the local '
                  'data model] [requires: question: Which conflict policy?]',
            },
          ],
        ),
        contract: const {'Which conflict policy?'},
      );

      expect(observation.parsed, isTrue);
      expect(observation.taskCount, 2);
      expect(observation.edgeCount, 2);
      expect(
        observation.resolvedEdgeCount,
        2,
        reason:
            'Both edges name something the same plan contains, which is '
            'the difference between a graph and a decoration.',
      );
    });

    test('is not case sensitive about the marker', () {
      final observation = _score(
        ChannelArm.title,
        _proposal(
          tasks: [
            {'title': 'Audit the model'},
            {'title': 'Sync [REQUIRES: TASK: Audit the model]'},
          ],
        ),
      );

      expect(observation.edgeCount, 1);
    });

    test('an edge resolves against the contract, not the response', () {
      final observation = _score(
        ChannelArm.title,
        _proposal(
          tasks: [
            {'title': 'Sync [requires: assumption: Record ids are stable]'},
          ],
        ),
      );

      expect(
        observation.resolvedEdgeCount,
        0,
        reason:
            'With no contract supplied there is nothing for an assumption '
            'edge to point at; a response that resolved against its own '
            'invented text would be pointing at nothing the plan is bound by.',
      );
      expect(
        _score(
          ChannelArm.title,
          _proposal(
            tasks: [
              {'title': 'Sync [requires: assumption: Record ids are stable]'},
            ],
          ),
          contract: const {'Record ids are stable across devices'},
        ).resolvedEdgeCount,
        1,
      );
    });

    test('an edge naming nothing in the plan is counted but not resolved', () {
      final observation = _score(
        ChannelArm.title,
        _proposal(
          tasks: [
            {'title': 'Sync [requires: task: A task nobody planned]'},
          ],
        ),
      );

      expect(observation.edgeCount, 1);
      expect(
        observation.resolvedEdgeCount,
        0,
        reason:
            'Writing an edge and pointing it somewhere real are different '
            'abilities, and a channel that produces only the first is not one '
            'a scheduler can use.',
      );
    });

    test('an unknown kind is not an edge', () {
      final observation = _score(
        ChannelArm.title,
        _proposal(
          tasks: [
            {'title': 'Audit the model'},
            {'title': 'Sync [requires: dependency: Audit the model]'},
          ],
        ),
      );

      expect(observation.edgeCount, 0);
    });
  });

  group('the schema channel', () {
    test('reads the array of objects it asked for', () {
      final observation = _score(
        ChannelArm.schema,
        _proposal(
          tasks: [
            {'title': 'Audit the local data model', 'preconditions': const []},
            {
              'title': 'Write the sync engine',
              'preconditions': const [
                {'kind': 'task', 'ref': 'Audit the local data model'},
                {'kind': 'assumption', 'ref': 'The archive fits in memory'},
              ],
            },
          ],
        ),
        contract: const {'The archive fits in memory'},
      );

      expect(observation.edgeCount, 2);
      expect(observation.resolvedEdgeCount, 2);
    });

    test('an object flattened into a string still counts as the intent', () {
      final observation = _score(
        ChannelArm.schema,
        _proposal(
          tasks: [
            {'title': 'Audit the model'},
            {
              'title': 'Sync',
              'preconditions': const ['task: Audit the model'],
            },
          ],
        ),
      );

      expect(
        observation.edgeCount,
        1,
        reason:
            'Scoring the strict shape only would report a channel failure '
            'where the model in fact used the channel.',
      );
    });

    test('the title marker is not read in this arm', () {
      final observation = _score(
        ChannelArm.schema,
        _proposal(
          tasks: [
            {'title': 'Audit the model'},
            {'title': 'Sync [requires: task: Audit the model]'},
          ],
        ),
      );

      expect(
        observation.edgeCount,
        0,
        reason:
            'Each arm is scored through its own channel, or the comparison '
            'measures the union rather than the choice.',
      );
    });
  });

  group('the control arm', () {
    test('reads no edges even when the model writes them anyway', () {
      final observation = _score(
        ChannelArm.none,
        _proposal(
          tasks: [
            {'title': 'Audit the model'},
            {
              'title': 'Sync [requires: task: Audit the model]',
              'preconditions': const [
                {'kind': 'task', 'ref': 'Audit the model'},
              ],
            },
          ],
        ),
      );

      expect(observation.edgeCount, 0);
      expect(
        observation.mentionsWithoutEdge,
        isTrue,
        reason:
            'The control is what says whether an edge in another arm came '
            'from the instruction. That it wrote ordering prose anyway is the '
            'interesting part, and it has to be visible.',
      );
    });
  });

  group('numbers that would otherwise lie', () {
    test('an unparseable response is unscored, not an empty plan', () {
      final observation = _score(ChannelArm.title, 'I cannot plan this.');

      expect(observation.parsed, isFalse);
      expect(observation.failure, isNotNull);
      expect(
        observation.edgeCount,
        0,
        reason:
            'The count is zero either way; `parsed` is what stops it being '
            'averaged in as a model that declined to write edges.',
      );
    });

    test('a proposal with no tasks is unscored', () {
      final observation = _score(ChannelArm.title, _proposal(tasks: const []));

      expect(observation.parsed, isFalse);
      expect(observation.failure, contains('no tasks'));
    });

    test('a fenced response is read', () {
      final observation = _score(
        ChannelArm.title,
        '```json\n${_proposal(tasks: [
          {'title': 'Audit the model'},
          {'title': 'Sync [requires: task: Audit the model]'},
        ])}\n```',
      );

      expect(observation.parsed, isTrue);
      expect(observation.edgeCount, 1);
    });

    test('ordering prose with an edge is not flagged as a miss', () {
      final observation = _score(
        ChannelArm.title,
        _proposal(
          tasks: [
            {'title': 'Audit the model'},
            {
              'title': 'Sync [requires: task: Audit the model]',
              'notes': 'This depends on the audit.',
            },
          ],
        ),
      );

      expect(observation.mentionsWithoutEdge, isFalse);
    });
  });

  group('the arms differ only in their instruction', () {
    const scenario = ChannelScenario(id: 'probe', request: 'Plan the work.');

    test('the control adds nothing to the production prompt', () {
      expect(armInstruction(ChannelArm.none), isEmpty);
      expect(
        buildChannelPrompt(scenario: scenario, arm: ChannelArm.none),
        isNot(contains('requires')),
      );
    });

    test('each arm teaches a form its own extractor accepts', () {
      final titlePrompt = buildChannelPrompt(
        scenario: scenario,
        arm: ChannelArm.title,
      );
      expect(
        extractTitleEdges('Sync [requires: task: Audit]'),
        [
          const ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.task,
            ref: 'Audit',
          ),
        ],
        reason:
            'The prompt and the extractor are string literals in different '
            'places; nothing else relates them.',
      );
      expect(titlePrompt, contains('[requires: task: '));

      final schemaPrompt = buildChannelPrompt(
        scenario: scenario,
        arm: ChannelArm.schema,
      );
      expect(schemaPrompt, contains('"preconditions"'));
      expect(
        extractSchemaEdges(const {
          'preconditions': [
            {'kind': 'question', 'ref': 'Which policy?'},
          ],
        }),
        [
          const ConversationTaskPrecondition(
            kind: ConversationTaskPreconditionKind.question,
            ref: 'Which policy?',
          ),
        ],
      );
    });
  });
}
