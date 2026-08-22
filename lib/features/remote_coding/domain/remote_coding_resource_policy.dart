enum RemoteCodingConnectionAdmission {
  allowed,
  totalLimitReached,
  peerLimitReached,
}

/// Bounds Remote Coding socket occupancy before message-level limits apply.
class RemoteCodingResourcePolicy {
  const RemoteCodingResourcePolicy({
    this.maxConnections = 16,
    this.maxConnectionsPerAddress = 4,
    this.authenticationDeadline = const Duration(seconds: 10),
  }) : assert(maxConnections > 0),
       assert(maxConnectionsPerAddress > 0),
       assert(maxConnectionsPerAddress <= maxConnections);

  final int maxConnections;
  final int maxConnectionsPerAddress;
  final Duration authenticationDeadline;

  RemoteCodingConnectionAdmission evaluateConnection({
    required int activeConnections,
    required int activeConnectionsForAddress,
  }) {
    if (activeConnections >= maxConnections) {
      return RemoteCodingConnectionAdmission.totalLimitReached;
    }
    if (activeConnectionsForAddress >= maxConnectionsPerAddress) {
      return RemoteCodingConnectionAdmission.peerLimitReached;
    }
    return RemoteCodingConnectionAdmission.allowed;
  }
}
