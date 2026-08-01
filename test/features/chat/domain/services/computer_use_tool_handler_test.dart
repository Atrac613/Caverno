import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/computer_use_action_policy.dart';
import 'package:caverno/features/chat/domain/services/computer_use_runtime_coordinator.dart';
import 'package:caverno/features/chat/domain/services/computer_use_tool_handler.dart';
import 'package:test/test.dart';

final ownerA = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 3,
);
final ownerANext = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 4,
);
final ownerB = ChatTurnOwner(
  conversationId: 'conversation-b',
  interactionGeneration: 3,
);
final _now = DateTime.utc(2026, 7, 31, 12);
const _runtimeSessionId = 'runtime-session-a';
const _runtimeRevision = 7;

void main() {
  group('ComputerUseToolHandler approval routing', () {
    test(
      'preserves approval, action, observation, audit, and payload order',
      () async {
        final fixture = _Fixture();
        final request = _request('computer_click', {
          'x': 10,
          'y': 20,
          'window_id': 42,
          'display_id': 2,
          'vision_observation_id': 'vision-before',
          'reason': '  Click Save.  ',
        });
        const actionResult = McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true,"text":"secret","imageBase64":"old-image"}',
          isSuccess: true,
        );
        fixture.execution.result = _owned(request, actionResult);
        fixture.observation.result = _owned(
          request,
          const ComputerUsePostActionObservation(
            toolName: 'computer_vision_observe',
            success: true,
            result:
                '{"imageBase64":"new-image","imageMimeType":"image/jpeg",'
                '"windowId":42}',
          ),
        );

        final result = await fixture.handler.handle(request);
        final payload = jsonDecode(result.result) as Map<String, dynamic>;
        final approval = fixture.approval.requests.single;
        final observation = fixture.observation.requests.single;

        expect(fixture.events, [
          'cache',
          'approval',
          'execute:computer_click',
          'observe:computer_vision_observe',
          'audit:approved',
        ]);
        expect(approval.toolRequest, same(request));
        expect(approval.toolPolicy?.toolName, 'computer_click');
        expect(approval.presentation.summary, 'Click left at (10, 20)');
        expect(approval.target, {
          'label': 'Click target (10, 20)',
          'role': 'coordinate',
          'action': 'click',
        });
        expect(approval.exactText, isNull);
        expect(approval.reason, '  Click Save.  ');
        expect(approval.visionContext.details, [
          'Observation ID: vision-before',
          'Target window ID: 42',
          'Target display ID: 2',
        ]);
        expect(approval.details, [
          'Policy: pointer_input',
          'Risk category: input',
          'Requires approval: true',
          'Requires smoke arming: true',
          'Requires post-action observation: true',
          'Approval boundaries: target',
          'Action proposal next action: '
              'Ask the user to approve the exact target before acting.',
          'Tool: computer_click',
          'Coordinates: x=10, y=20',
          'Button: left',
          'Click count: 1',
          'Window ID: 42',
          'Display ID: 2',
          'Model reason: Click Save.',
        ]);
        expect(observation.toolRequest, same(request));
        expect(observation.actionResult, same(actionResult));
        expect(observation.arguments, {
          'target': 'window',
          'max_width': 800,
          'include_windows': true,
          'window_id': 42,
          'display_id': 2,
        });
        expect(payload['action'], {
          'ok': true,
          'textRedacted': true,
          'textLength': 6,
        });
        expect(payload['postActionObservation'], {
          'toolName': 'computer_vision_observe',
          'success': true,
          'imageAttached': true,
          'imageMimeType': 'image/jpeg',
          'windowId': 42,
        });
        expect(payload['imageBase64'], 'new-image');
        expect(payload['imageMimeType'], 'image/jpeg');
        expect(fixture.execution.audits.single.result, actionResult.result);
        expect(
          fixture.execution.audits.single.postActionObservation?.result,
          fixture.observation.result?.value.result,
        );
      },
    );

    test('returns and caches an exact manual denial', () async {
      final fixture = _Fixture()
        ..approval.outcome = const ComputerUseApprovalOutcome.decided(
          ComputerUseApprovalDecision(
            approved: false,
            armed: false,
            blockerCode: 'approval_denied',
          ),
        );
      final request = _request('computer_click', {'x': 1, 'y': 2});

      final result = await fixture.handler.handle(request);

      expect(fixture.events, ['cache', 'approval', 'audit:denied', 'remember']);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'User denied macOS computer use action.');
      expect(
        result.result,
        '{"ok":false,"toolName":"computer_click",'
        '"code":"approval_denied",'
        '"error":"User denied macOS computer use action.",'
        '"policy":{"toolName":"computer_click","category":"pointerInput",'
        '"riskCategory":"input","requiresUserApproval":true,'
        '"requiresSmokeArming":true,"allowedInPlanning":false,'
        '"requiresPostActionObservation":true,"emergencyStop":false,'
        '"policyLabel":"pointer_input"},"requiresUserApproval":true,'
        '"requiresSmokeArming":true,"emergencyStop":false,'
        '"nextAction":"Ask the user for explicit approval before retrying '
        'this Computer Use action."}',
      );
      expect(fixture.approval.remembered.single, same(result));
    });

    test('preserves arming and unusual denial audit mappings', () async {
      final cases = [
        (
          code: 'arming_missing',
          audit: 'arming_missing',
          error:
              'Computer Use action blocked because the unsafe arming confirmation was not enabled.',
        ),
        (
          code: 'action_policy_blocked',
          audit: 'denied',
          error: 'Computer Use action blocked by the target safety policy.',
        ),
      ];

      for (final testCase in cases) {
        final fixture = _Fixture()
          ..approval.outcome = ComputerUseApprovalOutcome.decided(
            ComputerUseApprovalDecision(
              approved: false,
              armed: false,
              blockerCode: testCase.code,
            ),
          );
        final result = await fixture.handler.handle(
          _request('computer_click', {'x': 1, 'y': 2}),
        );

        expect(fixture.execution.audits.single.approvalResult, testCase.audit);
        expect(result.errorMessage, testCase.error);
      }
    });

    test('blocks an approved action when required arming is absent', () async {
      final fixture = _Fixture()
        ..approval.outcome = const ComputerUseApprovalOutcome.decided(
          ComputerUseApprovalDecision(approved: true, armed: false),
        );

      final result = await fixture.handler.handle(
        _request('computer_click', {'x': 1, 'y': 2}),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Computer Use action blocked because the unsafe arming confirmation was not enabled.',
      );
      expect(fixture.events, [
        'cache',
        'approval',
        'audit:arming_missing',
        'remember',
      ]);
      expect(fixture.execution.requests, isEmpty);
    });

    test('blocks an approved proposal with missing exact text', () async {
      final fixture = _Fixture();
      final request = _request('computer_type_text');

      final result = await fixture.handler.handle(request);
      final payload = jsonDecode(result.result) as Map<String, dynamic>;

      expect(fixture.events, [
        'cache',
        'approval',
        'audit:blocked',
        'remember',
      ]);
      expect(payload['approvalBlockers'], containsAll(['exact_text_missing']));
      expect(payload['code'], 'action_policy_blocked');
      expect(
        fixture.approval.requests.single.actionProposalPolicy?.blockerCodes,
        ['exact_text_missing'],
      );
    });

    test('replays an owner-tagged cached denial before policy work', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      const denial = McpToolResult(
        toolName: 'computer_click',
        result: 'cached denial',
        isSuccess: false,
        errorMessage: 'denied',
      );
      fixture.approval.cached = _owned(request, denial);

      final result = await fixture.handler.handle(request);

      expect(result, same(denial));
      expect(fixture.events, ['cache']);
      expect(fixture.approval.requests, isEmpty);
      expect(fixture.execution.requests, isEmpty);
    });

    test('returns an owner-tagged immediate auto-review result', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      const denied = McpToolResult(
        toolName: 'computer_click',
        result: '{"code":"auto_review_denied"}',
        isSuccess: false,
        errorMessage: 'Auto-review denied',
      );
      fixture.approval.outcome = const ComputerUseApprovalOutcome.immediate(
        denied,
      );

      final result = await fixture.handler.handle(request);

      expect(result, same(denied));
      expect(fixture.events, ['cache', 'approval']);
      expect(fixture.execution.requests, isEmpty);
    });
  });

  group('ComputerUseToolHandler execution and observation results', () {
    test(
      'does not observe a failed action and returns the original result',
      () async {
        final fixture = _Fixture();
        final request = _request('computer_click', {'x': 1, 'y': 2});
        const failure = McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":false}',
          isSuccess: false,
          errorMessage: 'click failed',
        );
        fixture.execution.result = _owned(request, failure);

        final result = await fixture.handler.handle(request);

        expect(result, same(failure));
        expect(fixture.events, [
          'cache',
          'approval',
          'execute:computer_click',
          'audit:approved',
        ]);
        expect(fixture.observation.requests, isEmpty);
      },
    );

    test(
      'treats action transport errors as uncertain after dispatch',
      () async {
        final fixture = _Fixture()
          ..execution.error = StateError('transport failed');

        final result = await fixture.handler.handle(
          _request('computer_click', {'x': 1, 'y': 2}),
        );

        _expectUncertain(result);
        expect(fixture.events, [
          'cache',
          'approval',
          'execute:computer_click',
          'audit:approved',
        ]);
        expect(fixture.execution.audits.single.effectUncertain, isTrue);
      },
    );

    test('preserves the no-approval execution and audit route', () async {
      final fixture = _Fixture();
      final request = _request('computer_get_permissions');
      const actionResult = McpToolResult(
        toolName: 'computer_get_permissions',
        result: '{"ok":true}',
        isSuccess: true,
      );
      fixture.execution.result = _owned(request, actionResult);

      final result = await fixture.handler.handleWithoutApproval(request);

      expect(result, same(actionResult));
      expect(fixture.events, [
        'execute:computer_get_permissions',
        'audit:not_required',
      ]);
      expect(fixture.approval.requests, isEmpty);
      expect(
        fixture.execution.audits.single.policy?.riskCategory,
        MacosComputerUseRiskCategory.setup,
      );
    });

    test(
      'marks no-approval transport errors uncertain after dispatch',
      () async {
        final fixture = _Fixture()..execution.error = ArgumentError('offline');

        final result = await fixture.handler.handleWithoutApproval(
          _request('computer_get_permissions'),
        );

        _expectUncertain(result);
        expect(fixture.events, [
          'execute:computer_get_permissions',
          'audit:not_required',
        ]);
        expect(fixture.execution.audits.single.effectUncertain, isTrue);
      },
    );

    test(
      'returns an absent observation when policy does not require one',
      () async {
        final fixture = _Fixture();
        final request = _request('computer_get_permissions');
        final run = await fixture.handler.runPostActionObservation(
          request,
          MacosComputerUseToolPolicy.decision('computer_get_permissions'),
          const McpToolResult(
            toolName: 'computer_get_permissions',
            result: '{}',
            isSuccess: true,
          ),
          fixture.acquireLease(request),
        );

        expect(run.runtimeExpired, isFalse);
        expect(run.observation, isNull);
        expect(fixture.events, isEmpty);
      },
    );

    test('rejects action metadata before selecting an observation', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});

      final run = await fixture.handler.runPostActionObservation(
        request,
        MacosComputerUseToolPolicy.decision(request.toolName),
        const McpToolResult(
          toolName: 'computer_drag',
          result: '{"ok":true}',
          isSuccess: true,
        ),
        fixture.acquireLease(request),
      );

      expect(run.runtimeExpired, isTrue);
      expect(run.observation, isNull);
      expect(fixture.observation.requests, isEmpty);
    });

    test('selects the recovery observation with empty arguments', () async {
      final fixture = _Fixture();
      final request = _request('computer_stop_system_audio_recording');
      const actionResult = McpToolResult(
        toolName: 'computer_stop_system_audio_recording',
        result: '{"ok":true}',
        isSuccess: true,
      );
      fixture.observation.result = _owned(
        request,
        const ComputerUsePostActionObservation(
          toolName: 'computer_get_permissions',
          success: true,
          result: '{"ok":true}',
        ),
      );

      final run = await fixture.handler.runPostActionObservation(
        request,
        MacosComputerUseToolPolicy.decision(request.toolName),
        actionResult,
        fixture.acquireLease(request),
      );

      expect(run.observation?.toolName, 'computer_get_permissions');
      expect(fixture.observation.requests.single.arguments, isEmpty);
      expect(
        fixture.observation.requests.single.actionResult,
        same(actionResult),
      );
    });

    test(
      'composes an observation transport error as legacy metadata',
      () async {
        final fixture = _Fixture()
          ..observation.error = StateError('vision offline');
        final request = _request('computer_click', {'x': 1, 'y': 2});
        const actionResult = McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true}',
          isSuccess: true,
        );
        fixture.execution.result = _owned(request, actionResult);

        final result = await fixture.handler.handle(request);
        final payload = jsonDecode(result.result) as Map<String, dynamic>;

        expect(payload['postActionObservation'], {
          'toolName': 'computer_vision_observe',
          'success': false,
          'imageAttached': false,
          'errorCode': 'Bad state: vision offline',
          'ok': false,
          'code': 'Bad state: vision offline',
        });
        expect(fixture.events, [
          'cache',
          'approval',
          'execute:computer_click',
          'observe:computer_vision_observe',
          'audit:approved',
        ]);
      },
    );
  });

  group('ComputerUseToolHandler owner poison and stale effects', () {
    test('rejects a stale owner before the cache lookup', () async {
      final fixture = _Fixture()..approval.currentOwners.clear();

      final result = await fixture.handler.handle(
        _request('computer_click', {'x': 1, 'y': 2}),
      );

      _expectExpired(result);
      expect(fixture.events, isEmpty);
    });

    test('rejects another conversation cached result', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      fixture.approval.cached = ComputerUseOwnedValue(
        identity: _identity(request, owner: ownerB),
        value: const McpToolResult(
          toolName: 'computer_click',
          result: 'poison',
          isSuccess: true,
        ),
      );

      final result = await fixture.handler.handle(request);

      _expectExpired(result);
      expect(fixture.events, ['cache']);
      expect(fixture.execution.requests, isEmpty);
    });

    test('rejects another generation manual approval', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      fixture.approval.resultOwner = ownerANext;

      final result = await fixture.handler.handle(request);

      _expectExpired(result);
      expect(fixture.events, ['cache', 'approval']);
      expect(fixture.execution.requests, isEmpty);
    });

    test('rejects approval carrying another action identity', () async {
      final fixture = _Fixture()..approval.resultToolCallId = 'other-call';

      final result = await fixture.handler.handle(
        _request('computer_click', {'x': 1, 'y': 2}),
      );

      _expectExpired(result);
      expect(fixture.execution.requests, isEmpty);
    });

    test('does not execute after the owner expires during approval', () async {
      final fixture = _Fixture();
      fixture.approval.afterRequest = () {
        fixture.approval.currentOwners.remove(ownerA);
      };

      final result = await fixture.handler.handle(
        _request('computer_click', {'x': 1, 'y': 2}),
      );

      _expectExpired(result);
      expect(fixture.execution.requests, isEmpty);
      expect(fixture.execution.audits, isEmpty);
    });

    test(
      'rejects another action execution result before observation',
      () async {
        final fixture = _Fixture();
        final request = _request('computer_click', {'x': 1, 'y': 2});
        fixture.execution.result = ComputerUseOwnedValue(
          identity: _identity(request, toolCallId: 'other-call'),
          value: const McpToolResult(
            toolName: 'computer_click',
            result: '{"ok":true,"windowId":999}',
            isSuccess: true,
          ),
        );

        final result = await fixture.handler.handle(request);

        _expectUncertain(result);
        expect(fixture.observation.requests, isEmpty);
        expect(fixture.execution.audits.single.effectUncertain, isTrue);
      },
    );

    test(
      'rejects a nested action result with a different tool identity',
      () async {
        final fixture = _Fixture();
        final request = _request('computer_click', {'x': 1, 'y': 2});
        fixture.execution.result = _owned(
          request,
          const McpToolResult(
            toolName: 'computer_drag',
            result: '{"ok":true}',
            isSuccess: true,
          ),
        );

        final result = await fixture.handler.handle(request);

        _expectUncertain(result);
        expect(fixture.observation.requests, isEmpty);
        expect(fixture.execution.audits.single.effectUncertain, isTrue);
      },
    );

    test('warns and audits after action completion expires', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      fixture.execution.result = _owned(
        request,
        const McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true}',
          isSuccess: true,
        ),
      );
      fixture.execution.afterExecute = () {
        fixture.approval.currentOwners.remove(ownerA);
      };

      final result = await fixture.handler.handle(request);

      _expectUncertain(result);
      expect(fixture.observation.requests, isEmpty);
      expect(fixture.execution.audits.single.effectUncertain, isTrue);
    });

    test('rejects another conversation observation before audit', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      fixture.execution.result = _owned(
        request,
        const McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true}',
          isSuccess: true,
        ),
      );
      fixture.observation.result = ComputerUseOwnedValue(
        identity: _identity(request, owner: ownerB),
        value: const ComputerUsePostActionObservation(
          toolName: 'computer_vision_observe',
          success: true,
          result: '{"windowId":999}',
        ),
      );

      final result = await fixture.handler.handle(request);

      _expectUncertain(result);
      expect(fixture.execution.audits.single.effectUncertain, isTrue);
    });

    test('rejects another observation tool before audit', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      fixture.execution.result = _owned(
        request,
        const McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true}',
          isSuccess: true,
        ),
      );
      fixture.observation.result = _owned(
        request,
        const ComputerUsePostActionObservation(
          toolName: 'computer_get_permissions',
          success: true,
          result: '{"ok":true}',
        ),
      );

      final result = await fixture.handler.handle(request);

      _expectUncertain(result);
      expect(fixture.execution.audits.single.effectUncertain, isTrue);
    });

    test('warns and audits after observation completion expires', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      fixture.execution.result = _owned(
        request,
        const McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true}',
          isSuccess: true,
        ),
      );
      fixture.observation.result = _owned(
        request,
        const ComputerUsePostActionObservation(
          toolName: 'computer_vision_observe',
          success: true,
          result: '{"ok":true}',
        ),
      );
      fixture.observation.afterObserve = () {
        fixture.approval.currentOwners.remove(ownerA);
      };

      final result = await fixture.handler.handle(request);

      _expectUncertain(result);
      expect(fixture.execution.audits.single.effectUncertain, isTrue);
    });

    test(
      'does not convert a stale observation error into owner output',
      () async {
        final fixture = _Fixture();
        final request = _request('computer_click', {'x': 1, 'y': 2});
        fixture.execution.result = _owned(
          request,
          const McpToolResult(
            toolName: 'computer_click',
            result: '{"ok":true}',
            isSuccess: true,
          ),
        );
        fixture.observation.error = StateError('late');
        fixture.observation.afterObserve = () {
          fixture.approval.currentOwners.remove(ownerA);
        };

        final result = await fixture.handler.handle(request);

        _expectUncertain(result);
        expect(fixture.execution.audits.single.effectUncertain, isTrue);
      },
    );

    test('rejects a stale runtime before the cache lookup', () async {
      final fixture = _Fixture();
      fixture.runtime.state = ComputerUseRuntimeState(
        sessionId: _runtimeSessionId,
        revision: _runtimeRevision + 1,
      );

      final result = await fixture.handler.handle(
        _request('computer_click', {'x': 1, 'y': 2}),
      );

      _expectExpired(result);
      expect(fixture.events, isEmpty);
    });

    test('warns when the runtime changes after action completion', () async {
      final fixture = _Fixture();
      fixture.execution.afterExecute = () {
        fixture.runtime.state = ComputerUseRuntimeState(
          sessionId: 'runtime-session-b',
          revision: _runtimeRevision + 1,
        );
      };

      final result = await fixture.handler.handle(
        _request('computer_click', {'x': 1, 'y': 2}),
      );

      _expectUncertain(result);
      expect(fixture.observation.requests, isEmpty);
      expect(fixture.execution.audits.single.effectUncertain, isTrue);
    });

    test('settles a lease invalidated while the action is running', () async {
      final fixture = _Fixture();
      fixture.execution.afterExecute = fixture.coordinator.helperRestarted;

      final result = await fixture.handler.handle(
        _request('computer_click', {'x': 1, 'y': 2}),
      );

      _expectUncertain(result);
      expect(fixture.coordinator.activeLease, isNull);
    });

    test('does not start while another runtime lease is active', () async {
      final fixture = _Fixture();
      final blockingRequest = ComputerUseToolRequest(
        owner: ownerB,
        toolCallId: 'blocking-call',
        toolName: 'computer_get_permissions',
        arguments: const {},
        runtimeSessionId: _runtimeSessionId,
        runtimeRevision: _runtimeRevision,
        authorizationExpiresAt: _now.add(const Duration(minutes: 5)),
      );
      fixture.acquireLease(blockingRequest);

      final result = await fixture.handler.handle(
        _request('computer_click', {'x': 1, 'y': 2}),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Another Computer Use action is still active',
      );
      expect(fixture.execution.requests, isEmpty);
    });

    test('rejects a completion carrying another argument digest', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      fixture.execution.result = ComputerUseOwnedValue(
        identity: _identity(request, argumentDigest: 'another-digest'),
        value: const McpToolResult(
          toolName: 'computer_click',
          result: '{"ok":true}',
          isSuccess: true,
        ),
      );

      final result = await fixture.handler.handle(request);

      _expectUncertain(result);
      expect(fixture.execution.audits.single.effectUncertain, isTrue);
    });

    test('warns when the audit port acknowledges another operation', () async {
      final fixture = _Fixture();
      final request = _request('computer_click', {'x': 1, 'y': 2});
      fixture.execution.auditIdentity = _identity(
        request,
        toolCallId: 'another-call',
      );

      final result = await fixture.handler.handle(request);

      _expectUncertain(result);
      expect(fixture.execution.audits, hasLength(2));
      expect(fixture.execution.audits.last.effectUncertain, isTrue);
    });
  });

  group('ComputerUseToolHandler immutable packets', () {
    test('freezes action arguments before any asynchronous port call', () {
      final nested = <String, dynamic>{
        'labels': <String>['save'],
      };
      final arguments = <String, dynamic>{'x': 1, 'y': 2, 'target': nested};
      final request = _request('computer_click', arguments);

      (nested['labels'] as List<String>).add('poison');
      arguments['x'] = 999;

      expect(request.arguments['x'], 1);
      expect(request.arguments['target'], {
        'labels': ['save'],
      });
      expect(
        () => (request.arguments['target'] as Map)['late'] = true,
        throwsUnsupportedError,
      );
    });

    test('freezes approval details and target metadata', () {
      final request = _request('computer_click', {'x': 1, 'y': 2});
      final details = <String>['detail'];
      final labels = <Object?>['save'];
      final targetMetadata = <String, Object?>{
        'labels': labels,
        'flags': <Object?>['safe'],
      };
      final target = <String, dynamic>{
        'label': 'Save',
        'metadata': targetMetadata,
      };
      final approval = ComputerUseApprovalRequest(
        toolRequest: request,
        toolPolicy: null,
        actionProposalPolicy: null,
        presentation: ComputerUseActionPresentation(
          summary: 'Click',
          details: const [],
        ),
        target: target,
        exactText: null,
        visionContext: ComputerUseContext(summary: null, details: const []),
        details: details,
      );

      details.add('poison');
      target['label'] = 'Poison';
      labels.add('poison');
      (targetMetadata['flags'] as List<Object?>).add('poison');
      targetMetadata['labels'] = <Object?>['replaced'];

      expect(approval.details, ['detail']);
      expect(approval.target, {
        'label': 'Save',
        'metadata': {
          'labels': ['save'],
          'flags': ['safe'],
        },
      });
      expect(() => approval.details.add('late'), throwsUnsupportedError);
      expect(() => approval.target!['late'] = true, throwsUnsupportedError);
      expect(
        () => ((approval.target!['metadata'] as Map)['labels'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => ((approval.target!['metadata'] as Map)['flags'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
    });

    test('freezes observation arguments and retains the action result', () {
      final request = _request('computer_click', {'x': 1, 'y': 2});
      final regions = <Object?>['content'];
      final arguments = <String, dynamic>{'window_id': 42, 'regions': regions};
      const actionResult = McpToolResult(
        toolName: 'computer_click',
        result: '{"ok":true}',
        isSuccess: true,
      );
      final observation = ComputerUseObservationRequest(
        toolRequest: request,
        actionResult: actionResult,
        observationToolName: 'computer_vision_observe',
        arguments: arguments,
      );

      arguments['window_id'] = 999;
      regions.add('poison');

      expect(observation.actionResult, same(actionResult));
      expect(observation.arguments, {
        'window_id': 42,
        'regions': ['content'],
      });
      expect(
        () => observation.arguments['late'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => (observation.arguments['regions'] as List).add('late'),
        throwsUnsupportedError,
      );
    });
  });
}

ComputerUseToolRequest _request(
  String toolName, [
  Map<String, dynamic> arguments = const {},
]) {
  return ComputerUseToolRequest(
    owner: ownerA,
    toolCallId: 'call-$toolName',
    toolName: toolName,
    arguments: arguments,
    runtimeSessionId: _runtimeSessionId,
    runtimeRevision: _runtimeRevision,
    authorizationExpiresAt: _now.add(const Duration(minutes: 5)),
  );
}

ComputerUseOwnedValue<T> _owned<T>(ComputerUseToolRequest request, T value) {
  return ComputerUseOwnedValue(identity: request.identity, value: value);
}

ComputerUseOperationIdentity _identity(
  ComputerUseToolRequest request, {
  ChatTurnOwner? owner,
  String? toolCallId,
  String? toolName,
  String? argumentDigest,
  String? runtimeSessionId,
}) {
  return ComputerUseOperationIdentity(
    owner: owner ?? request.owner,
    toolCallId: toolCallId ?? request.toolCallId,
    toolName: toolName ?? request.toolName,
    argumentDigest: argumentDigest ?? request.argumentDigest,
    runtimeSessionId: runtimeSessionId ?? request.runtimeSessionId,
  );
}

void _expectExpired(McpToolResult result) {
  expect(result.isSuccess, isFalse);
  expect(result.result, isEmpty);
  expect(result.errorMessage, 'The approval turn expired before execution');
}

void _expectUncertain(McpToolResult result) {
  expect(result.isSuccess, isFalse);
  expect(result.result, isEmpty);
  expect(
    result.errorMessage,
    'The Computer Use action may have completed after its owner or runtime '
    'expired; inspect possible side effects before retrying',
  );
}

final class _Fixture {
  _Fixture()
    : approval = _FakeApprovalPort(),
      execution = _FakeExecutionPort(),
      observation = _FakeObservationPort(),
      runtime = _FakeRuntimeStatePort(),
      coordinator = ComputerUseRuntimeCoordinator() {
    approval.events = events;
    execution.events = events;
    observation.events = events;
    handler = ComputerUseToolHandler(
      executionPort: execution,
      approvalPort: approval,
      observationPort: observation,
      runtimeStatePort: runtime,
      runtimeCoordinator: coordinator,
      clock: () => _now,
    );
  }

  final List<String> events = [];
  final _FakeApprovalPort approval;
  final _FakeExecutionPort execution;
  final _FakeObservationPort observation;
  final _FakeRuntimeStatePort runtime;
  final ComputerUseRuntimeCoordinator coordinator;
  late final ComputerUseToolHandler handler;

  ComputerUseRuntimeLease acquireLease(ComputerUseToolRequest request) {
    final grant = coordinator
        .arm(
          identity: request.identity,
          runtimeRevision: request.runtimeRevision,
          armed: true,
          now: _now,
          expiresAt: request.authorizationExpiresAt,
        )
        .grant!;
    final permit = coordinator
        .consumeGrant(
          grant: grant,
          identity: request.identity,
          runtimeRevision: request.runtimeRevision,
          now: _now,
        )
        .permit!;
    return coordinator
        .acquireLease(
          permit: permit,
          identity: request.identity,
          currentRuntimeRevision: request.runtimeRevision,
          now: _now,
        )
        .lease!;
  }
}

final class _FakeApprovalPort implements ComputerUseApprovalPort {
  final Set<ChatTurnOwner> currentOwners = {ownerA};
  final List<ComputerUseApprovalRequest> requests = [];
  final List<McpToolResult> remembered = [];
  late List<String> events;
  ComputerUseOwnedValue<McpToolResult>? cached;
  ComputerUseApprovalOutcome outcome = const ComputerUseApprovalOutcome.decided(
    ComputerUseApprovalDecision(approved: true, armed: true),
  );
  ChatTurnOwner? resultOwner;
  String? resultToolCallId;
  String? resultToolName;
  void Function()? afterRequest;

  @override
  bool isOwnerCurrent(ChatTurnOwner owner) => currentOwners.contains(owner);

  @override
  ComputerUseOwnedValue<McpToolResult>? lookupDenial(
    ComputerUseToolRequest request,
  ) {
    events.add('cache');
    return cached;
  }

  @override
  Future<ComputerUseOwnedValue<ComputerUseApprovalOutcome>> requestApproval(
    ComputerUseApprovalRequest request,
  ) async {
    events.add('approval');
    requests.add(request);
    afterRequest?.call();
    return ComputerUseOwnedValue(
      identity: _identity(
        request.toolRequest,
        owner: resultOwner,
        toolCallId: resultToolCallId,
        toolName: resultToolName,
      ),
      value: outcome,
    );
  }

  @override
  ComputerUseEffectAcknowledgement rememberDenial(
    ComputerUseToolRequest request,
    McpToolResult result,
  ) {
    events.add('remember');
    remembered.add(result);
    return ComputerUseEffectAcknowledgement(
      identity: request.identity,
      accepted: true,
    );
  }
}

final class _FakeExecutionPort implements ComputerUseExecutionPort {
  late List<String> events;
  final List<ComputerUseToolRequest> requests = [];
  final List<ComputerUseAuditRecord> audits = [];
  ComputerUseOwnedValue<McpToolResult>? result;
  ComputerUseOperationIdentity? auditIdentity;
  bool auditAccepted = true;
  Object? error;
  void Function()? afterExecute;

  @override
  Future<ComputerUseOwnedValue<McpToolResult>> execute(
    ComputerUseToolRequest request,
    ComputerUseRuntimeLease lease,
  ) async {
    events.add('execute:${request.toolName}');
    requests.add(request);
    afterExecute?.call();
    if (error case final error?) throw error;
    return result ??
        _owned(
          request,
          McpToolResult(
            toolName: request.toolName,
            result: '{"ok":true}',
            isSuccess: true,
          ),
        );
  }

  @override
  ComputerUseEffectAcknowledgement recordAudit(
    ComputerUseToolRequest request,
    ComputerUseAuditRecord record,
  ) {
    events.add('audit:${record.approvalResult}');
    audits.add(record);
    return ComputerUseEffectAcknowledgement(
      identity: auditIdentity ?? request.identity,
      accepted: auditAccepted,
    );
  }
}

final class _FakeObservationPort implements ComputerUseObservationPort {
  late List<String> events;
  final List<ComputerUseObservationRequest> requests = [];
  ComputerUseOwnedValue<ComputerUsePostActionObservation>? result;
  Object? error;
  void Function()? afterObserve;

  @override
  Future<ComputerUseOwnedValue<ComputerUsePostActionObservation>> observe(
    ComputerUseObservationRequest request,
    ComputerUseRuntimeLease lease,
  ) async {
    events.add('observe:${request.observationToolName}');
    requests.add(request);
    afterObserve?.call();
    if (error case final error?) throw error;
    return result ??
        _owned(
          request.toolRequest,
          ComputerUsePostActionObservation(
            toolName: request.observationToolName,
            success: true,
            result: '{"ok":true}',
          ),
        );
  }
}

final class _FakeRuntimeStatePort implements ComputerUseRuntimeStatePort {
  ComputerUseRuntimeState state = ComputerUseRuntimeState(
    sessionId: _runtimeSessionId,
    revision: _runtimeRevision,
  );

  @override
  ComputerUseRuntimeState capture() => state;
}
