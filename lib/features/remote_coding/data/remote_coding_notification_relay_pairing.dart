import 'dart:convert';

import 'package:crypto/crypto.dart';

final class RemoteCodingNotificationRelayPairingPayload {
  const RemoteCodingNotificationRelayPairingPayload({
    required this.challengeId,
    required this.challengeSecret,
    required this.targetDeviceId,
    required this.expiresAt,
  });

  static const kind = 'caverno_remote_coding_relay_v2';

  final String challengeId;
  final String challengeSecret;
  final String targetDeviceId;
  final DateTime expiresAt;

  String get challengeDigest =>
      sha256.convert(utf8.encode(challengeSecret)).toString();

  String toQrData() => jsonEncode(<String, dynamic>{
    'kind': kind,
    'challengeId': challengeId,
    'challengeSecret': challengeSecret,
    'targetDeviceId': targetDeviceId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  });

  factory RemoteCodingNotificationRelayPairingPayload.fromQrData(String value) {
    final decoded = jsonDecode(value.trim());
    if (decoded is! Map<String, dynamic> || decoded['kind'] != kind) {
      throw const FormatException(
        'QR code is not a Caverno notification relay code.',
      );
    }
    const allowedKeys = <String>{
      'kind',
      'challengeId',
      'challengeSecret',
      'targetDeviceId',
      'expiresAt',
    };
    if (decoded.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException(
        'Notification relay code contains unsupported fields.',
      );
    }
    final challengeId = (decoded['challengeId'] as String?)?.trim() ?? '';
    final challengeSecret =
        (decoded['challengeSecret'] as String?)?.trim() ?? '';
    final targetDeviceId = (decoded['targetDeviceId'] as String?)?.trim() ?? '';
    final expiresAt = DateTime.tryParse(
      (decoded['expiresAt'] as String?) ?? '',
    );
    if (!_isIdentifier(challengeId) || !_isIdentifier(targetDeviceId)) {
      throw const FormatException(
        'Notification relay code contains an invalid identifier.',
      );
    }
    if (!_hasMinimumSecretEntropy(challengeSecret)) {
      throw const FormatException(
        'Notification relay challenge secret is invalid.',
      );
    }
    if (expiresAt == null) {
      throw const FormatException(
        'Notification relay code has an invalid expiry.',
      );
    }
    return RemoteCodingNotificationRelayPairingPayload(
      challengeId: challengeId,
      challengeSecret: challengeSecret,
      targetDeviceId: targetDeviceId,
      expiresAt: expiresAt.toUtc(),
    );
  }

  static bool _isIdentifier(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(value);
  }

  static bool _hasMinimumSecretEntropy(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      return false;
    }
    try {
      final padding = '=' * ((4 - value.length % 4) % 4);
      return base64Url.decode('$value$padding').length >= 32;
    } on FormatException {
      return false;
    }
  }
}

enum RemoteCodingRelayPairingConsumeStatus {
  accepted,
  missing,
  expired,
  wrongDevice,
}

final class RemoteCodingRelayPairingConsumeResult {
  const RemoteCodingRelayPairingConsumeResult._(this.status, this.payload);

  const RemoteCodingRelayPairingConsumeResult.accepted(
    RemoteCodingNotificationRelayPairingPayload payload,
  ) : this._(RemoteCodingRelayPairingConsumeStatus.accepted, payload);

  const RemoteCodingRelayPairingConsumeResult.rejected(
    RemoteCodingRelayPairingConsumeStatus status,
  ) : this._(status, null);

  final RemoteCodingRelayPairingConsumeStatus status;
  final RemoteCodingNotificationRelayPairingPayload? payload;

  bool get isAccepted =>
      status == RemoteCodingRelayPairingConsumeStatus.accepted;
}

final class RemoteCodingNotificationRelayPairingRegistry {
  final Map<String, RemoteCodingNotificationRelayPairingPayload> _challenges =
      <String, RemoteCodingNotificationRelayPairingPayload>{};

  void add(RemoteCodingNotificationRelayPairingPayload payload) {
    _challenges[payload.challengeId] = payload;
  }

  void remove(String challengeId) => _challenges.remove(challengeId);

  void clear() => _challenges.clear();

  bool contains(String challengeId) => _challenges.containsKey(challengeId);

  RemoteCodingRelayPairingConsumeResult consume({
    required String challengeId,
    required String authenticatedDeviceId,
    DateTime? now,
  }) {
    final challenge = _challenges.remove(challengeId);
    if (challenge == null) {
      return const RemoteCodingRelayPairingConsumeResult.rejected(
        RemoteCodingRelayPairingConsumeStatus.missing,
      );
    }
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    if (!challenge.expiresAt.toUtc().isAfter(effectiveNow)) {
      return const RemoteCodingRelayPairingConsumeResult.rejected(
        RemoteCodingRelayPairingConsumeStatus.expired,
      );
    }
    if (challenge.targetDeviceId != authenticatedDeviceId) {
      return const RemoteCodingRelayPairingConsumeResult.rejected(
        RemoteCodingRelayPairingConsumeStatus.wrongDevice,
      );
    }
    return RemoteCodingRelayPairingConsumeResult.accepted(challenge);
  }

  void purgeExpired({DateTime? now}) {
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    _challenges.removeWhere(
      (_, challenge) => !challenge.expiresAt.toUtc().isAfter(effectiveNow),
    );
  }
}

final class RemoteCodingRelayDelegationReadyMessage {
  const RemoteCodingRelayDelegationReadyMessage({
    required this.challengeId,
    required this.delegationId,
    required this.expiresAt,
  });

  final String challengeId;
  final String delegationId;
  final DateTime expiresAt;

  Map<String, dynamic> toPayload() => <String, dynamic>{
    'challengeId': challengeId,
    'delegationId': delegationId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayDelegationReadyMessage.fromPayload(
    Map<String, dynamic> payload,
  ) {
    const allowedKeys = <String>{'challengeId', 'delegationId', 'expiresAt'};
    if (payload.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException(
        'Relay delegation response contains unsupported fields.',
      );
    }
    final challengeId = (payload['challengeId'] as String?)?.trim() ?? '';
    final delegationId = (payload['delegationId'] as String?)?.trim() ?? '';
    final expiresAt = DateTime.tryParse(
      (payload['expiresAt'] as String?) ?? '',
    );
    if (!RemoteCodingNotificationRelayPairingPayload._isIdentifier(
          challengeId,
        ) ||
        !RemoteCodingNotificationRelayPairingPayload._isIdentifier(
          delegationId,
        ) ||
        expiresAt == null) {
      throw const FormatException('Relay delegation response is invalid.');
    }
    return RemoteCodingRelayDelegationReadyMessage(
      challengeId: challengeId,
      delegationId: delegationId,
      expiresAt: expiresAt.toUtc(),
    );
  }
}
