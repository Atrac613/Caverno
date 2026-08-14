import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/serial_connection_attempt_coordinator.dart';
import 'package:caverno/features/chat/domain/services/serial_connection_tool_handler.dart';
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

final class _SerialCall {
  const _SerialCall(this.owner, this.request);

  final ChatTurnOwner owner;
  final SerialConnectionRequest request;
}

typedef _OpenBehavior =
    Future<SerialConnectionResult> Function(
      ChatTurnOwner owner,
      SerialConnectionRequest request,
    );
typedef _RollbackBehavior =
    Future<SerialConnectionRollbackResult> Function(
      ChatTurnOwner owner,
      SerialConnectionRequest request,
      String expectedSessionFingerprint,
    );

final class _SerialRollbackCall {
  const _SerialRollbackCall(
    this.owner,
    this.request,
    this.expectedSessionFingerprint,
  );

  final ChatTurnOwner owner;
  final SerialConnectionRequest request;
  final String expectedSessionFingerprint;
}

final class _SerialPort implements SerialConnectionPort {
  String resultJson = '{"success":true}';
  SerialConnectionResultKind resultKind = SerialConnectionResultKind.completed;
  Object failure = StateError('serial adapter failed');
  bool expiredHasResult = true;
  String sessionFingerprint = 'session-a';
  String? activeSessionFingerprint;
  ChatTurnOwner? resultOwner;
  SerialConnectionRequest? resultRequest;
  _OpenBehavior? openBehavior;
  _RollbackBehavior? rollbackBehavior;
  final List<_SerialCall> openCalls = [];
  final List<_SerialRollbackCall> rollbackCalls = [];

  @override
  Future<SerialConnectionResult> open(
    ChatTurnOwner owner,
    SerialConnectionRequest request,
  ) async {
    openCalls.add(_SerialCall(owner, request));
    if (openBehavior case final behavior?) {
      return behavior(owner, request);
    }
    final actualOwner = resultOwner ?? owner;
    final actualRequest = resultRequest ?? request;
    if (resultKind != SerialConnectionResultKind.failed &&
        expiredHasResult &&
        !_isError(resultJson)) {
      activeSessionFingerprint = sessionFingerprint;
    }
    return switch (resultKind) {
      SerialConnectionResultKind.completed => SerialConnectionResult.completed(
        owner: actualOwner,
        request: actualRequest,
        resultJson: resultJson,
        sessionFingerprint: sessionFingerprint,
      ),
      SerialConnectionResultKind.ownerExpired =>
        SerialConnectionResult.ownerExpired(
          owner: actualOwner,
          request: actualRequest,
          resultJson: expiredHasResult ? resultJson : null,
          sessionFingerprint: expiredHasResult ? sessionFingerprint : null,
        ),
      SerialConnectionResultKind.failed => SerialConnectionResult.failed(
        owner: actualOwner,
        request: actualRequest,
        error: failure,
      ),
    };
  }

  @override
  Future<SerialConnectionRollbackResult> rollbackOpen(
    SerialConnectionRollbackPermit permit,
  ) async {
    final identity = permit.receipt.identity;
    final owner = identity.owner;
    final request = SerialConnectionRequest(
      toolCallId: identity.toolCallId,
      portName: identity.portName,
      options: identity.options,
    );
    final expectedSessionFingerprint = permit.receipt.sessionFingerprint;
    rollbackCalls.add(
      _SerialRollbackCall(owner, request, expectedSessionFingerprint),
    );
    if (rollbackBehavior case final behavior?) {
      return behavior(owner, request, expectedSessionFingerprint);
    }
    if (activeSessionFingerprint == null) {
      return SerialConnectionRollbackResult.alreadyAbsent(
        owner: owner,
        request: request,
        expectedSessionFingerprint: expectedSessionFingerprint,
      );
    }
    if (activeSessionFingerprint != expectedSessionFingerprint) {
      return SerialConnectionRollbackResult.sessionMismatch(
        owner: owner,
        request: request,
        expectedSessionFingerprint: expectedSessionFingerprint,
      );
    }
    activeSessionFingerprint = null;
    return SerialConnectionRollbackResult.closed(
      owner: owner,
      request: request,
      expectedSessionFingerprint: expectedSessionFingerprint,
    );
  }

  bool _isError(String value) {
    return value.contains('"error":true');
  }
}

final class _Harness {
  _Harness({SerialConnectionApprovalMemoryCallback? rememberApprovalResult}) {
    coordinator = TurnToolApprovalCoordinator(
      manualApprovalPort: manual,
      autoReviewPort: autoReview,
      auditPort: audit,
      ownerPort: owners,
    );
    handler = SerialConnectionToolHandler(
      connectionPort: serial,
      approvalCoordinator: coordinator,
      attemptCoordinator: attempts,
      rememberApprovalResult: rememberApprovalResult,
    );
  }

  final _OwnerPort owners = _OwnerPort();
  final _ManualPort manual = _ManualPort();
  final _AutoReviewPort autoReview = _AutoReviewPort();
  final _AuditPort audit = _AuditPort();
  final _SerialPort serial = _SerialPort();
  final SerialConnectionAttemptCoordinator attempts =
      SerialConnectionAttemptCoordinator();
  late final TurnToolApprovalCoordinator coordinator;
  late final SerialConnectionToolHandler handler;
}

ChatTurnOwner _owner(String conversationId, [int generation = 1]) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

SerialConnectionToolRequest _request({
  required ChatTurnOwner owner,
  String toolCallId = 'call-serial-1',
  String toolName = 'serial_open',
  Map<String, dynamic>? arguments,
  ToolApprovalMode approvalMode = ToolApprovalMode.defaultPermissions,
  List<Message> conversationMessages = const [],
  bool hasUntrustedInfluence = false,
}) {
  return SerialConnectionToolRequest(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
    arguments:
        arguments ??
        <String, dynamic>{
          'port': ' /dev/cu.sensor ',
          'reason': 'Open the requested serial device.',
        },
    approvalMode: approvalMode,
    conversationMessages: conversationMessages,
    hasUntrustedInfluence: hasUntrustedInfluence,
  );
}

SerialConnectionRequest _connectionRequest({
  String toolCallId = 'call-serial-1',
  String port = '/dev/cu.sensor',
  int baudRate = 9600,
  int dataBits = 8,
  String parity = 'none',
  int stopBits = 1,
  String flowControl = 'none',
}) {
  return SerialConnectionRequest(
    toolCallId: toolCallId,
    portName: port,
    options: SerialConnectionOptions(
      baudRate: baudRate,
      dataBits: dataBits,
      parity: parity,
      stopBits: stopBits,
      flowControl: flowControl,
    ),
  );
}

McpToolResult _failure(String message) {
  return McpToolResult(
    toolName: 'serial_open',
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}

McpToolResult _result(String payload, {required bool isSuccess}) {
  return McpToolResult(
    toolName: 'serial_open',
    result: payload,
    isSuccess: isSuccess,
  );
}

McpToolResult _effectsUncertain({bool cleanupPending = false}) {
  final pending = cleanupPending
      ? '; Rollback cleanup is pending; do not retry this port until the exact '
            'session fingerprint has been reconciled'
      : '';
  return _failure(
    'The serial open may have completed after its owner expired or its '
    'completion identity changed; inspect possible side effects before '
    'retrying$pending',
  );
}

ToolApprovalAutoReviewDecision _reviewDecision(
  ToolApprovalAutoReviewOutcome outcome,
) {
  return ToolApprovalAutoReviewDecision(
    outcome: outcome,
    riskLevel: 'low',
    userAuthorization: 'high',
    rationale: 'The serial request is scoped.',
  );
}

void main() {
  group('typed requests and validation', () {
    test('recursively freezes tool arguments and conversation messages', () {
      final owner = _owner('conversation-a');
      final arguments = <String, dynamic>{
        'port': '/dev/cu.sensor',
        'metadata': <String, Object?>{
          'owners': <Object?>[
            <String, Object?>{'enabled': true},
          ],
          'modes': <Object?>['read', 'write'],
        },
      };
      final messages = <Message>[
        Message(
          id: 'message-1',
          role: MessageRole.user,
          content: 'Open the serial device.',
          timestamp: DateTime(2026),
        ),
      ];

      final request = _request(
        owner: owner,
        arguments: arguments,
        conversationMessages: messages,
        hasUntrustedInfluence: true,
      );
      (arguments['metadata'] as Map)['owners'] = ['changed'];
      messages.clear();

      expect(request.arguments['metadata'], {
        'owners': [
          {'enabled': true},
        ],
        'modes': ['read', 'write'],
      });
      expect(request.owner, owner);
      expect(request.toolCallId, 'call-serial-1');
      expect(request.hasUntrustedInfluence, isTrue);
      expect(request.conversationMessages, hasLength(1));
      expect(
        () => request.arguments['port'] = '/dev/cu.other',
        throwsUnsupportedError,
      );
      expect(
        () => (request.arguments['metadata'] as Map)['new'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['owners'] as List).add(
          false,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['modes'] as List).add(
          'admin',
        ),
        throwsUnsupportedError,
      );
    });

    test(
      'returns the exact missing-port payload before approval or I/O',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);

        final result = await harness.handler.handle(
          _request(owner: owner, arguments: <String, dynamic>{'port': ' \n '}),
        );

        expect(result, _failure('port is required'));
        expect(harness.manual.requests, isEmpty);
        expect(harness.serial.openCalls, isEmpty);
      },
    );

    test('rejects blank and wrong fixed tool names before ports run', () async {
      for (final toolName in ['', 'ble_connect']) {
        final harness = _Harness();
        final owner = _owner('conversation-$toolName');
        harness.owners.current.add(owner);

        final result = await harness.handler.handle(
          _request(owner: owner, toolName: toolName),
        );

        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'SerialConnectionToolHandler only accepts serial_open',
        );
        expect(harness.manual.requests, isEmpty);
        expect(harness.serial.openCalls, isEmpty);
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
      expect(harness.manual.requests, isEmpty);
      expect(harness.serial.openCalls, isEmpty);
    });

    test('rejects mutable leaves and non-primitive nested map keys', () {
      final owner = _owner('conversation-a');

      expect(
        () => _request(
          owner: owner,
          arguments: <String, dynamic>{
            'port': '/dev/cu.sensor',
            'metadata': <Object?, Object?>{DateTime(2026): true},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          owner: owner,
          arguments: <String, dynamic>{
            'port': '/dev/cu.sensor',
            'metadata': <Object?>{'not-json'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          owner: owner,
          arguments: <String, dynamic>{
            'port': '/dev/cu.sensor',
            'metadata': double.infinity,
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          owner: owner,
          arguments: <String, dynamic>{
            'port': '/dev/cu.sensor',
            'metadata': StringBuffer('mutable'),
          },
        ),
        throwsArgumentError,
      );
    });

    test('keeps typed connection values immutable and snapshots errors', () {
      final owner = _owner('conversation-a');
      final request = _connectionRequest();
      final error = StringBuffer('adapter failed');

      final result = SerialConnectionResult.failed(
        owner: owner,
        request: request,
        error: error,
      );
      error.write(' later');

      expect(request.toArguments(), {
        'port': '/dev/cu.sensor',
        'baud_rate': 9600,
        'data_bits': 8,
        'parity': 'none',
        'stop_bits': 1,
        'flow_control': 'none',
      });
      expect(result.kind, SerialConnectionResultKind.failed);
      expect(result.resultJson, isNull);
      expect(result.errorMessage, 'adapter failed');
      expect(result.belongsTo(owner, _connectionRequest()), isTrue);
    });
  });

  group('options, results, and approval flow', () {
    test(
      'forwards exact defaults and preserves the successful payload',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        harness.serial.resultJson = '{"success":true,"port":"/dev/cu.sensor"}';

        final result = await harness.handler.handle(_request(owner: owner));

        expect(
          result,
          _result('{"success":true,"port":"/dev/cu.sensor"}', isSuccess: true),
        );
        expect(harness.serial.openCalls.single.owner, owner);
        expect(harness.serial.openCalls.single.request.toArguments(), {
          'port': '/dev/cu.sensor',
          'baud_rate': 9600,
          'data_bits': 8,
          'parity': 'none',
          'stop_bits': 1,
          'flow_control': 'none',
        });
        expect(harness.manual.owners, [owner]);
        expect(harness.manual.requests.single.toolCallId, 'call-serial-1');
        expect(harness.manual.requests.single.actionKind, 'serial_open');
        expect(harness.manual.requests.single.arguments, {
          'port': '/dev/cu.sensor',
          'baud_rate': 9600,
          'data_bits': 8,
          'parity': 'none',
          'stop_bits': 1,
          'flow_control': 'none',
        });
      },
    );

    test('normalizes numeric options and forwards explicit strings', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);

      await harness.handler.handle(
        _request(
          owner: owner,
          arguments: <String, dynamic>{
            'port': ' COM7 ',
            'baud_rate': 115200.9,
            'data_bits': 7.8,
            'parity': 'even',
            'stop_bits': 2.9,
            'flow_control': 'rtscts',
          },
        ),
      );

      expect(harness.serial.openCalls.single.request.toArguments(), {
        'port': 'COM7',
        'baud_rate': 115200,
        'data_bits': 7,
        'parity': 'even',
        'stop_bits': 2,
        'flow_control': 'rtscts',
      });
      expect(
        harness.manual.requests.single.arguments,
        harness.serial.openCalls.single.request.toArguments(),
      );
    });

    test('passes the exact normalized facts to auto-review', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.autoReview.decision = _reviewDecision(
        ToolApprovalAutoReviewOutcome.allow,
      );

      final result = await harness.handler.handle(
        _request(
          owner: owner,
          approvalMode: ToolApprovalMode.autoReview,
          hasUntrustedInfluence: false,
        ),
      );

      expect(result, _result('{"success":true}', isSuccess: true));
      expect(harness.autoReview.owners, [owner]);
      expect(harness.autoReview.domains, [
        ToolApprovalAutoReviewDomain.connection,
      ]);
      expect(harness.autoReview.requests.single.actionKind, 'serial_open');
      expect(harness.autoReview.requests.single.arguments, {
        'port': '/dev/cu.sensor',
        'baud_rate': 9600,
        'data_bits': 8,
        'parity': 'none',
        'stop_bits': 1,
        'flow_control': 'none',
      });
      expect(
        harness.autoReview.requests.single.reason,
        'Open the requested serial device.',
      );
      expect(harness.autoReview.requests.single.hasUntrustedInfluence, isFalse);
      expect(harness.manual.requests, isEmpty);
    });

    test('reuses a cached successful approval but opens each time', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final request = _request(owner: owner);

      final first = await harness.handler.handle(request);
      final second = await harness.handler.handle(
        _request(
          owner: owner,
          arguments: <String, dynamic>{
            'port': '/dev/cu.sensor',
            'reason': 'Use different non-semantic wording.',
          },
        ),
      );

      expect(first, _result('{"success":true}', isSuccess: true));
      expect(second, first);
      expect(harness.manual.requests, hasLength(1));
      expect(harness.serial.openCalls, hasLength(2));
      expect(harness.audit.records.map((record) => record.decisionSource), [
        'cached_approval',
      ]);
    });

    test('short-circuits a cached denial before serial transport', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final denial = _failure(
        'User cancelled opening serial port /dev/cu.sensor',
      );
      harness.manual.decision = ManualToolApprovalDecision.denied(denial);
      final request = _request(owner: owner);

      final first = await harness.handler.handle(request);
      harness.serial.openBehavior = (owner, request) async {
        throw StateError('must not run');
      };
      final second = await harness.handler.handle(
        _request(
          owner: owner,
          arguments: <String, dynamic>{
            'port': '/dev/cu.sensor',
            'reason': 'Use different non-semantic wording.',
          },
        ),
      );

      expect(first, denial);
      expect(second, denial);
      expect(harness.manual.requests, hasLength(1));
      expect(harness.serial.openCalls, isEmpty);
    });

    test('does not cache a full-access bypass as an approval', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);

      final bypassed = await harness.handler.handle(
        _request(owner: owner, approvalMode: ToolApprovalMode.fullAccess),
      );
      final manual = await harness.handler.handle(_request(owner: owner));

      expect(bypassed, _result('{"success":true}', isSuccess: true));
      expect(manual, bypassed);
      expect(harness.manual.owners, [owner]);
      expect(harness.serial.openCalls, hasLength(2));
      expect(harness.audit.records.single.decisionSource, 'full_access');
    });

    test('returns and caches the exact manual denial', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final denial = _failure(
        'User cancelled opening serial port /dev/cu.sensor',
      );
      harness.manual.decision = ManualToolApprovalDecision.denied(denial);

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, denial);
      expect(harness.serial.openCalls, isEmpty);
    });

    test('returns the exact auto-review denial without opening', () async {
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
          toolName: 'serial_open',
          result:
              'Auto-review denied this action. Rationale: '
              'The serial request is scoped.',
          isSuccess: false,
          errorMessage: 'Auto-review denied: The serial request is scoped.',
        ),
      );
      expect(harness.manual.requests, isEmpty);
      expect(harness.serial.openCalls, isEmpty);
    });

    test('returns structured error JSON without caching approval', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultJson = '{"error":true,"message":"Port is busy."}';
      final request = _request(owner: owner);

      final first = await harness.handler.handle(request);
      final second = await harness.handler.handle(request);

      expect(
        first,
        _result('{"error":true,"message":"Port is busy."}', isSuccess: false),
      );
      expect(second, first);
      expect(first.errorMessage, isNull);
      expect(harness.manual.requests, hasLength(2));
      expect(harness.serial.openCalls, hasLength(2));
    });

    test('treats malformed JSON as success and caches approval', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultJson = 'not-json';
      final request = _request(owner: owner);

      final first = await harness.handler.handle(request);
      final second = await harness.handler.handle(request);

      expect(first, _result('not-json', isSuccess: true));
      expect(second, first);
      expect(harness.manual.requests, hasLength(1));
      expect(harness.serial.openCalls, hasLength(2));
    });

    test('matches only a top-level boolean error flag', () async {
      const fixtures = <(String, bool)>[
        ('{"error":true}', false),
        ('{"error":false}', true),
        ('{"error":"true"}', true),
        ('{"nested":{"error":true}}', true),
        ('[{"error":true}]', true),
        ('true', true),
      ];

      for (final (payload, expectedSuccess) in fixtures) {
        final harness = _Harness();
        final owner = _owner('conversation-$payload');
        harness.owners.current.add(owner);
        harness.serial.resultJson = payload;

        final result = await harness.handler.handle(_request(owner: owner));

        expect(result, _result(payload, isSuccess: expectedSuccess));
      }
    });
  });

  group('port failures', () {
    test('returns the exact typed port-failure payload', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultKind = SerialConnectionResultKind.failed;
      harness.serial.failure = StateError('port unavailable');

      final result = await harness.handler.handle(_request(owner: owner));

      expect(
        result,
        _failure('Serial open failed: Bad state: port unavailable'),
      );
      expect(harness.serial.rollbackCalls, isEmpty);
    });

    test(
      'retains an uncertain launch after an unexpected port throw',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        harness.serial.openBehavior = (owner, request) async {
          throw StateError('adapter crashed');
        };

        final result = await harness.handler.handle(_request(owner: owner));

        expect(result, _effectsUncertain(cleanupPending: true));
        expect(harness.serial.rollbackCalls, isEmpty);
        expect(harness.handler.pendingEffectLeases, hasLength(1));

        final successor = _owner('conversation-b');
        harness.owners.current.add(successor);
        expect(
          await harness.handler.handle(_request(owner: successor)),
          _failure('A serial open is already in progress for /dev/cu.sensor'),
        );
        final pendingLease = harness.handler.pendingEffectLeases.single;
        expect(harness.handler.settlePendingOpenNoEffect(pendingLease), isTrue);
        harness.serial.openBehavior = null;
        expect(
          await harness.handler.handle(_request(owner: successor)),
          _result('{"success":true}', isSuccess: true),
        );
      },
    );

    test('does not cache a transient typed failure', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultKind = SerialConnectionResultKind.failed;

      await harness.handler.handle(_request(owner: owner));
      await harness.handler.handle(_request(owner: owner));

      expect(harness.manual.requests, hasLength(2));
      expect(harness.serial.openCalls, hasLength(2));
    });
  });

  group('final approval settlement fence', () {
    test(
      'rolls back the exact opened session when the callback throws',
      () async {
        final harness = _Harness(
          rememberApprovalResult: (_) async {
            throw StateError('approval cache unavailable');
          },
        );
        final owner = _owner('conversation-final-throw');
        harness.owners.current.add(owner);

        final result = await harness.handler.handle(_request(owner: owner));

        expect(result, _effectsUncertain());
        expect(harness.serial.rollbackCalls, hasLength(1));
        expect(harness.serial.rollbackCalls.single.owner, owner);
        expect(
          harness.serial.rollbackCalls.single.expectedSessionFingerprint,
          'session-a',
        );
        expect(harness.serial.activeSessionFingerprint, isNull);
        expect(harness.handler.pendingCleanupReceipts, isEmpty);
      },
    );

    test('rejects a typed acknowledgement for a different result', () async {
      final harness = _Harness(
        rememberApprovalResult: (request) async {
          final expected = request.identity;
          return SerialConnectionApprovalMemoryAcknowledgement(
            identity: SerialConnectionApprovalMemoryIdentity(
              receipt: expected.receipt,
              approvalRequest: expected.approvalRequest,
              result: McpToolResult(
                toolName: expected.result.toolName,
                result: expected.result.result,
                isSuccess: expected.result.isSuccess,
              ),
            ),
            disposition: SerialConnectionApprovalMemoryDisposition.remembered,
          );
        },
      );
      final owner = _owner('conversation-wrong-final-ack');
      harness.owners.current.add(owner);

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain());
      expect(harness.serial.rollbackCalls, hasLength(1));
      expect(
        harness.serial.rollbackCalls.single.expectedSessionFingerprint,
        'session-a',
      );
      expect(harness.serial.activeSessionFingerprint, isNull);
    });

    test('rolls back when the owner expires during final settlement', () async {
      late _Harness harness;
      final owner = _owner('conversation-late-final-expiry');
      harness = _Harness(
        rememberApprovalResult: (request) async {
          harness.owners.current.remove(owner);
          return SerialConnectionApprovalMemoryAcknowledgement(
            identity: request.identity,
            disposition: SerialConnectionApprovalMemoryDisposition.remembered,
          );
        },
      );
      harness.owners.current.add(owner);

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain());
      expect(harness.serial.rollbackCalls, hasLength(1));
      expect(harness.serial.rollbackCalls.single.owner, owner);
      expect(harness.serial.activeSessionFingerprint, isNull);
      expect(harness.handler.pendingCleanupReceipts, isEmpty);
    });

    test(
      'retains the exact receipt when final-settlement close fails',
      () async {
        final harness = _Harness(
          rememberApprovalResult: (_) async {
            throw StateError('approval cache unavailable');
          },
        );
        final owner = _owner('conversation-final-close-failure');
        harness.owners.current.add(owner);
        harness.serial.rollbackBehavior = (owner, request, fingerprint) async {
          throw StateError('conditional close failed');
        };

        final result = await harness.handler.handle(_request(owner: owner));

        expect(result, _effectsUncertain(cleanupPending: true));
        expect(harness.serial.rollbackCalls, hasLength(1));
        expect(harness.handler.pendingCleanupReceipts, hasLength(1));
        expect(
          harness.handler.pendingCleanupReceipts.single.sessionFingerprint,
          'session-a',
        );

        harness.serial.rollbackBehavior = null;
        expect(
          await harness.handler.retryPendingCleanup(
            harness.handler.pendingCleanupReceipts.single,
          ),
          isTrue,
        );
        expect(harness.handler.pendingCleanupReceipts, isEmpty);
      },
    );

    test('fences a successor until the exact final acknowledgement', () async {
      final acknowledgement =
          Completer<SerialConnectionApprovalMemoryAcknowledgement>();
      final callbackObserved = Completer<void>();
      SerialConnectionApprovalMemoryRequest? firstMemoryRequest;
      var callbackCount = 0;
      final harness = _Harness(
        rememberApprovalResult: (request) {
          callbackCount++;
          if (callbackCount == 1) {
            firstMemoryRequest = request;
            callbackObserved.complete();
            return acknowledgement.future;
          }
          return Future.value(
            SerialConnectionApprovalMemoryAcknowledgement(
              identity: request.identity,
              disposition: SerialConnectionApprovalMemoryDisposition.remembered,
            ),
          );
        },
      );
      final ownerA = _owner('conversation-final-fence-a');
      final ownerB = _owner('conversation-final-fence-b');
      harness.owners.current.addAll([ownerA, ownerB]);

      final first = harness.handler.handle(_request(owner: ownerA));
      await callbackObserved.future;

      expect(
        await harness.handler.handle(_request(owner: ownerB)),
        _failure('A serial open is already in progress for /dev/cu.sensor'),
      );
      expect(harness.serial.openCalls, hasLength(1));
      expect(harness.serial.activeSessionFingerprint, 'session-a');

      acknowledgement.complete(
        SerialConnectionApprovalMemoryAcknowledgement(
          identity: firstMemoryRequest!.identity,
          disposition: SerialConnectionApprovalMemoryDisposition.remembered,
        ),
      );
      expect(await first, _result('{"success":true}', isSuccess: true));
      expect(
        await harness.handler.handle(_request(owner: ownerB)),
        _result('{"success":true}', isSuccess: true),
      );
      expect(harness.serial.openCalls, hasLength(2));
    });
  });

  group('owner, generation, and rollback isolation', () {
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
      expect(harness.serial.openCalls, isEmpty);
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
      expect(harness.serial.openCalls, isEmpty);
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
      expect(harness.serial.openCalls, isEmpty);
    });

    test('does not reuse another conversation approval cache', () async {
      final harness = _Harness();
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      harness.owners.current.addAll([ownerA, ownerB]);

      await harness.handler.handle(_request(owner: ownerA));
      await harness.handler.handle(_request(owner: ownerB));

      expect(harness.manual.owners, [ownerA, ownerB]);
      expect(harness.serial.openCalls, hasLength(2));
    });

    test('does not reuse another generation approval cache', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      final nextGeneration = _owner('conversation-a', 2);
      harness.owners.current.addAll([owner, nextGeneration]);

      await harness.handler.handle(_request(owner: owner));
      await harness.handler.handle(_request(owner: nextGeneration));

      expect(harness.manual.owners, [owner, nextGeneration]);
      expect(harness.serial.openCalls, hasLength(2));
    });

    test('rejects a result from another conversation', () async {
      final harness = _Harness();
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      harness.owners.current.addAll([ownerA, ownerB]);
      harness.serial.resultOwner = ownerB;

      final result = await harness.handler.handle(_request(owner: ownerA));

      expect(result, _effectsUncertain(cleanupPending: true));
      expect(harness.serial.rollbackCalls, isEmpty);
    });

    test('rejects a result from another generation', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      final nextGeneration = _owner('conversation-a', 2);
      harness.owners.current.addAll([owner, nextGeneration]);
      harness.serial.resultOwner = nextGeneration;

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain(cleanupPending: true));
      expect(harness.serial.rollbackCalls, isEmpty);
    });

    test('rejects a result for another explicit port', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultRequest = _connectionRequest(port: '/dev/cu.other');

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain(cleanupPending: true));
      expect(harness.serial.rollbackCalls, isEmpty);
    });

    test('rejects a result for different serial options', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultRequest = _connectionRequest(baudRate: 115200);

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain(cleanupPending: true));
      expect(harness.serial.rollbackCalls, isEmpty);
    });

    test('rejects a result for another tool call', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultRequest = _connectionRequest(
        toolCallId: 'call-serial-other',
      );

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain(cleanupPending: true));
      expect(harness.serial.rollbackCalls, isEmpty);
    });

    test(
      'rolls back an expired successful open with the exact owner',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        harness.serial.resultKind = SerialConnectionResultKind.ownerExpired;
        harness.serial.resultJson = '{"success":true}';

        final result = await harness.handler.handle(_request(owner: owner));

        expect(result, _effectsUncertain());
        expect(harness.serial.rollbackCalls.single.owner, owner);
        expect(
          harness.serial.rollbackCalls.single.expectedSessionFingerprint,
          'session-a',
        );
        expect(
          harness.serial.rollbackCalls.single.request.toArguments(),
          _connectionRequest().toArguments(),
        );
        expect(harness.handler.pendingCleanupReceipts, isEmpty);

        final successor = _owner('conversation-b');
        harness.owners.current.add(successor);
        harness.serial.resultKind = SerialConnectionResultKind.completed;
        expect(
          await harness.handler.handle(_request(owner: successor)),
          _result('{"success":true}', isSuccess: true),
        );
        expect(harness.serial.openCalls, hasLength(2));
      },
    );

    test('does not roll back an expired structured error result', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultKind = SerialConnectionResultKind.ownerExpired;
      harness.serial.resultJson = '{"error":true,"message":"not opened"}';

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain());
      expect(harness.serial.rollbackCalls, isEmpty);
    });

    test(
      'retains an expired result without enough rollback identity',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        harness.serial.resultKind = SerialConnectionResultKind.ownerExpired;
        harness.serial.expiredHasResult = false;

        final result = await harness.handler.handle(_request(owner: owner));

        expect(result, _effectsUncertain(cleanupPending: true));
        expect(harness.serial.rollbackCalls, isEmpty);
        expect(harness.handler.pendingEffectLeases, hasLength(1));
      },
    );

    test('retains a successful open with a blank fingerprint', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.sessionFingerprint = ' ';

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain(cleanupPending: true));
      expect(harness.serial.rollbackCalls, isEmpty);
      expect(harness.handler.pendingEffectLeases, hasLength(1));
    });

    test('preserves the side-effect warning when rollback throws', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      harness.serial.resultKind = SerialConnectionResultKind.ownerExpired;
      harness.serial.rollbackBehavior = (owner, request, fingerprint) async {
        throw StateError('close failed');
      };

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, _effectsUncertain(cleanupPending: true));
      expect(harness.serial.rollbackCalls, hasLength(1));
      expect(harness.handler.pendingCleanupReceipts, hasLength(1));

      final successor = _owner('conversation-b');
      harness.owners.current.add(successor);
      expect(
        await harness.handler.handle(_request(owner: successor)),
        _failure('A serial open is already in progress for /dev/cu.sensor'),
      );
      expect(harness.serial.openCalls, hasLength(1));

      harness.serial.rollbackBehavior = null;
      final receipt = harness.handler.pendingCleanupReceipts.single;
      expect(await harness.handler.retryPendingCleanup(receipt), isTrue);
      expect(harness.handler.pendingCleanupReceipts, isEmpty);

      harness.serial.resultKind = SerialConnectionResultKind.completed;
      expect(
        await harness.handler.handle(_request(owner: successor)),
        _result('{"success":true}', isSuccess: true),
      );
      expect(harness.serial.openCalls, hasLength(2));
    });

    test(
      'protects a successor session when the rollback fingerprint differs',
      () async {
        final harness = _Harness();
        final owner = _owner('conversation-a');
        harness.owners.current.add(owner);
        harness.serial.openBehavior = (actualOwner, request) async {
          harness.serial.activeSessionFingerprint = 'successor-session';
          return SerialConnectionResult.ownerExpired(
            owner: actualOwner,
            request: request,
            resultJson: '{"success":true}',
            sessionFingerprint: 'retired-session',
          );
        };

        final result = await harness.handler.handle(_request(owner: owner));

        expect(result, _effectsUncertain(cleanupPending: true));
        expect(
          harness.serial.rollbackCalls.single.expectedSessionFingerprint,
          'retired-session',
        );
        expect(harness.serial.activeSessionFingerprint, 'successor-session');
        expect(harness.handler.pendingCleanupReceipts, hasLength(1));
      },
    );

    test('retires an owner during open and settles its exact lease', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final completion = Completer<SerialConnectionResult>();
      final openObserved = Completer<void>();
      harness.serial.openBehavior = (actualOwner, request) {
        openObserved.complete();
        return completion.future;
      };

      final pending = harness.handler.handle(_request(owner: owner));
      await openObserved.future;
      final retirement = harness.handler.retireOwner(owner);
      expect(retirement.opensInFlight, hasLength(1));
      harness.serial.activeSessionFingerprint = 'session-a';
      completion.complete(
        SerialConnectionResult.completed(
          owner: owner,
          request: _connectionRequest(),
          resultJson: '{"success":true}',
          sessionFingerprint: 'session-a',
        ),
      );

      expect(await pending, _effectsUncertain());
      expect(harness.serial.rollbackCalls, hasLength(1));
      expect(harness.serial.activeSessionFingerprint, isNull);
      expect(harness.handler.pendingCleanupReceipts, isEmpty);
    });

    test('holds one exclusive port lease while an open is in flight', () async {
      final harness = _Harness();
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      harness.owners.current.addAll([ownerA, ownerB]);
      final completion = Completer<SerialConnectionResult>();
      final openObserved = Completer<void>();
      harness.serial.openBehavior = (actualOwner, request) {
        if (!openObserved.isCompleted) openObserved.complete();
        return completion.future;
      };

      final first = harness.handler.handle(_request(owner: ownerA));
      await openObserved.future;
      expect(
        await harness.handler.handle(_request(owner: ownerB)),
        _failure('A serial open is already in progress for /dev/cu.sensor'),
      );
      completion.complete(
        SerialConnectionResult.completed(
          owner: ownerA,
          request: _connectionRequest(),
          resultJson: '{"success":true}',
          sessionFingerprint: 'session-a',
        ),
      );

      expect(await first, _result('{"success":true}', isSuccess: true));
      expect(harness.serial.openCalls, hasLength(1));
    });

    test('rechecks the owner and rolls back after open completion', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final completion = Completer<SerialConnectionResult>();
      final openObserved = Completer<void>();
      harness.serial.openBehavior = (actualOwner, request) {
        openObserved.complete();
        return completion.future;
      };

      final pending = harness.handler.handle(_request(owner: owner));
      await openObserved.future;
      harness.owners.current.remove(owner);
      completion.complete(
        SerialConnectionResult.completed(
          owner: owner,
          request: _connectionRequest(),
          resultJson: '{"success":true}',
          sessionFingerprint: 'session-a',
        ),
      );

      expect(await pending, _effectsUncertain());
      expect(harness.serial.rollbackCalls.single.owner, owner);
    });

    test('warns when an open throw settles after owner expiry', () async {
      final harness = _Harness();
      final owner = _owner('conversation-a');
      harness.owners.current.add(owner);
      final completion = Completer<SerialConnectionResult>();
      final openObserved = Completer<void>();
      harness.serial.openBehavior = (actualOwner, request) {
        openObserved.complete();
        return completion.future;
      };

      final pending = harness.handler.handle(_request(owner: owner));
      await openObserved.future;
      harness.owners.current.remove(owner);
      completion.completeError(StateError('adapter stopped'));

      expect(await pending, _effectsUncertain(cleanupPending: true));
      expect(harness.serial.rollbackCalls, isEmpty);
      expect(harness.handler.pendingEffectLeases, hasLength(1));
    });
  });
}
