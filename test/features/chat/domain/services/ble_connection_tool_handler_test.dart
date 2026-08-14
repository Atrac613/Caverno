import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/ble_connection_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_approval_coordinator.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

final class _OwnerPort implements ToolApprovalOwnerPort {
  final Set<ChatTurnOwner> current = {};

  @override
  bool isCurrent(ChatTurnOwner owner) => current.contains(owner);
}

final class _ManualPort implements ManualToolApprovalPort {
  ManualToolApprovalDecision decision =
      const ManualToolApprovalDecision.approved();
  bool deferDecisions = false;
  final List<ChatTurnOwner> owners = [];
  final List<ManualToolApprovalRequest> requests = [];
  final Map<ChatTurnOwner, Completer<ManualToolApprovalDecision>> _pending = {};
  final Completer<void> firstRequestObserved = Completer<void>();

  @override
  Future<ManualToolApprovalDecision> requestApproval(
    ChatTurnOwner owner,
    ManualToolApprovalRequest request,
  ) {
    owners.add(owner);
    requests.add(request);
    if (!firstRequestObserved.isCompleted) {
      firstRequestObserved.complete();
    }
    if (!deferDecisions) return Future.value(decision);
    final completer = Completer<ManualToolApprovalDecision>();
    _pending[owner] = completer;
    return completer.future;
  }

  bool resolve(ChatTurnOwner owner, ManualToolApprovalDecision resolution) {
    final completer = _pending.remove(owner);
    if (completer == null) return false;
    completer.complete(resolution);
    return true;
  }
}

final class _AutoReviewPort implements ToolApprovalAutoReviewPort {
  ToolApprovalAutoReviewDecision? decision;
  final List<ChatTurnOwner> owners = [];
  final List<ToolApprovalAutoReviewRequest> requests = [];
  final List<ToolApprovalAutoReviewDomain> domains = [];

  @override
  Future<ToolApprovalAutoReviewDecision?> review(
    ChatTurnOwner owner,
    ToolApprovalAutoReviewRequest request, {
    required ToolApprovalAutoReviewDomain domain,
  }) async {
    owners.add(owner);
    requests.add(request);
    domains.add(domain);
    return decision;
  }
}

final class _AuditPort implements ToolApprovalAuditPort {
  final List<ChatTurnOwner> owners = [];
  final List<ToolApprovalAuditRecord> records = [];

  @override
  Future<void> record(
    ChatTurnOwner owner,
    ToolApprovalAuditRecord record,
  ) async {
    owners.add(owner);
    records.add(record);
  }
}

final class _ConnectionCall {
  const _ConnectionCall(this.owner, this.request);

  final ChatTurnOwner owner;
  final BleConnectionRequest request;
}

typedef _LookupBehavior =
    Future<BleConnectionLookupResult> Function(
      ChatTurnOwner owner,
      BleConnectionRequest request,
    );
typedef _ConnectBehavior =
    Future<BleConnectionResult> Function(
      ChatTurnOwner owner,
      BleConnectionRequest request,
    );

final class _ConnectionPort implements BleConnectionPort {
  String? displayName;
  ChatTurnOwner? lookupResultOwner;
  String? lookupResultToolCallId;
  String? lookupResultDeviceId;
  ChatTurnOwner? connectionResultOwner;
  String? connectionResultToolCallId;
  String? connectionResultDeviceId;
  BleConnectionResultKind connectionKind = BleConnectionResultKind.connected;
  Object connectionError = StateError('adapter failure');
  _LookupBehavior? lookupBehavior;
  _ConnectBehavior? connectBehavior;
  final List<_ConnectionCall> lookupCalls = [];
  final List<_ConnectionCall> connectCalls = [];

  @override
  Future<BleConnectionLookupResult> lookupDisplayName(
    ChatTurnOwner owner,
    BleConnectionRequest request,
  ) async {
    lookupCalls.add(_ConnectionCall(owner, request));
    if (lookupBehavior case final behavior?) {
      return behavior(owner, request);
    }
    return BleConnectionLookupResult(
      owner: lookupResultOwner ?? owner,
      toolCallId: lookupResultToolCallId ?? request.toolCallId,
      deviceId: lookupResultDeviceId ?? request.deviceId,
      displayName: displayName,
    );
  }

  @override
  Future<BleConnectionResult> connect(
    ChatTurnOwner owner,
    BleConnectionRequest request,
  ) async {
    connectCalls.add(_ConnectionCall(owner, request));
    if (connectBehavior case final behavior?) {
      return behavior(owner, request);
    }
    final resultOwner = connectionResultOwner ?? owner;
    final resultDeviceId = connectionResultDeviceId ?? request.deviceId;
    return switch (connectionKind) {
      BleConnectionResultKind.connected => BleConnectionResult.connected(
        owner: resultOwner,
        toolCallId: connectionResultToolCallId ?? request.toolCallId,
        deviceId: resultDeviceId,
      ),
      BleConnectionResultKind.ownerExpired => BleConnectionResult.ownerExpired(
        owner: resultOwner,
        toolCallId: connectionResultToolCallId ?? request.toolCallId,
        deviceId: resultDeviceId,
      ),
      BleConnectionResultKind.failed => BleConnectionResult.failed(
        owner: resultOwner,
        toolCallId: connectionResultToolCallId ?? request.toolCallId,
        deviceId: resultDeviceId,
        error: connectionError,
      ),
    };
  }
}

final class _Harness {
  _Harness() {
    coordinator = TurnToolApprovalCoordinator(
      manualApprovalPort: manual,
      autoReviewPort: autoReview,
      auditPort: audit,
      ownerPort: owners,
    );
    handler = BleConnectionToolHandler(
      connectionPort: connection,
      approvalCoordinator: coordinator,
    );
  }

  final _OwnerPort owners = _OwnerPort();
  final _ManualPort manual = _ManualPort();
  final _AutoReviewPort autoReview = _AutoReviewPort();
  final _AuditPort audit = _AuditPort();
  final _ConnectionPort connection = _ConnectionPort();
  late final TurnToolApprovalCoordinator coordinator;
  late final BleConnectionToolHandler handler;
}

ChatTurnOwner _owner(String conversationId, [int generation = 1]) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

BleConnectionToolRequest _request({
  required ChatTurnOwner owner,
  String toolCallId = 'call-ble-1',
  String toolName = 'ble_connect',
  String deviceId = 'device-a',
  ToolApprovalMode approvalMode = ToolApprovalMode.defaultPermissions,
  String? reason = 'Connect the requested sensor.',
  List<Message> conversationMessages = const [],
  bool hasUntrustedInfluence = false,
}) {
  return BleConnectionToolRequest(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
    deviceId: deviceId,
    approvalMode: approvalMode,
    reason: reason,
    conversationMessages: conversationMessages,
    hasUntrustedInfluence: hasUntrustedInfluence,
  );
}

McpToolResult _failure(String message) {
  return McpToolResult(
    toolName: 'ble_connect',
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}

McpToolResult _success(String target) {
  return McpToolResult(
    toolName: 'ble_connect',
    result: 'Connected to $target',
    isSuccess: true,
  );
}

McpToolResult _effectsUncertain() {
  return _failure(
    'The BLE connection may have completed after its owner expired or its '
    'completion identity changed; inspect possible side effects before '
    'retrying',
  );
}

ToolApprovalAutoReviewDecision _reviewDecision(
  ToolApprovalAutoReviewOutcome outcome,
) {
  return ToolApprovalAutoReviewDecision(
    outcome: outcome,
    riskLevel: 'low',
    userAuthorization: 'high',
    rationale: 'The BLE request is scoped.',
  );
}

void main() {
  group('typed values and validation', () {
    test('normalizes the explicit device ID and freezes messages', () {
      final owner = _owner('conversation-a');
      final messages = <Message>[
        Message(
          id: 'message-1',
          role: MessageRole.user,
          content: 'Connect the sensor.',
          timestamp: DateTime(2026),
        ),
      ];

      final request = _request(
        owner: owner,
        deviceId: '  device-a  ',
        conversationMessages: messages,
        hasUntrustedInfluence: true,
      );
      messages.clear();

      expect(request.deviceId, 'device-a');
      expect(request.owner, owner);
      expect(request.toolCallId, 'call-ble-1');
      expect(request.reason, 'Connect the requested sensor.');
      expect(request.hasUntrustedInfluence, isTrue);
      expect(request.conversationMessages, hasLength(1));
      expect(
        () => request.conversationMessages.add(
          Message(
            id: 'message-2',
            role: MessageRole.assistant,
            content: 'Done.',
            timestamp: DateTime(2026),
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test(
      'returns the exact missing device ID payload before ports run',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);

        final result = await harness.handler.handle(
          _request(owner: owner, deviceId: ' \n '),
        );

        expect(result, _failure('device_id is required'));
        expect(harness.connection.lookupCalls, isEmpty);
        expect(harness.connection.connectCalls, isEmpty);
        expect(harness.manual.requests, isEmpty);
      },
    );

    test('snapshots a typed failure error as immutable text', () {
      final owner = _owner('conversation-a');
      final error = StringBuffer('connection failed');

      final result = BleConnectionResult.failed(
        owner: owner,
        toolCallId: 'call-ble-1',
        deviceId: 'device-a',
        error: error,
      );
      error.write(' later');

      expect(result.kind, BleConnectionResultKind.failed);
      expect(result.errorMessage, 'connection failed');
      expect(
        result.belongsTo(
          owner,
          const BleConnectionRequest(
            toolCallId: 'call-ble-1',
            deviceId: 'device-a',
          ),
        ),
        isTrue,
      );
    });

    test('rejects blank and wrong fixed tool names before ports run', () async {
      for (final toolName in ['', 'serial_open']) {
        final harness = _Harness();
        final owner = _owner('conversation-$toolName');
        harness.owners.current.add(owner);

        final result = await harness.handler.handle(
          _request(owner: owner, toolName: toolName),
        );

        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'BleConnectionToolHandler only accepts ble_connect',
        );
        expect(harness.connection.lookupCalls, isEmpty);
        expect(harness.connection.connectCalls, isEmpty);
        expect(harness.manual.requests, isEmpty);
      }
    });

    test('rejects a blank tool call ID before ports run', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);

      final result = await harness.handler.handle(
        _request(owner: owner, toolCallId: ' \n '),
      );

      expect(result, _failure('tool_call_id is required'));
      expect(harness.connection.lookupCalls, isEmpty);
      expect(harness.connection.connectCalls, isEmpty);
      expect(harness.manual.requests, isEmpty);
    });
  });

  group('display lookup and approval flow', () {
    test(
      'uses a known display name without replacing the explicit ID',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        harness.connection.displayName = 'Desk Sensor';

        final result = await harness.handler.handle(_request(owner: owner));

        expect(result, _success('Desk Sensor'));
        expect(harness.connection.lookupCalls.single.owner, owner);
        expect(
          harness.connection.lookupCalls.single.request.deviceId,
          'device-a',
        );
        expect(harness.connection.connectCalls.single.owner, owner);
        expect(
          harness.connection.connectCalls.single.request.deviceId,
          'device-a',
        );
        expect(harness.manual.owners, [owner]);
        expect(harness.manual.requests.single.toolCallId, 'call-ble-1');
        expect(harness.manual.requests.single.actionKind, 'ble_connect');
        expect(harness.manual.requests.single.targetDisplayName, 'Desk Sensor');
        expect(harness.manual.requests.single.arguments, {
          'device_id': 'device-a',
        });
        expect(
          () => harness.manual.requests.single.arguments['device_id'] = 'other',
          throwsUnsupportedError,
        );
      },
    );

    test('falls back to the explicit ID for an unknown display name', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _success('device-a'));
      expect(harness.manual.requests.single.arguments, {
        'device_id': 'device-a',
      });
      expect(harness.manual.requests.single.targetDisplayName, isNull);
    });

    test('reuses a cached approval but executes each connection', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final request = _request(owner: owner);

      final first = await harness.handler.handle(request);
      final second = await harness.handler.handle(request);

      expect(first, _success('device-a'));
      expect(second, _success('device-a'));
      expect(harness.manual.requests, hasLength(1));
      expect(harness.connection.connectCalls, hasLength(2));
      expect(harness.audit.records.map((record) => record.decisionSource), [
        'cached_approval',
      ]);
    });

    test('does not cache a full-access bypass as an approval', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);

      final bypassed = await harness.handler.handle(
        _request(owner: owner, approvalMode: ToolApprovalMode.fullAccess),
      );
      final manual = await harness.handler.handle(_request(owner: owner));

      expect(bypassed, _success('device-a'));
      expect(manual, _success('device-a'));
      expect(harness.manual.owners, [owner]);
      expect(harness.connection.connectCalls, hasLength(2));
      expect(harness.audit.records.single.decisionSource, 'full_access');
    });

    test(
      'passes exact connection facts to auto-review and caches allow',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        harness.connection.displayName = 'Desk Sensor';
        harness.autoReview.decision = _reviewDecision(
          ToolApprovalAutoReviewOutcome.allow,
        );
        final request = _request(
          owner: owner,
          approvalMode: ToolApprovalMode.autoReview,
          hasUntrustedInfluence: false,
        );

        final first = await harness.handler.handle(request);
        final second = await harness.handler.handle(request);

        expect(first, _success('Desk Sensor'));
        expect(second, _success('Desk Sensor'));
        expect(harness.autoReview.owners, [owner]);
        expect(harness.autoReview.domains, [
          ToolApprovalAutoReviewDomain.connection,
        ]);
        expect(harness.autoReview.requests.single.actionKind, 'ble_connect');
        expect(harness.autoReview.requests.single.toolName, 'ble_connect');
        expect(harness.autoReview.requests.single.arguments, {
          'device_id': 'device-a',
        });
        expect(
          harness.autoReview.requests.single.reason,
          'Connect the requested sensor.',
        );
        expect(
          harness.autoReview.requests.single.hasUntrustedInfluence,
          isFalse,
        );
        expect(harness.manual.requests, isEmpty);
        expect(harness.connection.connectCalls, hasLength(2));
      },
    );

    test('returns and caches the exact manual denial', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final denial = _failure('User cancelled BLE connection');
      harness.manual.decision = ManualToolApprovalDecision.denied(denial);
      final request = _request(owner: owner);

      final first = await harness.handler.handle(request);
      final second = await harness.handler.handle(request);

      expect(first, denial);
      expect(second, denial);
      expect(harness.manual.requests, hasLength(1));
      expect(harness.connection.lookupCalls, hasLength(1));
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('returns the exact auto-review denial without connecting', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.autoReview.decision = _reviewDecision(
        ToolApprovalAutoReviewOutcome.deny,
      );

      final result = await harness.handler.handle(
        _request(
          owner: owner,
          approvalMode: ToolApprovalMode.autoReview,
          hasUntrustedInfluence: false,
        ),
      );

      expect(
        result,
        McpToolResult(
          toolName: 'ble_connect',
          result:
              'Auto-review denied this action. Rationale: '
              'The BLE request is scoped.',
          isSuccess: false,
          errorMessage: 'Auto-review denied: The BLE request is scoped.',
        ),
      );
      expect(harness.manual.requests, isEmpty);
      expect(harness.connection.lookupCalls, hasLength(1));
      expect(harness.connection.connectCalls, isEmpty);
    });
  });

  group('connection failures', () {
    test('returns the exact lookup throw payload', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.connection.lookupBehavior = (owner, request) async {
        throw StateError('scan unavailable');
      };

      final result = await harness.handler.handle(_request(owner: owner));

      expect(
        result,
        _failure('BLE connect failed: Bad state: scan unavailable'),
      );
      expect(harness.manual.owners, isEmpty);
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('returns the exact typed connection error payload', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.connection.connectionKind = BleConnectionResultKind.failed;
      harness.connection.connectionError = StateError('radio unavailable');

      final result = await harness.handler.handle(_request(owner: owner));

      expect(
        result,
        _failure('BLE connect failed: Bad state: radio unavailable'),
      );
      expect(harness.connection.connectCalls, hasLength(1));
    });

    test(
      'converts a thrown connection port failure to the exact payload',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        harness.connection.connectBehavior = (owner, request) async {
          throw StateError('adapter crashed');
        };

        final result = await harness.handler.handle(_request(owner: owner));

        expect(
          result,
          _failure('BLE connect failed: Bad state: adapter crashed'),
        );
      },
    );
  });

  group('owner and generation isolation', () {
    test(
      'expires before approval when ownership changes during lookup',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        final lookupCompletion = Completer<BleConnectionLookupResult>();
        final lookupObserved = Completer<void>();
        harness.connection.lookupBehavior = (actualOwner, request) {
          lookupObserved.complete();
          return lookupCompletion.future;
        };

        final pending = harness.handler.handle(_request(owner: owner));
        await lookupObserved.future;
        harness.owners.current.remove(owner);
        lookupCompletion.complete(
          BleConnectionLookupResult(
            owner: owner,
            toolCallId: 'call-ble-1',
            deviceId: 'device-a',
            displayName: 'Desk Sensor',
          ),
        );

        expect(
          await pending,
          _failure('The approval turn expired before execution'),
        );
        expect(harness.manual.requests, isEmpty);
        expect(harness.connection.connectCalls, isEmpty);
      },
    );

    test('maps a stale lookup throw to expiration', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final lookupCompletion = Completer<BleConnectionLookupResult>();
      final lookupObserved = Completer<void>();
      harness.connection.lookupBehavior = (actualOwner, request) {
        lookupObserved.complete();
        return lookupCompletion.future;
      };

      final pending = harness.handler.handle(_request(owner: owner));
      await lookupObserved.future;
      harness.owners.current.remove(owner);
      lookupCompletion.completeError(StateError('scan ended'));

      expect(
        await pending,
        _failure('The approval turn expired before execution'),
      );
      expect(harness.manual.requests, isEmpty);
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('revalidates the owner after manual approval completes', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.manual.deferDecisions = true;

      final pending = harness.handler.handle(_request(owner: owner));
      await harness.manual.firstRequestObserved.future;
      harness.owners.current.remove(owner);
      expect(
        harness.manual.resolve(
          owner,
          const ManualToolApprovalDecision.approved(),
        ),
        isTrue,
      );

      expect(
        await pending,
        _failure('The approval turn expired before execution'),
      );
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('rejects another conversation resolving a pending approval', () async {
      final harness = _Harness();
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      harness.owners.current.addAll([ownerA, ownerB]);
      harness.manual.deferDecisions = true;

      final pending = harness.handler.handle(_request(owner: ownerA));
      await harness.manual.firstRequestObserved.future;
      expect(
        harness.manual.resolve(
          ownerB,
          const ManualToolApprovalDecision.approved(),
        ),
        isFalse,
      );
      expect(harness.connection.connectCalls, isEmpty);
      harness.owners.current.remove(ownerA);
      expect(
        harness.manual.resolve(
          ownerA,
          const ManualToolApprovalDecision.approved(),
        ),
        isTrue,
      );

      expect(
        await pending,
        _failure('The approval turn expired before execution'),
      );
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('rejects another generation resolving a pending approval', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      final nextGeneration = _owner('conversation-a', 2);
      harness.owners.current.addAll([owner, nextGeneration]);
      harness.manual.deferDecisions = true;

      final pending = harness.handler.handle(_request(owner: owner));
      await harness.manual.firstRequestObserved.future;
      expect(
        harness.manual.resolve(
          nextGeneration,
          const ManualToolApprovalDecision.approved(),
        ),
        isFalse,
      );
      harness.owners.current.remove(owner);
      expect(
        harness.manual.resolve(
          owner,
          const ManualToolApprovalDecision.approved(),
        ),
        isTrue,
      );

      expect(
        await pending,
        _failure('The approval turn expired before execution'),
      );
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('does not reuse another conversation approval cache', () async {
      final harness = _Harness();
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      harness.owners.current.addAll([ownerA, ownerB]);

      await harness.handler.handle(_request(owner: ownerA));
      await harness.handler.handle(_request(owner: ownerB));

      expect(harness.manual.owners, [ownerA, ownerB]);
      expect(harness.connection.connectCalls, hasLength(2));
    });

    test('does not reuse another generation approval cache', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      final nextGeneration = _owner('conversation-a', 2);
      harness.owners.current.addAll([owner, nextGeneration]);

      await harness.handler.handle(_request(owner: owner));
      await harness.handler.handle(_request(owner: nextGeneration));

      expect(harness.manual.owners, [owner, nextGeneration]);
      expect(harness.connection.connectCalls, hasLength(2));
    });

    test('rejects lookup metadata from another conversation', () async {
      final harness = _Harness();
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      harness.owners.current.addAll([ownerA, ownerB]);
      harness.connection.lookupResultOwner = ownerB;

      final result = await harness.handler.handle(_request(owner: ownerA));

      expect(result, _failure('The approval turn expired before execution'));
      expect(harness.manual.requests, isEmpty);
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('rejects lookup metadata from another generation', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      final nextGeneration = _owner('conversation-a', 2);
      harness.owners.current.addAll([owner, nextGeneration]);
      harness.connection.lookupResultOwner = nextGeneration;

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _failure('The approval turn expired before execution'));
      expect(harness.manual.requests, isEmpty);
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('rejects lookup metadata for another device', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.connection.lookupResultDeviceId = 'device-b';

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _failure('The approval turn expired before execution'));
      expect(harness.manual.requests, isEmpty);
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('rejects lookup metadata for another tool call', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.connection.lookupResultToolCallId = 'call-ble-other';

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _failure('The approval turn expired before execution'));
      expect(harness.manual.requests, isEmpty);
      expect(harness.connection.connectCalls, isEmpty);
    });

    test('rejects a connection result from another conversation', () async {
      final harness = _Harness();
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      harness.owners.current.addAll([ownerA, ownerB]);
      harness.connection.connectionResultOwner = ownerB;

      final result = await harness.handler.handle(_request(owner: ownerA));

      expect(result, _effectsUncertain());
    });

    test('rejects a connection result from another generation', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      final nextGeneration = _owner('conversation-a', 2);
      harness.owners.current.addAll([owner, nextGeneration]);
      harness.connection.connectionResultOwner = nextGeneration;

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain());
    });

    test('rejects a connection result for another device', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.connection.connectionResultDeviceId = 'device-b';

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain());
    });

    test('rejects a connection result for another tool call', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.connection.connectionResultToolCallId = 'call-ble-other';

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain());
    });

    test('warns when the adapter reports owner expiry after connect', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.connection.connectionKind = BleConnectionResultKind.ownerExpired;

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain());
    });

    test('rechecks the owner after a connected completion', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final completion = Completer<BleConnectionResult>();
      final connectionObserved = Completer<void>();
      harness.connection.connectBehavior = (actualOwner, request) {
        connectionObserved.complete();
        return completion.future;
      };

      final pending = harness.handler.handle(_request(owner: owner));
      await connectionObserved.future;
      harness.owners.current.remove(owner);
      completion.complete(
        BleConnectionResult.connected(
          owner: owner,
          toolCallId: 'call-ble-1',
          deviceId: 'device-a',
        ),
      );

      expect(await pending, _effectsUncertain());
    });

    test('warns when a connection throw settles after owner expiry', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final completion = Completer<BleConnectionResult>();
      final connectionObserved = Completer<void>();
      harness.connection.connectBehavior = (actualOwner, request) {
        connectionObserved.complete();
        return completion.future;
      };

      final pending = harness.handler.handle(_request(owner: owner));
      await connectionObserved.future;
      harness.owners.current.remove(owner);
      completion.completeError(StateError('radio stopped'));

      expect(await pending, _effectsUncertain());
    });
  });
}
