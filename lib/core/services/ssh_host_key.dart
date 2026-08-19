import 'dart:convert';
import 'dart:typed_data';

/// Host identity presented during an SSH handshake, before authentication.
final class SshKnownHostIdentity {
  const SshKnownHostIdentity({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
  });

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;

  String get recordKey => sshKnownHostRecordKey(host: host, port: port);

  bool matches(SshKnownHostIdentity other) {
    return recordKey == other.recordKey &&
        keyType == other.keyType &&
        fingerprint == other.fingerprint;
  }

  Map<String, Object> toJson() => {
    'host': host,
    'port': port,
    'keyType': keyType,
    'fingerprint': fingerprint,
  };

  static SshKnownHostIdentity? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final host = json['host'] as String?;
    final port = json['port'] as num?;
    final keyType = json['keyType'] as String?;
    final fingerprint = json['fingerprint'] as String?;
    if (host == null ||
        port == null ||
        keyType == null ||
        fingerprint == null) {
      return null;
    }
    return SshKnownHostIdentity(
      host: normalizeSshKnownHost(host),
      port: port.toInt(),
      keyType: keyType.trim(),
      fingerprint: normalizeSshHostKeyFingerprint(fingerprint),
    );
  }
}

enum SshHostKeyVerdict { match, unknown, mismatch, invalid }

final class SshHostKeyDecision {
  const SshHostKeyDecision({
    required this.verdict,
    required this.presented,
    this.stored,
  });

  final SshHostKeyVerdict verdict;
  final SshKnownHostIdentity presented;
  final SshKnownHostIdentity? stored;

  bool get isMatch => verdict == SshHostKeyVerdict.match;
}

sealed class SshHostKeyException implements Exception {
  const SshHostKeyException(this.decision);

  final SshHostKeyDecision decision;

  SshKnownHostIdentity get presented => decision.presented;
}

final class SshUnknownHostKeyException extends SshHostKeyException {
  const SshUnknownHostKeyException(super.decision);

  @override
  String toString() {
    return 'Unknown SSH host key for ${presented.host}:${presented.port} '
        '(${presented.keyType} ${presented.fingerprint}). '
        'Trust the fingerprint before connecting.';
  }
}

final class SshHostKeyMismatchException extends SshHostKeyException {
  const SshHostKeyMismatchException(super.decision);

  @override
  String toString() {
    final stored = decision.stored;
    return 'SSH host key for ${presented.host}:${presented.port} does not '
        'match the stored identity '
        '(stored ${stored?.keyType} ${stored?.fingerprint}; '
        'presented ${presented.keyType} ${presented.fingerprint}). '
        'Replace the stored key only if this change is expected.';
  }
}

final class SshHostKeyRejectedException extends SshHostKeyException {
  const SshHostKeyRejectedException(super.decision);

  @override
  String toString() {
    return 'User rejected the SSH host key for '
        '${presented.host}:${presented.port} '
        '(${presented.keyType} ${presented.fingerprint}).';
  }
}

String normalizeSshKnownHost(String host) {
  final trimmed = host.trim().toLowerCase();
  if (trimmed.length >= 2 &&
      trimmed.startsWith('[') &&
      trimmed.endsWith(']')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String normalizeSshHostKeyFingerprint(String fingerprint) {
  final trimmed = fingerprint.trim();
  if (trimmed.toUpperCase().startsWith('SHA256:')) {
    return 'SHA256:${trimmed.substring(7)}';
  }
  return trimmed.isEmpty ? trimmed : 'SHA256:$trimmed';
}

String sshKnownHostRecordKey({required String host, required int port}) {
  return '${normalizeSshKnownHost(host)}:$port';
}

String decodeSshHostKeyFingerprint(Uint8List bytes) {
  return normalizeSshHostKeyFingerprint(utf8.decode(bytes));
}
