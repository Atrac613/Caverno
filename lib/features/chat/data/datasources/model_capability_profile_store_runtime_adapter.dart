import '../../../settings/domain/entities/app_settings.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/model_edit_apply_telemetry_recorder.dart';

/// Owner-independent persistence used after exact-turn validation.
abstract interface class ModelCapabilityProfilePersistencePort {
  Future<void> persist(ModelCapabilityProfile profile);
}

/// Keeps telemetry persistence and follow-up feedback on one exact turn owner.
///
/// Goal and participant turns may advance to a newer generation while the
/// settings repository is saving. A post-write owner check turns that race
/// into a failed persistence receipt, preventing the caller from applying
/// follow-up feedback from the retired generation.
final class OwnerValidatedModelCapabilityProfileStoreAdapter
    implements ModelCapabilityProfileStorePort {
  OwnerValidatedModelCapabilityProfileStoreAdapter({
    required ModelCapabilityProfilePersistencePort persistence,
  }) : _persistence = persistence;

  final ModelCapabilityProfilePersistencePort _persistence;
  final Map<String, ChatTurnOwner> _activeOwnersByConversation = {};

  void activateOwner(ChatTurnOwner owner) {
    _activeOwnersByConversation[owner.conversationId] = owner;
  }

  bool retireOwner(ChatTurnOwner owner) {
    if (!isCurrent(owner)) {
      return false;
    }
    _activeOwnersByConversation.remove(owner.conversationId);
    return true;
  }

  bool isCurrent(ChatTurnOwner owner) =>
      _activeOwnersByConversation[owner.conversationId] == owner;

  void clear() => _activeOwnersByConversation.clear();

  @override
  Future<void> persist({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile profile,
  }) async {
    if (!isCurrent(owner)) {
      throw StateError('The telemetry turn expired before persistence');
    }
    final snapshot = profile.copyWith(
      probeMetadata: Map<String, String>.unmodifiable(profile.probeMetadata),
    );
    await _persistence.persist(snapshot);
    if (!isCurrent(owner)) {
      throw StateError('The telemetry turn expired during persistence');
    }
  }
}
