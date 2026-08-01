import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/ask_user_question_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_policy.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_turn_cache.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_ui_contract.dart';
import 'package:caverno/features/chat/domain/services/tool_terminal_response_policy.dart';
import 'package:test/test.dart';

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);

void main() {
  group('AskUserQuestionToolRuntimeAdapter', () {
    test(
      'binds an answer and same-turn reuse to the exact owner call',
      () async {
        final cache = AskUserQuestionTurnCache();
        final completions =
            <String, Completer<AskUserQuestionUiCompletionAcknowledgement>>{};
        final starts = <AskUserQuestionOperationIdentity>[];
        final adapter = _adapter(
          cache: cache,
          startQuestion: (identity, request) {
            starts.add(identity);
            final completion =
                Completer<AskUserQuestionUiCompletionAcknowledgement>();
            completions[identity.toolCallId] = completion;
            return AskUserQuestionUiStartAcknowledgement.started(
              identity: identity,
              pendingQuestionId: 'pending-${identity.toolCallId}',
              completion: completion.future,
            );
          },
        );

        final first = adapter.handle(
          owner: _owner,
          toolCall: _tool('question-a'),
        );
        completions['question-a']!.complete(
          AskUserQuestionUiCompletionAcknowledgement.answered(
            identity: starts.single,
            pendingQuestionId: 'pending-question-a',
            answer: _answer(),
          ),
        );

        final firstResult = await first;
        expect(firstResult.isSuccess, isTrue);
        expect(jsonDecode(firstResult.result), {
          'status': 'answered',
          'question': 'Choose a target?',
          'selected': [
            {'id': 'local', 'label': 'Local'},
          ],
          'answer': 'Local',
        });

        final reused = await adapter.handle(
          owner: _owner,
          toolCall: _tool('question-b'),
        );
        expect(starts, hasLength(1));
        expect(jsonDecode(reused.result), containsPair('reused', true));
        expect(reused.isSuccess, isTrue);
      },
    );

    test('maps an exact UI cancellation through the existing policy', () async {
      final adapter = _adapter(
        startQuestion: (identity, request) {
          return AskUserQuestionUiStartAcknowledgement.started(
            identity: identity,
            pendingQuestionId: 'pending-a',
            completion: Future.value(
              AskUserQuestionUiCompletionAcknowledgement.cancelled(
                identity: identity,
                pendingQuestionId: 'pending-a',
              ),
            ),
          );
        },
      );

      final result = await adapter.handle(
        owner: _owner,
        toolCall: _tool('question-a'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'User dismissed the question');
      expect(jsonDecode(result.result), {
        'question': 'Choose a target?',
        'status': 'cancelled',
      });
    });

    test('rejects a retired owner before projecting UI state', () async {
      var started = false;
      final adapter = _adapter(
        ownerIsCurrent: (_) => false,
        startQuestion: (identity, request) {
          started = true;
          return AskUserQuestionUiStartAcknowledgement.alreadyPending(
            identity: identity,
          );
        },
      );

      final result = await adapter.handle(
        owner: _owner,
        toolCall: _tool('question-a'),
      );

      _expectRetired(result);
      expect(started, isFalse);
    });

    test('does not cache a late answer after owner retirement', () async {
      final cache = AskUserQuestionTurnCache();
      late AskUserQuestionOperationIdentity identity;
      final completion =
          Completer<AskUserQuestionUiCompletionAcknowledgement>();
      final cancellations = <(AskUserQuestionOperationIdentity, String)>[];
      final adapter = _adapter(
        cache: cache,
        startQuestion: (value, request) {
          identity = value;
          return AskUserQuestionUiStartAcknowledgement.started(
            identity: value,
            pendingQuestionId: 'pending-a',
            completion: completion.future,
          );
        },
        cancelQuestion: (value, pendingId) {
          cancellations.add((value, pendingId));
          return AskUserQuestionUiCancellationAcknowledgement(
            identity: value,
            pendingQuestionId: pendingId,
            disposition: AskUserQuestionUiCancellationDisposition.cancelled,
          );
        },
      );
      final resultFuture = adapter.handle(
        owner: _owner,
        toolCall: _tool('question-a'),
      );

      final retirement = adapter.retireOwner(_owner);
      completion.complete(
        AskUserQuestionUiCompletionAcknowledgement.answered(
          identity: identity,
          pendingQuestionId: 'pending-a',
          answer: _answer(),
        ),
      );

      expect(
        retirement.disposition,
        AskUserQuestionOwnerRetirementDisposition.cancelled,
      );
      expect(retirement.identity, identity);
      expect(retirement.pendingQuestionId, 'pending-a');
      expect(cancellations, [(identity, 'pending-a')]);
      _expectRetired(await resultFuture);
      expect(cache.anyResult(_owner, (_) => true), isFalse);

      _expectRetired(
        await adapter.handle(owner: _owner, toolCall: _tool('question-b')),
      );
    });

    test('rejects a completion from another same-owner call', () async {
      final owner = _owner;
      late AskUserQuestionOperationIdentity expected;
      final adapter = _adapter(
        startQuestion: (identity, request) {
          expected = identity;
          final poisoned = AskUserQuestionOperationIdentity(
            owner: owner,
            toolCallId: 'question-b',
            toolName: askUserQuestionToolName,
          );
          return AskUserQuestionUiStartAcknowledgement.started(
            identity: identity,
            pendingQuestionId: 'pending-a',
            completion: Future.value(
              AskUserQuestionUiCompletionAcknowledgement.answered(
                identity: poisoned,
                pendingQuestionId: 'pending-a',
                answer: _answer(),
              ),
            ),
          );
        },
      );

      final result = await adapter.handle(
        owner: owner,
        toolCall: _tool('question-a'),
      );

      _expectBoundaryMismatch(result);
      expect(expected.toolCallId, 'question-a');
    });

    test('rejects a completion for another pending UI token', () async {
      final adapter = _adapter(
        startQuestion: (identity, request) {
          return AskUserQuestionUiStartAcknowledgement.started(
            identity: identity,
            pendingQuestionId: 'pending-a',
            completion: Future.value(
              AskUserQuestionUiCompletionAcknowledgement.cancelled(
                identity: identity,
                pendingQuestionId: 'pending-b',
              ),
            ),
          );
        },
      );

      _expectBoundaryMismatch(
        await adapter.handle(owner: _owner, toolCall: _tool('question-a')),
      );
    });

    test('reports an uncertain UI completion without caching it', () async {
      final cache = AskUserQuestionTurnCache();
      final adapter = _adapter(
        cache: cache,
        startQuestion: (identity, request) {
          return AskUserQuestionUiStartAcknowledgement.started(
            identity: identity,
            pendingQuestionId: 'pending-a',
            completion: Future.value(
              AskUserQuestionUiCompletionAcknowledgement.effectUncertain(
                identity: identity,
                pendingQuestionId: 'pending-a',
              ),
            ),
          );
        },
      );

      final result = await adapter.handle(
        owner: _owner,
        toolCall: _tool('question-a'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('could not be acknowledged safely'));
      expect(cache.anyResult(_owner, (_) => true), isFalse);
    });

    test('revalidates owner identity after the UI future completes', () async {
      var current = true;
      late AskUserQuestionOperationIdentity identity;
      final completion =
          Completer<AskUserQuestionUiCompletionAcknowledgement>();
      final adapter = _adapter(
        ownerIsCurrent: (_) => current,
        startQuestion: (value, request) {
          identity = value;
          return AskUserQuestionUiStartAcknowledgement.started(
            identity: value,
            pendingQuestionId: 'pending-a',
            completion: completion.future,
          );
        },
      );
      final resultFuture = adapter.handle(
        owner: _owner,
        toolCall: _tool('question-a'),
      );

      current = false;
      completion.complete(
        AskUserQuestionUiCompletionAcknowledgement.answered(
          identity: identity,
          pendingQuestionId: 'pending-a',
          answer: _answer(),
        ),
      );

      _expectRetired(await resultFuture);
    });

    test('preserves an immutable strict-JSON input snapshot', () async {
      final rawOption = <String, dynamic>{
        'id': 'local',
        'label': 'Local',
        'metadata': <String, dynamic>{'rank': 1},
      };
      final rawOptions = <Object?>[rawOption];
      final arguments = <String, dynamic>{
        'question': 'Choose a target?',
        'options': rawOptions,
      };
      late AskUserQuestionRequest captured;
      late AskUserQuestionOperationIdentity identity;
      final completion =
          Completer<AskUserQuestionUiCompletionAcknowledgement>();
      final adapter = _adapter(
        startQuestion: (value, request) {
          identity = value;
          captured = request;
          return AskUserQuestionUiStartAcknowledgement.started(
            identity: value,
            pendingQuestionId: 'pending-a',
            completion: completion.future,
          );
        },
      );

      final resultFuture = adapter.handle(
        owner: _owner,
        toolCall: ToolCallInfo(
          id: 'question-a',
          name: askUserQuestionToolName,
          arguments: arguments,
        ),
      );
      rawOption['label'] = 'Poison';
      rawOptions.add('Remote');
      arguments['question'] = 'Poisoned?';

      expect(captured.question, 'Choose a target?');
      expect(captured.options.single.label, 'Local');
      expect(
        () => captured.options.add(
          const AskUserQuestionOption(id: 'remote', label: 'Remote'),
        ),
        throwsUnsupportedError,
      );
      completion.complete(
        AskUserQuestionUiCompletionAcknowledgement.cancelled(
          identity: identity,
          pendingQuestionId: 'pending-a',
        ),
      );
      await resultFuture;
    });

    test('rejects non-JSON and non-finite argument leaves', () async {
      final adapter = _adapter();

      for (final invalid in <Object?>[
        <String>{'not-json'},
        double.nan,
        double.infinity,
      ]) {
        await expectLater(
          adapter.handle(
            owner: _owner,
            toolCall: ToolCallInfo(
              id: 'question-a',
              name: askUserQuestionToolName,
              arguments: {'question': 'Choose a target?', 'invalid': invalid},
            ),
          ),
          throwsArgumentError,
        );
      }
    });

    test('conditionally acknowledges cancellation against exact identity', () {
      late AskUserQuestionOperationIdentity expected;
      final completion =
          Completer<AskUserQuestionUiCompletionAcknowledgement>();
      final adapter = _adapter(
        startQuestion: (identity, request) {
          expected = identity;
          return AskUserQuestionUiStartAcknowledgement.started(
            identity: identity,
            pendingQuestionId: 'pending-a',
            completion: completion.future,
          );
        },
        cancelQuestion: (identity, pendingId) {
          return AskUserQuestionUiCancellationAcknowledgement(
            identity: AskUserQuestionOperationIdentity(
              owner: identity.owner,
              toolCallId: 'poisoned-call',
              toolName: askUserQuestionToolName,
            ),
            pendingQuestionId: pendingId,
            disposition: AskUserQuestionUiCancellationDisposition.cancelled,
          );
        },
      );
      adapter.handle(owner: _owner, toolCall: _tool('question-a'));

      final retirement = adapter.retireOwner(_owner);

      expect(
        retirement.disposition,
        AskUserQuestionOwnerRetirementDisposition.boundaryMismatch,
      );
      expect(retirement.identity, expected);
    });

    test('retirement clears prior cache entries and is idempotent', () async {
      final cache = AskUserQuestionTurnCache();
      cache.store(
        owner: _owner,
        question: 'Choose a target?',
        optionLabels: const ['Local', 'Remote'],
        result: const McpToolResult(
          toolName: askUserQuestionToolName,
          result: '{"status":"answered"}',
          isSuccess: true,
        ),
      );
      final adapter = _adapter(cache: cache);

      final first = adapter.retireOwner(_owner);
      final second = adapter.retireOwner(_owner);

      expect(
        first.disposition,
        AskUserQuestionOwnerRetirementDisposition.noPendingQuestion,
      );
      expect(
        second.disposition,
        AskUserQuestionOwnerRetirementDisposition.noPendingQuestion,
      );
      expect(cache.anyResult(_owner, (_) => true), isFalse);
    });
  });
}

AskUserQuestionToolRuntimeAdapter _adapter({
  AskUserQuestionTurnCache? cache,
  AskUserQuestionOwnerCurrentCallback? ownerIsCurrent,
  AskUserQuestionUiStartCallback? startQuestion,
  AskUserQuestionUiCancelCallback? cancelQuestion,
}) {
  return AskUserQuestionToolRuntimeAdapter(
    cache: cache ?? AskUserQuestionTurnCache(),
    terminalResponsePolicy: _terminalResponsePolicy(),
    ownerIsCurrent: ownerIsCurrent ?? (_) => true,
    startQuestion:
        startQuestion ??
        (identity, request) =>
            AskUserQuestionUiStartAcknowledgement.alreadyPending(
              identity: identity,
            ),
    cancelQuestion:
        cancelQuestion ??
        (identity, pendingId) => AskUserQuestionUiCancellationAcknowledgement(
          identity: identity,
          pendingQuestionId: pendingId,
          disposition: AskUserQuestionUiCancellationDisposition.cancelled,
        ),
  );
}

ToolCallInfo _tool(String id) {
  return ToolCallInfo(
    id: id,
    name: askUserQuestionToolName,
    arguments: const {
      'question': 'Choose a target?',
      'options': ['Local', 'Remote'],
      'allow_other': false,
    },
  );
}

AskUserQuestionAnswer _answer() {
  return AskUserQuestionAnswer(
    question: 'Choose a target?',
    selectedOptions: const [
      AskUserQuestionSelection(id: 'local', label: 'Local'),
    ],
  );
}

void _expectRetired(McpToolResult result) {
  expect(result.isSuccess, isFalse);
  expect(result.errorMessage, contains('turn expired'));
  expect(result.result, '');
}

void _expectBoundaryMismatch(McpToolResult result) {
  expect(result.isSuccess, isFalse);
  expect(result.errorMessage, contains('another pending question'));
  expect(result.result, '');
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
