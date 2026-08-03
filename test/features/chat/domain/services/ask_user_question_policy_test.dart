import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_policy.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_turn_cache.dart';
import 'package:caverno/features/chat/domain/services/tool_terminal_response_policy.dart';
import 'package:test/test.dart';

final _ownerA = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);
final _ownerB = ChatTurnOwner(
  conversationId: 'conversation-b',
  interactionGeneration: 7,
);
final _ownerANext = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 8,
);

AskUserQuestionOperationIdentity _identity({
  ChatTurnOwner? owner,
  String toolCallId = 'question-call-a',
}) {
  return AskUserQuestionOperationIdentity(
    owner: owner ?? _ownerA,
    toolCallId: toolCallId,
    toolName: askUserQuestionToolName,
  );
}

final class _QuestionCall {
  const _QuestionCall({required this.identity, required this.request});

  final AskUserQuestionOperationIdentity identity;
  final AskUserQuestionRequest request;

  ChatTurnOwner get owner => identity.owner;
}

final class _RecordingQuestionPort implements AskUserQuestionPort {
  final List<_QuestionCall> calls = [];
  final Map<AskUserQuestionOperationIdentity, AskUserQuestionPortResult>
  responses = {};
  final Map<
    AskUserQuestionOperationIdentity,
    Completer<AskUserQuestionPortResult>
  >
  pending = {};
  final List<Object> mutationErrors = [];
  Object? error;
  bool attemptRequestMutation = false;

  @override
  Future<AskUserQuestionPortResult> ask(
    AskUserQuestionOperationIdentity identity,
    AskUserQuestionRequest request,
  ) async {
    calls.add(_QuestionCall(identity: identity, request: request));
    if (attemptRequestMutation) {
      try {
        request.options.add(
          const AskUserQuestionOption(id: 'poison', label: 'Poison'),
        );
      } catch (error) {
        mutationErrors.add(error);
      }
    }
    final portError = error;
    if (portError != null) throw portError;
    final pendingResult = pending[identity];
    if (pendingResult != null) return pendingResult.future;
    return responses[identity] ??
        AskUserQuestionPortResult(identity: identity, answer: null);
  }
}

final class _Fixture {
  _Fixture({AskUserQuestionTurnCache? cache, _RecordingQuestionPort? port})
    : cache = cache ?? AskUserQuestionTurnCache(),
      port = port ?? _RecordingQuestionPort() {
    policy = AskUserQuestionPolicy(
      port: this.port,
      cache: this.cache,
      terminalResponsePolicy: _terminalResponsePolicy(),
    );
  }

  final AskUserQuestionTurnCache cache;
  final _RecordingQuestionPort port;
  late final AskUserQuestionPolicy policy;
}

ToolTerminalResponsePolicy _terminalResponsePolicy() {
  return ToolTerminalResponsePolicy(
    looksLikeUnexecutedToolRequest: (_) => false,
    looksLikePlanOnlyFinalToolAnswer: (_) => false,
    looksLikePendingToolActionResponse: (_) => false,
    looksLikeStructuredToolRequest: (_) => false,
    containsAnyCodeUnitSequence: (_, _) => false,
    containsCjkBlockerMarker: (_) => false,
    containsCjkMissingEvidenceMarker: (_) => false,
  );
}

AskUserQuestionToolInput _input({
  ChatTurnOwner? owner,
  String toolCallId = 'question-call-a',
  String toolName = askUserQuestionToolName,
  Map<String, dynamic> arguments = const {'question': 'Choose a target?'},
  ConversationWorkflowTask? savedTask,
}) {
  return AskUserQuestionToolInput(
    owner: owner ?? _ownerA,
    toolCallId: toolCallId,
    toolName: toolName,
    arguments: arguments,
    savedTask: savedTask,
  );
}

AskUserQuestionAnswer _answer(
  String question,
  String id,
  String label, {
  String otherText = '',
}) {
  return AskUserQuestionAnswer(
    question: question,
    selectedOptions: [AskUserQuestionSelection(id: id, label: label)],
    otherText: otherText,
  );
}

Map<String, dynamic> _payload(McpToolResult result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}

void main() {
  group('AskUserQuestionPolicy invocation identity', () {
    test('requires an exact non-empty canonical tool invocation', () {
      expect(
        () => _input(toolCallId: '   '),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'toolCallId',
          ),
        ),
      );
      expect(
        () => _input(toolName: 'custom_question'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'toolName',
          ),
        ),
      );
    });

    test('compares owner, tool call, and canonical tool name', () {
      final identity = _identity();
      final input = _input();

      expect(identity, _identity());
      expect(identity.hashCode, _identity().hashCode);
      expect(identity, isNot(_identity(owner: _ownerB)));
      expect(identity, isNot(_identity(toolCallId: 'question-call-b')));
      expect(input.toolCallId, 'question-call-a');
    });
  });

  group('AskUserQuestionPolicy validation', () {
    test('returns the exact failure for a missing question', () async {
      for (final arguments in const <Map<String, dynamic>>[
        {},
        {'question': null},
        {'question': ''},
        {'question': '   '},
      ]) {
        final fixture = _Fixture();

        final result = await fixture.policy.handle(
          _input(arguments: arguments),
        );

        expect(result.toolName, askUserQuestionToolName);
        expect(result.result, '');
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, 'question is required');
        expect(fixture.port.calls, isEmpty);
        expect(fixture.cache.anyResult(_ownerA, (_) => true), isFalse);
      }
    });

    test('preserves malformed string argument failures', () async {
      final fixture = _Fixture();

      await expectLater(
        fixture.policy.handle(_input(arguments: const {'question': 17})),
        throwsA(isA<TypeError>()),
      );

      expect(fixture.port.calls, isEmpty);
    });

    test(
      'uses exact request defaults and trims presentation strings',
      () async {
        final fixture = _Fixture();

        await fixture.policy.handle(
          _input(
            arguments: const {
              'question': '  Which target?  ',
              'help': '  Pick one.  ',
              'options': 'not-a-list',
              'other_placeholder': '  Enter another target  ',
            },
          ),
        );

        final call = fixture.port.calls.single;
        expect(call.owner, _ownerA);
        expect(call.identity.toolCallId, 'question-call-a');
        expect(call.identity.toolName, askUserQuestionToolName);
        expect(call.request.question, 'Which target?');
        expect(call.request.help, 'Pick one.');
        expect(call.request.options, isEmpty);
        expect(call.request.allowMultiple, isFalse);
        expect(call.request.allowOther, isTrue);
        expect(call.request.otherPlaceholder, 'Enter another target');
      },
    );

    test('requires either one option or allow_other', () async {
      final fixture = _Fixture();

      final result = await fixture.policy.handle(
        _input(
          arguments: const {
            'question': 'Choose?',
            'options': [],
            'allow_other': false,
          },
        ),
      );

      expect(result.result, '');
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'at least one option or allow_other is required',
      );
      expect(fixture.port.calls, isEmpty);
    });

    test('preserves invalid boolean failures', () async {
      for (final arguments in const [
        {'question': 'Choose?', 'allow_other': 'yes'},
        {
          'question': 'Choose?',
          'options': ['A'],
          'allow_multiple': 'yes',
        },
      ]) {
        final fixture = _Fixture();

        await expectLater(
          fixture.policy.handle(_input(arguments: arguments)),
          throwsA(isA<TypeError>()),
        );

        expect(fixture.port.calls, isEmpty);
      }
    });
  });

  group('AskUserQuestionPolicy option parsing', () {
    test(
      'parses strings, maps, fallback IDs, and skips invalid entries',
      () async {
        final fixture = _Fixture();

        await fixture.policy.handle(
          _input(
            arguments: const {
              'question': 'Choose?',
              'options': [
                '  Alpha Choice  ',
                {
                  'id': '  explicit-id  ',
                  'label': '  Beta Choice  ',
                  'description': '  Why beta  ',
                  'preview': '  beta preview  ',
                },
                42,
                null,
                '',
                {'label': '   '},
                {'label': '  Fallback Choice  '},
              ],
            },
          ),
        );

        final options = fixture.port.calls.single.request.options;
        expect(options, hasLength(3));
        expect(
          options
              .map(
                (option) => [
                  option.id,
                  option.label,
                  option.description,
                  option.preview,
                ],
              )
              .toList(),
          [
            ['alpha-choice', 'Alpha Choice', '', ''],
            ['explicit-id', 'Beta Choice', 'Why beta', 'beta preview'],
            ['fallback-choice', 'Fallback Choice', '', ''],
          ],
        );
        expect(
          () => options.add(
            const AskUserQuestionOption(id: 'other', label: 'Other'),
          ),
          throwsUnsupportedError,
        );
      },
    );

    test('returns no options for every non-list representation', () {
      final fixture = _Fixture();

      for (final rawOptions in [
        null,
        'Alpha',
        const {'label': 'Alpha'},
        7,
        true,
      ]) {
        expect(fixture.policy.parseOptions(rawOptions), isEmpty);
      }
    });

    test('preserves malformed map field failures', () {
      final fixture = _Fixture();

      for (final rawOption in const [
        {'label': 7},
        {'label': 'Alpha', 'id': 7},
        {'label': 'Alpha', 'description': 7},
        {'label': 'Alpha', 'preview': 7},
      ]) {
        expect(
          () => fixture.policy.parseOptions([rawOption]),
          throwsA(isA<TypeError>()),
        );
      }
    });

    test('makes duplicate IDs unique and handles symbol-only labels', () {
      final fixture = _Fixture();

      final options = fixture.policy.parseOptions(const [
        {'id': 'same', 'label': 'First'},
        {'id': 'same', 'label': 'Second'},
        '★★',
        '☃',
        'A B',
        'a-b',
      ]);

      expect(options.map((option) => option.id).toList(), [
        'same',
        'same-2',
        'option-3',
        'option-4',
        'a-b',
        'a-b-2',
      ]);
      expect(options[2].label, '★★');
      expect(options[3].label, '☃');
    });

    test('caps generated IDs and valid options at the exact limits', () {
      final fixture = _Fixture();
      final longLabel = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJK';
      final rawOptions = <Object?>[
        null,
        for (var index = 0; index < 10; index++)
          index == 0 ? longLabel : 'Choice $index',
      ];

      final options = fixture.policy.parseOptions(rawOptions);

      expect(options, hasLength(8));
      expect(options.first.id, longLabel.toLowerCase().substring(0, 40));
      expect(options.last.label, 'Choice 7');
      expect(
        fixture.policy
            .parseOptions(const [
              {
                'id':
                    'explicit-id-that-is-deliberately-longer-than-forty-chars',
                'label': 'Explicit',
              },
            ])
            .single
            .id,
        'explicit-id-that-is-deliberately-longer-than-forty-chars',
      );
    });

    test('preserves exact clipping boundaries for every option text field', () {
      final fixture = _Fixture();
      final exactLabel = 'l' * 120;
      final exactDescription = 'd' * 500;
      final exactPreview = 'p' * 2000;
      final overLabel = 'L' * 121;
      final overDescription = 'D' * 501;
      final overPreview = 'P' * 2001;

      final options = fixture.policy.parseOptions([
        {
          'id': 'exact',
          'label': exactLabel,
          'description': exactDescription,
          'preview': exactPreview,
        },
        {
          'id': 'over',
          'label': overLabel,
          'description': overDescription,
          'preview': overPreview,
        },
      ]);

      expect(options[0].label, exactLabel);
      expect(options[0].description, exactDescription);
      expect(options[0].preview, exactPreview);
      expect(options[1].label, '${'L' * 117}...');
      expect(options[1].description, '${'D' * 497}...');
      expect(options[1].preview, '${'P' * 1997}...');
      expect(options[1].label, hasLength(120));
      expect(options[1].description, hasLength(500));
      expect(options[1].preview, hasLength(2000));
    });

    test('snapshots raw option arguments recursively', () async {
      final rawOptions = <Object?>[
        <String, dynamic>{'label': 'Owner A', 'description': 'Original'},
      ];
      final arguments = <String, dynamic>{
        'question': 'Choose?',
        'options': rawOptions,
        'metadata': <String, dynamic>{
          'paths': <Object?>['owner-a'],
          'tags': <Object?>['safe'],
          'labels': <String, Object?>{'7': 'owner-a'},
        },
      };
      final input = _input(arguments: arguments);
      (rawOptions.single! as Map<String, dynamic>)
        ..['label'] = 'Visible project'
        ..['description'] = 'Poisoned';
      ((arguments['metadata'] as Map<String, dynamic>)['paths']
              as List<Object?>)
          .add('visible');
      ((arguments['metadata'] as Map<String, dynamic>)['tags'] as List<Object?>)
          .add('visible');
      ((arguments['metadata'] as Map<String, dynamic>)['labels'] as Map)['7'] =
          'visible';
      final fixture = _Fixture()..port.attemptRequestMutation = true;

      await fixture.policy.handle(input);

      final request = fixture.port.calls.single.request;
      expect(request.options.single.label, 'Owner A');
      expect(request.options.single.description, 'Original');
      expect(fixture.port.mutationErrors.single, isA<UnsupportedError>());
      expect(
        () => input.arguments['question'] = 'Poison?',
        throwsUnsupportedError,
      );
      final frozenLabels =
          (input.arguments['metadata'] as Map<String, dynamic>)['labels']
              as Map;
      expect(frozenLabels, {'7': 'owner-a'});
      expect(() => frozenLabels['7'] = 'late', throwsUnsupportedError);
      final frozenTags =
          (input.arguments['metadata'] as Map<String, dynamic>)['tags'] as List;
      expect(frozenTags, ['safe']);
      expect(() => frozenTags.add('late'), throwsUnsupportedError);
    });

    test('rejects non-JSON map keys and mutable or custom leaves', () {
      for (final poison in <Object?>[
        <Object?, Object?>{7: 'owner-a'},
        <Object?>{'owner-a'},
        StringBuffer('owner-a'),
        DateTime.utc(2026),
      ]) {
        expect(
          () => _input(
            arguments: <String, dynamic>{
              'question': 'Choose?',
              'metadata': poison,
            },
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'arguments',
            ),
          ),
        );
      }
    });
  });

  group('AskUserQuestionPolicy saved task and reuse', () {
    test(
      'resolves a saved continuation with exact validation payload',
      () async {
        final fixture = _Fixture();
        const savedTask = ConversationWorkflowTask(
          id: 'task-7',
          title: 'Implement the feature',
          validationCommand: '  dart test test/feature_test.dart  ',
        );

        final result = await fixture.policy.handle(
          _input(
            arguments: const {
              'question': 'Should I continue with the next saved task?',
              'options': ['Continue', 'Pause'],
              'allow_other': 'invalid-but-not-read',
            },
            savedTask: savedTask,
          ),
        );

        expect(result.isSuccess, isTrue);
        expect(_payload(result), {
          'status': 'policy_resolved',
          'question': 'Should I continue with the next saved task?',
          'answer':
              'Continue autonomously with the current saved task. Run its '
              'saved validation before moving to the next task.',
          'saved_task_id': 'task-7',
          'saved_validation_command': 'dart test test/feature_test.dart',
        });
        expect(fixture.port.calls, isEmpty);
        expect(fixture.cache.anyResult(_ownerA, (_) => true), isFalse);
      },
    );

    test(
      'omits an empty saved validation and asks non-continuations',
      () async {
        const savedTask = ConversationWorkflowTask(
          id: 'task-empty-validation',
          title: 'Implement',
          validationCommand: '   ',
        );
        final continuationFixture = _Fixture();
        final resolved = await continuationFixture.policy.handle(
          _input(
            arguments: const {'question': 'May I proceed with the next task?'},
            savedTask: savedTask,
          ),
        );
        expect(_payload(resolved), isNot(contains('saved_validation_command')));

        final ordinaryFixture = _Fixture();
        await ordinaryFixture.policy.handle(
          _input(
            arguments: const {'question': 'Which target should I use?'},
            savedTask: savedTask,
          ),
        );
        expect(ordinaryFixture.port.calls, hasLength(1));
      },
    );

    test('reuses an exact result before validating allow_other', () async {
      final fixture = _Fixture();
      const previous = McpToolResult(
        toolName: 'ask_user_question',
        result:
            '{"status":"answered","question":"Choose?",'
            '"selected":[],"answer":"Owner A"}',
        isSuccess: true,
      );
      fixture.cache.store(
        owner: _ownerA,
        question: 'Choose?',
        optionLabels: const ['Owner A', 'Owner B'],
        result: previous,
      );

      final result = await fixture.policy.handle(
        _input(
          arguments: const {
            'question': '  choose?  ',
            'options': ['Different'],
            'allow_other': 'invalid-but-not-read',
          },
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(_payload(result), {
        'status': 'answered',
        'question': 'Choose?',
        'selected': [],
        'answer': 'Owner A',
        'reused': true,
        'note':
            'The user already answered ask_user_question during this turn. '
            'Continue using the existing answer and do not ask again.',
      });
      expect(fixture.port.calls, isEmpty);
    });

    test('reuses successful overlapping options across wording', () async {
      final fixture = _Fixture();
      const previous = McpToolResult(
        toolName: 'ask_user_question',
        result: '{"status":"answered","answer":"Remote"}',
        isSuccess: true,
      );
      fixture.cache.store(
        owner: _ownerA,
        question: 'Where should this run?',
        optionLabels: const ['Local', 'Remote'],
        result: previous,
      );

      final result = await fixture.policy.handle(
        _input(
          arguments: const {
            'question': 'Choose the deployment target?',
            'options': ['Cloud', 'Remote'],
          },
        ),
      );

      expect(_payload(result)['answer'], 'Remote');
      expect(_payload(result)['reused'], isTrue);
      expect(fixture.port.calls, isEmpty);
    });

    test('preserves malformed repeated results and previous metadata', () {
      final fixture = _Fixture();
      const malformed = McpToolResult(
        toolName: 'previous_tool_name',
        result: 'not-json',
        isSuccess: false,
        isExternalMcpResult: true,
        errorMessage: 'previous failure',
      );
      const jsonList = McpToolResult(
        toolName: 'list-result',
        result: '[]',
        isSuccess: true,
      );

      final malformedRepeated = fixture.policy.buildRepeatedResult(malformed);
      final listRepeated = fixture.policy.buildRepeatedResult(jsonList);

      expect(malformedRepeated.toolName, 'previous_tool_name');
      expect(malformedRepeated.result, 'not-json');
      expect(malformedRepeated.isSuccess, isFalse);
      expect(malformedRepeated.isExternalMcpResult, isFalse);
      expect(malformedRepeated.errorMessage, 'previous failure');
      expect(listRepeated.result, '[]');
    });

    test('preserves the exact cancelled payload when it is repeated', () async {
      final fixture = _Fixture();
      const cancelled = McpToolResult(
        toolName: 'ask_user_question',
        result: '{"question":"Choose?","status":"cancelled"}',
        isSuccess: false,
        errorMessage: 'User dismissed the question',
      );
      fixture.cache.store(
        owner: _ownerA,
        question: 'Choose?',
        optionLabels: const ['Owner A', 'Owner B'],
        result: cancelled,
      );

      final repeated = await fixture.policy.handle(
        _input(
          arguments: const {
            'question': ' choose? ',
            'options': ['Different'],
          },
        ),
      );

      expect(repeated.toolName, 'ask_user_question');
      expect(repeated.isSuccess, isFalse);
      expect(repeated.errorMessage, 'User dismissed the question');
      expect(_payload(repeated), {
        'question': 'Choose?',
        'status': 'cancelled',
        'reused': true,
        'note':
            'The user already answered ask_user_question during this turn. '
            'Continue using the existing answer and do not ask again.',
      });
      expect(fixture.port.calls, isEmpty);
    });
  });

  group('AskUserQuestionPolicy answer mapping', () {
    test('maps selections and other text to the exact answered JSON', () async {
      final selected = <AskUserQuestionSelection>[
        const AskUserQuestionSelection(
          id: 'local',
          label: 'Local',
          description: '  Same machine  ',
          preview: '  localhost  ',
        ),
        const AskUserQuestionSelection(
          id: 'remote',
          label: 'Remote',
          description: '   ',
          preview: '',
        ),
      ];
      final answer = AskUserQuestionAnswer(
        question: 'Choose a target?',
        selectedOptions: selected,
        otherText: '  Custom fallback  ',
      );
      selected.clear();
      final fixture = _Fixture();
      fixture.port.responses[_identity()] = AskUserQuestionPortResult(
        identity: _identity(),
        answer: answer,
      );

      final result = await fixture.policy.handle(
        _input(
          arguments: const {
            'question': 'Choose a target?',
            'options': ['Local', 'Remote'],
            'allow_multiple': true,
            'allow_other': true,
          },
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(_payload(result), {
        'status': 'answered',
        'question': 'Choose a target?',
        'selected': [
          {
            'id': 'local',
            'label': 'Local',
            'description': 'Same machine',
            'preview': 'localhost',
          },
          {'id': 'remote', 'label': 'Remote'},
        ],
        'other': 'Custom fallback',
        'answer': 'Local; Remote; Custom fallback',
      });
      expect(answer.selectedOptions, hasLength(2));
      expect(
        () => answer.selectedOptions.add(
          const AskUserQuestionSelection(id: 'poison', label: 'Poison'),
        ),
        throwsUnsupportedError,
      );
      final cached = fixture.cache.findReusable(
        owner: _ownerA,
        question: 'Choose a target?',
        optionLabels: const [],
      );
      expect(cached, same(result));
    });

    test(
      'maps null and empty answers to the exact cancellation JSON',
      () async {
        for (final answer in <AskUserQuestionAnswer?>[
          null,
          AskUserQuestionAnswer(
            question: 'Choose?',
            selectedOptions: const [],
            otherText: '   ',
          ),
        ]) {
          final fixture = _Fixture();
          fixture.port.responses[_identity()] = AskUserQuestionPortResult(
            identity: _identity(),
            answer: answer,
          );

          final result = await fixture.policy.handle(
            _input(arguments: const {'question': '  Choose?  '}),
          );

          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, 'User dismissed the question');
          expect(_payload(result), {
            'question': 'Choose?',
            'status': 'cancelled',
          });
          expect(
            fixture.cache.findReusable(
              owner: _ownerA,
              question: 'Choose?',
              optionLabels: const [],
            ),
            same(result),
          );
        }
      },
    );

    test('propagates port errors without caching a result', () async {
      final fixture = _Fixture();
      final portError = StateError('question UI unavailable');
      fixture.port.error = portError;

      await expectLater(
        fixture.policy.handle(_input()),
        throwsA(same(portError)),
      );

      expect(fixture.cache.anyResult(_ownerA, (_) => true), isFalse);
    });

    test('rejects stale owner and foreign tool-call completions', () async {
      for (final poisonedIdentity in [
        _identity(owner: _ownerB),
        _identity(owner: _ownerANext),
        _identity(toolCallId: 'question-call-b'),
      ]) {
        final fixture = _Fixture();
        fixture.port.responses[_identity()] = AskUserQuestionPortResult(
          identity: poisonedIdentity,
          answer: _answer('Choose?', 'poison', 'Poison'),
        );

        await expectLater(
          fixture.policy.handle(
            _input(arguments: const {'question': 'Choose?'}),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Ask user question response identity mismatch.',
            ),
          ),
        );

        expect(fixture.cache.anyResult(_ownerA, (_) => true), isFalse);
        expect(
          fixture.cache.anyResult(poisonedIdentity.owner, (_) => true),
          isFalse,
        );
      }
    });
  });

  group('AskUserQuestionPolicy owner poison', () {
    test('isolates completed answers by conversation and generation', () async {
      final fixture = _Fixture();
      fixture.port.responses
        ..[_identity(owner: _ownerA)] = AskUserQuestionPortResult(
          identity: _identity(owner: _ownerA),
          answer: _answer('Choose?', 'a', 'Owner A'),
        )
        ..[_identity(owner: _ownerB)] = AskUserQuestionPortResult(
          identity: _identity(owner: _ownerB),
          answer: _answer('Choose?', 'b', 'Owner B'),
        )
        ..[_identity(owner: _ownerANext)] = AskUserQuestionPortResult(
          identity: _identity(owner: _ownerANext),
          answer: _answer('Choose?', 'a-next', 'Owner A next'),
        );

      for (final owner in [_ownerA, _ownerB, _ownerANext]) {
        await fixture.policy.handle(
          _input(owner: owner, arguments: const {'question': 'Choose?'}),
        );
      }
      expect(fixture.port.calls, hasLength(3));

      final repeated = <ChatTurnOwner, String>{};
      for (final owner in [_ownerA, _ownerB, _ownerANext]) {
        repeated[owner] =
            _payload(
                  await fixture.policy.handle(
                    _input(
                      owner: owner,
                      arguments: const {'question': 'Choose?'},
                    ),
                  ),
                )['answer']
                as String;
      }

      expect(repeated, {
        _ownerA: 'Owner A',
        _ownerB: 'Owner B',
        _ownerANext: 'Owner A next',
      });
      expect(fixture.port.calls, hasLength(3));
    });

    test(
      'isolates cancellation from an answered peer at one generation',
      () async {
        final fixture = _Fixture();
        fixture.port.responses
          ..[_identity(owner: _ownerA)] = AskUserQuestionPortResult(
            identity: _identity(owner: _ownerA),
            answer: null,
          )
          ..[_identity(owner: _ownerB)] = AskUserQuestionPortResult(
            identity: _identity(owner: _ownerB),
            answer: _answer('Choose?', 'b', 'Owner B'),
          );

        final cancelled = await fixture.policy.handle(
          _input(owner: _ownerA, arguments: const {'question': 'Choose?'}),
        );
        final answered = await fixture.policy.handle(
          _input(owner: _ownerB, arguments: const {'question': 'Choose?'}),
        );
        final repeatedCancellation = await fixture.policy.handle(
          _input(owner: _ownerA, arguments: const {'question': ' choose? '}),
        );

        expect(_payload(cancelled)['status'], 'cancelled');
        expect(_payload(answered)['answer'], 'Owner B');
        expect(_payload(repeatedCancellation), {
          'question': 'Choose?',
          'status': 'cancelled',
          'reused': true,
          'note':
              'The user already answered ask_user_question during this turn. '
              'Continue using the existing answer and do not ask again.',
        });
        expect(fixture.port.calls, hasLength(2));
      },
    );

    test('keeps concurrent pending completions owner-isolated', () async {
      final fixture = _Fixture();
      for (final owner in [_ownerA, _ownerB, _ownerANext]) {
        fixture.port.pending[_identity(owner: owner)] =
            Completer<AskUserQuestionPortResult>();
      }

      final ownerAFuture = fixture.policy.handle(
        _input(owner: _ownerA, arguments: const {'question': 'Choose?'}),
      );
      final ownerBFuture = fixture.policy.handle(
        _input(owner: _ownerB, arguments: const {'question': 'Choose?'}),
      );
      final ownerANextFuture = fixture.policy.handle(
        _input(owner: _ownerANext, arguments: const {'question': 'Choose?'}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fixture.port.calls.map((call) => call.owner).toList(), [
        _ownerA,
        _ownerB,
        _ownerANext,
      ]);

      fixture.port.pending[_identity(owner: _ownerB)]!.complete(
        AskUserQuestionPortResult(
          identity: _identity(owner: _ownerB),
          answer: _answer('Choose?', 'b', 'Owner B'),
        ),
      );
      fixture.port.pending[_identity(owner: _ownerANext)]!.complete(
        AskUserQuestionPortResult(
          identity: _identity(owner: _ownerANext),
          answer: _answer('Choose?', 'a-next', 'Owner A next'),
        ),
      );
      fixture.port.pending[_identity(owner: _ownerA)]!.complete(
        AskUserQuestionPortResult(
          identity: _identity(owner: _ownerA),
          answer: _answer('Choose?', 'a', 'Owner A'),
        ),
      );

      expect(_payload(await ownerAFuture)['answer'], 'Owner A');
      expect(_payload(await ownerBFuture)['answer'], 'Owner B');
      expect(_payload(await ownerANextFuture)['answer'], 'Owner A next');
      expect(
        fixture.cache
            .findReusable(
              owner: _ownerA,
              question: 'Choose?',
              optionLabels: const [],
            )
            ?.result,
        contains('Owner A'),
      );
      expect(
        fixture.cache
            .findReusable(
              owner: _ownerB,
              question: 'Choose?',
              optionLabels: const [],
            )
            ?.result,
        allOf(contains('Owner B'), isNot(contains('Owner A next'))),
      );
    });
  });
}
