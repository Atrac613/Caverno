import 'dart:convert';
import 'dart:typed_data';

import 'package:caverno/core/services/ssh_host_key.dart';
import 'package:caverno/core/services/ssh_host_key_verifier.dart';
import 'package:caverno/core/services/ssh_known_hosts_store.dart';
import 'package:test/test.dart';

void main() {
  const presented = SshKnownHostIdentity(
    host: 'ssh.example',
    port: 22,
    keyType: 'ssh-ed25519',
    fingerprint: 'SHA256:abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
  );

  test('matches a stored host:port identity', () async {
    final store = MemorySshKnownHostsStore({presented.recordKey: presented});
    final decision = await SshHostKeyVerifier(store).evaluate(
      host: 'SSH.EXAMPLE',
      port: 22,
      keyType: 'ssh-ed25519',
      fingerprint: presented.fingerprint,
    );

    expect(decision.verdict, SshHostKeyVerdict.match);
  });

  test('reports an unknown host before any record exists', () async {
    final decision = await SshHostKeyVerifier(
      MemorySshKnownHostsStore(),
    ).evaluate(
      host: presented.host,
      port: presented.port,
      keyType: presented.keyType,
      fingerprint: presented.fingerprint,
    );

    expect(decision.verdict, SshHostKeyVerdict.unknown);
    expect(decision.stored, isNull);
  });

  test('reports a mismatch when type or fingerprint differ', () async {
    final store = MemorySshKnownHostsStore({presented.recordKey: presented});
    final decision = await SshHostKeyVerifier(store).evaluate(
      host: presented.host,
      port: presented.port,
      keyType: presented.keyType,
      fingerprint: 'SHA256:other-fingerprint-value-000000000000000000000',
    );

    expect(decision.verdict, SshHostKeyVerdict.mismatch);
    expect(decision.stored, presented);
  });

  test('treats a missing store as unknown rather than trusted', () async {
    final decision = await const SshHostKeyVerifier.failClosed().evaluate(
      host: presented.host,
      port: presented.port,
      keyType: presented.keyType,
      fingerprint: presented.fingerprint,
    );

    expect(decision.verdict, SshHostKeyVerdict.unknown);
  });

  test('rejects empty fingerprints as invalid', () async {
    final decision = await SshHostKeyVerifier(
      MemorySshKnownHostsStore(),
    ).evaluate(
      host: presented.host,
      port: presented.port,
      keyType: presented.keyType,
      fingerprint: '',
    );

    expect(decision.verdict, SshHostKeyVerdict.invalid);
  });

  test('handshake accepts only a match and maps other verdicts', () async {
    final store = MemorySshKnownHostsStore();
    final handshake = SshHostKeyHandshake(
      verifier: SshHostKeyVerifier(store),
      host: presented.host,
      port: presented.port,
    );
    final fingerprint = Uint8List.fromList(utf8.encode(presented.fingerprint));

    expect(await handshake.verify(presented.keyType, fingerprint), isFalse);
    expect(
      () => handshake.rethrowIfRejected(StateError('wrapped')),
      throwsA(isA<SshUnknownHostKeyException>()),
    );

    await store.remember(presented);
    expect(await handshake.verify(presented.keyType, fingerprint), isTrue);
  });

  test('normalizes bracketed IPv6 hosts onto one record key', () {
    expect(
      sshKnownHostRecordKey(host: '[2001:db8::1]', port: 22),
      '2001:db8::1:22',
    );
  });
}
