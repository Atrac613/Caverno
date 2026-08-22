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
}
