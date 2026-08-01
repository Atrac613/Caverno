import 'dart:async';

import 'package:caverno/features/chat/data/datasources/python_script_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:test/test.dart';

import 'python_script_runtime_test_support.dart';

void main() {
  group('PythonScriptToolRuntimeAdapter uncertain effects', () {
    test('treats mismatched staging acknowledgement as uncertain', () async {
      final fixture = PythonRuntimeFixture(wrongStagingIdentity: true);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionCalls, 0);
      expect(fixture.cleanupCalls, 0);
    });

    test('treats mismatched gate acknowledgement as uncertain', () async {
      final fixture = PythonRuntimeFixture(wrongGateIdentity: true);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionCalls, 0);
      expect(fixture.cleanupCalls, 1);
    });

    test('treats thrown execution completion as uncertain', () async {
      final fixture = PythonRuntimeFixture(throwDuringExecution: true);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionCalls, 1);
      expect(fixture.executionEffectCalls, 1);
      expect(fixture.cleanupCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
      expect(
        completion.result.errorMessage,
        contains('may have completed after its owner expired'),
      );
    });

    test('treats mismatched execution acknowledgement as uncertain', () async {
      final fixture = PythonRuntimeFixture(wrongExecutionIdentity: true);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionCalls, 1);
      expect(fixture.cleanupCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('retains explicit owner expiry after an admitted effect', () async {
      final fixture = PythonRuntimeFixture(
        executionDisposition:
            PythonRuntimeAcknowledgementDisposition.ownerExpired,
      );

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionCalls, 1);
      expect(fixture.executionEffectCalls, 1);
      expect(fixture.cleanupCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('treats mismatched cleanup acknowledgement as uncertain', () async {
      final fixture = PythonRuntimeFixture(wrongCleanupIdentity: true);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionCalls, 1);
      expect(fixture.cleanupCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('treats post-execution cache mismatch as uncertain', () async {
      final fixture = PythonRuntimeFixture(wrongCacheWriteIdentity: true);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionCalls, 1);
      expect(fixture.cacheWriteCalls, 1);
      expect(fixture.cleanupCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('retains a thrown final cache acknowledgement', () async {
      final fixture = PythonRuntimeFixture(throwDuringCacheWrite: true);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.cacheWriteCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('retains a cleanup error after execution', () async {
      final fixture = PythonRuntimeFixture(throwDuringCleanup: true);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionEffectCalls, 1);
      expect(fixture.cleanupCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('propagates explicit effect uncertainty from execution', () async {
      final fixture = PythonRuntimeFixture(
        executionDisposition:
            PythonRuntimeAcknowledgementDisposition.effectUncertain,
      );

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionCalls, 1);
      expect(fixture.cleanupCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('rejects a raw callback that bypasses its permit', () async {
      final fixture = PythonRuntimeFixture(invokeExecutionEffect: false);

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionEffectCalls, 0);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('retains a success result labeled as rejected', () async {
      final fixture = PythonRuntimeFixture(
        executionDisposition: PythonRuntimeAcknowledgementDisposition.rejected,
        executionResult: const McpToolResult(
          toolName: 'run_python_script',
          result: '{"ok":true}',
          isSuccess: true,
        ),
      );

      final completion = await fixture.run();

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionEffectCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNotNull);
    });

    test('settles a rejected pre-effect launch without a receipt', () async {
      final fixture = PythonRuntimeFixture(
        invokeExecutionEffect: false,
        executionDisposition: PythonRuntimeAcknowledgementDisposition.rejected,
      );

      final completion = await fixture.run();

      expect(completion.disposition, PythonScriptRuntimeDisposition.rejected);
      expect(fixture.executionEffectCalls, 0);
      expect(fixture.cacheWriteCalls, 1);
      expect(fixture.adapter.pendingExecutionRecovery, isNull);
    });

    test('revokes a delayed permit before the raw effect starts', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final fixture = PythonRuntimeFixture(
        executionStarted: started,
        executionRelease: release,
      );
      final pending = fixture.run();
      await started.future;

      final retirement = await fixture.adapter.retireOwner(testPythonOwner);
      release.complete();
      final completion = await pending;

      expect(
        completion.disposition,
        PythonScriptRuntimeDisposition.ownerExpired,
      );
      expect(fixture.executionEffectCalls, 0);
      expect(retirement.executionRecoveryReceipt, isNull);
      expect(fixture.adapter.pendingExecutionRecovery, isNull);
    });

    test('rejects foreign receipts and exact-identity mismatches', () async {
      final fixture = PythonRuntimeFixture(throwDuringExecution: true);
      await fixture.run();
      final receipt = fixture.adapter.pendingExecutionRecovery!;
      final foreign = PythonRuntimeFixture(throwDuringExecution: true);
      await foreign.run(toolCall: testPythonToolCall(id: 'foreign-call'));
      final foreignReceipt = foreign.adapter.pendingExecutionRecovery!;

      expect(fixture.adapter.clearExecutionRecovery(foreignReceipt), isFalse);
      expect(
        fixture.adapter.reconcileExecutionRecovery(
          receipt: receipt,
          observedIdentity: foreignReceipt.identity,
        ),
        isFalse,
      );
      expect(fixture.adapter.pendingExecutionRecovery, same(receipt));
      expect(
        fixture.adapter.reconcileExecutionRecovery(
          receipt: receipt,
          observedIdentity: receipt.identity,
        ),
        isTrue,
      );
      expect(fixture.adapter.pendingExecutionRecovery, isNull);
    });

    test('fences successors until exact recovery is cleared', () async {
      final authority = PythonScriptExecutionAuthority();
      final first = PythonRuntimeFixture(
        executionAuthority: authority,
        throwDuringExecution: true,
      );
      await first.run();
      final receipt = first.adapter.pendingExecutionRecovery!;
      final blocked = PythonRuntimeFixture(executionAuthority: authority);

      final blockedCompletion = await blocked.run(
        toolCall: testPythonToolCall(id: 'blocked-call'),
      );

      expect(
        blockedCompletion.disposition,
        PythonScriptRuntimeDisposition.effectUncertain,
      );
      expect(blocked.executionCalls, 0);
      expect(first.adapter.pendingExecutionRecovery, same(receipt));
      expect(first.adapter.clearExecutionRecovery(receipt), isTrue);

      final successor = PythonRuntimeFixture(executionAuthority: authority);
      final completion = await successor.run(
        toolCall: testPythonToolCall(id: 'successor-call'),
      );
      expect(completion.disposition, PythonScriptRuntimeDisposition.completed);
      expect(successor.executionEffectCalls, 1);
    });
  });
}
