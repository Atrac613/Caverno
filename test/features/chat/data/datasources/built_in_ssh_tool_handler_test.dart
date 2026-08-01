import 'package:caverno/core/services/ssh_service.dart';
import 'package:caverno/features/chat/data/datasources/built_in_ssh_tool_handler.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuiltInSshToolHandler', () {
    late ChatTurnOwner owner;

    setUp(() {
      owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 1,
      );
    });

    test('owns the exact ordered family and schemas', () {
      final unavailable = BuiltInSshToolHandler();
      final available = BuiltInSshToolHandler(sshService: _FakeSshService());

      expect(BuiltInSshToolHandler.toolNames, const [
        'ssh_connect',
        'ssh_execute_command',
        'ssh_disconnect',
      ]);
      expect(
        available.definitions.map(_definitionName),
        BuiltInSshToolHandler.toolNames,
      );
      expect(unavailable.isAvailable, isFalse);
      expect(available.isAvailable, isTrue);
      expect(available.handles('ssh_execute_command'), isTrue);
      expect(available.handles('ssh_upload'), isFalse);

      final connectParameters = _parameters(available.definitions[0]);
      expect(connectParameters['required'], ['host']);
      expect((connectParameters['properties']! as Map<String, dynamic>).keys, [
        'host',
        'port',
        'username',
      ]);

      final executeParameters = _parameters(available.definitions[1]);
      expect(executeParameters['required'], ['command']);
      expect((executeParameters['properties']! as Map<String, dynamic>).keys, [
        'command',
        'reason',
      ]);

      final disconnectParameters = _parameters(available.definitions[2]);
      expect(
        disconnectParameters['properties'],
        isA<Map<String, dynamic>>().having(
          (properties) => properties,
          'properties',
          isEmpty,
        ),
      );
    });

    test('denies direct connect and rejects unknown names', () async {
      final handler = BuiltInSshToolHandler(sshService: _FakeSshService());

      final connect = await handler.execute(
        owner: owner,
        name: 'ssh_connect',
        arguments: const {'host': 'example.com'},
      );

      expect(connect.isSuccess, isFalse);
      expect(connect.result, isEmpty);
      expect(
        connect.errorMessage,
        'ssh_connect must be handled by ChatNotifier (internal error)',
      );
      await expectLater(
        handler.execute(owner: owner, name: 'ssh_upload', arguments: const {}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            'Unknown SSH tool',
          ),
        ),
      );
    });

    test('preserves unavailable and inactive results', () async {
      final unavailable = BuiltInSshToolHandler();
      final inactiveService = _FakeSshService();
      final inactive = BuiltInSshToolHandler(sshService: inactiveService);

      final unavailableExecute = await unavailable.execute(
        owner: owner,
        name: 'ssh_execute_command',
        arguments: const {'command': 'pwd'},
      );
      final unavailableDisconnect = await unavailable.execute(
        owner: owner,
        name: 'ssh_disconnect',
        arguments: const {},
      );
      final inactiveExecute = await inactive.execute(
        owner: owner,
        name: 'ssh_execute_command',
        arguments: const {'command': 'pwd'},
      );
      final inactiveDisconnect = await inactive.execute(
        owner: owner,
        name: 'ssh_disconnect',
        arguments: const {},
      );

      expect(unavailableExecute.errorMessage, 'SSH service is unavailable');
      expect(unavailableDisconnect.isSuccess, isTrue);
      expect(unavailableDisconnect.result, 'No active SSH session');
      expect(
        inactiveExecute.errorMessage,
        'No active SSH session — call ssh_connect first',
      );
      expect(inactiveDisconnect.isSuccess, isTrue);
      expect(inactiveDisconnect.result, 'No active SSH session');
      expect(inactiveService.disconnectCalls, 1);
    });

    test('trims approved commands and preserves formatted output', () async {
      final service = _FakeSshService(
        connectedOwners: {owner},
        executionResult: SshExecutionResult(
          stdout: 'output',
          stderr: 'warning',
          exitCode: 3,
        ),
      );
      final handler = BuiltInSshToolHandler(sshService: service);

      final result = await handler.execute(
        owner: owner,
        name: 'ssh_execute_command',
        arguments: const {'command': '  uname -a  ', 'reason': 'inspect'},
      );

      expect(result.isSuccess, isTrue);
      expect(
        result.result,
        'exit_code: 3\n--- stdout ---\noutput\n--- stderr ---\nwarning\n',
      );
      expect(service.executedCommands, ['uname -a']);
      expect(service.executionOwners, [owner]);
    });

    test('forwards exact owner and does not expose a peer session', () async {
      final peerOwner = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );
      final service = _FakeSshService(connectedOwners: {owner});
      final handler = BuiltInSshToolHandler(sshService: service);

      final peerExecute = await handler.execute(
        owner: peerOwner,
        name: 'ssh_execute_command',
        arguments: const {'command': 'hostname'},
      );
      final peerDisconnect = await handler.execute(
        owner: peerOwner,
        name: 'ssh_disconnect',
        arguments: const {},
      );

      expect(peerExecute.isSuccess, isFalse);
      expect(
        peerExecute.errorMessage,
        'No active SSH session — call ssh_connect first',
      );
      expect(peerDisconnect.result, 'No active SSH session');
      expect(service.connectedOwners, {owner});
      expect(service.executionOwners, isEmpty);
    });

    test('rejects empty commands and converts execution errors', () async {
      final service = _FakeSshService(
        connectedOwners: {owner},
        executionError: StateError('execute failed'),
      );
      final handler = BuiltInSshToolHandler(sshService: service);

      final empty = await handler.execute(
        owner: owner,
        name: 'ssh_execute_command',
        arguments: const {'command': '   '},
      );
      final malformed = await handler.execute(
        owner: owner,
        name: 'ssh_execute_command',
        arguments: const {'command': 42},
      );
      final failed = await handler.execute(
        owner: owner,
        name: 'ssh_execute_command',
        arguments: const {'command': 'false'},
      );

      expect(empty.errorMessage, 'command is required');
      expect(malformed.isSuccess, isFalse);
      expect(malformed.errorMessage, contains("type 'int'"));
      expect(failed.isSuccess, isFalse);
      expect(failed.errorMessage, 'Bad state: execute failed');
      expect(service.executedCommands, ['false']);
    });

    test(
      'disconnects active sessions and converts disconnect errors',
      () async {
        final connected = _FakeSshService(connectedOwners: {owner});
        final failing = _FakeSshService(
          connectedOwners: {owner},
          disconnectError: StateError('disconnect failed'),
        );

        final disconnected = await BuiltInSshToolHandler(
          sshService: connected,
        ).execute(owner: owner, name: 'ssh_disconnect', arguments: const {});
        final failed = await BuiltInSshToolHandler(
          sshService: failing,
        ).execute(owner: owner, name: 'ssh_disconnect', arguments: const {});

        expect(disconnected.isSuccess, isTrue);
        expect(disconnected.result, 'Disconnected');
        expect(connected.disconnectCalls, 1);
        expect(connected.connectedOwners, isEmpty);
        expect(failed.isSuccess, isFalse);
        expect(failed.errorMessage, 'Bad state: disconnect failed');
        expect(failing.disconnectCalls, 1);
        expect(failing.connectedOwners, {owner});
      },
    );
  });
}

String _definitionName(Map<String, dynamic> definition) =>
    (definition['function']! as Map<String, dynamic>)['name']! as String;

Map<String, dynamic> _parameters(Map<String, dynamic> definition) =>
    (definition['function']! as Map<String, dynamic>)['parameters']!
        as Map<String, dynamic>;

final class _FakeSshService extends SshService {
  _FakeSshService({
    Set<ChatTurnOwner>? connectedOwners,
    SshExecutionResult? executionResult,
    this.executionError,
    this.disconnectError,
  }) : connectedOwners = {...?connectedOwners},
       executionResult =
           executionResult ??
           SshExecutionResult(stdout: '', stderr: '', exitCode: 0);

  final Set<ChatTurnOwner> connectedOwners;
  final SshExecutionResult executionResult;
  final Object? executionError;
  final Object? disconnectError;
  final List<String> executedCommands = [];
  final List<ChatTurnOwner> executionOwners = [];
  int disconnectCalls = 0;

  @override
  bool isConnected({required ChatTurnOwner owner}) =>
      connectedOwners.contains(owner);

  @override
  Future<SshExecutionResult> execute({
    required ChatTurnOwner owner,
    required String command,
    String? expectedFingerprint,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    executionOwners.add(owner);
    executedCommands.add(command);
    final error = executionError;
    if (error != null) throw error;
    return executionResult;
  }

  @override
  Future<void> disconnect({required ChatTurnOwner owner}) async {
    disconnectCalls += 1;
    final error = disconnectError;
    if (error != null) throw error;
    connectedOwners.remove(owner);
  }
}
