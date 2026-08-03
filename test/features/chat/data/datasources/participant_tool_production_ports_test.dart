import 'package:caverno/features/chat/data/datasources/participant_tool_production_ports.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_approval_coordinator.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 4,
);

void main() {
  group('ParticipantToolProductionPorts', () {
    test(
      'routes manual approval and effects through one exact scope',
      () async {
        final fixture = _Fixture();

        final completion = await fixture.adapter.handle(_session(), _call());

        expect(
          completion.disposition,
          ParticipantToolRuntimeDisposition.completed,
        );
        expect(fixture.events, [
          'manual',
          'activity:read_file',
          'execute',
          'taint',
          'activity:clear',
        ]);
        expect(fixture.manualIdentity, completion.identity);
        expect(fixture.effectIdentity, completion.identity);
        expect(fixture.taintIdentity, completion.identity);
        expect(fixture.manualArguments, {'path': 'docs/spec.md'});
      },
    );

    test('expires the owner before dispatching the tool effect', () async {
      final fixture = _Fixture()
        ..manualApproval = (identity, arguments) async {
          fixtureCurrentOwner = false;
          return true;
        };
      fixtureCurrentOwner = true;
      addTearDown(() => fixtureCurrentOwner = true);

      final completion = await fixture.adapter.handle(_session(), _call());

      expect(
        completion.disposition,
        ParticipantToolRuntimeDisposition.ownerExpired,
      );
      expect(fixture.events, ['manual']);
      expect(fixture.effectIdentity, isNull);
    });

    test(
      'reports uncertainty when the owner expires after an effect',
      () async {
        final fixture = _Fixture(expireOwnerAfterEffect: true);
        fixtureCurrentOwner = true;
        addTearDown(() => fixtureCurrentOwner = true);

        final completion = await fixture.adapter.handle(
          _session(approvalMode: ToolApprovalMode.fullAccess),
          _call(),
        );

        expect(
          completion.disposition,
          ParticipantToolRuntimeDisposition.effectUncertain,
        );
        expect(fixture.events, ['activity:read_file', 'execute', 'taint']);
        expect(fixture.taintIdentity?.owner, _owner);
        expect(fixture.auditRecords, isNotEmpty);
      },
    );

    test('rejects a foreign scope without running an effect', () async {
      final fixture = _Fixture();
      final foreignIdentity = ParticipantToolRuntimeIdentity(
        scope: ParticipantToolScope(
          owner: ChatTurnOwner(
            conversationId: 'conversation-b',
            interactionGeneration: 4,
          ),
          participantId: 'researcher',
        ),
        toolCallId: 'call-a',
        toolName: 'read_file',
        argumentDigest: participantToolArgumentDigest(const {
          'path': 'docs/spec.md',
        }),
      );

      final acknowledgement = await fixture.ports.execute(
        ParticipantToolRuntimeExecutionRequest(
          identity: foreignIdentity,
          arguments: const {'path': 'docs/spec.md'},
        ),
      );

      expect(
        acknowledgement.disposition,
        ParticipantToolExecutionDisposition.effectUncertain,
      );
      expect(fixture.events, isEmpty);
    });

    test(
      'stops before execution when participant activity is absent',
      () async {
        final fixture = _Fixture()..acceptActivity = false;

        final completion = await fixture.adapter.handle(_session(), _call());

        expect(
          completion.disposition,
          ParticipantToolRuntimeDisposition.rejected,
        );
        expect(fixture.events, [
          'manual',
          'activity:read_file',
          'activity:clear',
        ]);
        expect(fixture.effectIdentity, isNull);
      },
    );
  });
}

bool fixtureCurrentOwner = true;

final class _Fixture {
  _Fixture({this.expireOwnerAfterEffect = false}) {
    ports = ParticipantToolProductionPorts(
      scope: ParticipantToolScope(owner: _owner, participantId: 'researcher'),
      participantDisplayName: 'Researcher',
      requestManualApproval: (identity, arguments) async {
        events.add('manual');
        manualIdentity = identity;
        manualArguments = arguments;
        return manualApproval(identity, arguments);
      },
      autoReviewPort: CallbackToolApprovalAutoReviewPort(
        (_, _, {required domain}) async => const ToolApprovalAutoReviewDecision(
          outcome: ToolApprovalAutoReviewOutcome.allow,
          riskLevel: 'low',
          userAuthorization: 'authorized',
          rationale: 'Read-only evidence request.',
        ),
      ),
      recordAudit: (identity, record) async {
        expect(identity.owner, _owner);
        auditRecords.add(record);
      },
      ownerPort: CallbackToolApprovalOwnerPort(
        (owner) => fixtureCurrentOwner && owner == _owner,
      ),
      executeEffect: (identity, arguments) async {
        events.add('execute');
        effectIdentity = identity;
        if (expireOwnerAfterEffect) fixtureCurrentOwner = false;
        return McpToolResult(
          toolName: identity.toolName,
          result: 'contents',
          isSuccess: true,
        );
      },
      projectActivity: (_, activeToolName) {
        events.add(
          activeToolName.isEmpty
              ? 'activity:clear'
              : 'activity:$activeToolName',
        );
        return acceptActivity;
      },
      recordTaint: (identity, _) {
        events.add('taint');
        taintIdentity = identity;
      },
    );
    adapter = ParticipantToolRuntimeAdapter(
      resolveApproval: ports.resolveApproval,
      execute: ports.execute,
      projectActivity: ports.projectActivity,
      recordTaint: ports.recordTaint,
    );
  }

  final bool expireOwnerAfterEffect;
  late final ParticipantToolProductionPorts ports;
  late final ParticipantToolRuntimeAdapter adapter;
  final List<String> events = [];
  final List<ToolApprovalAuditRecord> auditRecords = [];
  ParticipantToolRuntimeIdentity? manualIdentity;
  ParticipantToolRuntimeIdentity? effectIdentity;
  ParticipantToolRuntimeIdentity? taintIdentity;
  Map<String, dynamic>? manualArguments;
  bool acceptActivity = true;
  Future<bool> Function(ParticipantToolRuntimeIdentity, Map<String, dynamic>)
  manualApproval = (_, _) async => true;
}

ParticipantToolSession _session({
  ToolApprovalMode approvalMode = ToolApprovalMode.defaultPermissions,
}) => ParticipantToolSession(
  owner: _owner,
  participant: ConversationParticipant(
    id: 'researcher',
    displayName: 'Researcher',
    roleLabel: 'Evidence reviewer',
    toolApprovalMode: approvalMode,
    toolsEnabled: true,
  ),
  supportsToolAwareRequests: true,
  availableDefinitions: const [],
);

ToolCallInfo _call() => ToolCallInfo(
  id: 'call-a',
  name: 'read_file',
  arguments: const {'path': 'docs/spec.md'},
);
