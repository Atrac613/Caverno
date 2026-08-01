import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/participant_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/participant_tool_executor.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_approval_coordinator.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);
final _otherOwner = ChatTurnOwner(
  conversationId: 'conversation-b',
  interactionGeneration: 7,
);

void main() {
  group('ParticipantToolRuntimeAdapter', () {
    test('binds every callback to one strict invocation identity', () async {
      final fixture = _Fixture();
      final nested = <String, dynamic>{
        'path': 'lib/main.dart',
        'filters': <String, dynamic>{
          'extensions': <String>['dart'],
        },
      };

      final completion = await fixture.adapter.handle(
        _session(),
        _call(arguments: nested),
      );

      expect(
        completion.disposition,
        ParticipantToolRuntimeDisposition.completed,
      );
      expect(completion.result, same(fixture.executionResult));
      expect(fixture.events, [
        'approval',
        'activity:read_file',
        'execute',
        'taint',
        'activity:clear',
      ]);
      final identity = completion.identity;
      expect(identity.scope, _session().scope);
      expect(identity.toolCallId, 'call-a');
      expect(identity.toolName, 'read_file');
      expect(identity.argumentDigest, hasLength(64));
      expect(fixture.observedIdentities, everyElement(equals(identity)));
      expect(fixture.executionRequests.single.arguments, nested);
      expect(
        fixture.taintRequests.single.resultFingerprint,
        participantToolResultFingerprint(fixture.executionResult),
      );
    });

    test('holds immutable arguments across an approval await', () async {
      final fixture = _Fixture();
      final pending = Completer<ParticipantToolApprovalAcknowledgement>();
      fixture.pendingApproval = pending;
      final nested = <String, dynamic>{
        'path': 'docs/spec.md',
        'metadata': <String, dynamic>{
          'tags': <String>['review'],
        },
      };
      final future = fixture.adapter.handle(
        _session(),
        _call(arguments: nested),
      );
      final approval = fixture.approvalRequests.single;
      final identity = approval.identity;

      nested['path'] = 'poisoned';
      (nested['metadata'] as Map<String, dynamic>)['tags'] = ['poisoned'];
      expect(approval.request.manualArguments, {
        'path': 'docs/spec.md',
        'metadata': {
          'tags': ['review'],
        },
      });
      expect(
        () => (approval.request.manualArguments['metadata'] as Map)['late'] =
            true,
        throwsUnsupportedError,
      );

      pending.complete(
        ParticipantToolApprovalAcknowledgement(
          identity: identity,
          disposition: ParticipantToolApprovalDisposition.resolved,
          outcome: const ToolApprovalOutcome.approved(
            gateDecision: ToolApprovalGateDecision.autoReviewAllowed,
          ),
        ),
      );
      await future;
      expect(
        fixture.executionRequests.single.arguments['path'],
        'docs/spec.md',
      );
      expect(fixture.executionRequests.single.identity, identity);
    });

    test('rejects a stale approval acknowledgement before execution', () async {
      final fixture = _Fixture()
        ..approvalIdentity = _poisonIdentity(toolCallId: 'stale-call');

      final completion = await fixture.adapter.handle(_session(), _call());

      expect(
        completion.disposition,
        ParticipantToolRuntimeDisposition.boundaryMismatch,
      );
      _expectCode(completion.result, 'participant_tool_boundary_mismatch');
      expect(fixture.executionRequests, isEmpty);
      expect(fixture.activityRequests, isEmpty);
    });

    test('rejects malformed approval success before execution', () async {
      final fixture = _Fixture()..omitApprovalOutcome = true;

      final completion = await fixture.adapter.handle(_session(), _call());

      expect(
        completion.disposition,
        ParticipantToolRuntimeDisposition.boundaryMismatch,
      );
      expect(fixture.executionRequests, isEmpty);
    });

    test('reports post-dispatch acknowledgement poison as uncertain', () async {
      final fixture = _Fixture()
        ..executionIdentity = _poisonIdentity(toolName: 'web_search');

      final completion = await fixture.adapter.handle(_session(), _call());

      expect(
        completion.disposition,
        ParticipantToolRuntimeDisposition.effectUncertain,
      );
      _expectCode(completion.result, 'participant_tool_effect_uncertain');
      expect(fixture.executionRequests, hasLength(1));
      expect(fixture.taintRequests, isEmpty);
      expect(fixture.activityRequests.last.activeToolName, isEmpty);
    });

    test('reports a transport throw after dispatch as uncertain', () async {
      final fixture = _Fixture()
        ..executionError = StateError('transport ended ambiguously');

      final completion = await fixture.adapter.handle(_session(), _call());

      expect(
        completion.disposition,
        ParticipantToolRuntimeDisposition.effectUncertain,
      );
      _expectCode(completion.result, 'participant_tool_effect_uncertain');
      expect(fixture.taintRequests, isEmpty);
    });

    test('keeps certified owner expiry before effect distinct', () async {
      final fixture = _Fixture()
        ..executionDisposition =
            ParticipantToolExecutionDisposition.ownerExpiredBeforeEffect;

      final completion = await fixture.adapter.handle(_session(), _call());

      expect(
        completion.disposition,
        ParticipantToolRuntimeDisposition.ownerExpired,
      );
      _expectCode(completion.result, 'turn_owner_expired');
      expect(fixture.taintRequests, hasLength(1));
      expect(fixture.activityRequests.last.activeToolName, isEmpty);
    });

    test(
      'reports taint receipt mismatch after execution as uncertain',
      () async {
        final fixture = _Fixture()..taintFingerprint = 'stale-fingerprint';

        final completion = await fixture.adapter.handle(_session(), _call());

        expect(
          completion.disposition,
          ParticipantToolRuntimeDisposition.effectUncertain,
        );
        _expectCode(completion.result, 'participant_tool_effect_uncertain');
        expect(fixture.taintRequests, hasLength(1));
      },
    );

    test(
      'reports activity clear mismatch after execution as uncertain',
      () async {
        final fixture = _Fixture()
          ..clearActivityIdentity = _poisonIdentity(
            participantId: 'participant-b',
          );

        final completion = await fixture.adapter.handle(_session(), _call());

        expect(
          completion.disposition,
          ParticipantToolRuntimeDisposition.effectUncertain,
        );
        _expectCode(completion.result, 'participant_tool_effect_uncertain');
        expect(fixture.taintRequests, hasLength(1));
      },
    );

    test('maps explicit approval uncertainty without executing', () async {
      final fixture = _Fixture()
        ..approvalDisposition =
            ParticipantToolApprovalDisposition.effectUncertain;

      final completion = await fixture.adapter.handle(_session(), _call());

      expect(
        completion.disposition,
        ParticipantToolRuntimeDisposition.effectUncertain,
      );
      expect(fixture.executionRequests, isEmpty);
    });

    test('rejects non-JSON arguments before callbacks', () async {
      final invalidValues = <Object?>[
        <Object?>{'set'},
        <Object?, Object?>{7: 'numeric key'},
        Object(),
        double.nan,
        double.infinity,
      ];

      for (final invalid in invalidValues) {
        final fixture = _Fixture();
        await expectLater(
          fixture.adapter.handle(
            _session(),
            _call(arguments: {'invalid': invalid}),
          ),
          throwsArgumentError,
        );
        expect(fixture.events, isEmpty);
      }
    });

    test('filters definitions using participant availability and policy', () {
      final fixture = _Fixture();

      expect(
        fixture.adapter
            .definitionsFor(_session())
            .map((definition) => (definition['function'] as Map)['name']),
        ['read_file'],
      );
      expect(
        fixture.adapter.definitionsFor(
          _session(participant: _participant(toolsEnabled: false)),
        ),
        isEmpty,
      );
      expect(
        fixture.adapter.definitionsFor(
          _session(supportsToolAwareRequests: false),
        ),
        isEmpty,
      );
    });

    test('uses canonical argument order and exact result fingerprints', () {
      expect(
        participantToolArgumentDigest({
          'b': 2,
          'a': {'d': 4, 'c': 3},
        }),
        participantToolArgumentDigest({
          'a': {'c': 3, 'd': 4},
          'b': 2,
        }),
      );
      expect(
        participantToolResultFingerprint(fixtureResult('one')),
        isNot(participantToolResultFingerprint(fixtureResult('two'))),
      );
    });
  });
}

final class _Fixture {
  _Fixture() {
    adapter = ParticipantToolRuntimeAdapter(
      resolveApproval: (request) async {
        events.add('approval');
        approvalRequests.add(request);
        observedIdentities.add(request.identity);
        final pending = pendingApproval;
        if (pending != null) return pending.future;
        return ParticipantToolApprovalAcknowledgement(
          identity: approvalIdentity ?? request.identity,
          disposition: approvalDisposition,
          outcome: omitApprovalOutcome
              ? null
              : const ToolApprovalOutcome.approved(
                  gateDecision: ToolApprovalGateDecision.autoReviewAllowed,
                ),
        );
      },
      execute: (request) async {
        events.add('execute');
        executionRequests.add(request);
        observedIdentities.add(request.identity);
        final error = executionError;
        if (error != null) throw error;
        return ParticipantToolExecutionAcknowledgement(
          identity: executionIdentity ?? request.identity,
          disposition: executionDisposition,
          result:
              executionDisposition ==
                  ParticipantToolExecutionDisposition.ownerExpiredBeforeEffect
              ? null
              : executionResult,
        );
      },
      projectActivity: (request) {
        events.add(
          request.activeToolName.isEmpty
              ? 'activity:clear'
              : 'activity:${request.activeToolName}',
        );
        activityRequests.add(request);
        observedIdentities.add(request.identity);
        return ParticipantToolActivityAcknowledgement(
          identity: request.activeToolName.isEmpty
              ? clearActivityIdentity ?? request.identity
              : startActivityIdentity ?? request.identity,
          activeToolName: request.activeToolName,
          disposition: request.activeToolName.isEmpty
              ? clearActivityDisposition
              : startActivityDisposition,
        );
      },
      recordTaint: (request) {
        events.add('taint');
        taintRequests.add(request);
        observedIdentities.add(request.identity);
        return ParticipantToolTaintAcknowledgement(
          identity: taintIdentity ?? request.identity,
          resultFingerprint: taintFingerprint ?? request.resultFingerprint,
          disposition: taintDisposition,
        );
      },
    );
  }

  late final ParticipantToolRuntimeAdapter adapter;
  final List<String> events = [];
  final List<ParticipantToolRuntimeIdentity> observedIdentities = [];
  final List<ParticipantToolRuntimeApprovalRequest> approvalRequests = [];
  final List<ParticipantToolRuntimeExecutionRequest> executionRequests = [];
  final List<ParticipantToolRuntimeActivityRequest> activityRequests = [];
  final List<ParticipantToolRuntimeTaintRequest> taintRequests = [];

  Completer<ParticipantToolApprovalAcknowledgement>? pendingApproval;
  ParticipantToolRuntimeIdentity? approvalIdentity;
  ParticipantToolApprovalDisposition approvalDisposition =
      ParticipantToolApprovalDisposition.resolved;
  bool omitApprovalOutcome = false;
  ParticipantToolRuntimeIdentity? executionIdentity;
  ParticipantToolExecutionDisposition executionDisposition =
      ParticipantToolExecutionDisposition.completed;
  Object? executionError;
  McpToolResult executionResult = fixtureResult('contents');
  ParticipantToolRuntimeIdentity? startActivityIdentity;
  ParticipantToolRuntimeIdentity? clearActivityIdentity;
  ParticipantToolActivityDisposition startActivityDisposition =
      ParticipantToolActivityDisposition.applied;
  ParticipantToolActivityDisposition clearActivityDisposition =
      ParticipantToolActivityDisposition.applied;
  ParticipantToolRuntimeIdentity? taintIdentity;
  String? taintFingerprint;
  ParticipantToolTaintDisposition taintDisposition =
      ParticipantToolTaintDisposition.recorded;
}

ParticipantToolSession _session({
  ConversationParticipant? participant,
  bool supportsToolAwareRequests = true,
}) {
  return ParticipantToolSession(
    owner: _owner,
    participant: participant ?? _participant(),
    supportsToolAwareRequests: supportsToolAwareRequests,
    availableDefinitions: [_definition('read_file'), _definition('write_file')],
  );
}

ConversationParticipant _participant({
  String id = 'participant-a',
  bool toolsEnabled = true,
}) {
  return ConversationParticipant(
    id: id,
    displayName: 'Researcher',
    roleLabel: 'Evidence reviewer',
    toolApprovalMode: ToolApprovalMode.autoReview,
    toolsEnabled: toolsEnabled,
  );
}

ToolCallInfo _call({Map<String, dynamic>? arguments}) => ToolCallInfo(
  id: 'call-a',
  name: 'read_file',
  arguments: arguments ?? const {'path': 'lib/main.dart'},
);

Map<String, dynamic> _definition(String name) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': '$name description',
    'parameters': {'type': 'object'},
  },
};

ParticipantToolRuntimeIdentity _poisonIdentity({
  String toolCallId = 'call-a',
  String toolName = 'read_file',
  String participantId = 'participant-a',
}) {
  return ParticipantToolRuntimeIdentity(
    scope: ParticipantToolScope(
      owner: _otherOwner,
      participantId: participantId,
    ),
    toolCallId: toolCallId,
    toolName: toolName,
    argumentDigest: participantToolArgumentDigest(const {
      'path': 'lib/main.dart',
    }),
  );
}

McpToolResult fixtureResult(String result) => McpToolResult(
  toolName: 'read_file',
  result: result,
  isSuccess: true,
  isExternalMcpResult: true,
);

void _expectCode(McpToolResult result, String code) {
  expect(jsonDecode(result.result), containsPair('code', code));
}
