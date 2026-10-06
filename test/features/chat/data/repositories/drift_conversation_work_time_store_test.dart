import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:caverno/features/chat/data/repositories/conversation_work_time_usage_sink.dart';
import 'package:caverno/features/chat/data/repositories/drift_conversation_work_time_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_completion_terminal_metadata.dart';
import 'package:caverno/features/chat/domain/entities/conversation_work_time.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_sink.dart';
import 'package:flutter_test/flutter_test.dart';

final class _RecordingWorkTimeSink implements ConversationWorkTimeSink {
  final records =
      <
        ({
          String conversationId,
          ConversationWorkKind kind,
          String detail,
          int durationMs,
          bool isError,
        })
      >[];

  @override
  void record({
    required String conversationId,
    required ConversationWorkKind kind,
    required int durationMs,
    String detail = '',
    bool isError = false,
  }) {
    records.add((
      conversationId: conversationId,
      kind: kind,
      detail: detail,
      durationMs: durationMs,
      isError: isError,
    ));
  }
}

final class _CountingUsageSink implements ModelUsageSink {
  int calls = 0;
  String? lastConversationId;

  @override
  void record({
    required String model,
    required String endpointId,
    required ModelUsageRole role,
    required TokenUsage usage,
    required int durationMs,
    String? label,
    String? conversationId,
    String? finishReason,
    bool isError = false,
  }) {
    calls++;
    lastConversationId = conversationId;
  }
}

void main() {
  group('DriftConversationWorkTimeStore', () {
    late AppDatabase db;
    late DriftConversationWorkTimeStore store;

    setUp(() {
      db = AppDatabase.memory();
      store = DriftConversationWorkTimeStore(
        db,
        clock: () => DateTime(2026, 10, 1, 12),
      );
    });

    tearDown(() async => db.close());

    test('folds repeated work into one row per kind and detail', () async {
      await store.recorded(
        conversationId: 'c1',
        kind: ConversationWorkKind.llmInference,
        detail: 'chat',
        durationMs: 1200,
      );
      await store.recorded(
        conversationId: 'c1',
        kind: ConversationWorkKind.llmInference,
        detail: 'chat',
        durationMs: 800,
        isError: true,
      );
      await store.recorded(
        conversationId: 'c1',
        kind: ConversationWorkKind.toolExecution,
        detail: 'run_tests',
        durationMs: 5000,
      );
      await store.recorded(
        conversationId: 'other',
        kind: ConversationWorkKind.llmInference,
        detail: 'chat',
        durationMs: 99999,
      );

      final summary = await store.readConversation('c1');

      expect(summary.durationMsOf(ConversationWorkKind.llmInference), 2000);
      expect(summary.countOf(ConversationWorkKind.llmInference), 2);
      expect(
        summary
            .breakdownOf(ConversationWorkKind.llmInference)
            .single
            .errorCount,
        1,
      );
      expect(summary.durationMsOf(ConversationWorkKind.toolExecution), 5000);
      expect(summary.durationMsOf(ConversationWorkKind.backgroundProcess), 0);
    });

    test('clamps negative durations and ignores blank conversations', () async {
      await store.recorded(
        conversationId: 'c1',
        kind: ConversationWorkKind.toolExecution,
        durationMs: -5,
      );
      await store.recorded(
        conversationId: '  ',
        kind: ConversationWorkKind.toolExecution,
        durationMs: 10,
      );

      final rows = await db.select(db.conversationWorkTime).get();
      expect(rows.single.durationMs, 0);
      expect(rows.single.count, 1);
    });

    test('watchConversation emits after each write', () async {
      final stream = store.watchConversation('c1');
      final expectation = expectLater(
        stream.map((s) => s.durationMsOf(ConversationWorkKind.approvalWait)),
        emitsInOrder([0, 300]),
      );
      await Future<void>.delayed(Duration.zero);
      await store.recorded(
        conversationId: 'c1',
        kind: ConversationWorkKind.approvalWait,
        durationMs: 300,
      );
      await expectation;
    });

    test('clearConversation drops only that conversation', () async {
      for (final id in ['c1', 'c2']) {
        await store.recorded(
          conversationId: id,
          kind: ConversationWorkKind.toolExecution,
          durationMs: 10,
        );
      }
      await store.clearConversation('c1');

      expect((await store.readConversation('c1')).isEmpty, isTrue);
      expect((await store.readConversation('c2')).isEmpty, isFalse);
    });
  });

  group('ConversationWorkTimeUsageSink', () {
    test('books request time under the issuing conversation and role', () {
      final usage = _CountingUsageSink();
      final workTime = _RecordingWorkTimeSink();
      ConversationWorkTimeUsageSink(usage: usage, workTime: workTime).record(
        model: 'm',
        endpointId: 'primary',
        role: ModelUsageRole.subagent,
        usage: TokenUsage.zero,
        durationMs: 4200,
        conversationId: 'c1',
        isError: true,
      );

      expect(usage.calls, 1, reason: 'per-model usage still records');
      expect(usage.lastConversationId, 'c1');
      expect(workTime.records.single, (
        conversationId: 'c1',
        kind: ConversationWorkKind.llmInference,
        detail: 'subagent',
        durationMs: 4200,
        isError: true,
      ));
    });

    test('skips work time for requests no conversation owns', () {
      final usage = _CountingUsageSink();
      final workTime = _RecordingWorkTimeSink();
      ConversationWorkTimeUsageSink(usage: usage, workTime: workTime).record(
        model: 'm',
        endpointId: 'primary',
        role: ModelUsageRole.routine,
        usage: TokenUsage.zero,
        durationMs: 100,
      );

      expect(usage.calls, 1);
      expect(workTime.records, isEmpty);
    });
  });
}
