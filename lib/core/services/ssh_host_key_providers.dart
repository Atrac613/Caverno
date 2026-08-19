import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ssh_host_key_verifier.dart';
import 'ssh_known_hosts_store.dart';
import 'ssh_service.dart';

final sshKnownHostsStoreProvider = Provider<SshKnownHostsStore>(
  (ref) => SecureSshKnownHostsStore(),
);

final sshHostKeyVerifierProvider = Provider<SshHostKeyVerifier>(
  (ref) => SshHostKeyVerifier(ref.watch(sshKnownHostsStoreProvider)),
);

final sshServiceProvider = Provider<SshService>((ref) {
  final verifier = ref.watch(sshHostKeyVerifierProvider);
  final service = SshService(
    connector:
        ({
          required host,
          required port,
          required username,
          required credential,
          required timeout,
        }) {
          return SshClientConnector.connect(
            host: host,
            port: port,
            username: username,
            credential: credential,
            timeout: timeout,
            verifier: verifier,
          );
        },
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
