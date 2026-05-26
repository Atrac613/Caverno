import '../domain/remote_coding_models.dart';
import 'remote_coding_security.dart';

enum RemoteCodingPairingConsumeStatus {
  accepted,
  missing,
  expired,
  invalidSecret,
}

class RemoteCodingPairingConsumeResult {
  const RemoteCodingPairingConsumeResult._(this.status, this.payload);

  const RemoteCodingPairingConsumeResult.accepted(
    RemoteCodingPairingPayload payload,
  ) : this._(RemoteCodingPairingConsumeStatus.accepted, payload);

  const RemoteCodingPairingConsumeResult.rejected(
    RemoteCodingPairingConsumeStatus status,
  ) : this._(status, null);

  final RemoteCodingPairingConsumeStatus status;
  final RemoteCodingPairingPayload? payload;

  bool get isAccepted => status == RemoteCodingPairingConsumeStatus.accepted;
}

class RemoteCodingPairingRegistry {
  final Map<String, RemoteCodingPairingPayload> _tickets = {};

  bool get isEmpty => _tickets.isEmpty;
  int get length => _tickets.length;

  void add(RemoteCodingPairingPayload payload) {
    _tickets[payload.ticketId] = payload;
  }

  void clear() {
    _tickets.clear();
  }

  void remove(String ticketId) {
    _tickets.remove(ticketId);
  }

  bool contains(String ticketId) => _tickets.containsKey(ticketId);

  RemoteCodingPairingConsumeResult consume({
    required String ticketId,
    required String secret,
    DateTime? now,
  }) {
    final ticket = _tickets.remove(ticketId);
    if (ticket == null) {
      return const RemoteCodingPairingConsumeResult.rejected(
        RemoteCodingPairingConsumeStatus.missing,
      );
    }
    final effectiveNow = now ?? DateTime.now();
    if (!ticket.expiresAt.isAfter(effectiveNow)) {
      return const RemoteCodingPairingConsumeResult.rejected(
        RemoteCodingPairingConsumeStatus.expired,
      );
    }
    if (!RemoteCodingSecurity.constantTimeEquals(ticket.secret, secret)) {
      return const RemoteCodingPairingConsumeResult.rejected(
        RemoteCodingPairingConsumeStatus.invalidSecret,
      );
    }
    return RemoteCodingPairingConsumeResult.accepted(ticket);
  }

  void purgeExpired({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    _tickets.removeWhere(
      (_, ticket) => !ticket.expiresAt.isAfter(effectiveNow),
    );
  }
}
