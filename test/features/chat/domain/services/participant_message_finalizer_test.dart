import 'package:test/test.dart';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/participant_message_finalizer.dart';
import 'package:caverno/features/chat/domain/services/truncation_notice.dart';

void main() {
  const finalizer = ParticipantMessageFinalizer();

  group('ParticipantMessageVisibilityPolicy', () {
    test('matches text, reasoning, tool-call, and tool-result visibility', () {
      expect(
        ParticipantMessageVisibilityPolicy.hasVisibleAssistantContent(
          'Visible text.',
        ),
        isTrue,
      );
      expect(
        ParticipantMessageVisibilityPolicy.hasVisibleAssistantContent(
          '<think>Inspecting the implementation.</think>',
        ),
        isTrue,
      );
      expect(
        ParticipantMessageVisibilityPolicy.hasVisibleAssistantContent(
          '<tool_use>{"name":"read_file","path":"a.txt"}</tool_use>',
        ),
        isTrue,
      );
      expect(
        ParticipantMessageVisibilityPolicy.hasVisibleAssistantContent(
          '<tool_result>{"name":"read_file","summary":"Done"}</tool_result>',
        ),
        isFalse,
      );
      expect(
        ParticipantMessageVisibilityPolicy.hasVisibleAssistantContent('  '),
        isFalse,
      );
    });
  });

  group('two-phase finalization contract', () {
    test('freezes a consume plan before metadata is consumed', () {
      final source = <Message>[
        _message(id: 'assistant', content: 'Final answer.', isStreaming: true),
      ];
      final participants = _participants();
      final toolNames = <String>['read_file'];
      final plan = finalizer.plan(
        _input(
          owner: _owner('owner-a', 101),
          sourceMessages: source,
          participant: participants.first,
          participants: participants,
          participantToolNames: toolNames,
          isFinalTurn: true,
        ),
      );

      source.clear();
      participants.clear();
      toolNames.add('poison_tool');

      expect(
        plan.metricsDisposition,
        ParticipantResponseMetricsDisposition.consume,
      );
      expect(plan.preparedMessages.map((message) => message.id), ['assistant']);
      expect(plan.preparedMessages.single.responseMetrics, isNull);
      expect(plan.preparedMessages.single.participantToolNames, ['read_file']);
      expect(plan.preparedMessagesToSave, plan.preparedMessages);
      expect(
        () => plan.preparedMessages.add(
          _message(id: 'mutation', content: 'Mutation'),
        ),
        throwsUnsupportedError,
      );
      expect(() => plan.preparedMessagesToSave.clear(), throwsUnsupportedError);
    });

    test('applies metrics only to consume plans without re-finalizing', () {
      final consumePlan = finalizer.plan(
        _input(
          owner: _owner('owner-a', 102),
          sourceMessages: [
            _message(
              id: 'assistant',
              content: 'Partial answer.',
              isStreaming: true,
            ),
          ],
          finishReason: 'length',
        ),
      );
      final metrics = _metrics(totalTokens: 29, finishReason: 'length');

      final firstResult = finalizer.applyMetrics(consumePlan, metrics);
      final secondResult = finalizer.applyMetrics(consumePlan, metrics);

      expect(consumePlan.preparedMessages.single.responseMetrics, isNull);
      expect(firstResult.updatedMessages.single.responseMetrics, same(metrics));
      expect(
        secondResult.updatedMessages.single.responseMetrics,
        same(metrics),
      );
      expect(
        RegExp(
          RegExp.escape(TruncationNotice.maxTokenNotice),
        ).allMatches(firstResult.content),
        hasLength(1),
      );
      expect(
        () => finalizer.completeAfterDiscard(consumePlan),
        throwsStateError,
      );

      final discardPlan = finalizer.plan(
        _input(
          owner: _owner('owner-a', 103),
          sourceMessages: [
            _message(id: 'assistant', content: ' ', isStreaming: true),
          ],
        ),
      );

      expect(
        discardPlan.metricsDisposition,
        ParticipantResponseMetricsDisposition.discard,
      );
      expect(
        () => finalizer.applyMetrics(discardPlan, metrics),
        throwsStateError,
      );
      expect(
        finalizer.completeAfterDiscard(discardPlan).updatedMessages,
        isEmpty,
      );
    });
  });

  group('inactive inputs', () {
    test('discards stale-owner effects without transforming messages', () {
      final source = <Message>[
        _message(
          id: 'owner-a-assistant',
          content: 'Owner A response.',
          isStreaming: true,
          participantId: 'owner-a-primary',
        ),
      ];
      final metrics = _metrics(totalTokens: 37, finishReason: 'length');
      final input = _input(
        owner: _owner('owner-a', 1),
        ownerIsCurrent: false,
        sourceMessages: source,
        finishReason: 'length',
        isFinalTurn: true,
        isDetached: false,
        autoReadEnabled: true,
        ttsEnabled: true,
      );
      source.add(_message(id: 'visible-owner-poison', content: 'Poison'));

      final result = _complete(finalizer, input, responseMetrics: metrics);

      expect(result.owner, same(input.owner));
      expect(result.status, ParticipantMessageFinalizationStatus.staleOwner);
      expect(result.updatedMessages.map((message) => message.id), [
        'owner-a-assistant',
      ]);
      expect(result.updatedMessages.single.isStreaming, isTrue);
      expect(result.messagesToSave, isEmpty);
      expect(result.content, isEmpty);
      expect(result.handoffTargetParticipantId, isNull);
      expect(result.shouldApplyOwnerMessages, isFalse);
      expect(result.shouldPersist, isFalse);
      expect(result.shouldUpdateTokenUsage, isFalse);
      expect(result.shouldAutoRead, isFalse);
      expect(result.autoReadContent, isNull);
      expect(
        result.metricsDisposition,
        ParticipantResponseMetricsDisposition.discard,
      );
      expect(
        result.visibleStateDisposition,
        ParticipantVisibleStateDisposition.unchanged,
      );
      expect(result.shouldUpdateVisibleState, isFalse);
      expect(result.visibleIsLoading, isNull);
      expect(
        () => result.updatedMessages.add(
          _message(id: 'mutation', content: 'Mutation'),
        ),
        throwsUnsupportedError,
      );
    });

    for (final source in <List<Message>?>[null, const <Message>[]]) {
      test(
        'discards ${source == null ? 'missing' : 'empty'} owner messages',
        () {
          final result = _complete(
            finalizer,
            _input(owner: _owner('owner-a', 2), sourceMessages: source),
            responseMetrics: _metrics(totalTokens: 11),
          );

          expect(
            result.status,
            ParticipantMessageFinalizationStatus.missingMessages,
          );
          expect(result.updatedMessages, isEmpty);
          expect(result.messagesToSave, isEmpty);
          expect(result.shouldApplyOwnerMessages, isFalse);
          expect(result.shouldPersist, isFalse);
          expect(result.shouldUpdateTokenUsage, isFalse);
          expect(result.shouldAutoRead, isFalse);
          expect(
            result.metricsDisposition,
            ParticipantResponseMetricsDisposition.discard,
          );
          expect(
            result.visibleStateDisposition,
            ParticipantVisibleStateDisposition.unchanged,
          );
        },
      );
    }
  });

  group('ordinary finalization', () {
    test(
      'finalizes visible content with metrics and ordered unique tool names',
      () {
        final source = <Message>[
          _message(
            id: 'user',
            content: 'Review the change.',
            role: MessageRole.user,
          ),
          _message(
            id: 'assistant',
            content: 'Review complete.',
            isStreaming: true,
            participantId: 'primary',
          ),
        ];
        final toolNames = <String>[
          ' read_file ',
          '',
          'search',
          'read_file',
          '  ',
          'search',
          'list_files',
        ];
        final metrics = _metrics(totalTokens: 23);
        final input = _input(
          owner: _owner('owner-a', 3),
          sourceMessages: source,
          participantToolNames: toolNames,
          isFinalTurn: true,
          autoReadEnabled: true,
          ttsEnabled: true,
        );
        source.clear();
        toolNames
          ..clear()
          ..add('poison_tool');

        final result = _complete(finalizer, input, responseMetrics: metrics);

        expect(result.status, ParticipantMessageFinalizationStatus.finalized);
        expect(result.updatedMessages, hasLength(2));
        final assistant = result.updatedMessages.last;
        expect(assistant.content, 'Review complete.');
        expect(assistant.isStreaming, isFalse);
        expect(assistant.participantToolNames, [
          'read_file',
          'search',
          'list_files',
        ]);
        expect(assistant.responseMetrics, same(metrics));
        expect(result.messagesToSave, result.updatedMessages);
        expect(result.content, 'Review complete.');
        expect(result.handoffTargetParticipantId, isNull);
        expect(result.shouldApplyOwnerMessages, isTrue);
        expect(result.shouldPersist, isTrue);
        expect(result.shouldUpdateTokenUsage, isTrue);
        expect(result.shouldAutoRead, isTrue);
        expect(result.autoReadContent, 'Review complete.');
        expect(
          result.metricsDisposition,
          ParticipantResponseMetricsDisposition.consume,
        );
        expect(
          result.visibleStateDisposition,
          ParticipantVisibleStateDisposition.complete,
        );
        expect(result.shouldUpdateVisibleState, isTrue);
        expect(result.visibleIsLoading, isFalse);
        expect(() => result.messagesToSave.clear(), throwsUnsupportedError);
      },
    );

    test('keeps attached non-final turns loading and disables auto-read', () {
      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 4),
          sourceMessages: [
            _message(
              id: 'assistant',
              content: 'Intermediate participant answer.',
              isStreaming: true,
            ),
          ],
          isFinalTurn: false,
          autoReadEnabled: true,
          ttsEnabled: true,
        ),
      );

      expect(result.status, ParticipantMessageFinalizationStatus.finalized);
      expect(
        result.visibleStateDisposition,
        ParticipantVisibleStateDisposition.loading,
      );
      expect(result.shouldUpdateVisibleState, isTrue);
      expect(result.visibleIsLoading, isTrue);
      expect(result.shouldAutoRead, isFalse);
    });

    for (final flags in <({bool autoReadEnabled, bool ttsEnabled})>[
      (autoReadEnabled: false, ttsEnabled: true),
      (autoReadEnabled: true, ttsEnabled: false),
    ]) {
      test('requires both auto-read and TTS settings for final content', () {
        final result = _complete(
          finalizer,
          _input(
            owner: _owner('owner-a', 5),
            sourceMessages: [
              _message(
                id: 'assistant',
                content: 'Final content.',
                isStreaming: true,
              ),
            ],
            isFinalTurn: true,
            autoReadEnabled: flags.autoReadEnabled,
            ttsEnabled: flags.ttsEnabled,
          ),
        );

        expect(result.shouldAutoRead, isFalse);
        expect(result.autoReadContent, isNull);
      });
    }

    test('keeps an empty non-assistant last message', () {
      final metrics = _metrics(totalTokens: 7);

      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 6),
          sourceMessages: [
            _message(
              id: 'user',
              content: '',
              role: MessageRole.user,
              isStreaming: true,
            ),
          ],
          isFinalTurn: true,
          autoReadEnabled: true,
          ttsEnabled: true,
        ),
        responseMetrics: metrics,
      );

      expect(result.status, ParticipantMessageFinalizationStatus.finalized);
      expect(result.updatedMessages.single.role, MessageRole.user);
      expect(result.updatedMessages.single.isStreaming, isFalse);
      expect(result.updatedMessages.single.responseMetrics, same(metrics));
      expect(result.messagesToSave, hasLength(1));
      expect(result.content, isEmpty);
      expect(result.shouldAutoRead, isFalse);
      expect(
        result.metricsDisposition,
        ParticipantResponseMetricsDisposition.consume,
      );
    });
  });

  group('empty and saved-message filtering', () {
    test('drops a whitespace-only assistant and discards metrics', () {
      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 7),
          sourceMessages: [
            _message(id: 'user', content: 'Start', role: MessageRole.user),
            _message(id: 'assistant', content: ' \n ', isStreaming: true),
          ],
          isFinalTurn: true,
          autoReadEnabled: true,
          ttsEnabled: true,
        ),
        responseMetrics: _metrics(totalTokens: 19),
      );

      expect(
        result.status,
        ParticipantMessageFinalizationStatus.droppedEmptyAssistant,
      );
      expect(result.updatedMessages.map((message) => message.id), ['user']);
      expect(result.messagesToSave.map((message) => message.id), ['user']);
      expect(result.content, isEmpty);
      expect(result.shouldApplyOwnerMessages, isTrue);
      expect(result.shouldPersist, isTrue);
      expect(result.shouldUpdateTokenUsage, isTrue);
      expect(result.shouldAutoRead, isFalse);
      expect(
        result.metricsDisposition,
        ParticipantResponseMetricsDisposition.discard,
      );
      expect(
        result.visibleStateDisposition,
        ParticipantVisibleStateDisposition.complete,
      );
    });

    test('drops memory-update-only assistant content', () {
      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 8),
          sourceMessages: [
            _message(
              id: 'assistant',
              content:
                  '<tool_use>{"name":"memory_update","status":"updated"}</tool_use>',
              isStreaming: true,
            ),
          ],
        ),
        responseMetrics: _metrics(totalTokens: 13),
      );

      expect(
        result.status,
        ParticipantMessageFinalizationStatus.droppedEmptyAssistant,
      );
      expect(result.updatedMessages, isEmpty);
      expect(result.messagesToSave, isEmpty);
      expect(result.shouldPersist, isTrue);
      expect(result.content, isEmpty);
      expect(
        result.metricsDisposition,
        ParticipantResponseMetricsDisposition.discard,
      );
    });

    test('filters streaming and empty assistants from saved messages', () {
      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 9),
          sourceMessages: [
            _message(id: 'empty-user', content: '', role: MessageRole.user),
            _message(id: 'empty-assistant', content: ''),
            _message(id: 'visible-assistant', content: 'Prior answer.'),
            _message(
              id: 'streaming-prior',
              content: 'Incomplete prior answer.',
              isStreaming: true,
            ),
            _message(
              id: 'participant-final',
              content: 'Final answer.',
              isStreaming: true,
            ),
          ],
        ),
      );

      expect(result.updatedMessages, hasLength(5));
      expect(result.messagesToSave.map((message) => message.id), [
        'empty-user',
        'visible-assistant',
        'participant-final',
      ]);
    });
  });

  group('handoff and truncation', () {
    test('strips a valid handoff and records target metadata', () {
      final participants = _participants();

      final input = _input(
        owner: _owner('owner-a', 10),
        sourceMessages: [
          _message(
            id: 'assistant',
            content:
                'The implementation needs review.\n'
                'Senior Engineer, what do you think?\n'
                'Handoff: Senior Engineer\n',
            isStreaming: true,
            participantId: 'facilitator',
          ),
        ],
        participant: participants.first,
        participants: participants,
        isFinalTurn: true,
        autoReadEnabled: true,
        ttsEnabled: true,
      );
      participants
        ..clear()
        ..add(
          const ConversationParticipant(
            id: 'visible-owner-poison',
            displayName: 'Visible Owner',
          ),
        );
      final result = _complete(finalizer, input);

      expect(result.status, ParticipantMessageFinalizationStatus.finalized);
      expect(
        result.content,
        'The implementation needs review.\n'
        'Senior Engineer, what do you think?',
      );
      expect(result.handoffTargetParticipantId, 'engineer');
      final message = result.updatedMessages.single;
      expect(message.handoffTargetParticipantId, 'engineer');
      expect(message.handoffTargetDisplayName, 'Engineer');
      expect(message.handoffTargetRoleLabel, 'Senior Engineer');
      expect(message.content, result.content);
      expect(result.autoReadContent, result.content);
    });

    test('strips an invalid handoff without target metadata', () {
      final participants = _participants();

      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 11),
          sourceMessages: [
            _message(
              id: 'assistant',
              content: 'Return to the user.\nHandoff: Unknown Specialist',
              isStreaming: true,
              participantId: 'facilitator',
            ),
          ],
          participant: participants.first,
          participants: participants,
        ),
      );

      expect(result.content, 'Return to the user.');
      expect(result.handoffTargetParticipantId, isNull);
      expect(result.updatedMessages.single.handoffTargetParticipantId, isNull);
      expect(result.updatedMessages.single.handoffTargetDisplayName, isNull);
      expect(result.updatedMessages.single.handoffTargetRoleLabel, isNull);
    });

    test('strips a self handoff without routing back to the source', () {
      final participants = _participants();

      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 12),
          sourceMessages: [
            _message(
              id: 'assistant',
              content: 'I will stop here.\nHandoff: Facilitator',
              isStreaming: true,
              participantId: 'facilitator',
            ),
          ],
          participant: participants.first,
          participants: participants,
        ),
      );

      expect(result.content, 'I will stop here.');
      expect(result.handoffTargetParticipantId, isNull);
      expect(result.updatedMessages.single.handoffTargetParticipantId, isNull);
    });

    test('keeps routing identity when a trimmed ID has no metadata match', () {
      final participants = <ConversationParticipant>[
        const ConversationParticipant(
          id: 'facilitator',
          displayName: 'Facilitator',
          roleLabel: 'Facilitator',
          facilitatesTurns: true,
        ),
        const ConversationParticipant(
          id: ' engineer ',
          displayName: 'Engineer',
          roleLabel: 'Senior Engineer',
          endpointId: 'engineer-endpoint',
        ),
      ];

      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 13),
          sourceMessages: [
            _message(
              id: 'assistant',
              content: 'Please review this.\nHandoff: Senior Engineer',
              isStreaming: true,
              participantId: 'facilitator',
            ),
          ],
          participant: participants.first,
          participants: participants,
        ),
      );

      expect(result.handoffTargetParticipantId, ' engineer ');
      expect(result.updatedMessages.single.handoffTargetParticipantId, isNull);
      expect(result.updatedMessages.single.handoffTargetDisplayName, isNull);
      expect(result.updatedMessages.single.handoffTargetRoleLabel, isNull);
    });

    test('retains a handoff target when marker-only content is dropped', () {
      final participants = _participants();

      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 14),
          sourceMessages: [
            _message(
              id: 'user',
              content: 'Ask the engineer.',
              role: MessageRole.user,
            ),
            _message(
              id: 'assistant',
              content: 'Handoff: Senior Engineer',
              isStreaming: true,
              participantId: 'facilitator',
            ),
          ],
          participant: participants.first,
          participants: participants,
        ),
        responseMetrics: _metrics(totalTokens: 17),
      );

      expect(
        result.status,
        ParticipantMessageFinalizationStatus.droppedEmptyAssistant,
      );
      expect(result.updatedMessages.map((message) => message.id), ['user']);
      expect(result.content, isEmpty);
      expect(result.handoffTargetParticipantId, 'engineer');
      expect(
        result.metricsDisposition,
        ParticipantResponseMetricsDisposition.discard,
      );
    });

    test('truncation suppresses handoff and appends the exact notice', () {
      final participants = _participants();
      const raw =
          'Partial answer.\n'
          'Handoff: Senior Engineer  ';

      final result = _complete(
        finalizer,
        _input(
          owner: _owner('owner-a', 15),
          sourceMessages: [
            _message(
              id: 'assistant',
              content: raw,
              isStreaming: true,
              participantId: 'facilitator',
            ),
          ],
          participant: participants.first,
          participants: participants,
          finishReason: ' LENGTH ',
        ),
        responseMetrics: _metrics(totalTokens: 31, finishReason: 'length'),
      );

      expect(
        result.content,
        'Partial answer.\n'
        'Handoff: Senior Engineer\n\n'
        '${TruncationNotice.maxTokenNotice}',
      );
      expect(result.handoffTargetParticipantId, isNull);
      expect(result.updatedMessages.single.handoffTargetParticipantId, isNull);
      expect(
        result.updatedMessages.single.responseMetrics?.finishReason,
        'length',
      );
      expect(
        result.metricsDisposition,
        ParticipantResponseMetricsDisposition.consume,
      );
    });
  });

  group('detached owner isolation', () {
    test('finalizes and persists owner A while owner B remains visible', () {
      final ownerA = _owner('owner-a', 16);
      final ownerB = _owner('owner-b', 91);
      final participantsA = _participants(
        facilitatorId: 'a-facilitator',
        engineerId: 'a-engineer',
      );
      final participantsB = _participants(
        facilitatorId: 'b-facilitator',
        engineerId: 'b-engineer',
      );
      final visibleBMessages = <Message>[
        _message(
          id: 'b-user',
          content: 'Visible owner B request.',
          role: MessageRole.user,
        ),
        _message(
          id: 'b-assistant',
          content: 'Visible owner B answer.',
          isStreaming: true,
          participantId: 'b-facilitator',
        ),
      ];
      final visibleBSnapshot = List<Message>.of(visibleBMessages);

      final ownerBResult = _complete(
        finalizer,
        _input(
          owner: ownerB,
          sourceMessages: visibleBMessages,
          participant: participantsB.first,
          participants: participantsB,
          isFinalTurn: true,
        ),
        responseMetrics: _metrics(totalTokens: 91),
      );
      final ownerAResult = _complete(
        finalizer,
        _input(
          owner: ownerA,
          sourceMessages: [
            _message(
              id: 'a-user',
              content: 'Detached owner A request.',
              role: MessageRole.user,
            ),
            _message(
              id: 'a-assistant',
              content:
                  'Owner A delegates review.\n'
                  'Handoff: Senior Engineer',
              isStreaming: true,
              participantId: 'a-facilitator',
            ),
          ],
          participant: participantsA.first,
          participants: participantsA,
          participantToolNames: const ['read_file'],
          isFinalTurn: true,
          isDetached: true,
          autoReadEnabled: true,
          ttsEnabled: true,
        ),
        responseMetrics: _metrics(totalTokens: 37),
      );

      expect(ownerAResult.owner, same(ownerA));
      expect(ownerAResult.updatedMessages.map((message) => message.id), [
        'a-user',
        'a-assistant',
      ]);
      expect(ownerAResult.messagesToSave.map((message) => message.id), [
        'a-user',
        'a-assistant',
      ]);
      expect(ownerAResult.content, 'Owner A delegates review.');
      expect(ownerAResult.handoffTargetParticipantId, 'a-engineer');
      expect(
        ownerAResult.updatedMessages.last.handoffTargetParticipantId,
        'a-engineer',
      );
      expect(ownerAResult.updatedMessages.last.participantToolNames, [
        'read_file',
      ]);
      expect(
        ownerAResult.updatedMessages.last.responseMetrics?.totalTokens,
        37,
      );
      expect(ownerAResult.shouldPersist, isTrue);
      expect(ownerAResult.shouldUpdateTokenUsage, isTrue);
      expect(ownerAResult.shouldAutoRead, isFalse);
      expect(
        ownerAResult.visibleStateDisposition,
        ParticipantVisibleStateDisposition.unchanged,
      );
      expect(ownerAResult.shouldUpdateVisibleState, isFalse);
      expect(ownerAResult.visibleIsLoading, isNull);

      expect(ownerBResult.owner, same(ownerB));
      expect(ownerBResult.content, 'Visible owner B answer.');
      expect(
        ownerBResult.updatedMessages.last.responseMetrics?.totalTokens,
        91,
      );
      expect(
        visibleBMessages,
        visibleBSnapshot,
        reason: 'The detached owner result must not mutate visible owner B.',
      );
    });
  });
}

ParticipantMessageFinalizationInput _input({
  required ChatTurnOwner owner,
  bool ownerIsCurrent = true,
  List<Message>? sourceMessages,
  bool isFinalTurn = false,
  ConversationParticipant? participant,
  List<ConversationParticipant>? participants,
  List<String> participantToolNames = const <String>[],
  String finishReason = 'stop',
  bool isDetached = false,
  bool autoReadEnabled = false,
  bool ttsEnabled = false,
}) {
  final resolvedParticipants = participants ?? _participants();
  return ParticipantMessageFinalizationInput(
    owner: owner,
    ownerIsCurrent: ownerIsCurrent,
    sourceMessages: sourceMessages,
    isFinalTurn: isFinalTurn,
    participant: participant ?? resolvedParticipants.first,
    participants: resolvedParticipants,
    participantToolNames: participantToolNames,
    finishReason: finishReason,
    isDetached: isDetached,
    autoReadEnabled: autoReadEnabled,
    ttsEnabled: ttsEnabled,
  );
}

ParticipantMessageFinalizationResult _complete(
  ParticipantMessageFinalizer finalizer,
  ParticipantMessageFinalizationInput input, {
  MessageResponseMetrics? responseMetrics,
}) {
  final plan = finalizer.plan(input);
  return switch (plan.metricsDisposition) {
    ParticipantResponseMetricsDisposition.consume => finalizer.applyMetrics(
      plan,
      responseMetrics,
    ),
    ParticipantResponseMetricsDisposition.discard =>
      finalizer.completeAfterDiscard(plan),
  };
}

List<ConversationParticipant> _participants({
  String facilitatorId = 'facilitator',
  String engineerId = 'engineer',
}) {
  return <ConversationParticipant>[
    ConversationParticipant(
      id: facilitatorId,
      displayName: 'Facilitator',
      roleLabel: 'Facilitator',
      facilitatesTurns: true,
      order: 0,
    ),
    ConversationParticipant(
      id: engineerId,
      displayName: ' Engineer ',
      roleLabel: ' Senior Engineer ',
      endpointId: 'engineer-endpoint',
      order: 1,
    ),
  ];
}

ChatTurnOwner _owner(String conversationId, int generation) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

MessageResponseMetrics _metrics({
  required int totalTokens,
  String finishReason = 'stop',
}) {
  return MessageResponseMetrics(
    promptTokens: totalTokens ~/ 2,
    completionTokens: totalTokens - (totalTokens ~/ 2),
    totalTokens: totalTokens,
    elapsedMilliseconds: 250,
    finishReason: finishReason,
  );
}

Message _message({
  required String id,
  required String content,
  MessageRole role = MessageRole.assistant,
  bool isStreaming = false,
  String? participantId,
}) {
  return Message(
    id: id,
    content: content,
    role: role,
    timestamp: DateTime.utc(2026, 7, 31),
    isStreaming: isStreaming,
    participantId: participantId,
    participantDisplayName: participantId == null ? null : 'Participant',
    participantRoleLabel: participantId == null ? null : 'Role',
    participantColorValue: participantId == null ? null : 0xFF123456,
  );
}
