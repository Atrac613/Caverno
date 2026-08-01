import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:caverno/features/chat/data/datasources/turn_tool_approval_runtime_ports.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_approval_coordinator.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );

  test('manual adapter forwards the exact owner and request', () async {
    ChatTurnOwner? seenOwner;
    ManualToolApprovalRequest? seenRequest;
    final expected = const ManualToolApprovalDecision.approved(
      rememberApproval: true,
    );
    final adapter = CallbackManualToolApprovalPort((receivedOwner, request) {
      seenOwner = receivedOwner;
      seenRequest = request;
      return Future.value(expected);
    });
    final request = ManualToolApprovalRequest(
      toolCallId: 'call-1',
      toolName: 'serial_open',
      actionKind: 'serial_open',
      arguments: const {'port': '/dev/tty.test'},
      warningTitle: 'Open serial port',
      warningMessage: 'Device access is required',
      preview: '/dev/tty.test',
      targetDisplayName: '/dev/tty.test',
    );

    final result = await adapter.requestApproval(owner, request);

    expect(result, same(expected));
    expect(seenOwner, same(owner));
    expect(seenRequest, same(request));
  });

  test('auto-review adapter forwards domain and nullable result', () async {
    ChatTurnOwner? seenOwner;
    ToolApprovalAutoReviewRequest? seenRequest;
    ToolApprovalAutoReviewDomain? seenDomain;
    final expected = const ToolApprovalAutoReviewDecision(
      outcome: ToolApprovalAutoReviewOutcome.allow,
      rationale: 'The action matches the request.',
      riskLevel: 'low',
      userAuthorization: 'explicit',
    );
    final adapter = CallbackToolApprovalAutoReviewPort((
      receivedOwner,
      request, {
      required domain,
    }) async {
      seenOwner = receivedOwner;
      seenRequest = request;
      seenDomain = domain;
      return expected;
    });
    final request = ToolApprovalAutoReviewRequest(
      actionKind: 'serial_open',
      toolName: 'serial_open',
      arguments: const {'port': '/dev/tty.test'},
      conversationTail: const [],
    );

    final result = await adapter.review(
      owner,
      request,
      domain: ToolApprovalAutoReviewDomain.connection,
    );

    expect(result, same(expected));
    expect(seenOwner, same(owner));
    expect(seenRequest, same(request));
    expect(seenDomain, ToolApprovalAutoReviewDomain.connection);
  });

  test('audit adapter forwards the exact owner and record', () async {
    ChatTurnOwner? seenOwner;
    ToolApprovalAuditRecord? seenRecord;
    final adapter = CallbackToolApprovalAuditPort((
      receivedOwner,
      record,
    ) async {
      seenOwner = receivedOwner;
      seenRecord = record;
    });
    final record = ToolApprovalAuditRecord(
      toolName: 'serial_open',
      actionKind: 'serial_open',
      domain: ToolApprovalAutoReviewDomain.connection,
      mode: ToolApprovalMode.defaultPermissions,
      outcome: 'approved',
      decisionSource: 'manual',
      arguments: const {'port': '/dev/tty.test'},
      hasUntrustedInfluence: false,
    );

    await adapter.record(owner, record);

    expect(seenOwner, same(owner));
    expect(seenRecord, same(record));
  });

  test('owner adapter forwards the exact owner and result', () {
    ChatTurnOwner? seenOwner;
    final adapter = CallbackToolApprovalOwnerPort((receivedOwner) {
      seenOwner = receivedOwner;
      return receivedOwner == owner;
    });

    expect(adapter.isCurrent(owner), isTrue);
    expect(seenOwner, same(owner));
  });

  test('manual adapter preserves denial result identity', () async {
    final denial = McpToolResult(
      toolName: 'serial_open',
      result: '',
      isSuccess: false,
      errorMessage: 'User denied serial access',
    );
    final decision = ManualToolApprovalDecision.denied(denial);
    final adapter = CallbackManualToolApprovalPort((_, _) async => decision);
    final request = ManualToolApprovalRequest(
      toolCallId: 'call-2',
      toolName: 'serial_open',
      actionKind: 'serial_open',
      arguments: const {'port': '/dev/tty.test'},
      warningTitle: null,
      warningMessage: null,
      preview: null,
    );

    final result = await adapter.requestApproval(owner, request);

    expect(result, same(decision));
    expect(result.denialResult, same(denial));
  });
}
