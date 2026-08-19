import 'dart:typed_data';

import 'ssh_host_key.dart';
import 'ssh_known_hosts_store.dart';

/// Compares a presented SSH host key against the stored identity.
///
/// A missing store is fail-closed: every presented key is unknown and must not
/// authenticate.
final class SshHostKeyVerifier {
  const SshHostKeyVerifier(this._store);

  const SshHostKeyVerifier.failClosed() : _store = null;

  final SshKnownHostsStore? _store;

  Future<SshHostKeyDecision> evaluate({
    required String host,
    required int port,
    required String keyType,
    required String fingerprint,
  }) async {
    final presented = SshKnownHostIdentity(
      host: normalizeSshKnownHost(host),
      port: port,
      keyType: keyType.trim(),
      fingerprint: normalizeSshHostKeyFingerprint(fingerprint),
    );
    if (presented.host.isEmpty ||
        presented.port <= 0 ||
        presented.keyType.isEmpty ||
        presented.fingerprint.isEmpty ||
        presented.fingerprint == 'SHA256:') {
      return SshHostKeyDecision(
        verdict: SshHostKeyVerdict.invalid,
        presented: presented,
      );
    }
    final store = _store;
    if (store == null) {
      return SshHostKeyDecision(
        verdict: SshHostKeyVerdict.unknown,
        presented: presented,
      );
    }
    final stored = await store.lookup(host: presented.host, port: presented.port);
    if (stored == null) {
      return SshHostKeyDecision(
        verdict: SshHostKeyVerdict.unknown,
        presented: presented,
      );
    }
    if (stored.matches(presented)) {
      return SshHostKeyDecision(
        verdict: SshHostKeyVerdict.match,
        presented: presented,
        stored: stored,
      );
    }
    return SshHostKeyDecision(
      verdict: SshHostKeyVerdict.mismatch,
      presented: presented,
      stored: stored,
    );
  }
}

/// Adapts [SshHostKeyVerifier] onto dartssh2's `onVerifyHostKey` callback.
final class SshHostKeyHandshake {
  SshHostKeyHandshake({
    required this.verifier,
    required this.host,
    required this.port,
  });

  final SshHostKeyVerifier verifier;
  final String host;
  final int port;
  SshHostKeyDecision? decision;

  Future<bool> verify(String keyType, Uint8List fingerprintBytes) async {
    decision = await verifier.evaluate(
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: decodeSshHostKeyFingerprint(fingerprintBytes),
    );
    return decision?.isMatch ?? false;
  }

  void rethrowIfRejected(Object error) {
    final rejected = decision;
    if (rejected == null || rejected.isMatch) return;
    throw switch (rejected.verdict) {
      SshHostKeyVerdict.unknown => SshUnknownHostKeyException(rejected),
      SshHostKeyVerdict.mismatch => SshHostKeyMismatchException(rejected),
      SshHostKeyVerdict.invalid => SshUnknownHostKeyException(rejected),
      SshHostKeyVerdict.match => error,
    };
  }
}
