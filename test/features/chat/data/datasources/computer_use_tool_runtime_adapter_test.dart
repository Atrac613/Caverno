import 'dart:async';
import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_runtime_identity.dart';
import 'package:caverno/features/chat/data/datasources/computer_use_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/computer_use_runtime_coordinator.dart';
import 'package:caverno/features/chat/domain/services/computer_use_tool_contract.dart';
import 'package:test/test.dart';

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);
final _initialTime = DateTime.utc(2026, 7, 31, 12);

void main() {
  group('ComputerUseToolRuntimeAdapter', () {
    test(
      'binds approval, transport, observation, and audit to one identity',
      () async {
        final fixture = _Fixture();
        fixture.actionResult = const McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true,"text":"secret"}',
          isSuccess: true,
        );
        fixture.observationResult = const McpToolResult(
          toolName: 'computer_vision_observe',
          result:
              '{"ok":true,"imageBase64":"image","imageMimeType":"image/png"}',
          isSuccess: true,
        );

        final result = await fixture.adapter.handle(
          owner: _owner,
          toolCall: _click(
            'click-a',
            arguments: {
              'x': 10,
              'y': 20,
              'target': {'label': 'Save', 'role': 'button', 'action': 'click'},
            },
          ),
        );

        expect(fixture.events, [
          'lookup',
          'approval',
          'execute',
          'observe',
          'audit:approved',
        ]);
        final approvalRequest = fixture.approvals.single;
        final executionRequest = fixture.executions.single;
        final observationRequest = fixture.observations.single;
        expect(approvalRequest.toolRequest, same(executionRequest));
        expect(observationRequest.toolRequest, same(executionRequest));
        expect(executionRequest.owner, _owner);
        expect(executionRequest.toolCallId, 'click-a');
        expect(executionRequest.toolName, 'computer_click');
        expect(executionRequest.runtimeSessionId, 'runtime-a');
        expect(executionRequest.runtimeRevision, 3);
        expect(executionRequest.argumentDigest, hasLength(64));
        expect(
          fixture.lifecycleIdentities,
          everyElement(executionRequest.identity),
        );
        expect(
          fixture.runtimeIdentities,
          everyElement(executionRequest.identity),
        );
        expect(fixture.runtimeIdentities, isNotEmpty);
        expect(approvalRequest.target, {
          'label': 'Save',
          'role': 'button',
          'action': 'click',
        });
        expect(
          observationRequest.observationToolName,
          'computer_vision_observe',
        );

        final payload = jsonDecode(result.result) as Map<String, dynamic>;
        expect(payload['action'], {
          'ok': true,
          'textRedacted': true,
          'textLength': 6,
        });
        expect(payload['imageBase64'], 'image');
        expect(fixture.audits.single.postActionObservation?.success, isTrue);
      },
    );

    test('routes observation-only tools without approval', () async {
      final fixture = _Fixture();
      fixture.actionResult = const McpToolResult(
        toolName: 'computer_get_permissions',
        result: '{"ok":true}',
        isSuccess: true,
      );

      final result = await fixture.adapter.handle(
        owner: _owner,
        toolCall: ToolCallInfo(
          id: 'permissions-a',
          name: 'computer_get_permissions',
          arguments: const {},
        ),
      );

      expect(result, same(fixture.actionResult));
      expect(fixture.events, ['execute', 'audit:not_required']);
      expect(fixture.approvals, isEmpty);
      expect(fixture.observations, isEmpty);
    });

    test('records and rebinds a cached denial to the current call', () async {
      final fixture = _Fixture()
        ..approvalOutcome = const ComputerUseApprovalOutcome.decided(
          ComputerUseApprovalDecision(
            approved: false,
            armed: false,
            blockerCode: 'approval_denied',
          ),
        );

      final first = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );
      final second = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-b'),
      );

      expect(first.isSuccess, isFalse);
      expect(second, same(fixture.cachedDenial));
      expect(fixture.approvals, hasLength(1));
      expect(fixture.executions, isEmpty);
      expect(fixture.events, [
        'lookup',
        'approval',
        'audit:denied',
        'remember',
        'lookup',
      ]);
    });

    test('rejects a retired owner before approval or transport', () async {
      final fixture = _Fixture()..ownerCurrent = false;

      final result = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );

      _expectExpired(result);
      expect(fixture.approvals, isEmpty);
      expect(fixture.executions, isEmpty);
      expect(fixture.lifecycleIdentities.single.toolCallId, 'click-a');
    });

    test(
      'rejects another conversation owner with shared runtime state',
      () async {
        final fixture = _Fixture(sharedRuntime: true)
          ..currentOwner = ChatTurnOwner(
            conversationId: 'conversation-b',
            interactionGeneration: 7,
          );

        final result = await fixture.adapter.handle(
          owner: _owner,
          toolCall: _click('click-a'),
        );

        _expectExpired(result);
        expect(fixture.approvals, isEmpty);
        expect(fixture.executions, isEmpty);
        expect(
          fixture.runtimeIdentityProvider.capture().sessionId,
          'runtime-a',
        );
      },
    );

    test('rejects a helper-session poison while approval is pending', () async {
      final fixture = _Fixture(sharedRuntime: true);
      final approval = Completer<ComputerUseApprovalOutcome>();
      fixture.approvalCompleter = approval;
      final resultFuture = fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );
      expect(fixture.approvals, hasLength(1));

      final invalidation = fixture.runtimeIdentityProvider.helperRestarted();
      approval.complete(
        const ComputerUseApprovalOutcome.decided(
          ComputerUseApprovalDecision(approved: true, armed: true),
        ),
      );

      _expectExpired(await resultFuture);
      expect(invalidation.rotatedSession, isTrue);
      expect(invalidation.current.revision, 4);
      expect(fixture.executions, isEmpty);
    });

    test(
      'rejects a runtime-revision poison while approval is pending',
      () async {
        final fixture = _Fixture(sharedRuntime: true);
        final approval = Completer<ComputerUseApprovalOutcome>();
        fixture.approvalCompleter = approval;
        final resultFuture = fixture.adapter.handle(
          owner: _owner,
          toolCall: _click('click-a'),
        );
        expect(fixture.approvals, hasLength(1));

        final invalidation = fixture.runtimeIdentityProvider.emergencyStop();
        approval.complete(
          const ComputerUseApprovalOutcome.decided(
            ComputerUseApprovalDecision(approved: true, armed: true),
          ),
        );

        _expectExpired(await resultFuture);
        expect(invalidation.rotatedSession, isFalse);
        expect(invalidation.current.sessionId, 'runtime-a');
        expect(invalidation.current.revision, 4);
        expect(fixture.executions, isEmpty);
      },
    );

    test(
      'reports uncertainty when the owner retires after transport',
      () async {
        final fixture = _Fixture();
        fixture.afterExecute = () {
          final retirement = fixture.adapter.retireOwner(_owner);
          expect(
            retirement.disposition,
            ComputerUseTerminalClearDisposition.cleared,
          );
        };

        final result = await fixture.adapter.handle(
          owner: _owner,
          toolCall: _click('click-a'),
        );

        _expectUncertain(result);
        expect(fixture.executions, hasLength(1));
        expect(fixture.observations, isEmpty);
        expect(fixture.audits.single.effectUncertain, isTrue);
      },
    );

    test(
      'reports uncertainty when the helper changes after transport',
      () async {
        final fixture = _Fixture();
        fixture.afterExecute = () {
          fixture.runtime = ComputerUseRuntimeState(
            sessionId: 'runtime-b',
            revision: 4,
          );
        };

        final result = await fixture.adapter.handle(
          owner: _owner,
          toolCall: _click('click-a'),
        );

        _expectUncertain(result);
        expect(fixture.observations, isEmpty);
        expect(fixture.audits.single.effectUncertain, isTrue);
      },
    );

    test('settles helper invalidation during the transport effect', () async {
      final fixture = _Fixture();
      fixture.afterExecute = fixture.adapter.helperRestarted;

      final result = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );

      _expectUncertain(result);
      final secondRestart = fixture.adapter.helperRestarted();
      expect(
        secondRestart.disposition,
        ComputerUseRuntimeInvalidationDisposition.invalidated,
      );
    });

    test('fences an in-flight action when the helper restarts', () async {
      final fixture = _Fixture(sharedRuntime: true);
      final started = Completer<void>();
      final execution = Completer<McpToolResult>();
      fixture
        ..executionStarted = started
        ..executionCompleter = execution;
      final resultFuture = fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );
      await started.future;

      final invalidation = fixture.runtimeIdentityProvider.helperRestarted();
      execution.complete(
        const McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true}',
          isSuccess: true,
        ),
      );

      _expectUncertain(await resultFuture);
      expect(
        invalidation.cause,
        MacosComputerUseRuntimeInvalidationCause.helperRestart,
      );
      expect(fixture.observations, isEmpty);
      expect(fixture.audits.single.effectUncertain, isTrue);
    });

    test('fences an in-flight action on emergency stop', () async {
      final fixture = _Fixture(sharedRuntime: true);
      final started = Completer<void>();
      final execution = Completer<McpToolResult>();
      fixture
        ..executionStarted = started
        ..executionCompleter = execution;
      final resultFuture = fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );
      await started.future;

      final invalidation = fixture.runtimeIdentityProvider.emergencyStop();
      execution.complete(
        const McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true}',
          isSuccess: true,
        ),
      );

      _expectUncertain(await resultFuture);
      expect(
        invalidation.cause,
        MacosComputerUseRuntimeInvalidationCause.emergencyStop,
      );
      expect(fixture.observations, isEmpty);
      expect(fixture.audits.single.effectUncertain, isTrue);
    });

    test(
      'converts a post-effect retirement exception to uncertainty',
      () async {
        final fixture = _Fixture();
        fixture.executionError = StateError('transport ended ambiguously');
        fixture.afterExecute = () => fixture.adapter.retireOwner(_owner);

        final result = await fixture.adapter.handle(
          owner: _owner,
          toolCall: _click('click-a'),
        );

        _expectUncertain(result);
        expect(fixture.audits.single.effectUncertain, isTrue);
      },
    );

    test('treats a post-dispatch transport exception as uncertain', () async {
      final fixture = _Fixture()
        ..executionError = StateError('transport unavailable');

      final result = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );

      _expectUncertain(result);
      expect(fixture.audits.single.effectUncertain, isTrue);
    });

    test('rejects new actions while the helper is transitioning', () async {
      final fixture = _Fixture(sharedRuntime: true);
      final transition = fixture.runtimeIdentityProvider.beginHelperRestart();

      final result = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );

      _expectExpired(result);
      expect(fixture.approvals, isEmpty);
      expect(fixture.executions, isEmpty);
      expect(
        fixture.runtimeIdentityProvider.captureSnapshot().availability,
        MacosComputerUseRuntimeAvailability.transitioning,
      );
      expect(
        fixture.runtimeIdentityProvider.finishTransition(
          transition,
          helperAvailable: true,
        ),
        isTrue,
      );
    });

    test('reports uncertainty for a rejected audit acknowledgement', () async {
      final fixture = _Fixture()..auditAccepted = false;

      final result = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );

      _expectUncertain(result);
      expect(fixture.audits, hasLength(2));
      expect(fixture.audits.last.effectUncertain, isTrue);
    });

    test('reports uncertainty when audit recording throws', () async {
      final fixture = _Fixture()..auditError = StateError('audit unavailable');

      final result = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );

      _expectUncertain(result);
      expect(fixture.auditAttempts, 2);
    });

    test('rejects an observation response for another tool', () async {
      final fixture = _Fixture();
      fixture.observationResult = const McpToolResult(
        toolName: 'computer_get_permissions',
        result: '{"ok":true}',
        isSuccess: true,
      );

      final result = await fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );

      _expectUncertain(result);
      expect(fixture.audits.single.effectUncertain, isTrue);
    });

    test('freezes strict JSON before any runtime callback', () async {
      final fixture = _Fixture();
      final invalidValues = <Object?>[
        <Object?>{'set'},
        <Object?, Object?>{7: 'non-string key'},
        double.nan,
        double.negativeInfinity,
      ];

      for (final invalid in invalidValues) {
        await expectLater(
          fixture.adapter.handle(
            owner: _owner,
            toolCall: _click(
              'click-a',
              arguments: {'x': 1, 'y': 2, 'invalid': invalid},
            ),
          ),
          throwsArgumentError,
        );
      }

      expect(fixture.runtimeCaptureCount, 0);
      expect(fixture.approvals, isEmpty);
      expect(fixture.executions, isEmpty);
    });

    test('rejects a non-Computer Use tool before runtime capture', () async {
      final fixture = _Fixture();

      await expectLater(
        fixture.adapter.handle(
          owner: _owner,
          toolCall: ToolCallInfo(
            id: 'shell-a',
            name: 'local_execute_command',
            arguments: const {'command': 'pwd'},
          ),
        ),
        throwsArgumentError,
      );

      expect(fixture.runtimeCaptureCount, 0);
      expect(fixture.executions, isEmpty);
    });

    test(
      'holds an immutable argument snapshot across approval await',
      () async {
        final fixture = _Fixture();
        final approval = Completer<ComputerUseApprovalOutcome>();
        fixture.approvalCompleter = approval;
        final nested = <String, dynamic>{
          'label': 'Save',
          'metadata': <String, dynamic>{
            'tags': <String>['primary'],
          },
        };
        final arguments = <String, dynamic>{'x': 1, 'y': 2, 'target': nested};

        final resultFuture = fixture.adapter.handle(
          owner: _owner,
          toolCall: _click('click-a', arguments: arguments),
        );
        final captured = fixture.approvals.single.toolRequest;
        final digest = captured.argumentDigest;
        nested['label'] = 'Poison';
        (nested['metadata'] as Map<String, dynamic>)['tags'] = ['poison'];
        arguments['x'] = 999;

        expect(captured.arguments['x'], 1);
        expect(captured.arguments['target'], {
          'label': 'Save',
          'metadata': {
            'tags': ['primary'],
          },
        });
        expect(captured.argumentDigest, digest);
        expect(
          () => (captured.arguments['target'] as Map)['late'] = true,
          throwsUnsupportedError,
        );

        approval.complete(
          const ComputerUseApprovalOutcome.decided(
            ComputerUseApprovalDecision(approved: true, armed: true),
          ),
        );
        expect((await resultFuture).isSuccess, isTrue);
      },
    );

    test('expires authorization while approval is pending', () async {
      final fixture = _Fixture();
      final approval = Completer<ComputerUseApprovalOutcome>();
      fixture.approvalCompleter = approval;
      final resultFuture = fixture.adapter.handle(
        owner: _owner,
        toolCall: _click('click-a'),
      );
      fixture.now = fixture.now.add(const Duration(minutes: 6));
      approval.complete(
        const ComputerUseApprovalOutcome.decided(
          ComputerUseApprovalDecision(approved: true, armed: true),
        ),
      );

      _expectExpired(await resultFuture);
      expect(fixture.executions, isEmpty);
    });

    test('returns typed idempotent lifecycle acknowledgements', () {
      final fixture = _Fixture();

      final first = fixture.adapter.retireOwner(_owner);
      final second = fixture.adapter.retireOwner(_owner);
      final stopped = fixture.adapter.emergencyStop();
      final cleared = fixture.adapter.clearAll();

      expect(first.disposition, ComputerUseTerminalClearDisposition.cleared);
      expect(
        second.disposition,
        ComputerUseTerminalClearDisposition.alreadyCleared,
      );
      expect(stopped.cause, ComputerUseRuntimeInvalidationCause.emergencyStop);
      expect(cleared.disposition, ComputerUseTerminalClearDisposition.cleared);
      expect(
        fixture.adapter.clearAll().disposition,
        ComputerUseTerminalClearDisposition.alreadyCleared,
      );
    });
  });
}

final class _Fixture {
  _Fixture({bool sharedRuntime = false}) {
    runtimeIdentityProvider = MacosComputerUseRuntimeIdentityProvider(
      initialSessionId: 'runtime-a',
      initialRevision: 3,
      sessionIdFactory: () => 'runtime-${_nextRuntimeSession++}',
    );
    adapter = ComputerUseToolRuntimeAdapter(
      runtimeCoordinator: runtimeCoordinator,
      captureRuntimeState: sharedRuntime
          ? null
          : (expectedIdentity) {
              runtimeCaptureCount++;
              if (expectedIdentity != null) {
                runtimeIdentities.add(expectedIdentity);
              }
              return runtime;
            },
      runtimeIdentityProvider: sharedRuntime ? runtimeIdentityProvider : null,
      ownerIsCurrent: (identity) {
        lifecycleIdentities.add(identity);
        return ownerCurrent && identity.owner == currentOwner;
      },
      lookupDenial: (request) {
        events.add('lookup');
        return cachedDenial;
      },
      requestApproval: (request) async {
        events.add('approval');
        approvals.add(request);
        final completer = approvalCompleter;
        return completer == null ? approvalOutcome : completer.future;
      },
      rememberDenial: (request, result) {
        events.add('remember');
        cachedDenial = result;
        return denialAccepted;
      },
      execute: (request, lease) async {
        events.add('execute');
        executions.add(request);
        final started = executionStarted;
        if (started != null && !started.isCompleted) {
          started.complete();
        }
        afterExecute?.call();
        final error = executionError;
        if (error != null) throw error;
        final completer = executionCompleter;
        if (completer != null) return completer.future;
        return actionResult ??
            McpToolResult(
              toolName: request.toolName,
              result: '{"ok":true}',
              isSuccess: true,
            );
      },
      observe: (request, lease) async {
        events.add('observe');
        observations.add(request);
        afterObserve?.call();
        return observationResult ??
            McpToolResult(
              toolName: request.observationToolName,
              result: '{"ok":true}',
              isSuccess: true,
            );
      },
      recordAudit: (request, record) {
        auditAttempts++;
        final error = auditError;
        if (error != null) throw error;
        events.add('audit:${record.approvalResult}');
        audits.add(record);
        return auditAccepted;
      },
      clock: () => now,
    );
  }

  late final ComputerUseToolRuntimeAdapter adapter;
  late final MacosComputerUseRuntimeIdentityProvider runtimeIdentityProvider;
  final ComputerUseRuntimeCoordinator runtimeCoordinator =
      ComputerUseRuntimeCoordinator();
  DateTime now = _initialTime;
  ComputerUseRuntimeState runtime = ComputerUseRuntimeState(
    sessionId: 'runtime-a',
    revision: 3,
  );
  ChatTurnOwner currentOwner = _owner;
  bool ownerCurrent = true;
  bool denialAccepted = true;
  bool auditAccepted = true;
  int runtimeCaptureCount = 0;
  int auditAttempts = 0;
  final events = <String>[];
  final lifecycleIdentities = <ComputerUseOperationIdentity>[];
  final runtimeIdentities = <ComputerUseOperationIdentity>[];
  final approvals = <ComputerUseApprovalRequest>[];
  final executions = <ComputerUseToolRequest>[];
  final observations = <ComputerUseObservationRequest>[];
  final audits = <ComputerUseAuditRecord>[];
  ComputerUseApprovalOutcome approvalOutcome =
      const ComputerUseApprovalOutcome.decided(
        ComputerUseApprovalDecision(approved: true, armed: true),
      );
  Completer<ComputerUseApprovalOutcome>? approvalCompleter;
  McpToolResult? cachedDenial;
  McpToolResult? actionResult;
  McpToolResult? observationResult;
  Object? executionError;
  Object? auditError;
  Completer<void>? executionStarted;
  Completer<McpToolResult>? executionCompleter;
  void Function()? afterExecute;
  void Function()? afterObserve;
  int _nextRuntimeSession = 1;
}

ToolCallInfo _click(
  String id, {
  Map<String, dynamic> arguments = const {'x': 1, 'y': 2},
}) {
  return ToolCallInfo(id: id, name: 'computer_click', arguments: arguments);
}

void _expectExpired(McpToolResult result) {
  expect(result.isSuccess, isFalse);
  expect(result.result, isEmpty);
  expect(result.errorMessage, 'The approval turn expired before execution');
}

void _expectUncertain(McpToolResult result) {
  expect(result.isSuccess, isFalse);
  expect(result.result, isEmpty);
  expect(result.errorMessage, contains('may have completed'));
}
