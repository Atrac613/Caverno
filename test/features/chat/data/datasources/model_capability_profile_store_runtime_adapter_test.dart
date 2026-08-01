import 'dart:async';

import 'package:caverno/features/chat/data/datasources/model_capability_profile_store_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:test/test.dart';

void main() {
  group('OwnerValidatedModelCapabilityProfileStoreAdapter', () {
    test('persists an immutable snapshot for the exact active owner', () async {
      final persistence = _PersistencePort();
      final adapter = OwnerValidatedModelCapabilityProfileStoreAdapter(
        persistence: persistence,
      );
      final owner = _owner('conversation-a', 7);
      final metadata = <String, String>{'owner': 'generation-7'};
      final profile = _profile(metadata: metadata);
      adapter.activateOwner(owner);

      await adapter.persist(owner: owner, profile: profile);
      metadata['owner'] = 'poisoned';

      expect(
        persistence.profiles.single.probeMetadata['owner'],
        'generation-7',
      );
      expect(
        () => persistence.profiles.single.probeMetadata['owner'] = 'later',
        throwsUnsupportedError,
      );
      expect(adapter.isCurrent(owner), isTrue);
    });

    test('rejects an owner that was never active or was retired', () async {
      final persistence = _PersistencePort();
      final adapter = OwnerValidatedModelCapabilityProfileStoreAdapter(
        persistence: persistence,
      );
      final owner = _owner('conversation-a', 7);

      await expectLater(
        adapter.persist(owner: owner, profile: _profile()),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'The telemetry turn expired before persistence',
          ),
        ),
      );
      adapter.activateOwner(owner);
      expect(adapter.retireOwner(owner), isTrue);
      expect(adapter.retireOwner(owner), isFalse);
      await expectLater(
        adapter.persist(owner: owner, profile: _profile()),
        throwsStateError,
      );
      expect(persistence.profiles, isEmpty);
    });

    test(
      'rejects delayed same-conversation feedback after a new generation',
      () async {
        final gate = Completer<void>();
        final persistence = _PersistencePort(gate: gate);
        final adapter = OwnerValidatedModelCapabilityProfileStoreAdapter(
          persistence: persistence,
        );
        final ownerA = _owner('conversation-a', 7);
        final ownerANext = _owner('conversation-a', 8);
        adapter.activateOwner(ownerA);

        final ownerAFuture = adapter.persist(
          owner: ownerA,
          profile: _profile(model: 'generation-7'),
        );
        await Future<void>.delayed(Duration.zero);
        adapter.activateOwner(ownerANext);
        expect(adapter.isCurrent(ownerA), isFalse);
        expect(adapter.isCurrent(ownerANext), isTrue);
        expect(adapter.retireOwner(ownerA), isFalse);

        gate.complete();
        await expectLater(
          ownerAFuture,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'The telemetry turn expired during persistence',
            ),
          ),
        );

        await adapter.persist(
          owner: ownerANext,
          profile: _profile(model: 'generation-8'),
        );
        expect(persistence.profiles.map((profile) => profile.model), [
          'generation-7',
          'generation-8',
        ]);
        expect(adapter.retireOwner(ownerANext), isTrue);
      },
    );

    test('keeps other conversations active and supports global disposal', () {
      final adapter = OwnerValidatedModelCapabilityProfileStoreAdapter(
        persistence: _PersistencePort(),
      );
      final ownerA = _owner('conversation-a', 1);
      final ownerB = _owner('conversation-b', 1);
      adapter
        ..activateOwner(ownerA)
        ..activateOwner(ownerB);

      expect(adapter.retireOwner(ownerA), isTrue);
      expect(adapter.isCurrent(ownerB), isTrue);

      adapter.clear();

      expect(adapter.isCurrent(ownerB), isFalse);
    });
  });
}

final class _PersistencePort implements ModelCapabilityProfilePersistencePort {
  _PersistencePort({this.gate});

  final Completer<void>? gate;
  final List<ModelCapabilityProfile> profiles = [];

  @override
  Future<void> persist(ModelCapabilityProfile profile) async {
    profiles.add(profile);
    await gate?.future;
  }
}

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

ModelCapabilityProfile _profile({
  String model = 'model-a',
  Map<String, String> metadata = const {},
}) => ModelCapabilityProfile(
  id: '',
  baseUrl: 'http://localhost:1234/v1',
  model: model,
  probeMetadata: metadata,
).normalizedForPersistence();
