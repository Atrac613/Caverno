import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/ssh_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

final _connectIdentity = SshConnectionIdentity('ssh-connection-a');
final _activeIdentity = SshConnectionIdentity('active-connection-a');
const _keyA = SshCredentialKey(
  host: 'host-a.example',
  port: 22,
  username: 'alice',
);
const _manualSelection = SshConnectCredentialSelection(
  key: _keyA,
  password: 'manual-secret',
  savePassword: false,
);

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 5,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 5,
  );

  group('SshToolRequest', () {
    test('captures exact tool-call identity and deeply freezes arguments', () {
      final nested = <String, Object?>{
        'tags': <Object?>['owner-a'],
        'flags': <Object?>['safe'],
      };
      final source = <String, dynamic>{
        'host': 'host-a.example',
        'nested': nested,
      };
      final request = SshToolRequest.connect(
        owner: ownerA,
        toolCallId: ' call-connect-a ',
        connectionIdentity: _connectIdentity,
        arguments: source,
      );

      (nested['tags'] as List<Object?>).add('poisoned');
      (nested['flags'] as List<Object?>).add('poisoned');
      source['host'] = 'poisoned.example';

      expect(request.toolCallId, 'call-connect-a');
      expect(request.toolName, 'ssh_connect');
      expect(request.arguments['host'], 'host-a.example');
      expect(request.arguments['nested'], {
        'tags': ['owner-a'],
        'flags': ['safe'],
      });
      expect(
        () => (request.arguments['nested'] as Map)['late'] = true,
        throwsUnsupportedError,
      );
    });

    test('rejects empty identities and arbitrary mutable leaves or keys', () {
      expect(
        () => SshToolRequest.disconnect(owner: ownerA, toolCallId: ' \n '),
        throwsArgumentError,
      );
      expect(
        () => SshToolRequest.executeCommand(
          owner: ownerA,
          toolCallId: 'call-command-a',
          arguments: {'value': DateTime(2026)},
        ),
        throwsArgumentError,
      );
      expect(
        () => SshToolRequest.executeCommand(
          owner: ownerA,
          toolCallId: 'call-command-a',
          arguments: {
            'value': <Object?>{'not-json'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => SshToolRequest.executeCommand(
          owner: ownerA,
          toolCallId: 'call-command-a',
          arguments: {'value': double.negativeInfinity},
        ),
        throwsArgumentError,
      );
      expect(
        () => SshToolRequest.executeCommand(
          owner: ownerA,
          toolCallId: 'call-command-a',
          arguments: {
            'value': {Object(): 'poisoned'},
          },
        ),
        throwsArgumentError,
      );
      expect(() => SshConnectionIdentity(' \t '), throwsArgumentError);
      expect(
        () => SshOwnedConnection(
          owner: ownerA,
          connectToolCallId: ' ',
          identity: _activeIdentity,
          key: _keyA,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SshToolHandler connect', () {
    test('validates host before consulting owner-scoped ports', () async {
      final fixture = _fixture();

      final result = await fixture.handler.handle(
        SshToolRequest.connect(
          owner: ownerA,
          toolCallId: 'call-connect-a',
          connectionIdentity: _connectIdentity,
          arguments: const {'host': '  '},
        ),
      );

      expect(result.errorMessage, 'host is required');
      expect(fixture.approval.lookups, isEmpty);
      expect(fixture.connection.connects, isEmpty);
    });

    test('uses one exact approved target through cache and connect', () async {
      final fixture = _fixture();
      fixture.credential.savedPasswords[ownerA] = 'saved-secret';
      fixture.approval.gates[ownerA] = ToolApprovalGateDecision.fullAccess;

      final result = await fixture.handler.handle(
        _connectRequest(
          ownerA,
          arguments: const {
            'host': ' host-a.example ',
            'port': 2200.9,
            'username': ' alice ',
          },
        ),
      );

      expect(result.result, 'Connected to alice@host-a.example:2200');
      final operation = fixture.connection.connects.single.operation;
      expect(operation.owner, ownerA);
      expect(operation.toolCallId, 'call-connect-a');
      expect(operation.sessionToolCallId, 'call-connect-a');
      expect(operation.connectionIdentity.value, 'ssh-connection-a');
      expect(operation.target.host, 'host-a.example');
      expect(operation.target.port, 2200);
      expect(operation.target.username, 'alice');
      expect(fixture.approval.lookups.single.toolCallId, 'call-connect-a');
      expect(fixture.approval.lookups.single.cacheArguments, {
        'host': 'host-a.example',
        'port': 2200,
        'username': 'alice',
      });
      expect(fixture.credential.requests, isEmpty);
      expect(
        fixture.credential.saves.single.operation.toolCallId,
        'call-connect-a',
      );
    });

    test('requires reapproval when credential UI edits the target', () async {
      const editedSelection = SshConnectCredentialSelection(
        key: SshCredentialKey(
          host: 'edited.example',
          port: 2222,
          username: 'operator',
        ),
        password: 'edited-secret',
        savePassword: true,
      );
      final fixture = _fixture();
      fixture.credential.selections[ownerA] = editedSelection;

      final result = await fixture.handler.handle(_connectRequest(ownerA));

      expect(
        result.errorMessage,
        contains('SSH target changed after approval'),
      );
      expect(
        fixture.credential.results.single.kind,
        SshCredentialSelectionResultKind.reapprovalRequired,
      );
      expect(fixture.connection.connects, isEmpty);
      expect(fixture.credential.saves, isEmpty);
      expect(fixture.credential.deletes, isEmpty);
    });

    test('keeps cancellation and auto-review denials call-scoped', () async {
      final cancelled = _fixture();
      cancelled.credential.cancelledOwners.add(ownerA);
      final cancelledResult = await cancelled.handler.handle(
        _connectRequest(ownerA),
      );
      expect(cancelledResult.errorMessage, 'User cancelled SSH connection');
      expect(
        cancelled.approval.rememberedDenials.single.operation.toolCallId,
        'call-connect-a',
      );

      final denied = _fixture();
      denied.approval.gates[ownerA] = ToolApprovalGateDecision.denied(
        'target is not trusted',
      );
      final deniedResult = await denied.handler.handle(_connectRequest(ownerA));
      expect(
        deniedResult.errorMessage,
        'Auto-review denied: target is not trusted',
      );
      expect(denied.credential.requests, isEmpty);
      expect(denied.connection.connects, isEmpty);
    });

    test('falls back to credential UI after password lookup failure', () async {
      final fixture = _fixture();
      fixture.credential.loadErrors[ownerA] = StateError('locked');

      final result = await fixture.handler.handle(_connectRequest(ownerA));

      expect(result.isSuccess, isTrue);
      expect(fixture.credential.requests.single.savedPassword, isNull);
      expect(fixture.connection.connects.single.password, 'manual-secret');
    });

    test('rejects poisoned async identities before connecting', () async {
      final cachePoison = _fixture();
      cachePoison.approval.poisonStage = 'lookup';
      final cacheResult = await cachePoison.handler.handle(
        _connectRequest(ownerA),
      );
      expect(
        cacheResult.errorMessage,
        'SSH operation identity changed before completion',
      );
      expect(cachePoison.credential.requests, isEmpty);
      expect(cachePoison.connection.connects, isEmpty);

      final credentialPoison = _fixture();
      credentialPoison.credential.poisonStage = 'request';
      final credentialResult = await credentialPoison.handler.handle(
        _connectRequest(ownerA),
      );
      expect(
        credentialResult.errorMessage,
        'SSH operation identity changed before completion',
      );
      expect(credentialPoison.connection.connects, isEmpty);

      final gatePoison = _fixture();
      gatePoison.approval.poisonStage = 'gate';
      final gateResult = await gatePoison.handler.handle(
        _connectRequest(ownerA),
      );
      expect(
        gateResult.errorMessage,
        'SSH operation identity changed before completion',
      );
      expect(gatePoison.connection.connects, isEmpty);
    });

    test(
      'uses possible-side-effect guidance after completion identity drift',
      () async {
        final fixture = _fixture();
        fixture.connection.poisonConnectCompletion = true;

        final result = await fixture.handler.handle(_connectRequest(ownerA));

        expect(result.errorMessage, contains('possible side effects'));
        expect(fixture.connection.connects, hasLength(1));
        expect(fixture.credential.deletes, isEmpty);
      },
    );

    test(
      'rolls back exact target and warns after post-connect expiry',
      () async {
        final fixture = _fixture();
        fixture.approval.expirations.addAll([null, _expired('ssh_connect')]);

        final result = await fixture.handler.handle(_connectRequest(ownerA));

        expect(result.errorMessage, contains('possible side effects'));
        final rollback = fixture.connection.disconnects.single;
        expect(rollback.toolCallId, 'call-connect-a');
        expect(rollback.target.host, 'host-a.example');
        expect(rollback.connectionIdentity.value, 'ssh-connection-a');
        expect(fixture.credential.deletes, isEmpty);
      },
    );

    test(
      'warns that connection remains after credential persistence failure',
      () async {
        final fixture = _fixture();
        fixture.credential.deleteErrors[ownerA] = StateError(
          'keychain unavailable',
        );

        final result = await fixture.handler.handle(_connectRequest(ownerA));

        expect(result.errorMessage, contains('connection succeeded'));
        expect(result.errorMessage, contains('possible side effects'));
        expect(result.errorMessage, contains('keychain unavailable'));
        expect(fixture.connection.connects, hasLength(1));
        expect(fixture.connection.disconnects, isEmpty);
      },
    );
  });

  group('SshToolHandler command', () {
    test('requires an exact-call active connection completion', () async {
      final absent = _fixture();
      expect(
        (await absent.handler.handle(_commandRequest(ownerA))).errorMessage,
        'No active SSH session — call ssh_connect first',
      );

      final wrongOwner = _fixture();
      wrongOwner.connection.activeConnections[ownerA] = _connection(ownerB);
      expect(
        (await wrongOwner.handler.handle(_commandRequest(ownerA))).errorMessage,
        'No active SSH session — call ssh_connect first',
      );

      final poisonedLookup = _connectedFixture(ownerA);
      poisonedLookup.connection.poisonLookupCompletion = true;
      expect(
        (await poisonedLookup.handler.handle(
          _commandRequest(ownerA),
        )).errorMessage,
        'No active SSH session — call ssh_connect first',
      );
    });

    test(
      'binds approval, execution, and result cache to call and target',
      () async {
        final fixture = _connectedFixture(ownerA);
        fixture.approval.gates[ownerA] =
            ToolApprovalGateDecision.needsManualApproval;

        final result = await fixture.handler.handle(_commandRequest(ownerA));

        expect(result.isSuccess, isTrue);
        final execution = fixture.execution.commands.single;
        expect(execution.operation.toolCallId, 'call-command-a');
        expect(execution.operation.sessionToolCallId, 'call-connect-active');
        expect(
          execution.operation.connectionIdentity.value,
          'active-connection-a',
        );
        expect(execution.operation.target.host, 'host-a.example');
        expect(execution.arguments['command'], 'uname -a');
        expect(
          fixture.approval.manualRequests.single.operation.toolCallId,
          'call-command-a',
        );
        expect(
          fixture.approval.rememberedResults.single.operation.toolCallId,
          'call-command-a',
        );
      },
    );

    test('does not dispatch cached, automatic, or manual denials', () async {
      final cached = _connectedFixture(ownerA);
      cached.approval.cachedDenials[ownerA] = _failureResult(
        'ssh_execute_command',
        'cached denial',
      );
      expect(
        (await cached.handler.handle(_commandRequest(ownerA))).errorMessage,
        'cached denial',
      );

      final automatic = _connectedFixture(ownerA);
      automatic.approval.gates[ownerA] = ToolApprovalGateDecision.denied(
        'unsafe command',
      );
      expect(
        (await automatic.handler.handle(_commandRequest(ownerA))).errorMessage,
        'Auto-review denied: unsafe command',
      );

      final manual = _connectedFixture(ownerA);
      manual.approval.gates[ownerA] =
          ToolApprovalGateDecision.needsManualApproval;
      manual.approval.manualDecisions[ownerA] = false;
      expect(
        (await manual.handler.handle(_commandRequest(ownerA))).errorMessage,
        'User denied SSH command execution',
      );
      expect(cached.execution.commands, isEmpty);
      expect(automatic.execution.commands, isEmpty);
      expect(manual.execution.commands, isEmpty);
    });

    test('warns when command completion expires or changes identity', () async {
      final expired = _connectedFixture(ownerA);
      expired.approval.expirations.addAll([
        null,
        _expired('ssh_execute_command'),
      ]);
      final expiredResult = await expired.handler.handle(
        _commandRequest(ownerA),
      );
      expect(expiredResult.errorMessage, contains('possible side effects'));
      expect(expired.execution.commands, hasLength(1));

      final poisoned = _connectedFixture(ownerA);
      poisoned.execution.poisonCommandCompletion = true;
      final poisonedResult = await poisoned.handler.handle(
        _commandRequest(ownerA),
      );
      expect(poisonedResult.errorMessage, contains('possible side effects'));
      expect(poisoned.execution.commands, hasLength(1));

      final cachePoisoned = _connectedFixture(ownerA);
      cachePoisoned.approval.poisonStage = 'rememberResult';
      final cachePoisonedResult = await cachePoisoned.handler.handle(
        _commandRequest(ownerA),
      );
      expect(
        cachePoisonedResult.errorMessage,
        contains('possible side effects'),
      );
      expect(cachePoisoned.execution.commands, hasLength(1));
    });

    test('treats post-dispatch exceptions as possible side effects', () async {
      final fixture = _connectedFixture(ownerA);
      fixture.execution.commandErrors[ownerA] = StateError('transport lost');

      final result = await fixture.handler.handle(_commandRequest(ownerA));

      expect(result.errorMessage, contains('possible side effects'));
      expect(fixture.execution.commands, hasLength(1));
    });
  });

  group('SshToolHandler disconnect', () {
    test('returns locally when there is no exact-owner session', () async {
      final fixture = _fixture();

      final result = await fixture.handler.handle(_disconnectRequest(ownerA));

      expect(result.result, 'No active SSH session');
      expect(result.isSuccess, isTrue);
      expect(fixture.execution.disconnects, isEmpty);
    });

    test(
      'validates exact target before and after disconnect dispatch',
      () async {
        final fixture = _connectedFixture(ownerA);

        final result = await fixture.handler.handle(_disconnectRequest(ownerA));

        expect(result.result, 'Disconnected');
        final use = fixture.execution.disconnects.single;
        expect(use.operation.toolCallId, 'call-disconnect-a');
        expect(use.operation.sessionToolCallId, 'call-connect-active');
        expect(use.operation.connectionIdentity.value, 'active-connection-a');
        expect(use.operation.target.host, 'host-a.example');

        final poisoned = _connectedFixture(ownerA);
        poisoned.execution.poisonDisconnectCompletion = true;
        final poisonedResult = await poisoned.handler.handle(
          _disconnectRequest(ownerA),
        );
        expect(poisonedResult.errorMessage, contains('possible side effects'));

        final expired = _connectedFixture(ownerA);
        expired.approval.expirations.addAll([null, _expired('ssh_disconnect')]);
        final expiredResult = await expired.handler.handle(
          _disconnectRequest(ownerA),
        );
        expect(expiredResult.errorMessage, contains('possible side effects'));
        expect(expired.execution.disconnects, hasLength(1));
      },
    );

    test(
      'does not disconnect when exact operation is already expired',
      () async {
        final fixture = _connectedFixture(ownerA);
        fixture.approval.expirations.add(_expired('ssh_disconnect'));

        final result = await fixture.handler.handle(_disconnectRequest(ownerA));

        expect(
          result.errorMessage,
          'The approval turn expired before execution',
        );
        expect(fixture.execution.disconnects, isEmpty);
      },
    );
  });
}

SshToolRequest _connectRequest(
  ChatTurnOwner owner, {
  Map<String, dynamic> arguments = const {
    'host': 'host-a.example',
    'username': 'alice',
    'reason': 'Connect for diagnostics.',
  },
}) {
  return SshToolRequest.connect(
    owner: owner,
    toolCallId: 'call-connect-a',
    connectionIdentity: _connectIdentity,
    arguments: arguments,
  );
}

SshToolRequest _commandRequest(ChatTurnOwner owner) {
  return SshToolRequest.executeCommand(
    owner: owner,
    toolCallId: 'call-command-a',
    arguments: const {
      'command': 'uname -a',
      'reason': 'Inspect the remote host.',
    },
  );
}

SshToolRequest _disconnectRequest(ChatTurnOwner owner) {
  return SshToolRequest.disconnect(
    owner: owner,
    toolCallId: 'call-disconnect-a',
  );
}

SshOwnedConnection _connection(ChatTurnOwner owner) {
  return SshOwnedConnection(
    owner: owner,
    connectToolCallId: 'call-connect-active',
    identity: _activeIdentity,
    key: _keyA,
  );
}

McpToolResult _expired(String toolName) {
  return McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: 'The approval turn expired before execution',
  );
}

McpToolResult _failureResult(String toolName, String message) {
  return McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}

typedef _Fixture = ({
  SshToolHandler handler,
  _CredentialPort credential,
  _ConnectionPort connection,
  _ExecutionPort execution,
  _ApprovalPort approval,
});

_Fixture _fixture() {
  final credential = _CredentialPort();
  final connection = _ConnectionPort();
  final execution = _ExecutionPort();
  final approval = _ApprovalPort();
  return (
    handler: SshToolHandler(
      credentialPort: credential,
      connectionPort: connection,
      executionPort: execution,
      approvalPort: approval,
    ),
    credential: credential,
    connection: connection,
    execution: execution,
    approval: approval,
  );
}

_Fixture _connectedFixture(ChatTurnOwner owner) {
  final fixture = _fixture();
  fixture.connection.activeConnections[owner] = _connection(owner);
  return fixture;
}

SshOperationIdentity _poisonOperation(SshOperationIdentity operation) {
  final request = switch (operation.request.kind) {
    SshToolKind.connect => SshToolRequest.connect(
      owner: operation.owner,
      toolCallId: 'poisoned-call',
      connectionIdentity: operation.connectionIdentity,
      arguments: operation.request.arguments,
    ),
    SshToolKind.executeCommand => SshToolRequest.executeCommand(
      owner: operation.owner,
      toolCallId: 'poisoned-call',
      arguments: operation.request.arguments,
    ),
    SshToolKind.disconnect => SshToolRequest.disconnect(
      owner: operation.owner,
      toolCallId: 'poisoned-call',
      arguments: operation.request.arguments,
    ),
  };
  return SshOperationIdentity(
    request: request,
    connectionIdentity: operation.connectionIdentity,
    sessionToolCallId: operation.sessionToolCallId,
    target: operation.target,
  );
}

SshToolRequest _poisonRequest(SshToolRequest request) {
  return switch (request.kind) {
    SshToolKind.connect => SshToolRequest.connect(
      owner: request.owner,
      toolCallId: 'poisoned-call',
      connectionIdentity: request.connectionIdentity!,
      arguments: request.arguments,
    ),
    SshToolKind.executeCommand => SshToolRequest.executeCommand(
      owner: request.owner,
      toolCallId: 'poisoned-call',
      arguments: request.arguments,
    ),
    SshToolKind.disconnect => SshToolRequest.disconnect(
      owner: request.owner,
      toolCallId: 'poisoned-call',
      arguments: request.arguments,
    ),
  };
}

typedef _CredentialRequestUse = SshConnectCredentialRequest;
typedef _PasswordUse = ({SshOperationIdentity operation, String password});

final class _CredentialPort implements SshCredentialPort {
  final Map<ChatTurnOwner, String?> savedPasswords = {};
  final Map<ChatTurnOwner, Object> loadErrors = {};
  final Map<ChatTurnOwner, SshConnectCredentialSelection> selections = {};
  final Set<ChatTurnOwner> cancelledOwners = {};
  final Map<ChatTurnOwner, Object> saveErrors = {};
  final Map<ChatTurnOwner, Object> deleteErrors = {};
  final List<_CredentialRequestUse> requests = [];
  final List<SshCredentialSelectionResult> results = [];
  final List<_PasswordUse> saves = [];
  final List<SshOperationIdentity> deletes = [];
  String? poisonStage;

  @override
  Future<SshOperationCompletion<String?>> loadSavedPassword(
    SshOperationIdentity operation,
  ) async {
    final error = loadErrors[operation.owner];
    if (error != null) throw error;
    return SshOperationCompletion(
      operation: poisonStage == 'load'
          ? _poisonOperation(operation)
          : operation,
      value: savedPasswords[operation.owner],
    );
  }

  @override
  Future<SshCredentialSelectionResult> requestCredential(
    SshConnectCredentialRequest request,
  ) async {
    requests.add(request);
    final operation = poisonStage == 'request'
        ? _poisonOperation(request.operation)
        : request.operation;
    final result = cancelledOwners.contains(request.operation.owner)
        ? SshCredentialSelectionResult.cancelled(operation: operation)
        : SshCredentialSelectionResult.fromSelection(
            operation: operation,
            selection: selections[request.operation.owner] ?? _manualSelection,
          );
    results.add(result);
    return result;
  }

  @override
  Future<SshOperationCompletion<void>> savePassword(
    SshOperationIdentity operation,
    String password,
  ) async {
    saves.add((operation: operation, password: password));
    final error = saveErrors[operation.owner];
    if (error != null) throw error;
    return SshOperationCompletion(operation: operation, value: null);
  }

  @override
  Future<SshOperationCompletion<void>> deletePassword(
    SshOperationIdentity operation,
  ) async {
    deletes.add(operation);
    final error = deleteErrors[operation.owner];
    if (error != null) throw error;
    return SshOperationCompletion(operation: operation, value: null);
  }
}

typedef _ConnectUse = ({SshOperationIdentity operation, String password});

final class _ConnectionPort implements SshConnectionPort {
  final Map<ChatTurnOwner, SshOwnedConnection> activeConnections = {};
  final List<_ConnectUse> connects = [];
  final List<SshOperationIdentity> disconnects = [];
  bool poisonLookupCompletion = false;
  bool poisonConnectCompletion = false;

  @override
  SshCallCompletion<SshOwnedConnection?> lookupActive(SshToolRequest request) {
    return SshCallCompletion(
      request: poisonLookupCompletion ? _poisonRequest(request) : request,
      value: activeConnections[request.owner],
    );
  }

  @override
  Future<SshOperationCompletion<void>> connect(
    SshOperationIdentity operation, {
    required String password,
  }) async {
    connects.add((operation: operation, password: password));
    activeConnections[operation.owner] = SshOwnedConnection(
      owner: operation.owner,
      connectToolCallId: operation.sessionToolCallId,
      identity: operation.connectionIdentity,
      key: operation.target,
    );
    return SshOperationCompletion(
      operation: poisonConnectCompletion
          ? _poisonOperation(operation)
          : operation,
      value: null,
    );
  }

  @override
  Future<SshOperationCompletion<void>> disconnect(
    SshOperationIdentity operation,
  ) async {
    disconnects.add(operation);
    activeConnections.remove(operation.owner);
    return SshOperationCompletion(operation: operation, value: null);
  }
}

typedef _ExecutionUse = ({
  SshOperationIdentity operation,
  Map<String, dynamic> arguments,
});

final class _ExecutionPort implements SshCommandExecutionPort {
  final Map<ChatTurnOwner, Object> commandErrors = {};
  final List<_ExecutionUse> commands = [];
  final List<_ExecutionUse> disconnects = [];
  bool poisonCommandCompletion = false;
  bool poisonDisconnectCompletion = false;

  @override
  Future<SshOperationCompletion<McpToolResult>> executeCommand(
    SshOperationIdentity operation, {
    required Map<String, dynamic> arguments,
  }) async {
    commands.add((operation: operation, arguments: arguments));
    final error = commandErrors[operation.owner];
    if (error != null) throw error;
    return SshOperationCompletion(
      operation: poisonCommandCompletion
          ? _poisonOperation(operation)
          : operation,
      value: const McpToolResult(
        toolName: 'ssh_execute_command',
        result: 'exit_code: 0\n',
        isSuccess: true,
      ),
    );
  }

  @override
  Future<SshOperationCompletion<McpToolResult>> disconnect(
    SshOperationIdentity operation, {
    required Map<String, dynamic> arguments,
  }) async {
    disconnects.add((operation: operation, arguments: arguments));
    return SshOperationCompletion(
      operation: poisonDisconnectCompletion
          ? _poisonOperation(operation)
          : operation,
      value: const McpToolResult(
        toolName: 'ssh_disconnect',
        result: 'Disconnected',
        isSuccess: true,
      ),
    );
  }
}

final class _ApprovalPort implements SshCommandApprovalPort {
  final Map<ChatTurnOwner, McpToolResult> cachedDenials = {};
  final Map<ChatTurnOwner, ToolApprovalGateDecision> gates = {};
  final Map<ChatTurnOwner, bool> manualDecisions = {};
  final List<McpToolResult?> expirations = [];
  final List<SshApprovalRequest> lookups = [];
  final List<SshApprovalRequest> manualRequests = [];
  final List<SshApprovalRequest> rememberedDenials = [];
  final List<SshApprovalRequest> rememberedResults = [];
  String? poisonStage;

  SshOperationIdentity _operation(
    SshOperationIdentity operation,
    String stage,
  ) {
    return poisonStage == stage ? _poisonOperation(operation) : operation;
  }

  @override
  SshOperationCompletion<McpToolResult?> lookupDenial(
    SshApprovalRequest request,
  ) {
    lookups.add(request);
    return SshOperationCompletion(
      operation: _operation(request.operation, 'lookup'),
      value: cachedDenials[request.owner],
    );
  }

  @override
  Future<SshOperationCompletion<ToolApprovalGateDecision>> resolveGate(
    SshApprovalRequest request, {
    required bool fullAccessEligible,
  }) async {
    return SshOperationCompletion(
      operation: _operation(request.operation, 'gate'),
      value: gates[request.owner] ?? ToolApprovalGateDecision.autoReviewAllowed,
    );
  }

  @override
  Future<SshOperationCompletion<bool>> requestCommandApproval(
    SshApprovalRequest request,
  ) async {
    manualRequests.add(request);
    return SshOperationCompletion(
      operation: _operation(request.operation, 'manual'),
      value: manualDecisions[request.owner] ?? true,
    );
  }

  @override
  SshOperationCompletion<McpToolResult> rememberDenial(
    SshApprovalRequest request,
    McpToolResult result,
  ) {
    rememberedDenials.add(request);
    return SshOperationCompletion(
      operation: _operation(request.operation, 'rememberDenial'),
      value: result,
    );
  }

  @override
  SshOperationCompletion<McpToolResult> rememberResult(
    SshApprovalRequest request,
    McpToolResult result,
  ) {
    rememberedResults.add(request);
    return SshOperationCompletion(
      operation: _operation(request.operation, 'rememberResult'),
      value: result,
    );
  }

  @override
  SshOperationCompletion<McpToolResult?> expiredResult(
    SshOperationIdentity operation,
  ) {
    return SshOperationCompletion(
      operation: _operation(operation, 'expiration'),
      value: expirations.isEmpty ? null : expirations.removeAt(0),
    );
  }
}
