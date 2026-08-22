import 'package:caverno/features/remote_coding/domain/remote_coding_resource_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = RemoteCodingResourcePolicy(
    maxConnections: 4,
    maxConnectionsPerAddress: 2,
  );

  test('allows a connection below both occupancy limits', () {
    expect(
      policy.evaluateConnection(
        activeConnections: 2,
        activeConnectionsForAddress: 1,
      ),
      RemoteCodingConnectionAdmission.allowed,
    );
  });

  test('rejects a connection when the total limit is reached', () {
    expect(
      policy.evaluateConnection(
        activeConnections: 4,
        activeConnectionsForAddress: 1,
      ),
      RemoteCodingConnectionAdmission.totalLimitReached,
    );
  });

  test('rejects a connection when the peer limit is reached', () {
    expect(
      policy.evaluateConnection(
        activeConnections: 2,
        activeConnectionsForAddress: 2,
      ),
      RemoteCodingConnectionAdmission.peerLimitReached,
    );
  });

  test('measures exact UTF-8 bytes for inbound text frames', () {
    const bytePolicy = RemoteCodingResourcePolicy(maxInboundFrameBytes: 4);

    expect(bytePolicy.acceptsInboundFrame('abcd'), isTrue);
    expect(bytePolicy.acceptsInboundFrame('abcde'), isFalse);
    expect(bytePolicy.acceptsInboundFrame('éé'), isTrue);
    expect(bytePolicy.acceptsInboundFrame('ééé'), isFalse);
  });

  test('bounds inbound binary frame bytes', () {
    const bytePolicy = RemoteCodingResourcePolicy(maxInboundFrameBytes: 4);

    expect(bytePolicy.acceptsInboundFrame(<int>[0, 1, 2, 3]), isTrue);
    expect(bytePolicy.acceptsInboundFrame(<int>[0, 1, 2, 3, 4]), isFalse);
  });

  test('sliding-window limiter recovers only after the window', () {
    var now = DateTime.utc(2026, 8, 22, 12);
    final limiter = RemoteCodingMessageRateLimiter(
      maxMessages: 2,
      window: const Duration(seconds: 10),
      clock: () => now,
    );

    expect(limiter.tryAcquire(), isTrue);
    expect(limiter.tryAcquire(), isTrue);
    expect(limiter.tryAcquire(), isFalse);

    now = now.add(const Duration(seconds: 9));
    expect(limiter.tryAcquire(), isFalse);

    now = now.add(const Duration(seconds: 1));
    expect(limiter.tryAcquire(), isTrue);
  });

  test('creates separate unauthenticated and authenticated budgets', () {
    const ratePolicy = RemoteCodingResourcePolicy(
      maxUnauthenticatedMessagesPerWindow: 1,
      maxAuthenticatedMessagesPerWindow: 2,
    );
    final unauthenticated = ratePolicy
        .createUnauthenticatedMessageRateLimiter();
    final authenticated = ratePolicy.createAuthenticatedMessageRateLimiter();

    expect(unauthenticated.tryAcquire(), isTrue);
    expect(unauthenticated.tryAcquire(), isFalse);
    expect(authenticated.tryAcquire(), isTrue);
    expect(authenticated.tryAcquire(), isTrue);
    expect(authenticated.tryAcquire(), isFalse);
  });
}
