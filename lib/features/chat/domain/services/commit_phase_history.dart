import '../entities/message.dart';

/// Selects only messages after the current owner-bound commit prompt.
abstract final class CommitPhaseHistory {
  static List<Message> from(List<Message> messages, String? id) {
    final start = messages.indexWhere((message) => message.id == id);
    if (id == null || start < 0) {
      throw StateError(
        'Current task phase input is unavailable for this owner.',
      );
    }
    return messages.sublist(start);
  }
}
