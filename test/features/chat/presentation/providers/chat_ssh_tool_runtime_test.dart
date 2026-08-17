import 'dart:io';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/presentation/providers/chat_ssh_tool_runtime.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 3,
);

void main() {
  test('notifier dispatch and terminalization use the SSH runtime', () {
    final handlers = File(
      'lib/features/chat/presentation/providers/'
      'chat_notifier_ssh_handlers.dart',
    ).readAsStringSync();
    final terminalization = File(
      'lib/features/chat/presentation/providers/'
      'chat_notifier_execution_runtime.dart',
    ).readAsStringSync();

    expect(handlers, contains('_runSshTool(toolCall, approvalCache)'));
    expect(handlers, contains('ChatSshToolRuntime('));
    expect(terminalization, contains('unawaited(_clearSshOwner(owner))'));
    expect(handlers, isNot(contains('_mcpToolService!.executeSshTool')));
  });

  test('connects and executes through one exact external session', () async {
    final transport = _FakeTransport();
    final runtime = ChatSshToolRuntime(transport);
    final ports = _Ports();

    final connected = await _handle(runtime, ports, 'connect', 'ssh_connect', {
      'host': 'ssh.example',
      'username': 'tester',
    });
    final executed = await _handle(
      runtime,
      ports,
      'command',
      'ssh_execute_command',
      {'command': 'pwd'},
    );

    expect(connected.isSuccess, isTrue);
    expect(executed.result, 'exit_code: 0\npwd');
    expect(transport.executedFingerprints, ['session-1']);
  });

  test('stale disconnect cannot close an external successor', () async {
    final transport = _FakeTransport();
    final runtime = ChatSshToolRuntime(transport);
    final ports = _Ports();
    await _handle(runtime, ports, 'connect', 'ssh_connect', {
      'host': 'ssh.example',
      'username': 'tester',
    });
    transport.replaceWithSuccessor(_owner);

    final result = await _handle(
      runtime,
      ports,
      'disconnect',
      'ssh_disconnect',
      const {},
    );

    expect(result.result, 'No active SSH session');
    expect(transport.activeSession(_owner)?.fingerprint, 'successor');
    expect(transport.disconnectAttempts, isEmpty);
  });

  test('owner terminalization settles runtime and transport state', () async {
    final transport = _FakeTransport();
    final runtime = ChatSshToolRuntime(transport);
    final ports = _Ports();
    await _handle(runtime, ports, 'connect', 'ssh_connect', {
      'host': 'ssh.example',
      'username': 'tester',
    });

    await runtime.clearOwner(_owner);

    expect(transport.activeSession(_owner), isNull);
    expect(transport.clearedOwners, [_owner]);
    final late = await _handle(runtime, ports, 'late', 'ssh_connect', {
      'host': 'ssh.example',
      'username': 'tester',
    });
    expect(late.isSuccess, isFalse);
  });
}

Future<McpToolResult> _handle(
  ChatSshToolRuntime runtime,
  _Ports ports,
  String id,
  String name,
  Map<String, dynamic> arguments,
) => runtime.handle(
  owner: _owner,
  toolCallId: id,
  toolName: name,
  arguments: arguments,
  credentialPort: ports,
  approvalPort: ports,
);

final class _FakeTransport implements ChatSshTransport {
  final Map<ChatTurnOwner, ChatSshSession> sessions = {};
  final List<String> executedFingerprints = [];
  final List<String> disconnectAttempts = [];
  final List<ChatTurnOwner> clearedOwners = [];
  int nextSession = 0;

  @override
  ChatSshSession? activeSession(ChatTurnOwner owner) => sessions[owner];

  @override
  Future<void> connect(
    ChatTurnOwner owner,
    SshCredentialKey target,
    SshAuthCredential credential,
  ) async {
    sessions[owner] = (
      host: target.host,
      port: target.port,
      username: target.username,
      fingerprint: 'session-${++nextSession}',
    );
  }

  @override
  Future<String> execute(
    ChatTurnOwner owner,
    String command,
    String expectedFingerprint,
  ) async {
    expect(sessions[owner]?.fingerprint, expectedFingerprint);
    executedFingerprints.add(expectedFingerprint);
    return 'exit_code: 0\n$command';
  }

  @override
  Future<bool> disconnectIfFingerprint(
    ChatTurnOwner owner,
    String expectedFingerprint,
  ) async {
    disconnectAttempts.add(expectedFingerprint);
    if (sessions[owner]?.fingerprint != expectedFingerprint) return false;
    sessions.remove(owner);
    return true;
  }

  @override
  Future<void> clearOwner(ChatTurnOwner owner) async {
    clearedOwners.add(owner);
    sessions.remove(owner);
  }

  void replaceWithSuccessor(ChatTurnOwner owner) {
    final prior = sessions[owner]!;
    sessions[owner] = (
      host: prior.host,
      port: prior.port,
      username: prior.username,
      fingerprint: 'successor',
    );
  }
}

final class _Ports implements SshCredentialPort, SshCommandApprovalPort {
  @override
  Future<SshOperationCompletion<SshAuthCredential?>> loadSavedCredential(
    SshOperationIdentity operation,
  ) async => SshOperationCompletion(
    operation: operation,
    value: const SshPasswordCredential('secret'),
  );

  @override
  Future<SshCredentialSelectionResult> requestCredential(
    SshConnectCredentialRequest request,
  ) => throw StateError('full access uses the saved credential');

  @override
  Future<SshOperationCompletion<void>> saveCredential(
    SshOperationIdentity operation,
    SshAuthCredential credential,
  ) async => SshOperationCompletion(operation: operation, value: null);

  @override
  Future<SshOperationCompletion<void>> deleteCredential(
    SshOperationIdentity operation,
  ) async => SshOperationCompletion(operation: operation, value: null);

  @override
  SshOperationCompletion<McpToolResult?> lookupDenial(
    SshApprovalRequest request,
  ) => SshOperationCompletion(operation: request.operation, value: null);

  @override
  Future<SshOperationCompletion<ToolApprovalGateDecision>> resolveGate(
    SshApprovalRequest request, {
    required bool fullAccessEligible,
  }) async => SshOperationCompletion(
    operation: request.operation,
    value: ToolApprovalGateDecision.fullAccess,
  );

  @override
  Future<SshOperationCompletion<bool>> requestCommandApproval(
    SshApprovalRequest request,
  ) => throw StateError('full access skips manual approval');

  @override
  SshOperationCompletion<McpToolResult> rememberDenial(
    SshApprovalRequest request,
    McpToolResult result,
  ) => SshOperationCompletion(operation: request.operation, value: result);

  @override
  SshOperationCompletion<McpToolResult> rememberResult(
    SshApprovalRequest request,
    McpToolResult result,
  ) => SshOperationCompletion(operation: request.operation, value: result);

  @override
  SshOperationCompletion<McpToolResult?> expiredResult(
    SshOperationIdentity operation,
  ) => SshOperationCompletion(operation: operation, value: null);
}
