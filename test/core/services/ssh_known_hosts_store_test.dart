import 'package:caverno/core/services/ssh_host_key.dart';
import 'package:caverno/core/services/ssh_known_hosts_store.dart';
import 'package:test/test.dart';

void main() {
  const first = SshKnownHostIdentity(
    host: 'ssh.example',
    port: 22,
    keyType: 'ssh-ed25519',
    fingerprint: 'SHA256:first-fingerprint',
  );
  const rotated = SshKnownHostIdentity(
    host: 'ssh.example',
    port: 22,
    keyType: 'ssh-ed25519',
    fingerprint: 'SHA256:rotated-fingerprint',
  );

  test('remembers and looks up a host by host and port', () async {
    final store = MemorySshKnownHostsStore();

    await store.remember(first);

    expect(
      await store.lookup(host: 'SSH.example', port: 22),
      first,
    );
  });

  test('replace overwrites the previous identity for the same host', () async {
    final store = MemorySshKnownHostsStore();
    await store.remember(first);
    await store.remember(rotated);

    expect(await store.lookup(host: first.host, port: first.port), rotated);
  });

  test('remove forgets a host so the next lookup is empty', () async {
    final store = MemorySshKnownHostsStore();
    await store.remember(first);
    await store.remove(host: first.host, port: first.port);

    expect(await store.lookup(host: first.host, port: first.port), isNull);
  });
}
