import '../domain/remote_coding_session_policy.dart';
import 'remote_coding_security.dart';

enum RemoteCodingSessionChallengeConsumeStatus {
  accepted,
  missing,
  expired,
  wrongConnection,
  invalidProof,
}

class RemoteCodingSessionChallengeConsumeResult {
  const RemoteCodingSessionChallengeConsumeResult._(this.status, this.challenge);

  const RemoteCodingSessionChallengeConsumeResult.accepted(
    RemoteCodingSessionChallenge challenge,
  ) : this._(RemoteCodingSessionChallengeConsumeStatus.accepted, challenge);

  const RemoteCodingSessionChallengeConsumeResult.rejected(
    RemoteCodingSessionChallengeConsumeStatus status,
  ) : this._(status, null);

  final RemoteCodingSessionChallengeConsumeStatus status;
  final RemoteCodingSessionChallenge? challenge;

  bool get isAccepted =>
      status == RemoteCodingSessionChallengeConsumeStatus.accepted;
}

/// Stores one-time auth challenges keyed by id and bound to a connection.
class RemoteCodingSessionChallengeRegistry {
  RemoteCodingSessionChallengeRegistry({
    this.lifetime = RemoteCodingSessionPolicy.challengeLifetime,
  });

  final Duration lifetime;
  final Map<String, RemoteCodingSessionChallenge> _challenges =
      <String, RemoteCodingSessionChallenge>{};

  bool get isEmpty => _challenges.isEmpty;
  int get length => _challenges.length;

  RemoteCodingSessionChallenge issue({
    required String connectionId,
    required String certificatePin,
    DateTime? now,
    String? challengeId,
    String? nonce,
  }) {
    final effectiveNow = now ?? DateTime.now().toUtc();
    purgeExpired(now: effectiveNow);
    final challenge = RemoteCodingSessionChallenge(
      challengeId: challengeId ?? RemoteCodingSecurity.randomToken(),
      nonce: nonce ?? RemoteCodingSecurity.randomToken(),
      connectionId: connectionId,
      certificatePin: certificatePin,
      expiresAt: effectiveNow.add(lifetime),
    );
    _challenges[challenge.challengeId] = challenge;
    return challenge;
  }

  RemoteCodingSessionChallengeConsumeResult consume({
    required String challengeId,
    required String connectionId,
    required String credential,
    required String proof,
    DateTime? now,
  }) {
    final normalizedId = challengeId.trim();
    final challenge = _challenges[normalizedId];
    if (challenge == null) {
      return const RemoteCodingSessionChallengeConsumeResult.rejected(
        RemoteCodingSessionChallengeConsumeStatus.missing,
      );
    }
    final effectiveNow = now ?? DateTime.now().toUtc();
    if (!challenge.expiresAt.isAfter(effectiveNow)) {
      _challenges.remove(normalizedId);
      return const RemoteCodingSessionChallengeConsumeResult.rejected(
        RemoteCodingSessionChallengeConsumeStatus.expired,
      );
    }
    if (challenge.connectionId != connectionId) {
      return const RemoteCodingSessionChallengeConsumeResult.rejected(
        RemoteCodingSessionChallengeConsumeStatus.wrongConnection,
      );
    }
    _challenges.remove(normalizedId);
    if (!RemoteCodingSessionPolicy.proofMatches(
      credential: credential,
      challengeId: challenge.challengeId,
      nonce: challenge.nonce,
      certificatePin: challenge.certificatePin,
      proof: proof,
    )) {
      return const RemoteCodingSessionChallengeConsumeResult.rejected(
        RemoteCodingSessionChallengeConsumeStatus.invalidProof,
      );
    }
    return RemoteCodingSessionChallengeConsumeResult.accepted(challenge);
  }

  void removeConnection(String connectionId) {
    _challenges.removeWhere(
      (_, challenge) => challenge.connectionId == connectionId,
    );
  }

  void clear() {
    _challenges.clear();
  }

  void purgeExpired({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now().toUtc();
    _challenges.removeWhere(
      (_, challenge) => !challenge.expiresAt.isAfter(effectiveNow),
    );
  }
}
