import 'dart:convert';

enum RemoteCodingConnectionAdmission {
  allowed,
  totalLimitReached,
  peerLimitReached,
}

/// Bounds Remote Coding socket occupancy and inbound message processing.
class RemoteCodingResourcePolicy {
  static const String frameTooLargeCode = 'frame_too_large';
  static const String messageRateExceededCode = 'message_rate_exceeded';

  const RemoteCodingResourcePolicy({
    this.maxConnections = 16,
    this.maxConnectionsPerAddress = 4,
    this.authenticationDeadline = const Duration(seconds: 10),
    this.maxInboundFrameBytes = 256 * 1024,
    this.maxUnauthenticatedMessagesPerWindow = 8,
    this.maxAuthenticatedMessagesPerWindow = 60,
    this.messageRateWindow = const Duration(seconds: 10),
  }) : assert(maxConnections > 0),
       assert(maxConnectionsPerAddress > 0),
       assert(maxConnectionsPerAddress <= maxConnections),
       assert(maxInboundFrameBytes > 0),
       assert(maxUnauthenticatedMessagesPerWindow > 0),
       assert(maxAuthenticatedMessagesPerWindow > 0);

  final int maxConnections;
  final int maxConnectionsPerAddress;
  final Duration authenticationDeadline;
  final int maxInboundFrameBytes;
  final int maxUnauthenticatedMessagesPerWindow;
  final int maxAuthenticatedMessagesPerWindow;
  final Duration messageRateWindow;

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

  bool acceptsInboundFrame(Object? frame) {
    if (frame is String) {
      if (frame.length > maxInboundFrameBytes) {
        return false;
      }
      return utf8.encode(frame).length <= maxInboundFrameBytes;
    }
    if (frame is List<int>) {
      return frame.length <= maxInboundFrameBytes;
    }
    return true;
  }

  RemoteCodingMessageRateLimiter createUnauthenticatedMessageRateLimiter({
    DateTime Function()? clock,
  }) {
    return RemoteCodingMessageRateLimiter(
      maxMessages: maxUnauthenticatedMessagesPerWindow,
      window: messageRateWindow,
      clock: clock,
    );
  }

  RemoteCodingMessageRateLimiter createAuthenticatedMessageRateLimiter({
    DateTime Function()? clock,
  }) {
    return RemoteCodingMessageRateLimiter(
      maxMessages: maxAuthenticatedMessagesPerWindow,
      window: messageRateWindow,
      clock: clock,
    );
  }
}

/// Enforces a per-connection sliding-window message budget.
class RemoteCodingMessageRateLimiter {
  RemoteCodingMessageRateLimiter({
    required this.maxMessages,
    required this.window,
    DateTime Function()? clock,
  }) : assert(maxMessages > 0),
       assert(window > Duration.zero),
       _clock = clock ?? DateTime.now;

  final int maxMessages;
  final Duration window;
  final DateTime Function() _clock;
  final List<DateTime> _acceptedAt = <DateTime>[];

  bool tryAcquire() {
    final now = _clock().toUtc();
    final cutoff = now.subtract(window);
    _acceptedAt.removeWhere((acceptedAt) => !acceptedAt.isAfter(cutoff));
    if (_acceptedAt.length >= maxMessages) {
      return false;
    }
    _acceptedAt.add(now);
    return true;
  }
}
