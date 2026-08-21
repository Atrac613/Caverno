import 'package:caverno/features/remote_coding/data/remote_coding_session_challenge_registry.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_session_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const connectionId = 'connection-a';
  const otherConnectionId = 'connection-b';
  const pin = 'pin-1';
  const token = 'device-token';

  String proofFor(RemoteCodingSessionChallenge challenge) {
    return RemoteCodingSessionPolicy.proof(
      credential: token,
      challengeId: challenge.challengeId,
      nonce: challenge.nonce,
      certificatePin: pin,
    );
  }

  test('consumes a matching proof once on the issuing connection', () {
    final registry = RemoteCodingSessionChallengeRegistry();
    final now = DateTime.utc(2026, 8, 21, 10);
    final challenge = registry.issue(
      connectionId: connectionId,
      certificatePin: pin,
      now: now,
      challengeId: 'challenge-1',
      nonce: 'nonce-1',
    );

    final accepted = registry.consume(
      challengeId: challenge.challengeId,
      connectionId: connectionId,
      credential: token,
      proof: proofFor(challenge),
      now: now,
    );
    expect(accepted.isAccepted, isTrue);

    final replay = registry.consume(
      challengeId: challenge.challengeId,
      connectionId: connectionId,
      credential: token,
      proof: proofFor(challenge),
      now: now,
    );
    expect(
      replay.status,
      RemoteCodingSessionChallengeConsumeStatus.missing,
    );
  });

  test('does not burn a challenge presented on the wrong connection', () {
    final registry = RemoteCodingSessionChallengeRegistry();
    final now = DateTime.utc(2026, 8, 21, 10);
    final challenge = registry.issue(
      connectionId: connectionId,
      certificatePin: pin,
      now: now,
      challengeId: 'challenge-1',
      nonce: 'nonce-1',
    );

    final foreign = registry.consume(
      challengeId: challenge.challengeId,
      connectionId: otherConnectionId,
      credential: token,
      proof: proofFor(challenge),
      now: now,
    );
    expect(
      foreign.status,
      RemoteCodingSessionChallengeConsumeStatus.wrongConnection,
    );

    final owner = registry.consume(
      challengeId: challenge.challengeId,
      connectionId: connectionId,
      credential: token,
      proof: proofFor(challenge),
      now: now,
    );
    expect(owner.isAccepted, isTrue);
  });

  test('rejects an expired challenge', () {
    final registry = RemoteCodingSessionChallengeRegistry(
      lifetime: const Duration(seconds: 30),
    );
    final now = DateTime.utc(2026, 8, 21, 10);
    final challenge = registry.issue(
      connectionId: connectionId,
      certificatePin: pin,
      now: now,
      challengeId: 'challenge-1',
      nonce: 'nonce-1',
    );

    final expired = registry.consume(
      challengeId: challenge.challengeId,
      connectionId: connectionId,
      credential: token,
      proof: proofFor(challenge),
      now: now.add(const Duration(seconds: 31)),
    );
    expect(
      expired.status,
      RemoteCodingSessionChallengeConsumeStatus.expired,
    );
  });
}
