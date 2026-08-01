import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/turn_message_persistence_coordinator.dart';

void main() {
  group('TurnMessagePersistenceCoordinator', () {
    test('prepares visible and model-history messages independently', () {
      final coordinator = _coordinator();
      final snapshot = coordinator.prepareTurn([
        _message('user', MessageRole.user, 'Question'),
        _message(
          'streaming',
          MessageRole.assistant,
          'Partial',
          isStreaming: true,
        ),
        _message('empty', MessageRole.assistant, '   '),
        _message(
          'tool-only',
          MessageRole.assistant,
          '<tool_call>{"name":"read_file","arguments":{}}</tool_call>',
        ),
        _message(
          'answer',
          MessageRole.assistant,
          '<think>Private notes.</think>\n'
              'Visible answer.\n'
              '<tool_result>{"ok":true}</tool_result>',
        ),
      ]);

      expect(snapshot.visibleMessages.map((message) => message.id), [
        'user',
        'tool-only',
        'answer',
      ]);
      expect(snapshot.targetAssistantMessageId, 'answer');
      expect(snapshot.modelHistoryMessages.map((message) => message.id), [
        'user',
        'answer',
      ]);
      expect(snapshot.modelHistoryMessages.last.content, 'Visible answer.');
      expect(
        () => snapshot.visibleMessages.add(
          _message('late', MessageRole.user, 'Late mutation'),
        ),
        throwsUnsupportedError,
      );
    });

    test('skips persistence when no conversation owns the messages', () async {
      var writes = 0;
      final coordinator = TurnMessagePersistenceCoordinator(
        currentConversationId: () => null,
        writeConversationMessages: (_, _) async {
          writes++;
        },
      );

      await coordinator.persistMessages(null, [
        _message('orphan', MessageRole.user, 'No owner'),
      ]);

      expect(writes, 0);
    });

    test('serializes ordinary writes within one conversation', () async {
      final firstWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      final writes = <String>[];
      final coordinator = TurnMessagePersistenceCoordinator(
        currentConversationId: () => 'current',
        writeConversationMessages: (conversationId, messages) async {
          writes.add('$conversationId:${messages.single.id}');
          if (writes.length == 1) {
            firstWriteStarted.complete();
            await releaseFirstWrite.future;
          }
        },
      );

      final first = coordinator.persistCurrentMessages([
        _message('first', MessageRole.user, 'First'),
      ]);
      await firstWriteStarted.future;
      final second = coordinator.persistMessages('current', [
        _message('second', MessageRole.user, 'Second'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(writes, ['current:first']);
      releaseFirstWrite.complete();
      await Future.wait([first, second]);
      expect(writes, ['current:first', 'current:second']);
    });

    test('allows different conversations to write concurrently', () async {
      final firstWriteStarted = Completer<void>();
      final secondWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      final coordinator = TurnMessagePersistenceCoordinator(
        currentConversationId: () => null,
        writeConversationMessages: (conversationId, _) async {
          if (conversationId == 'first') {
            firstWriteStarted.complete();
            await releaseFirstWrite.future;
          } else {
            secondWriteStarted.complete();
          }
        },
      );

      final first = coordinator.persistMessages('first', [
        _message('first', MessageRole.user, 'First'),
      ]);
      await firstWriteStarted.future;
      final second = coordinator.persistMessages('second', [
        _message('second', MessageRole.user, 'Second'),
      ]);

      await secondWriteStarted.future;
      await second;
      releaseFirstWrite.complete();
      await first;
    });

    test(
      'propagates an ordinary failure without poisoning later writes',
      () async {
        var attempts = 0;
        final logs = <String>[];
        final coordinator = TurnMessagePersistenceCoordinator(
          currentConversationId: () => 'current',
          log: logs.add,
          writeConversationMessages: (_, _) async {
            attempts++;
            if (attempts == 1) throw StateError('write failed');
          },
        );

        final failedWrite = coordinator.persistMessages('first', [
          _message('first', MessageRole.user, 'First'),
        ]);
        final recoveredWrite = coordinator.persistMessages('first', [
          _message('second', MessageRole.user, 'Second'),
        ]);

        await expectLater(failedWrite, throwsStateError);
        await recoveredWrite;
        expect(attempts, 2);
        expect(
          logs,
          contains(
            contains(
              '[ChatNotifier] Conversation message persistence failed: '
              'StateError',
            ),
          ),
        );
      },
    );

    test('admits a cancelled save before an immediate flush', () async {
      final writeStarted = Completer<void>();
      final releaseWrite = Completer<void>();
      final coordinator = TurnMessagePersistenceCoordinator(
        currentConversationId: () => 'current',
        writeConversationMessages: (_, _) async {
          writeStarted.complete();
          await releaseWrite.future;
        },
      );

      final cancelledSave = coordinator.enqueueCancelledTurn(
        conversationId: 'cancelled',
        messages: [_message('partial', MessageRole.assistant, 'Partial')],
      );
      var flushCompleted = false;
      final flush = coordinator.flush().then((_) => flushCompleted = true);
      await writeStarted.future;
      await Future<void>.delayed(Duration.zero);

      expect(flushCompleted, isFalse);
      releaseWrite.complete();
      await Future.wait([cancelledSave, flush]);
      expect(flushCompleted, isTrue);
    });

    test('catches cancelled failures and keeps the tail usable', () async {
      var attempts = 0;
      final logs = <String>[];
      final coordinator = TurnMessagePersistenceCoordinator(
        currentConversationId: () => 'current',
        log: logs.add,
        writeConversationMessages: (_, _) async {
          attempts++;
          if (attempts == 1) throw StateError('cancelled write failed');
        },
      );

      await coordinator.enqueueCancelledTurn(
        conversationId: 'first',
        messages: [_message('first', MessageRole.assistant, 'Partial')],
      );
      await coordinator.enqueueCancelledTurn(
        conversationId: 'second',
        messages: [_message('second', MessageRole.assistant, 'Complete')],
      );
      await coordinator.flush();

      expect(attempts, 2);
      expect(
        logs,
        contains(
          contains(
            '[ChatNotifier] Cancelled message persistence failed: StateError',
          ),
        ),
      );
    });
  });
}

TurnMessagePersistenceCoordinator _coordinator() =>
    TurnMessagePersistenceCoordinator(
      currentConversationId: () => null,
      writeConversationMessages: (_, _) async {},
    );

Message _message(
  String id,
  MessageRole role,
  String content, {
  bool isStreaming = false,
}) => Message(
  id: id,
  role: role,
  content: content,
  timestamp: DateTime.utc(2026, 7, 29),
  isStreaming: isStreaming,
);
