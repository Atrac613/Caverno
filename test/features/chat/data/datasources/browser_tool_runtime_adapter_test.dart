import 'dart:async';

import 'package:caverno/features/chat/data/datasources/browser_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/browser_session_ownership_coordinator.dart';
import 'package:caverno/features/chat/domain/services/browser_tool_contract.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 3,
);

void main() {
  test('forwards a safe action with one exact operation identity', () async {
    BrowserSessionOperationIdentity? executedOperation;
    BrowserExecutionRequest? executionRequest;
    final adapter = _adapter(
      execute: (operation, request) async {
        executedOperation = operation;
        executionRequest = request;
        return BrowserExecutionResult(
          operation: operation,
          result: _success(operation.toolName),
        );
      },
    );

    final result = await adapter.handle(
      owner: _owner,
      toolCall: ToolCallInfo(
        id: 'open-call',
        name: 'browser_open',
        arguments: const {'url': 'https://example.test'},
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(executedOperation?.owner, _owner);
    expect(executedOperation?.toolCallId, 'open-call');
    expect(executedOperation?.toolName, 'browser_open');
    expect(executionRequest?.operation, executedOperation);
    expect(executionRequest?.arguments, {'url': 'https://example.test'});
  });

  test('bridges lazy review, manual approval, and execution exactly', () async {
    BrowserSessionOperationIdentity? gateOperation;
    BrowserSessionOperationIdentity? manualOperation;
    BrowserApprovalGateRequest? gateRequest;
    BrowserManualApprovalRequest? manualRequest;
    final adapter = _adapter(
      resolveApprovalGate: (operation, request) async {
        gateOperation = operation;
        gateRequest = request;
        expect(request.reviewArguments, {
          'selector': '#password',
          'reason': 'Sign in.',
          'pageHost': 'example.test',
        });
        return BrowserApprovalGateResult(
          operation: operation,
          decision: ToolApprovalGateDecision.needsManualApproval,
        );
      },
      requestManualApproval: (operation, request) async {
        manualOperation = operation;
        manualRequest = request;
        return BrowserManualApprovalResult(
          operation: operation,
          approved: true,
        );
      },
    );

    final result = await adapter.handle(
      owner: _owner,
      toolCall: ToolCallInfo(
        id: 'fill-call',
        name: 'browser_fill',
        arguments: const {
          'selector': '#password',
          'value': 'secret',
          'reason': 'Sign in.',
        },
      ),
    );

    expect(result.isSuccess, isTrue);
    expect(gateOperation?.owner, _owner);
    expect(gateOperation?.toolCallId, 'fill-call');
    expect(manualOperation, gateOperation);
    expect(gateRequest?.sensitiveValuePreview, '•••••• (6 chars, hidden)');
    expect(
      manualRequest?.summary,
      'Fill selector "#password" with •••••• (6 chars, hidden)',
    );
    expect(manualRequest?.details, [
      'Tool: browser_fill',
      'Selector: #password',
      'Model reason: Sign in.',
      'Page: example.test',
    ]);
  });

  test(
    'retirement fences an in-flight action before its result returns',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final adapter = _adapter(
        execute: (operation, request) async {
          started.complete();
          await release.future;
          return BrowserExecutionResult(
            operation: operation,
            result: _success(operation.toolName),
          );
        },
      );
      final pending = adapter.handle(
        owner: _owner,
        toolCall: ToolCallInfo(
          id: 'open-call',
          name: 'browser_open',
          arguments: const {'url': 'https://example.test'},
        ),
      );

      await started.future;
      final clear = adapter.clearOwner(_owner);
      expect(clear.becameTerminal, isTrue);
      expect(clear.invalidatedLease?.operation.owner, _owner);
      release.complete();

      final result = await pending;
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'The browser operation expired before completion.',
      );
    },
  );

  test('clearAll invalidates the in-flight browser session lease', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final adapter = _adapter(
      execute: (operation, request) async {
        started.complete();
        await release.future;
        return BrowserExecutionResult(
          operation: operation,
          result: _success(operation.toolName),
        );
      },
    );
    final pending = adapter.handle(
      owner: _owner,
      toolCall: ToolCallInfo(
        id: 'open-call',
        name: 'browser_open',
        arguments: const {'url': 'https://example.test'},
      ),
    );

    await started.future;
    final invalidation = adapter.clearAll();
    expect(invalidation.invalidatedLease?.operation.owner, _owner);
    expect(
      invalidation.currentEpoch.epoch,
      greaterThan(invalidation.previousEpoch.epoch),
    );
    release.complete();

    final result = await pending;
    expect(result.isSuccess, isFalse);
    expect(
      result.errorMessage,
      'The browser operation expired before completion.',
    );
    final receipt = adapter.pendingEffectRecovery;
    expect(receipt, isNotNull);
    expect(adapter.clearEffectRecovery(receipt!), isTrue);
  });

  test(
    'retains the exact effect after a poisoned transport acknowledgement',
    () async {
      final adapter = _adapter(
        execute: (operation, request) async => BrowserExecutionResult(
          operation: BrowserSessionOperationIdentity(
            owner: operation.owner,
            toolCallId: 'poisoned-call',
            toolName: operation.toolName,
          ),
          result: _success(operation.toolName),
        ),
      );

      await expectLater(
        adapter.handle(
          owner: _owner,
          toolCall: ToolCallInfo(
            id: 'open-call',
            name: 'browser_open',
            arguments: const {'url': 'https://example.test'},
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Browser execution operation mismatch.',
          ),
        ),
      );

      final receipt = adapter.pendingEffectRecovery;
      expect(receipt, isNotNull);
      final blocked = await adapter.handle(
        owner: ChatTurnOwner(
          conversationId: 'conversation-b',
          interactionGeneration: 1,
        ),
        toolCall: ToolCallInfo(
          id: 'successor-call',
          name: 'browser_open',
          arguments: const {'url': 'https://successor.test'},
        ),
      );
      expect(blocked.isSuccess, isFalse);
      expect(blocked.result, contains('browser_busy'));
      expect(adapter.clearEffectRecovery(receipt!), isTrue);
    },
  );

  test('retains the exact effect when transport commits then throws', () async {
    final adapter = _adapter(
      execute: (operation, request) async {
        throw StateError('transport acknowledgement failed');
      },
    );

    await expectLater(
      adapter.handle(
        owner: _owner,
        toolCall: ToolCallInfo(
          id: 'open-call',
          name: 'browser_open',
          arguments: const {'url': 'https://example.test'},
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final receipt = adapter.pendingEffectRecovery;
    expect(receipt, isNotNull);
    expect(adapter.clearEffectRecovery(receipt!), isTrue);
  });

  test('withoutApproval bypasses the approval callbacks only', () async {
    var gateCalls = 0;
    var manualCalls = 0;
    final adapter = _adapter(
      resolveApprovalGate: (operation, request) async {
        gateCalls += 1;
        return BrowserApprovalGateResult(
          operation: operation,
          decision: ToolApprovalGateDecision.needsManualApproval,
        );
      },
      requestManualApproval: (operation, request) async {
        manualCalls += 1;
        return BrowserManualApprovalResult(
          operation: operation,
          approved: true,
        );
      },
    );

    final result = await adapter.handle(
      owner: _owner,
      toolCall: ToolCallInfo(
        id: 'eval-call',
        name: 'browser_eval',
        arguments: const {'script': 'document.title'},
      ),
      withoutApproval: true,
    );

    expect(result.isSuccess, isTrue);
    expect(gateCalls, 0);
    expect(manualCalls, 0);
  });
}

BrowserToolRuntimeAdapter _adapter({
  BrowserExecutionCallback? execute,
  BrowserApprovalGateCallback? resolveApprovalGate,
  BrowserManualApprovalCallback? requestManualApproval,
  BrowserSessionOwnershipCoordinator? sessionCoordinator,
}) {
  return BrowserToolRuntimeAdapter(
    sessionCoordinator:
        sessionCoordinator ?? BrowserSessionOwnershipCoordinator(),
    execute:
        execute ??
        (operation, request) async => BrowserExecutionResult(
          operation: operation,
          result: _success(operation.toolName),
        ),
    resolveApprovalGate:
        resolveApprovalGate ??
        (operation, request) async => BrowserApprovalGateResult(
          operation: operation,
          decision: ToolApprovalGateDecision.autoReviewAllowed,
        ),
    requestManualApproval:
        requestManualApproval ??
        (operation, request) async =>
            BrowserManualApprovalResult(operation: operation, approved: true),
    isOperationCurrent: (_) => true,
    expiredResult: (_) => null,
    currentPage: (operation) => BrowserPageObservation(
      operation: operation,
      currentUrl: 'https://example.test/account',
    ),
    resolveSaveTarget: (operation, request) async =>
        BrowserSaveTargetObservation(
          operation: operation,
          destinationLabel: 'Downloads',
          destinationChanged: false,
          requestedDestination: 'downloads',
          requestedFilename: request.filename,
          filename: request.filename,
          directoryPath: '/tmp',
          path: '/tmp/${request.filename}',
        ),
  );
}

McpToolResult _success(String toolName) {
  return McpToolResult(toolName: toolName, result: 'ok', isSuccess: true);
}
