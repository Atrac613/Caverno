import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/serial_connection_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/serial_connection_attempt_coordinator.dart';
import 'package:caverno/features/chat/domain/services/serial_connection_tool_contract.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_approval_coordinator.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );

  group('SerialConnectionRuntimeInput', () {
    test('captures strict immutable arguments and approval facts', () {
      final nested = <String, dynamic>{
        'labels': <Object?>[
          'sensor',
          <String, Object?>{'trusted': true},
        ],
      };
      final arguments = <String, dynamic>{
        'port': '/dev/cu.sensor',
        'metadata': nested,
      };
      final messages = <Message>[_message('Open the sensor.')];
      final input = SerialConnectionRuntimeInput(
        owner: owner,
        toolCall: ToolCallInfo(
          id: 'call-serial',
          name: 'serial_open',
          arguments: arguments,
        ),
        approval: SerialConnectionApprovalFacts(
          mode: ToolApprovalMode.autoReview,
          conversationMessages: messages,
          hasUntrustedInfluence: true,
        ),
      );
      nested['labels'] = <Object?>['changed'];
      messages.clear();

      expect(input.identity.owner, owner);
      expect(input.identity.toolCallId, 'call-serial');
      expect(input.identity.toolName, canonicalSerialOpenToolName);
      expect(input.arguments['metadata'], {
        'labels': [
          'sensor',
          {'trusted': true},
        ],
      });
      expect(input.approval.mode, ToolApprovalMode.autoReview);
      expect(input.approval.conversationMessages, hasLength(1));
      expect(input.approval.hasUntrustedInfluence, isTrue);
      expect(
        () => (input.arguments['metadata'] as Map)['other'] = true,
        throwsUnsupportedError,
      );
    });

    test('uses a canonical digest while retaining exact invocation fields', () {
      final left = SerialConnectionRuntimeInput(
        owner: owner,
        toolCall: _tool(
          id: 'call-serial',
          arguments: <String, dynamic>{
            'z': <Object?>[2, 1],
            'a': <String, Object?>{'right': false, 'left': true},
          },
        ),
        approval: _approval(),
      );
      final right = SerialConnectionRuntimeInput(
        owner: owner,
        toolCall: _tool(
          id: 'call-serial',
          arguments: <String, dynamic>{
            'a': <String, Object?>{'left': true, 'right': false},
            'z': <Object?>[2, 1],
          },
        ),
        approval: _approval(),
      );

      expect(left.identity, right.identity);
      expect(left.identity.argumentDigest, hasLength(64));
      expect(
        left.identity,
        isNot(
          SerialConnectionRuntimeInput(
            owner: owner,
            toolCall: _tool(id: 'other-call', arguments: right.arguments),
            approval: _approval(),
          ).identity,
        ),
      );
    });

    test('rejects inexact identity and non-JSON arguments', () {
      for (final tool in [
        _tool(id: ' call-serial '),
        _tool(name: 'SERIAL_OPEN'),
        _tool(arguments: <String, dynamic>{'value': double.nan}),
        _tool(
          arguments: <String, dynamic>{
            'value': <Object?>{'mutable'},
          },
        ),
        _tool(
          arguments: <String, dynamic>{
            'value': <Object?, Object?>{1: 'not-json'},
          },
        ),
      ]) {
        expect(
          () => SerialConnectionRuntimeInput(
            owner: owner,
            toolCall: tool,
            approval: _approval(),
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('SerialConnectionToolRuntimeAdapter', () {
    test('forwards exact options and auto-review approval facts', () async {
      final fixture = _Fixture(owner);
      fixture.autoReview.decision = const ToolApprovalAutoReviewDecision(
        outcome: ToolApprovalAutoReviewOutcome.allow,
        riskLevel: 'low',
        userAuthorization: 'high',
        rationale: 'The connection is scoped.',
      );

      final result = await fixture.handle(
        approval: SerialConnectionApprovalFacts(
          mode: ToolApprovalMode.autoReview,
          conversationMessages: <Message>[_message('Use the desk sensor.')],
          hasUntrustedInfluence: false,
        ),
        arguments: <String, dynamic>{
          'port': ' /dev/cu.sensor ',
          'baud_rate': 115200,
          'data_bits': 7,
          'parity': 'even',
          'stop_bits': 2,
          'flow_control': 'rtscts',
          'reason': 'Open the requested device.',
        },
      );

      expect(result.isSuccess, isTrue);
      expect(fixture.service.openCalls.single, (
        port: '/dev/cu.sensor',
        baudRate: 115200,
        dataBits: 7,
        parity: 'even',
        stopBits: 2,
        flowControl: 'rtscts',
      ));
      final review = fixture.autoReview.requests.single;
      expect(review.toolName, canonicalSerialOpenToolName);
      expect(review.reason, 'Open the requested device.');
      expect(review.hasUntrustedInfluence, isFalse);
      expect(review.conversationTail.single.content, 'Use the desk sensor.');
      expect(fixture.manual.requests, isEmpty);
    });

    test('keeps one attempt coordinator across concurrent calls', () async {
      final fixture = _Fixture(owner);
      final firstOpen = Completer<String>();
      fixture.service.deferredOpen = firstOpen;

      final first = fixture.handle(
        id: 'call-first',
        approval: _approval(mode: ToolApprovalMode.fullAccess),
      );
      await fixture.service.openObserved.future;
      final second = await fixture.handle(
        id: 'call-second',
        approval: _approval(mode: ToolApprovalMode.fullAccess),
      );

      expect(second.isSuccess, isFalse);
      expect(second.errorMessage, contains('already in progress'));
      expect(fixture.service.openCalls, hasLength(1));

      firstOpen.complete(fixture.service.resultJson);
      expect((await first).isSuccess, isTrue);
    });

    test(
      'retires an in-flight owner and rolls back its exact session',
      () async {
        final fixture = _Fixture(owner);
        final open = Completer<String>();
        fixture.service.deferredOpen = open;

        final pending = fixture.handle(
          approval: _approval(mode: ToolApprovalMode.fullAccess),
        );
        await fixture.service.openObserved.future;
        final retirement = fixture.adapter.retireOwner(owner);

        expect(retirement.opensInFlight, hasLength(1));
        expect(fixture.adapter.pendingEffectLeases, hasLength(1));

        open.complete(fixture.service.resultJson);
        final result = await pending;

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('may have completed'));
        expect(result.errorMessage, isNot(contains('cleanup is pending')));
        expect(fixture.service.closeCalls.single, (
          port: '/dev/cu.sensor',
          fingerprint: 'session-a',
        ));
        expect(fixture.adapter.pendingEffectLeases, isEmpty);
        expect(fixture.adapter.pendingCleanupReceipts, isEmpty);
      },
    );

    test('retains failed cleanup and retries the exact receipt', () async {
      final fixture = _Fixture(owner);
      final open = Completer<String>();
      fixture.service
        ..deferredOpen = open
        ..closeError = StateError('port still closing');

      final pending = fixture.handle(
        approval: _approval(mode: ToolApprovalMode.fullAccess),
      );
      await fixture.service.openObserved.future;
      fixture.adapter.retireOwner(owner);
      open.complete(fixture.service.resultJson);

      final result = await pending;
      expect(result.errorMessage, contains('cleanup is pending'));
      expect(fixture.adapter.pendingCleanupReceipts, hasLength(1));
      final receipt = fixture.adapter.pendingCleanupReceipts.single;

      fixture.service.closeError = null;
      expect(await fixture.adapter.retryPendingCleanup(receipt), isTrue);
      expect(fixture.service.closeCalls, hasLength(2));
      expect(fixture.adapter.pendingCleanupReceipts, isEmpty);
    });

    test('reconciles a retired pending open as no effect', () {
      final attempts = SerialConnectionAttemptCoordinator();
      final fixture = _Fixture(owner, attempts: attempts);
      final lease = _beginOpen(attempts, owner);
      fixture.adapter.retireOwner(owner);

      expect(fixture.adapter.pendingEffectLeases, [same(lease)]);
      expect(fixture.adapter.settlePendingOpenNoEffect(lease), isTrue);
      expect(fixture.adapter.pendingEffectLeases, isEmpty);
    });

    test(
      'reconciles a retired pending open with conditional rollback',
      () async {
        final attempts = SerialConnectionAttemptCoordinator();
        final fixture = _Fixture(owner, attempts: attempts);
        final lease = _beginOpen(attempts, owner);
        fixture.adapter.retireOwner(owner);

        expect(
          await fixture.adapter.rollbackPendingOpen(
            lease,
            sessionFingerprint: 'session-a',
          ),
          isTrue,
        );
        expect(fixture.service.closeCalls.single, (
          port: '/dev/cu.sensor',
          fingerprint: 'session-a',
        ));
        expect(fixture.adapter.pendingEffectLeases, isEmpty);
        expect(fixture.adapter.pendingCleanupReceipts, isEmpty);
      },
    );

    test(
      'individual retirement releases tracking while retireAll stays exact',
      () async {
        final fixture = _Fixture(owner);
        final first = await fixture.handle(
          approval: _approval(mode: ToolApprovalMode.fullAccess),
        );
        expect(first.isSuccess, isTrue);

        fixture.adapter.retireOwner(owner);
        final otherOwner = ChatTurnOwner(
          conversationId: 'conversation-b',
          interactionGeneration: owner.interactionGeneration,
        );
        fixture.owners.current.add(otherOwner);
        final other = await fixture.adapter.handle(
          owner: otherOwner,
          toolCall: _tool(id: 'call-other-owner'),
          approval: _approval(mode: ToolApprovalMode.fullAccess),
        );
        expect(other.isSuccess, isTrue);

        fixture.adapter.retireAll();
        final retired = await fixture.handle(
          id: 'call-after-retirement',
          approval: _approval(mode: ToolApprovalMode.fullAccess),
        );
        final retiredOther = await fixture.adapter.handle(
          owner: otherOwner,
          toolCall: _tool(id: 'call-other-after-retirement'),
          approval: _approval(mode: ToolApprovalMode.fullAccess),
        );

        expect(retired.isSuccess, isFalse);
        expect(retiredOther.isSuccess, isFalse);
        expect(
          retired.errorMessage,
          'The approval turn expired before execution',
        );
        expect(
          retiredOther.errorMessage,
          'The approval turn expired before execution',
        );
        expect(fixture.service.openCalls, hasLength(2));
      },
    );
  });
}

final class _Fixture {
  _Fixture(this.owner, {SerialConnectionAttemptCoordinator? attempts}) {
    owners.current.add(owner);
    approvalCoordinator = TurnToolApprovalCoordinator(
      manualApprovalPort: manual,
      autoReviewPort: autoReview,
      auditPort: audit,
      ownerPort: owners,
    );
    adapter = SerialConnectionToolRuntimeAdapter(
      sessionPort: service,
      ownerIsCurrent: owners.isCurrent,
      approvalCoordinator: approvalCoordinator,
      attemptCoordinator: attempts ?? SerialConnectionAttemptCoordinator(),
    );
  }

  final ChatTurnOwner owner;
  final _OwnerPort owners = _OwnerPort();
  final _ManualPort manual = _ManualPort();
  final _AutoReviewPort autoReview = _AutoReviewPort();
  final _AuditPort audit = _AuditPort();
  final _SerialSessionPort service = _SerialSessionPort();
  late final TurnToolApprovalCoordinator approvalCoordinator;
  late final SerialConnectionToolRuntimeAdapter adapter;

  Future<McpToolResult> handle({
    String id = 'call-serial',
    Map<String, dynamic>? arguments,
    SerialConnectionApprovalFacts? approval,
  }) {
    return adapter.handle(
      owner: owner,
      toolCall: _tool(id: id, arguments: arguments),
      approval: approval ?? _approval(),
    );
  }
}

final class _OwnerPort implements ToolApprovalOwnerPort {
  final Set<ChatTurnOwner> current = <ChatTurnOwner>{};

  @override
  bool isCurrent(ChatTurnOwner owner) => current.contains(owner);
}

final class _ManualPort implements ManualToolApprovalPort {
  final List<ManualToolApprovalRequest> requests =
      <ManualToolApprovalRequest>[];

  @override
  Future<ManualToolApprovalDecision> requestApproval(
    ChatTurnOwner owner,
    ManualToolApprovalRequest request,
  ) async {
    requests.add(request);
    return const ManualToolApprovalDecision.approved();
  }
}

final class _AutoReviewPort implements ToolApprovalAutoReviewPort {
  ToolApprovalAutoReviewDecision? decision;
  final List<ToolApprovalAutoReviewRequest> requests =
      <ToolApprovalAutoReviewRequest>[];

  @override
  Future<ToolApprovalAutoReviewDecision?> review(
    ChatTurnOwner owner,
    ToolApprovalAutoReviewRequest request, {
    required ToolApprovalAutoReviewDomain domain,
  }) async {
    requests.add(request);
    return decision;
  }
}

final class _AuditPort implements ToolApprovalAuditPort {
  @override
  Future<void> record(
    ChatTurnOwner owner,
    ToolApprovalAuditRecord record,
  ) async {}
}

final class _SerialSessionPort implements SerialSessionPort {
  final List<
    ({
      String port,
      int baudRate,
      int dataBits,
      String parity,
      int stopBits,
      String flowControl,
    })
  >
  openCalls = [];
  final List<({String port, String fingerprint})> closeCalls = [];
  final Completer<void> openObserved = Completer<void>();
  String resultJson = '{"success":true,"session_fingerprint":"session-a"}';
  String? currentFingerprint = 'session-a';
  Completer<String>? deferredOpen;
  Object? closeError;

  @override
  Future<String> open(
    String portName, {
    required int baudRate,
    required int dataBits,
    required String parity,
    required int stopBits,
    required String flowControl,
  }) async {
    openCalls.add((
      port: portName,
      baudRate: baudRate,
      dataBits: dataBits,
      parity: parity,
      stopBits: stopBits,
      flowControl: flowControl,
    ));
    if (!openObserved.isCompleted) openObserved.complete();
    final result = deferredOpen == null
        ? resultJson
        : await deferredOpen!.future;
    final decoded = jsonDecode(result);
    if (decoded is Map && decoded['session_fingerprint'] is String) {
      currentFingerprint = decoded['session_fingerprint'] as String;
    }
    return result;
  }

  @override
  String? sessionFingerprint(String portName) => currentFingerprint;

  @override
  Future<SerialSessionCloseKind> closeIfSessionMatches(
    String portName,
    String expectedFingerprint,
  ) async {
    closeCalls.add((port: portName, fingerprint: expectedFingerprint));
    if (closeError case final error?) throw error;
    if (currentFingerprint == null) {
      return SerialSessionCloseKind.alreadyAbsent;
    }
    if (currentFingerprint != expectedFingerprint) {
      return SerialSessionCloseKind.sessionMismatch;
    }
    currentFingerprint = null;
    return SerialSessionCloseKind.closed;
  }
}

SerialConnectionAttemptLease _beginOpen(
  SerialConnectionAttemptCoordinator attempts,
  ChatTurnOwner owner,
) {
  final identity = SerialConnectionAttemptIdentity(
    owner: owner,
    toolCallId: 'call-serial',
    toolName: canonicalSerialOpenToolName,
    portName: '/dev/cu.sensor',
    options: const SerialConnectionOptions(
      baudRate: 9600,
      dataBits: 8,
      parity: 'none',
      stopBits: 1,
      flowControl: 'none',
    ),
  );
  final lease = attempts.acquire(identity).lease!;
  expect(
    attempts.beginOpen(identity, lease.token),
    SerialConnectionBeginOpenKind.begun,
  );
  return lease;
}

ToolCallInfo _tool({
  String id = 'call-serial',
  String name = canonicalSerialOpenToolName,
  Map<String, dynamic>? arguments,
}) => ToolCallInfo(
  id: id,
  name: name,
  arguments:
      arguments ??
      <String, dynamic>{
        'port': '/dev/cu.sensor',
        'reason': 'Open the requested device.',
      },
);

SerialConnectionApprovalFacts _approval({
  ToolApprovalMode mode = ToolApprovalMode.defaultPermissions,
}) => SerialConnectionApprovalFacts(mode: mode);

Message _message(String content) => Message(
  id: 'message-1',
  role: MessageRole.user,
  content: content,
  timestamp: DateTime.utc(2026),
);
