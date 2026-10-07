import 'dart:convert';

import 'package:caverno/features/chat/application/runtime/background_wait_iteration_refund.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ToolResultInfo wait({
    Object? waitMs = 120000,
    String status = 'running',
    ToolOutcome? outcome,
    String name = 'process_wait',
  }) => ToolResultInfo(
    id: 'wait-$status',
    name: name,
    arguments: {'job_id': 'proc_1', 'wait_ms': ?waitMs},
    result: jsonEncode({'job_id': 'proc_1', 'status': status}),
    outcome: outcome,
  );

  test('refunds a full-length wait on a job that is still running', () {
    // Session 23d19ede: seven 120s polls on an 11 minute release.
    final refund = BackgroundWaitIterationRefund();

    expect(refund.claim([wait()]), isTrue);
    expect(refund.claim([wait(), wait()]), isTrue);
    expect(refund.claim([wait(waitMs: '90000')]), isTrue);
    expect(refund.refunded, 3);
  });

  test('prefers the typed process state over the payload status', () {
    final refund = BackgroundWaitIterationRefund();

    expect(
      refund.claim([
        wait(
          status: 'running',
          outcome: const ToolOutcome(processState: ToolProcessState.exited),
        ),
      ]),
      isFalse,
    );
    expect(
      refund.claim([
        wait(
          status: 'unknown',
          outcome: const ToolOutcome(processState: ToolProcessState.running),
        ),
      ]),
      isTrue,
    );
  });

  test('earns nothing without evidence that the call blocked', () {
    final refund = BackgroundWaitIterationRefund();

    expect(refund.claim(const []), isFalse);
    expect(refund.claim([wait(status: 'exited')]), isFalse, reason: 'exited');
    expect(refund.claim([wait(waitMs: 15000)]), isFalse, reason: 'short poll');
    expect(refund.claim([wait(waitMs: null)]), isFalse, reason: 'no wait_ms');
    expect(
      refund.claim([wait(name: 'process_status')]),
      isFalse,
      reason: 'status spins do not block',
    );
    expect(
      refund.claim([wait(), wait(name: 'git_execute_command')]),
      isFalse,
      reason: 'a batch that also did work is work',
    );
    expect(refund.refunded, 0);
  });

  test('stops refunding at the cap', () {
    final refund = BackgroundWaitIterationRefund();
    for (var i = 0; i < BackgroundWaitIterationRefund.maxRefunds; i++) {
      expect(refund.claim([wait()]), isTrue);
    }

    expect(refund.claim([wait()]), isFalse);
    expect(refund.refunded, BackgroundWaitIterationRefund.maxRefunds);
  });
}
