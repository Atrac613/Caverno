import '../entities/chat_turn_owner.dart';

/// Exact identity for one Computer Use operation and helper session.
final class ComputerUseOperationIdentity {
  ComputerUseOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
    required String runtimeSessionId,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = _requiredValue(toolName, 'toolName'),
       argumentDigest = _requiredValue(argumentDigest, 'argumentDigest'),
       runtimeSessionId = _requiredValue(runtimeSessionId, 'runtimeSessionId');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;
  final String runtimeSessionId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ComputerUseOperationIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.argumentDigest == argumentDigest &&
            other.runtimeSessionId == runtimeSessionId;
  }

  @override
  int get hashCode => Object.hash(
    owner,
    toolCallId,
    toolName,
    argumentDigest,
    runtimeSessionId,
  );

  static String _requiredValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty.');
    }
    return normalized;
  }
}
