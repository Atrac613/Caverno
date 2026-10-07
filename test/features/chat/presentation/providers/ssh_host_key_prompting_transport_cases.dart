part of 'chat_presentation_providers_tiny_test.dart';

final _ownerSshHostKeyPromptingTransport = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 1,
);

const _target = SshCredentialKey(
  host: 'ssh.example',
  port: 22,
  username: 'tester',
);

const _credential = SshPasswordCredential('secret');

const _presented = SshKnownHostIdentity(
  host: 'ssh.example',
  port: 22,
  keyType: 'ssh-ed25519',
  fingerprint: 'SHA256:presented-fingerprint',
);

void _runSshHostKeyPromptingTransport() {
  test('trusts an unknown host, persists it, and retries once', () async {
    final inner = _FakeTransport()
      ..failNext = SshUnknownHostKeyException(
        const SshHostKeyDecision(
          verdict: SshHostKeyVerdict.unknown,
          presented: _presented,
        ),
      );
    final store = MemorySshKnownHostsStore();
    final prompts = _FakePrompter(accept: true);
    final transport = SshHostKeyPromptingTransport(
      inner: inner,
      store: store,
      prompts: prompts,
    );

    await transport.connect(
      _ownerSshHostKeyPromptingTransport,
      _target,
      _credential,
    );

    expect(inner.connectCount, 2);
    expect(
      await store.lookup(host: _presented.host, port: _presented.port),
      _presented,
    );
    expect(prompts.asked, 1);
  });

  test(
    'does not persist or retry when the user rejects an unknown host',
    () async {
      final inner = _FakeTransport()
        ..failNext = SshUnknownHostKeyException(
          const SshHostKeyDecision(
            verdict: SshHostKeyVerdict.unknown,
            presented: _presented,
          ),
        );
      final store = MemorySshKnownHostsStore();
      final transport = SshHostKeyPromptingTransport(
        inner: inner,
        store: store,
        prompts: _FakePrompter(accept: false),
      );

      await expectLater(
        transport.connect(
          _ownerSshHostKeyPromptingTransport,
          _target,
          _credential,
        ),
        throwsA(isA<SshHostKeyRejectedException>()),
      );
      expect(inner.connectCount, 1);
      expect(
        await store.lookup(host: _presented.host, port: _presented.port),
        isNull,
      );
    },
  );

  test('replaces a mismatched host only after confirmation', () async {
    const stored = SshKnownHostIdentity(
      host: 'ssh.example',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: 'SHA256:stored-fingerprint',
    );
    final inner = _FakeTransport()
      ..failNext = SshHostKeyMismatchException(
        const SshHostKeyDecision(
          verdict: SshHostKeyVerdict.mismatch,
          presented: _presented,
          stored: stored,
        ),
      );
    final store = MemorySshKnownHostsStore({stored.recordKey: stored});
    final transport = SshHostKeyPromptingTransport(
      inner: inner,
      store: store,
      prompts: _FakePrompter(accept: true),
    );

    await transport.connect(
      _ownerSshHostKeyPromptingTransport,
      _target,
      _credential,
    );

    expect(inner.connectCount, 2);
    expect(
      await store.lookup(host: stored.host, port: stored.port),
      _presented,
    );
  });
}

final class _FakePrompter implements SshHostKeyPrompter {
  _FakePrompter({required this.accept});

  final bool accept;
  int asked = 0;

  @override
  Future<bool> requestDecision(SshHostKeyDecision decision) async {
    asked += 1;
    return accept;
  }
}

final class _FakeTransport implements ChatSshTransport {
  Object? failNext;
  int connectCount = 0;

  @override
  ChatSshSession? activeSession(ChatTurnOwner owner) => null;

  @override
  Future<void> connect(
    ChatTurnOwner owner,
    SshCredentialKey target,
    SshAuthCredential credential,
  ) async {
    connectCount += 1;
    final pending = failNext;
    failNext = null;
    if (pending != null) throw pending;
  }

  @override
  Future<String> execute(
    ChatTurnOwner owner,
    String command,
    String expectedFingerprint,
  ) async => '';

  @override
  Future<bool> disconnectIfFingerprint(
    ChatTurnOwner owner,
    String expectedFingerprint,
  ) async => false;

  @override
  Future<void> clearOwner(ChatTurnOwner owner) async {}
}
