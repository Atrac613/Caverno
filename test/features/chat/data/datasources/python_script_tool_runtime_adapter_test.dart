import 'dart:async';

import 'package:caverno/features/chat/data/datasources/python_script_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

import 'python_script_runtime_test_support.dart';

void main() {
  group('PythonScriptToolRuntimeAdapter exact success path', () {
    test(
      'binds owner messages, staging, approval, execution, and cache',
      () async {
        final fixture = PythonRuntimeFixture();

        final completion = await fixture.run();

        expect(
          completion.disposition,
          PythonScriptRuntimeDisposition.completed,
        );
        expect(completion.result.isSuccess, isTrue);
        expect(completion.identity.owner, testPythonOwner);
        expect(completion.identity.toolCallId, 'python-call');
        expect(fixture.ownerMessageCalls, 1);
        expect(fixture.stagingCalls, 1);
        expect(fixture.gateCalls, 1);
        expect(fixture.manualCalls, 0);
        expect(fixture.executionCalls, 1);
        expect(fixture.cleanupCalls, 1);
        expect(fixture.cacheWriteCalls, 1);
        expect(
          fixture.stagingRequest!.attachment!.originalImagePath,
          '/owner/input.png',
        );
        expect(fixture.approvalRequest!.identity.runtime, completion.identity);
        expect(fixture.executionRequest!.identity.runtime, completion.identity);
        expect(fixture.executionRequest!.arguments, {
          'code': 'print("ok")',
          'working_directory': '/tmp/caverno_python_test_python-call',
          'inputs': [
            {
              'name': 'input.png',
              'path': '/tmp/caverno_python_test_python-call/input.png',
              'mime': 'image/png',
            },
          ],
          'timeout_seconds': 7,
        });
        expect(
          () => fixture.executionRequest!.arguments['late'] = true,
          throwsUnsupportedError,
        );
        expect(
          fixture.cleanupRequest!.identity.directoryIdentity,
          fixture.executionRequest!.identity.directoryIdentity,
        );
        expect(
          fixture.cacheWriteRequest!.identity.runtime,
          completion.identity,
        );
      },
    );

    test('uses only the exact owner snapshot attachment', () async {
      final ownerAttachment = testPythonMessage(
        originalImagePath: '/owner/only.png',
      );
      final visiblePoison = testPythonMessage(
        id: 'visible-poison',
        originalImagePath: '/visible/poison.png',
      );
      final messages = <Message>[ownerAttachment];
      final fixture = PythonRuntimeFixture(messages: messages);
      final adapter = fixture.adapter;
      messages.add(visiblePoison);

      final completion = await adapter.handle(
        owner: testPythonOwner,
        toolCall: testPythonToolCall(),
      );

      expect(completion.disposition, PythonScriptRuntimeDisposition.completed);
      expect(
        fixture.stagingRequest!.attachment!.originalImagePath,
        '/owner/only.png',
      );
    });

    test('routes manual approval and records an exact denial', () async {
      final fixture = PythonRuntimeFixture(
        gate: ToolApprovalGateDecision.needsManualApproval,
        manualApproved: false,
      );

      final completion = await fixture.run();

      expect(completion.disposition, PythonScriptRuntimeDisposition.rejected);
      expect(
        completion.result.errorMessage,
        'User denied Python script execution',
      );
      expect(fixture.manualCalls, 1);
      expect(fixture.executionCalls, 0);
      expect(fixture.cacheWriteCalls, 1);
      expect(fixture.cleanupCalls, 1);
    });

    test('reuses exact cached denial without staging', () async {
      final denial = McpToolResult(
        toolName: 'run_python_script',
        result: '',
        isSuccess: false,
        errorMessage: 'Previously denied',
      );
      final fixture = PythonRuntimeFixture(cachedDenial: denial);

      final completion = await fixture.run();

      expect(completion.disposition, PythonScriptRuntimeDisposition.rejected);
      expect(completion.result, same(denial));
      expect(fixture.denialLookupCalls, 1);
      expect(fixture.stagingCalls, 0);
      expect(fixture.executionCalls, 0);
    });

    test('preserves full-access execution without writing cache', () async {
      final fixture = PythonRuntimeFixture(
        gate: ToolApprovalGateDecision.fullAccess,
      );

      final completion = await fixture.run();

      expect(completion.disposition, PythonScriptRuntimeDisposition.completed);
      expect(fixture.executionCalls, 1);
      expect(fixture.cacheWriteCalls, 0);
      expect(fixture.cleanupCalls, 1);
    });
  });

  group('PythonScriptToolRuntimeAdapter pre-effect fences', () {
    test('rejects mismatched owner-message acknowledgement', () async {
      final fixture = PythonRuntimeFixture(wrongOwnerMessageIdentity: true);

      final completion = await fixture.run();

      expect(completion.disposition, PythonScriptRuntimeDisposition.rejected);
      expect(fixture.stagingCalls, 0);
      expect(fixture.executionCalls, 0);
    });

    test(
      'returns ownerExpired before staging when lifecycle expires',
      () async {
        final fixture = PythonRuntimeFixture(
          lifecycleDisposition:
              PythonRuntimeAcknowledgementDisposition.ownerExpired,
        );

        final completion = await fixture.run();

        expect(
          completion.disposition,
          PythonScriptRuntimeDisposition.ownerExpired,
        );
        expect(fixture.stagingCalls, 0);
        expect(fixture.executionCalls, 0);
      },
    );

    test('maps an explicit gate rejection without execution', () async {
      final fixture = PythonRuntimeFixture(
        gateDisposition: PythonRuntimeAcknowledgementDisposition.rejected,
      );

      final completion = await fixture.run();

      expect(completion.disposition, PythonScriptRuntimeDisposition.rejected);
      expect(fixture.executionCalls, 0);
      expect(fixture.cleanupCalls, 1);
    });
  });

  group('PythonScriptToolRuntimeAdapter staging retirement', () {
    test('retireOwner drains the exact in-flight staging lease', () async {
      final executionStarted = Completer<void>();
      final executionRelease = Completer<void>();
      final fixture = PythonRuntimeFixture(
        executionStarted: executionStarted,
        executionRelease: executionRelease,
      );
      final pending = fixture.run();
      await executionStarted.future;

      final retirement = await fixture.adapter.retireOwner(testPythonOwner);

      expect(retirement.retiredReservationCount, 0);
      expect(retirement.cleanupClaimCount, 1);
      expect(retirement.settledCleanupCount, 1);
      expect(retirement.failedCleanupCount, 0);
      expect(retirement.cleanupSettled, isTrue);
      expect(retirement.outstandingCleanupAttempts, isEmpty);
      expect(fixture.cleanupCalls, 1);
      expect(fixture.cleanupRequest!.identity.runtime.owner, testPythonOwner);

      executionRelease.complete();
      await pending;
      expect(fixture.cleanupCalls, 1);
    });

    test('retireOwner preserves a failed cleanup for an exact retry', () async {
      final executionStarted = Completer<void>();
      final executionRelease = Completer<void>();
      final fixture = PythonRuntimeFixture(
        cleanupDisposition:
            PythonRuntimeAcknowledgementDisposition.effectUncertain,
        executionStarted: executionStarted,
        executionRelease: executionRelease,
      );
      final pending = fixture.run();
      await executionStarted.future;

      final failed = await fixture.adapter.retireOwner(testPythonOwner);

      expect(failed.cleanupClaimCount, 1);
      expect(failed.settledCleanupCount, 0);
      expect(failed.failedCleanupCount, 1);
      expect(failed.cleanupSettled, isFalse);
      expect(failed.outstandingCleanupAttempts, hasLength(1));

      fixture.cleanupDisposition =
          PythonRuntimeAcknowledgementDisposition.completed;
      final retried = await fixture.adapter.retireOwner(testPythonOwner);

      expect(retried.cleanupClaimCount, 1);
      expect(retried.settledCleanupCount, 1);
      expect(retried.cleanupSettled, isTrue);
      expect(retried.outstandingCleanupAttempts, isEmpty);
      expect(fixture.cleanupCalls, 2);

      executionRelease.complete();
      await pending;
      expect(fixture.cleanupCalls, 2);
    });

    test('clearAll drains every immediately claimable staging lease', () async {
      final executionStarted = Completer<void>();
      final executionRelease = Completer<void>();
      final fixture = PythonRuntimeFixture(
        executionStarted: executionStarted,
        executionRelease: executionRelease,
      );
      final pending = fixture.run();
      await executionStarted.future;

      final retirement = await fixture.adapter.clearAll();

      expect(retirement.cleanupClaimCount, 1);
      expect(retirement.settledCleanupCount, 1);
      expect(retirement.cleanupSettled, isTrue);
      expect(retirement.outstandingCleanupAttempts, isEmpty);

      executionRelease.complete();
      await pending;
    });
  });
}
