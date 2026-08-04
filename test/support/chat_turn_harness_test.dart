import 'dart:async';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_turn_harness.dart';

void main() {
  group('ScriptedChatDataSource', () {
    test('records each call before its response is observable', () async {
      final source = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(content: 'first', finishReason: 'stop'),
        ],
      );

      source.streamChatCompletionWithTools(
        messages: [_message('hello')],
        tools: [_tool('read_file')],
        model: 'model-a',
        temperature: 0.4,
        maxTokens: 128,
      );

      expect(source.ledger.length, 1);
      final record = source.ledger.records.single;
      expect(record.call, ChatDataSourceCall.streamChatCompletionWithTools);
      expect(record.index, 0);
      expect(record.toolNames, ['read_file']);
      expect(record.model, 'model-a');
      expect(record.temperature, 0.4);
      expect(record.maxTokens, 128);
    });

    test('preserves call order across distinct methods', () async {
      final source = ScriptedChatDataSource();

      source.streamChatCompletionWithTools(
        messages: [_message('a')],
        tools: const [],
      );
      await source.createChatCompletionWithToolResults(
        messages: [_message('b')],
        toolResults: [_toolResult('call-1')],
      );
      await source.createChatCompletion(messages: [_message('c')]);

      expect(source.ledger.records.map((record) => record.call), [
        ChatDataSourceCall.streamChatCompletionWithTools,
        ChatDataSourceCall.createChatCompletionWithToolResults,
        ChatDataSourceCall.createChatCompletion,
      ]);
      expect(source.ledger.countOf(ChatDataSourceCall.createChatCompletion), 1);
    });

    // Distinct methods must stay distinct: the loop treats a streamed
    // tool-result follow-up and a non-streamed one differently, and a test
    // asserting on the wrong one would pass for the wrong reason.
    test('keeps streamed and non-streamed tool-result calls apart', () async {
      final source = ScriptedChatDataSource();

      await source
          .streamWithToolResult(
            messages: [_message('a')],
            toolCallId: 'call-1',
            toolName: 'read_file',
            toolArguments: '{"path":"a.dart"}',
            toolResult: '{"ok":true}',
          )
          .drain<void>();
      await source.createChatCompletionWithToolResult(
        messages: [_message('b')],
        toolCallId: 'call-2',
        toolName: 'read_file',
        toolArguments: '{"path":"b.dart"}',
        toolResult: '{"ok":true}',
      );

      expect(source.ledger.countOf(ChatDataSourceCall.streamWithToolResult), 1);
      expect(
        source.ledger.countOf(
          ChatDataSourceCall.createChatCompletionWithToolResult,
        ),
        1,
      );
      expect(source.toolResultBatches, hasLength(2));
    });

    test('captures defensive copies', () async {
      final messages = [_message('original')];
      final source = ScriptedChatDataSource();

      await source.createChatCompletion(messages: messages);
      messages.add(_message('added after the call'));

      expect(source.ledger.records.single.messages, hasLength(1));
      expect(
        () => source.ledger.records.single.messages.add(_message('x')),
        throwsUnsupportedError,
      );
    });

    test('holds a step until its barrier releases', () async {
      final gate = Completer<void>();
      final source = ScriptedChatDataSource(
        initialSteps: [
          ScriptedStep(
            ChatCompletionResult(content: 'held', finishReason: 'tool_calls'),
            barrier: () => gate.future,
          ),
        ],
      );

      final result = source.streamChatCompletionWithTools(
        messages: [_message('go')],
        tools: const [],
      );
      var completed = false;
      unawaited(result.completion.then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);

      expect(
        completed,
        isFalse,
        reason: 'the barrier has not been released yet',
      );
      expect(
        source.ledger.length,
        1,
        reason: 'the request is recorded before the response is observable',
      );

      gate.complete();
      await result.completion;
      expect(completed, isTrue);
    });

    test('reports exact counts so exhaustion is distinguishable', () async {
      final source = ScriptedChatDataSource(
        initialResponses: [
          ChatCompletionResult(content: 'scripted', finishReason: 'stop'),
        ],
      );

      source.streamChatCompletionWithTools(
        messages: [_message('a')],
        tools: const [],
      );
      source.streamChatCompletionWithTools(
        messages: [_message('b')],
        tools: const [],
      );

      // Two requests, one scripted response: the second fell through to the
      // terminal default rather than consuming a script entry.
      expect(source.initialRequests, 2);
      expect(source.ledger.length, 2);
    });

    test('keeps shared completion state poisoned', () {
      final source = ScriptedChatDataSource();

      expect(() => source.lastFinishReason, throwsStateError);
      expect(() => source.lastUsage, throwsStateError);
      expect(source.finishReasonReads, 1);
      expect(source.usageReads, 1);
    });
  });

  group('RuntimeEventLedger', () {
    test('does not consume unmatched events', () async {
      final controller = StreamController<CavernoRuntimeEvent>();
      final ledger = RuntimeEventLedger(controller.stream);
      addTearDown(() async {
        await ledger.dispose();
        await controller.close();
      });

      controller
        ..add(_started('conversation-a'))
        ..add(_started('conversation-b'));
      await Future<void>.delayed(Duration.zero);

      final first = await ledger.waitFor(
        (event) =>
            event is CavernoRuntimeRunStarted &&
            event.conversationId == 'conversation-a',
      );
      final second = await ledger.waitFor(
        (event) =>
            event is CavernoRuntimeRunStarted &&
            event.conversationId == 'conversation-b',
      );
      // The same predicate still matches: waiting is a read, not a take.
      final firstAgain = await ledger.waitFor(
        (event) =>
            event is CavernoRuntimeRunStarted &&
            event.conversationId == 'conversation-a',
      );

      expect(first, isNot(same(second)));
      expect(firstAgain, same(first));
      expect(ledger.events, hasLength(2));
    });

    test('completes for an event that arrives after the wait begins', () async {
      final controller = StreamController<CavernoRuntimeEvent>();
      final ledger = RuntimeEventLedger(controller.stream);
      addTearDown(() async {
        await ledger.dispose();
        await controller.close();
      });

      final pending = ledger.waitFor(
        (event) => event.conversationId == 'conversation-late',
      );
      controller.add(_started('conversation-late'));

      expect((await pending).conversationId, 'conversation-late');
    });

    test('reports what it recorded when nothing matches', () async {
      final controller = StreamController<CavernoRuntimeEvent>();
      final ledger = RuntimeEventLedger(controller.stream);
      addTearDown(() async {
        await ledger.dispose();
        await controller.close();
      });

      controller.add(_started('conversation-a'));
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        ledger.waitFor(
          (event) => event.conversationId == 'never',
          timeout: const Duration(milliseconds: 50),
          description: 'a never-sent conversation',
        ),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('a never-sent conversation'),
              contains('run_started'),
            ),
          ),
        ),
      );
    });
  });
}

var _messageId = 0;

Message _message(String content) => Message(
  id: 'message-${_messageId += 1}',
  content: content,
  role: MessageRole.user,
  timestamp: DateTime.utc(2026, 8, 4),
);

Map<String, dynamic> _tool(String name) => {
  'type': 'function',
  'function': {'name': name},
};

ToolResultInfo _toolResult(String id) => ToolResultInfo(
  id: id,
  name: 'read_file',
  arguments: const {'path': 'a.dart'},
  result: '{"ok":true}',
);

var _sequence = 0;

CavernoRuntimeEvent _started(String conversationId) => CavernoRuntimeRunStarted(
  sequence: _sequence += 1,
  timestamp: DateTime.utc(2026, 8, 4),
  turnId: 'gen-1',
  conversationId: conversationId,
  surface: CavernoRuntimeSurface.headless,
  mode: 'general',
  model: 'test-model',
  baseUrl: 'http://127.0.0.1:1234/v1',
  workspace: null,
  toolNames: const <String>[],
  hidden: false,
);
