import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:caverno/core/services/ssh_service.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  group('SshExecutionResult', () {
    test('formats stdout, stderr, and absent exit codes', () {
      expect(
        SshExecutionResult(
          stdout: 'output',
          stderr: 'warning',
          exitCode: 3,
        ).formatted(),
        'exit_code: 3\n'
        '--- stdout ---\n'
        'output\n'
        '--- stderr ---\n'
        'warning\n',
      );
      expect(
        SshExecutionResult(stdout: '', stderr: '', exitCode: null).formatted(),
        'exit_code: n/a\n',
      );
    });
  });

  group('SshService owner lifecycle', () {
    late ChatTurnOwner owner;

    setUp(() {
      owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 1,
      );
    });

    for (final peer in [
      ChatTurnOwner(conversationId: 'conversation-b', interactionGeneration: 1),
      ChatTurnOwner(conversationId: 'conversation-a', interactionGeneration: 2),
    ]) {
      test('isolates peer ${peer.toString()}', () async {
        final first = _MockSshClient();
        final second = _MockSshClient();
        _stubClient(first);
        _stubClient(second);
        final connector = _ClientQueueConnector([first, second]);
        final service = SshService(connector: connector.call);
        addTearDown(service.dispose);

        await _connect(service, owner, host: 'first.example');
        await _connect(service, peer, host: 'second.example');

        expect(service.isConnected(owner: owner), isTrue);
        expect(service.isConnected(owner: peer), isTrue);
        expect(service.status(owner: owner)?.host, 'first.example');
        expect(service.activeSession(owner: peer)?.host, 'second.example');
        expect(service.status(owner: owner)?.connectedAt, isNotNull);

        await service.clearOwner(owner: owner);

        expect(service.isConnected(owner: owner), isFalse);
        expect(service.status(owner: owner), isNull);
        expect(service.isConnected(owner: peer), isTrue);
        verify(first.close).called(1);
        verifyNever(second.close);
      });
    }

    test('replaces only the same owner session', () async {
      final first = _MockSshClient();
      final replacement = _MockSshClient();
      _stubClient(first);
      _stubClient(replacement);
      final connector = _ClientQueueConnector([first, replacement]);
      final service = SshService(connector: connector.call);
      addTearDown(service.dispose);

      await _connect(service, owner, host: 'old.example');
      await _connect(service, owner, host: 'new.example');

      expect(service.status(owner: owner)?.host, 'new.example');
      verify(first.close).called(1);
      verifyNever(replacement.close);
    });

    test('conditionally disconnects only the observed session', () async {
      final first = _MockSshClient();
      final successor = _MockSshClient();
      _stubClient(first);
      _stubClient(successor);
      final service = SshService(
        connector: _ClientQueueConnector([first, successor]).call,
      );
      addTearDown(service.dispose);

      await _connect(service, owner, host: 'old.example');
      final oldFingerprint = service.activeSessionFingerprint(owner: owner)!;
      await _connect(service, owner, host: 'successor.example');
      final successorFingerprint = service.activeSessionFingerprint(
        owner: owner,
      )!;

      expect(
        await service.disconnectIfFingerprint(
          owner: owner,
          expectedFingerprint: oldFingerprint,
        ),
        isFalse,
      );
      expect(service.status(owner: owner)?.host, 'successor.example');
      verifyNever(successor.close);
      expect(
        await service.disconnectIfFingerprint(
          owner: owner,
          expectedFingerprint: successorFingerprint,
        ),
        isTrue,
      );
      verify(successor.close).called(1);
    });

    test(
      'disconnect fences current work but permits explicit reconnect',
      () async {
        final first = _MockSshClient();
        final reconnected = _MockSshClient();
        _stubClient(first);
        _stubClient(reconnected);
        final service = SshService(
          connector: _ClientQueueConnector([first, reconnected]).call,
        );
        addTearDown(service.dispose);
        await _connect(service, owner, host: 'first.example');

        await service.disconnect(owner: owner);
        await _connect(service, owner, host: 'reconnected.example');

        expect(service.status(owner: owner)?.host, 'reconnected.example');
        verify(first.close).called(1);
        verifyNever(reconnected.close);
      },
    );

    test('late disconnected client cannot replace a reconnect', () async {
      final late = _MockSshClient();
      final reconnected = _MockSshClient();
      _stubClient(late);
      _stubClient(reconnected);
      final firstConnectorEntered = Completer<void>();
      final lateClient = Completer<SSHClient>();
      var connectCount = 0;
      final service = SshService(
        connector:
            ({
              required host,
              required port,
              required username,
              required credential,
              required timeout,
            }) {
              connectCount += 1;
              if (connectCount == 1) {
                firstConnectorEntered.complete();
                return lateClient.future;
              }
              return Future.value(reconnected);
            },
      );
      addTearDown(service.dispose);

      final firstConnect = _connect(service, owner, host: 'late.example');
      await firstConnectorEntered.future;
      await service.disconnect(owner: owner);
      await _connect(service, owner, host: 'reconnected.example');
      lateClient.complete(late);

      await expectLater(firstConnect, throwsA(isA<StateError>()));
      expect(service.status(owner: owner)?.host, 'reconnected.example');
      verify(late.close).called(1);
      verifyNever(reconnected.close);
    });

    test('wrong owner cannot execute or disconnect a peer', () async {
      final client = _MockSshClient();
      _stubClient(client);
      final service = SshService(
        connector: _ClientQueueConnector([client]).call,
      );
      addTearDown(service.dispose);
      final peer = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: owner.interactionGeneration,
      );
      await _connect(service, owner);

      await expectLater(
        service.execute(owner: peer, command: 'pwd'),
        throwsA(isA<StateError>()),
      );
      await service.disconnect(owner: peer);

      expect(service.isConnected(owner: owner), isTrue);
      verifyNever(client.close);
    });

    test('executes commands and captures malformed output safely', () async {
      final client = _MockSshClient();
      final session = _MockSshSession();
      _stubClient(client);
      when(() => client.execute('inspect')).thenAnswer((_) async => session);
      when(
        () => session.stdout,
      ).thenAnswer((_) => Stream.value(Uint8List.fromList([0x6f, 0xff])));
      when(() => session.stderr).thenAnswer(
        (_) => Stream.value(Uint8List.fromList(utf8.encode('warn'))),
      );
      when(() => session.done).thenAnswer((_) async {});
      when(() => session.exitCode).thenReturn(7);
      final service = SshService(
        connector: _ClientQueueConnector([client]).call,
      );
      addTearDown(service.dispose);
      await _connect(service, owner);

      final result = await service.execute(owner: owner, command: 'inspect');

      expect(result.stdout, 'o\u{fffd}');
      expect(result.stderr, 'warn');
      expect(result.exitCode, 7);
    });

    test('rejects command dispatch for a stale session fingerprint', () async {
      final client = _MockSshClient();
      _stubClient(client);
      final service = SshService(
        connector: _ClientQueueConnector([client]).call,
      );
      addTearDown(service.dispose);
      await _connect(service, owner);

      await expectLater(
        service.execute(
          owner: owner,
          command: 'inspect',
          expectedFingerprint: 'stale-session',
        ),
        throwsA(isA<StateError>()),
      );
      verifyNever(() => client.execute(any()));
    });

    test('normalizes command timeouts', () async {
      final client = _MockSshClient();
      _stubClient(client);
      when(
        () => client.execute('slow'),
      ).thenAnswer((_) => Completer<SSHSession>().future);
      final service = SshService(
        connector: _ClientQueueConnector([client]).call,
      );
      addTearDown(service.dispose);
      await _connect(service, owner);

      await expectLater(
        service.execute(owner: owner, command: 'slow', timeout: Duration.zero),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('SSH command timed out after 0s'),
          ),
        ),
      );
    });

    test('clearOwner fences a late connector completion', () async {
      final connectorEntered = Completer<void>();
      final lateClient = Completer<SSHClient>();
      final client = _MockSshClient();
      _stubClient(client);
      final service = SshService(
        connector:
            ({
              required host,
              required port,
              required username,
              required credential,
              required timeout,
            }) {
              connectorEntered.complete();
              return lateClient.future;
            },
      );
      addTearDown(service.dispose);

      final connectFuture = _connect(service, owner);
      await connectorEntered.future;
      final clearFuture = service.clearOwner(owner: owner);
      lateClient.complete(client);

      await expectLater(connectFuture, throwsA(isA<StateError>()));
      await clearFuture;
      expect(service.status(owner: owner), isNull);
      verify(client.close).called(1);
    });

    test('clearOwner fences late authentication', () async {
      final authenticationRequested = Completer<void>();
      final authenticated = Completer<void>();
      final client = _MockSshClient();
      _stubClient(client, authenticated: authenticated.future);
      when(() => client.authenticated).thenAnswer((_) {
        authenticationRequested.complete();
        return authenticated.future;
      });
      final service = SshService(
        connector: _ClientQueueConnector([client]).call,
      );
      addTearDown(service.dispose);

      final connectFuture = _connect(service, owner);
      await authenticationRequested.future;
      final clearFuture = service.clearOwner(owner: owner);
      authenticated.complete();

      await expectLater(connectFuture, throwsA(isA<StateError>()));
      await clearFuture;
      expect(service.isConnected(owner: owner), isFalse);
      verify(client.close).called(1);
    });

    test('dispose fences pending work and is idempotent', () async {
      final connected = _MockSshClient();
      final late = _MockSshClient();
      _stubClient(connected);
      _stubClient(late);
      final pendingEntered = Completer<void>();
      final pendingClient = Completer<SSHClient>();
      var connectCount = 0;
      final service = SshService(
        connector:
            ({
              required host,
              required port,
              required username,
              required credential,
              required timeout,
            }) {
              connectCount += 1;
              if (connectCount == 1) return Future.value(connected);
              pendingEntered.complete();
              return pendingClient.future;
            },
      );
      final peer = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: owner.interactionGeneration,
      );
      await _connect(service, owner);
      final pendingConnect = _connect(service, peer);
      await pendingEntered.future;

      final firstDispose = service.dispose();
      final secondDispose = service.dispose();
      pendingClient.complete(late);

      await firstDispose;
      await secondDispose;
      await expectLater(pendingConnect, throwsA(isA<StateError>()));
      verify(connected.close).called(1);
      verify(late.close).called(1);
      await expectLater(_connect(service, owner), throwsA(isA<StateError>()));
    });

    test('disconnect clears state even when client cleanup fails', () async {
      final client = _MockSshClient();
      _stubClient(client);
      when(client.close).thenThrow(StateError('close failed'));
      final service = SshService(
        connector: _ClientQueueConnector([client]).call,
      );
      addTearDown(service.dispose);
      await _connect(service, owner);

      await service.disconnect(owner: owner);

      expect(service.status(owner: owner), isNull);
      verify(client.close).called(1);
    });

    test('clearOwner tombstones the exact owner without a session', () async {
      final service = SshService(
        connector: _ClientQueueConnector(const []).call,
      );
      addTearDown(service.dispose);

      await service.clearOwner(owner: owner);

      expect(service.isConnected(owner: owner), isFalse);
      await expectLater(
        _connect(service, owner),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'SSH session owner has been retired.',
          ),
        ),
      );
    });
  });

  group('SshService connection failures', () {
    late ChatTurnOwner owner;

    setUp(() {
      owner = ChatTurnOwner(
        conversationId: 'conversation-errors',
        interactionGeneration: 1,
      );
    });

    test('normalizes socket failures', () async {
      final service = SshService(
        connector:
            ({
              required host,
              required port,
              required username,
              required credential,
              required timeout,
            }) async => throw const SocketException('refused'),
      );

      await expectLater(
        _connect(service, owner),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('SSH connection failed: refused'),
          ),
        ),
      );
    });

    test('normalizes authentication failures and aborts', () async {
      for (final error in [
        SSHAuthFailError('denied'),
        SSHAuthAbortError('aborted'),
      ]) {
        final client = _MockSshClient();
        _stubClient(client);
        when(
          () => client.authenticated,
        ).thenAnswer((_) => Future<void>.error(error));
        final service = SshService(
          connector: _ClientQueueConnector([client]).call,
        );

        await expectLater(
          _connect(service, owner),
          throwsA(
            isA<Exception>().having(
              (exception) => exception.toString(),
              'message',
              contains(
                // A rejection names the target and the method offered, so
                // the next attempt can change something.
                error is SSHAuthFailError
                    ? 'SSH auth failed: tester@ssh.example:22, password auth'
                    : 'SSH authentication aborted',
              ),
            ),
          ),
        );
        expect(service.status(owner: owner), isNull);
        verify(client.close).called(1);
        await service.dispose();
      }
    });

    test('normalizes authentication timeouts', () async {
      final client = _MockSshClient();
      _stubClient(client, authenticated: Completer<void>().future);
      final service = SshService(
        connector: _ClientQueueConnector([client]).call,
      );

      await expectLater(
        _connect(service, owner, timeout: Duration.zero),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('SSH connect timed out after 0s'),
          ),
        ),
      );
      verify(client.close).called(1);
      await service.dispose();
    });

    test('preserves unexpected connector failures', () async {
      final service = SshService(
        connector:
            ({
              required host,
              required port,
              required username,
              required credential,
              required timeout,
            }) async => throw StateError('unexpected'),
      );

      await expectLater(
        _connect(service, owner),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'unexpected',
          ),
        ),
      );
      expect(service.status(owner: owner), isNull);
    });
  });

  test('provider owns global service disposal', () {
    final container = ProviderContainer();
    final first = container.read(sshServiceProvider);
    final second = container.read(sshServiceProvider);

    expect(identical(first, second), isTrue);

    container.dispose();
  });
}

Future<void> _connect(
  SshService service,
  ChatTurnOwner owner, {
  String host = 'ssh.example',
  Duration timeout = const Duration(seconds: 1),
}) {
  return service.connect(
    owner: owner,
    host: host,
    port: 22,
    username: 'tester',
    credential: const SshPasswordCredential('secret'),
    timeout: timeout,
  );
}

void _stubClient(
  _MockSshClient client, {
  Future<void>? authenticated,
  Future<void>? done,
}) {
  when(
    () => client.authenticated,
  ).thenAnswer((_) => authenticated ?? Future<void>.value());
  when(() => client.done).thenAnswer((_) => done ?? Future<void>.value());
  // dartssh2 3.0.0 changed SSHClient.close() from void to Future<void> so the
  // caller can await socket and channel teardown.
  when(client.close).thenAnswer((_) async {});
}

final class _ClientQueueConnector {
  _ClientQueueConnector(Iterable<SSHClient> clients)
    : _clients = Queue<SSHClient>.of(clients);

  final Queue<SSHClient> _clients;

  Future<SSHClient> call({
    required String host,
    required int port,
    required String username,
    required SshAuthCredential credential,
    required Duration timeout,
  }) async {
    return _clients.removeFirst();
  }
}

final class _MockSshClient extends Mock implements SSHClient {}

final class _MockSshSession extends Mock implements SSHSession {}
