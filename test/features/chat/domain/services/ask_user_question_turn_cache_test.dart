import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_turn_cache.dart';
import 'package:test/test.dart';

void main() {
  group('ChatTurnOwner', () {
    test('uses conversation and generation for equality', () {
      final owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 7,
      );

      final equalOwner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 7,
      );
      expect(owner, equalOwner);
      expect(owner.hashCode, equalOwner.hashCode);
      expect(owner, same(owner));
      expect(
        owner,
        isNot(
          ChatTurnOwner(
            conversationId: 'conversation-b',
            interactionGeneration: 7,
          ),
        ),
      );
      expect(
        owner,
        isNot(
          ChatTurnOwner(
            conversationId: 'conversation-a',
            interactionGeneration: 8,
          ),
        ),
      );
    });
  });

  group('AskUserQuestionTurnCache reuse', () {
    test('returns the exact result for the same normalized question', () {
      final cache = AskUserQuestionTurnCache();
      final owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 1,
      );
      final result = _result('answer');
      cache.store(
        owner: owner,
        question: '  Which   target? ',
        optionLabels: const ['Local', 'Remote'],
        result: result,
      );

      final reused = cache.findReusable(
        owner: owner,
        question: 'which target?',
        optionLabels: const ['Something else'],
      );

      expect(reused, same(result));
    });

    test('returns no result when neither question nor options match', () {
      final cache = AskUserQuestionTurnCache();
      final result = _result('answer');
      cache.store(
        owner: _owner(),
        question: 'Which target?',
        optionLabels: const ['Local', 'Remote'],
        result: result,
      );

      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'Which release?',
          optionLabels: const ['Stable', 'Beta'],
        ),
        isNull,
      );
    });

    test('reuses a successful overlapping option across wording', () {
      final cache = AskUserQuestionTurnCache();
      final result = _result('answer');
      cache.store(
        owner: _owner(),
        question: 'Choose a target',
        optionLabels: const [' Local ', 'Remote'],
        result: result,
      );

      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'Where should this run?',
          optionLabels: const ['LOCAL', 'Cloud'],
        ),
        same(result),
      );
    });

    test('requires a multi-option side for cross-wording reuse', () {
      final cache = AskUserQuestionTurnCache();
      final result = _result('answer');
      cache.store(
        owner: _owner(),
        question: 'Choose a target',
        optionLabels: const ['Local'],
        result: result,
      );

      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'Where should this run?',
          optionLabels: const ['Local'],
        ),
        isNull,
      );
      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'Where should this run?',
          optionLabels: const ['Local', 'Remote'],
        ),
        same(result),
      );
    });

    test('does not reuse a failed result across wording', () {
      final cache = AskUserQuestionTurnCache();
      final failed = _result('cancelled', isSuccess: false);
      cache.store(
        owner: _owner(),
        question: 'Choose a target',
        optionLabels: const ['Local', 'Remote'],
        result: failed,
      );

      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'Where should this run?',
          optionLabels: const ['Local', 'Cloud'],
        ),
        isNull,
      );
      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'choose a target',
          optionLabels: const [],
        ),
        same(failed),
      );
    });

    test('selects the most recently stored reusable result', () {
      final cache = AskUserQuestionTurnCache();
      final first = _result('first');
      final second = _result('second');
      cache
        ..store(
          owner: _owner(),
          question: 'Choose a target',
          optionLabels: const ['Local', 'Remote'],
          result: first,
        )
        ..store(
          owner: _owner(),
          question: ' choose   a target ',
          optionLabels: const ['Cloud', 'Remote'],
          result: second,
        );

      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'CHOOSE A TARGET',
          optionLabels: const [],
        ),
        same(second),
      );
    });

    test('ignores empty option labels for cross-wording reuse', () {
      final cache = AskUserQuestionTurnCache();
      cache.store(
        owner: _owner(),
        question: 'Choose a target',
        optionLabels: const [' ', '\n'],
        result: _result('answer'),
      );

      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'Where should this run?',
          optionLabels: const [' ', '\t'],
        ),
        isNull,
      );
    });

    test('copies option labels before storing them', () {
      final cache = AskUserQuestionTurnCache();
      final labels = <String>['Local', 'Remote'];
      final result = _result('answer');
      cache.store(
        owner: _owner(),
        question: 'Choose a target',
        optionLabels: labels,
        result: result,
      );
      labels
        ..clear()
        ..add('Cloud');

      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'Where should this run?',
          optionLabels: const ['Remote', 'Device'],
        ),
        same(result),
      );
      expect(
        cache.findReusable(
          owner: _owner(),
          question: 'Where should this run?',
          optionLabels: const ['Cloud', 'Device'],
        ),
        isNull,
      );
    });
  });

  group('AskUserQuestionTurnCache ownership and lifecycle', () {
    test('keeps identical generations isolated by conversation', () {
      final cache = AskUserQuestionTurnCache();
      final conversationAResult = _result('conversation-a');
      final conversationBResult = _result('conversation-b');
      cache
        ..store(
          owner: _owner(conversationId: 'conversation-a'),
          question: 'Choose a target',
          optionLabels: const ['Local', 'Remote'],
          result: conversationAResult,
        )
        ..store(
          owner: _owner(conversationId: 'conversation-b'),
          question: 'Choose a target',
          optionLabels: const ['Local', 'Remote'],
          result: conversationBResult,
        );

      expect(
        cache.findReusable(
          owner: _owner(conversationId: 'conversation-a'),
          question: 'Choose a target',
          optionLabels: const [],
        ),
        same(conversationAResult),
      );
      expect(
        cache.findReusable(
          owner: _owner(conversationId: 'conversation-b'),
          question: 'Choose a target',
          optionLabels: const [],
        ),
        same(conversationBResult),
      );
    });

    test('does not share cancellation across identical generations', () {
      final cache = AskUserQuestionTurnCache();
      final cancelled = _result('cancelled', isSuccess: false);
      final answered = _result('answered');
      cache
        ..store(
          owner: _owner(conversationId: 'conversation-a'),
          question: 'Choose a target',
          optionLabels: const ['Local', 'Remote'],
          result: cancelled,
        )
        ..store(
          owner: _owner(conversationId: 'conversation-b'),
          question: 'Choose a target',
          optionLabels: const ['Local', 'Remote'],
          result: answered,
        );

      expect(
        cache.findReusable(
          owner: _owner(conversationId: 'conversation-a'),
          question: 'choose a target',
          optionLabels: const [],
        ),
        same(cancelled),
      );
      expect(
        cache.findReusable(
          owner: _owner(conversationId: 'conversation-b'),
          question: 'choose a target',
          optionLabels: const [],
        ),
        same(answered),
      );
    });

    test('keeps generations isolated within one conversation', () {
      final cache = AskUserQuestionTurnCache();
      cache.store(
        owner: _owner(generation: 1),
        question: 'Choose a target',
        optionLabels: const ['Local', 'Remote'],
        result: _result('generation-1'),
      );

      expect(
        cache.findReusable(
          owner: _owner(generation: 2),
          question: 'Choose a target',
          optionLabels: const ['Local', 'Remote'],
        ),
        isNull,
      );
    });

    test('runs predicates only against one exact owner', () {
      final cache = AskUserQuestionTurnCache();
      cache
        ..store(
          owner: _owner(conversationId: 'conversation-a'),
          question: 'Approve?',
          optionLabels: const ['Approve', 'Reject'],
          result: _result('approved'),
        )
        ..store(
          owner: _owner(conversationId: 'conversation-b'),
          question: 'Approve?',
          optionLabels: const ['Approve', 'Reject'],
          result: _result('rejected'),
        );

      expect(
        cache.anyResult(
          _owner(conversationId: 'conversation-a'),
          (result) => result.result == 'approved',
        ),
        isTrue,
      );
      expect(
        cache.anyResult(
          _owner(conversationId: 'conversation-a'),
          (result) => result.result == 'rejected',
        ),
        isFalse,
      );
      expect(
        cache.anyResult(_owner(conversationId: 'missing'), (_) => true),
        isFalse,
      );
    });

    test('removes only the exact owner', () {
      final cache = AskUserQuestionTurnCache();
      final firstOwner = _owner(generation: 1);
      final secondOwner = _owner(generation: 2);
      cache
        ..store(
          owner: firstOwner,
          question: 'First?',
          optionLabels: const [],
          result: _result('first'),
        )
        ..store(
          owner: secondOwner,
          question: 'Second?',
          optionLabels: const [],
          result: _result('second'),
        );

      expect(cache.removeOwner(firstOwner), isTrue);
      expect(cache.removeOwner(firstOwner), isFalse);
      expect(cache.anyResult(firstOwner, (_) => true), isFalse);
      expect(cache.anyResult(secondOwner, (_) => true), isTrue);
    });

    test('clears every generation for one conversation only', () {
      final cache = AskUserQuestionTurnCache();
      for (final generation in [1, 2]) {
        cache.store(
          owner: _owner(
            conversationId: 'conversation-a',
            generation: generation,
          ),
          question: 'Question $generation',
          optionLabels: const [],
          result: _result('answer-$generation'),
        );
      }
      cache.store(
        owner: _owner(conversationId: 'conversation-b'),
        question: 'Other?',
        optionLabels: const [],
        result: _result('other'),
      );

      cache.clearConversation('conversation-a');

      expect(
        cache.anyResult(
          _owner(conversationId: 'conversation-a', generation: 1),
          (_) => true,
        ),
        isFalse,
      );
      expect(
        cache.anyResult(
          _owner(conversationId: 'conversation-a', generation: 2),
          (_) => true,
        ),
        isFalse,
      );
      expect(
        cache.anyResult(_owner(conversationId: 'conversation-b'), (_) => true),
        isTrue,
      );
    });

    test('clears all owners globally', () {
      final cache = AskUserQuestionTurnCache();
      cache
        ..store(
          owner: _owner(conversationId: 'conversation-a'),
          question: 'First?',
          optionLabels: const [],
          result: _result('first'),
        )
        ..store(
          owner: _owner(conversationId: 'conversation-b'),
          question: 'Second?',
          optionLabels: const [],
          result: _result('second'),
        )
        ..clear();

      expect(
        cache.anyResult(_owner(conversationId: 'conversation-a'), (_) => true),
        isFalse,
      );
      expect(
        cache.anyResult(_owner(conversationId: 'conversation-b'), (_) => true),
        isFalse,
      );
    });
  });
}

ChatTurnOwner _owner({
  String conversationId = 'conversation-a',
  int generation = 1,
}) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

McpToolResult _result(String value, {bool isSuccess = true}) {
  return McpToolResult(
    toolName: 'ask_user_question',
    result: value,
    isSuccess: isSuccess,
    errorMessage: isSuccess ? null : value,
  );
}
