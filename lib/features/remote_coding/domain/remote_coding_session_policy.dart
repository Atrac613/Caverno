import '../data/remote_coding_security.dart';

/// Thrown when Remote Coding auth is missing a live channel-bound challenge.
class RemoteCodingAuthChallengeRequiredException implements Exception {
  const RemoteCodingAuthChallengeRequiredException();

  @override
  String toString() =>
      'Remote Coding requires a fresh channel-bound auth challenge before '
      'pairing secrets or device tokens can authenticate a session.';
}

/// Per-connection challenge used to bind session issuance to one WebSocket.
class RemoteCodingSessionChallenge {
  const RemoteCodingSessionChallenge({
    required this.challengeId,
    required this.nonce,
    required this.connectionId,
    required this.certificatePin,
    required this.expiresAt,
  });

  final String challengeId;
  final String nonce;
  final String connectionId;
  final String certificatePin;
  final DateTime expiresAt;

  Map<String, dynamic> toPayload() => {
    'challengeId': challengeId,
    'nonce': nonce,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingSessionChallenge.fromPayload(
    Map<String, dynamic> payload, {
    String connectionId = '',
    String certificatePin = '',
  }) {
    final challengeId = (payload['challengeId'] as String?)?.trim() ?? '';
    final nonce = (payload['nonce'] as String?)?.trim() ?? '';
    if (challengeId.isEmpty || nonce.isEmpty) {
      throw const FormatException(
        'Remote coding auth challenge is missing an id or nonce.',
      );
    }
    final expiresAt =
        DateTime.tryParse((payload['expiresAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return RemoteCodingSessionChallenge(
      challengeId: challengeId,
      nonce: nonce,
      connectionId: connectionId,
      certificatePin: certificatePin,
      expiresAt: expiresAt.toUtc(),
    );
  }
}

/// In-memory session that authorizes one authenticated Remote Coding socket.
class RemoteCodingSessionAuthorization {
  const RemoteCodingSessionAuthorization({
    required this.sessionId,
    required this.deviceId,
    required this.connectionId,
    required this.issuedAt,
  });

  final String sessionId;
  final String deviceId;
  final String connectionId;
  final DateTime issuedAt;

  Map<String, dynamic> toAuthPayload() => {
    'deviceId': deviceId,
    'sessionId': sessionId,
  };
}

/// Builds and checks HMAC proofs for Remote Coding session issuance.
abstract final class RemoteCodingSessionPolicy {
  static const Duration challengeLifetime = Duration(seconds: 30);
  static const String proofVersion = 'v1';
  static const String challengeRequiredCode = 'auth_challenge_required';
  static const String challengeRejectedCode = 'auth_challenge_rejected';

  static String canonicalMessage({
    required String challengeId,
    required String nonce,
    required String certificatePin,
  }) {
    return '$proofVersion|$challengeId|$nonce|$certificatePin';
  }

  static String proof({
    required String credential,
    required String challengeId,
    required String nonce,
    required String certificatePin,
  }) {
    return RemoteCodingSecurity.hmacSha256Hex(
      key: credential,
      message: canonicalMessage(
        challengeId: challengeId,
        nonce: nonce,
        certificatePin: certificatePin,
      ),
    );
  }

  static bool proofMatches({
    required String credential,
    required String challengeId,
    required String nonce,
    required String certificatePin,
    required String proof,
  }) {
    final expected = RemoteCodingSessionPolicy.proof(
      credential: credential,
      challengeId: challengeId,
      nonce: nonce,
      certificatePin: certificatePin,
    );
    return RemoteCodingSecurity.constantTimeEquals(expected, proof.trim());
  }
}
