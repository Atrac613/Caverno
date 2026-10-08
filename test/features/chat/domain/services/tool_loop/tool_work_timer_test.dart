import 'package:caverno/features/chat/domain/entities/conversation_work_time.dart';
import 'package:caverno/features/chat/domain/services/approval_wait_ledger.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/tool_work_timer.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Sink implements ConversationWorkTimeSink {
  final records =
      <({ConversationWorkKind kind, String detail, int ms, bool isError})>[];

  @override
  void record({
    required String conversationId,
    required ConversationWorkKind kind,
    required int durationMs,
    String detail = '',
    bool isError = false,
  }) {
    records.add((kind: kind, detail: detail, ms: durationMs, isError: isError));
  }
}

void main() {
  late DateTime now;
  late ApprovalWaitLedger ledger;
  late ToolWorkTimer timer;
  late _Sink sink;

  setUp(() {
    now = DateTime(2026, 10, 1, 9);
    ledger = ApprovalWaitLedger(clock: () => now);
    timer = ToolWorkTimer(approvals: ledger, clock: () => now);
    sink = _Sink();
  });

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  group('ApprovalWaitLedger', () {
    test('books each closed wait once and counts open waits live', () {
      ledger.sink = sink;
      ledger.opened('a1', 'c1');
      advance(2000);
      expect(ledger.waitedMs('c1'), 2000, reason: 'open wait counts');
      ledger.closed('a1');
      ledger.closed('a1');
      advance(500);

      expect(ledger.waitedMs('c1'), 2000);
      expect(ledger.waitedMs('c2'), 0);
      expect(sink.records, [
        (
          kind: ConversationWorkKind.approvalWait,
          detail: '',
          ms: 2000,
          isError: false,
        ),
      ]);
    });
  });

  group('ToolWorkTimer', () {
    test('records start-to-finish time per tool', () {
      timer.track('c1', 'read_file', 'queued', sink: sink);
      timer.track('c1', 'read_file', 'started', sink: sink);
      advance(150);
      timer.track('c1', 'read_file', 'completed', sink: sink);

      expect(sink.records.single.detail, 'read_file');
      expect(sink.records.single.ms, 150);
    });

    test('takes approval wait out of the tool time', () {
      timer.track('c1', 'run_command', 'started', sink: sink);
      advance(100);
      ledger.opened('a1', 'c1');
      advance(60000);
      ledger.closed('a1');
      advance(900);
      timer.track('c1', 'run_command', 'completed', sink: sink);

      expect(sink.records.single.ms, 1000);
    });

    test('ignores another conversation\'s approval', () {
      timer.track('c1', 'run_command', 'started', sink: sink);
      ledger.opened('a1', 'c2');
      advance(500);
      ledger.closed('a1');
      timer.track('c1', 'run_command', 'completed', sink: sink);

      expect(sink.records.single.ms, 500);
    });

    test('a skipped call that never started records nothing', () {
      timer.track('c1', 'read_file', 'skipped', sink: sink);
      expect(sink.records, isEmpty);
    });

    test('concurrent calls of one tool keep their exact total', () {
      timer.track('c1', 'read_file', 'started', sink: sink);
      advance(100);
      timer.track('c1', 'read_file', 'started', sink: sink);
      advance(50);
      timer.track('c1', 'read_file', 'completed', sink: sink);
      advance(300);
      timer.track('c1', 'read_file', 'completed', sink: sink);

      final total = sink.records.fold(0, (sum, r) => sum + r.ms);
      expect(total, 150 + 350);
    });

    test('clear books calls cut off mid-run as errors', () {
      timer.track('c1', 'git', 'started', sink: sink);
      advance(700);
      timer.clear('c1', sink: sink);
      timer.track('c1', 'git', 'completed', sink: sink);

      expect(sink.records.single.ms, 700);
      expect(sink.records.single.isError, isTrue);
    });
  });
}
