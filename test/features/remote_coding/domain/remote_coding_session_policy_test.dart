import 'package:caverno/features/remote_coding/domain/remote_coding_session_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proof matches only the same credential, challenge, and pin', () {
    const challengeId = 'challenge-1';
    const nonce = 'nonce-1';
    const pin = 'pin-1';
    const token = 'device-token';

    final proof = RemoteCodingSessionPolicy.proof(
      credential: token,
      challengeId: challengeId,
      nonce: nonce,
      certificatePin: pin,
    );

    expect(
      RemoteCodingSessionPolicy.proofMatches(
        credential: token,
        challengeId: challengeId,
        nonce: nonce,
        certificatePin: pin,
        proof: proof,
      ),
      isTrue,
    );
    expect(
      RemoteCodingSessionPolicy.proofMatches(
        credential: 'other-token',
        challengeId: challengeId,
        nonce: nonce,
        certificatePin: pin,
        proof: proof,
      ),
      isFalse,
    );
    expect(
      RemoteCodingSessionPolicy.proofMatches(
        credential: token,
        challengeId: challengeId,
        nonce: 'other-nonce',
        certificatePin: pin,
        proof: proof,
      ),
      isFalse,
    );
    expect(
      RemoteCodingSessionPolicy.proofMatches(
        credential: token,
        challengeId: challengeId,
        nonce: nonce,
        certificatePin: 'other-pin',
        proof: proof,
      ),
      isFalse,
    );
  });

  test('wire payload omits connection binding and round-trips ids', () {
    final challenge = RemoteCodingSessionChallenge(
      challengeId: 'challenge-1',
      nonce: 'nonce-1',
      connectionId: 'connection-1',
      certificatePin: 'pin-1',
      expiresAt: DateTime.utc(2026, 8, 21, 10),
    );

    final decoded = RemoteCodingSessionChallenge.fromPayload(
      challenge.toPayload(),
    );

    expect(decoded.challengeId, 'challenge-1');
    expect(decoded.nonce, 'nonce-1');
    expect(decoded.expiresAt, DateTime.utc(2026, 8, 21, 10));
    expect(decoded.toPayload().containsKey('connectionId'), isFalse);
    expect(decoded.toPayload().containsKey('certificatePin'), isFalse);
  });

  test('session auth payload is not the reusable device token', () {
    final session = RemoteCodingSessionAuthorization(
      sessionId: 'session-1',
      deviceId: 'device-1',
      connectionId: 'connection-1',
      issuedAt: DateTime.utc(2026, 8, 21, 10),
    );

    expect(session.toAuthPayload()['sessionId'], 'session-1');
    expect(session.toAuthPayload().containsKey('deviceToken'), isFalse);
  });
}
