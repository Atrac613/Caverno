import '../entities/chat_turn_owner.dart';

/// Exact owner, call, tool, and immutable argument identity for one execution.
final class LocalCommandOperationIdentity {
  LocalCommandOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String argumentDigest,
  }) : toolCallId = _requiredLocalCommandIdentityValue(
         toolCallId,
         'toolCallId',
       ),
       toolName = _requiredLocalCommandIdentityValue(toolName, 'toolName'),
       argumentDigest = _requiredLocalCommandIdentityValue(
         argumentDigest,
         'argumentDigest',
       );

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String argumentDigest;

  bool belongsTo(LocalCommandOperationIdentity expected) => this == expected;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalCommandOperationIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.argumentDigest == argumentDigest;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, argumentDigest);
}

/// Exact one-use settlement capability retained through final cache writes.
final class LocalCommandEffectSettlement {
  LocalCommandEffectSettlement({
    required this.identity,
    required bool Function() settle,
  }) : _settle = settle;

  final LocalCommandOperationIdentity identity;
  final bool Function() _settle;

  bool settle() => _settle();
}

String _requiredLocalCommandIdentityValue(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return value;
}
