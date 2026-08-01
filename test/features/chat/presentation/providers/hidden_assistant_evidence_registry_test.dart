import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/presentation/providers/hidden_assistant_evidence_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const generation = 7;
  final ownerA = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: generation,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'thread-b',
    interactionGeneration: generation,
  );
  int score(String response) => response.contains('complete') ? 2 : 1;

  test('isolates, ranks, publishes, and consumes exact-owner evidence', () {
    final registry = HiddenAssistantEvidenceRegistry();

    expect(registry.begin(ownerA), isTrue);
    expect(registry.begin(ownerB), isTrue);
    expect(registry.begin(ownerA), isFalse);
    expect(registry.record(ownerA, ' ', evidenceScore: score), isFalse);
    expect(registry.record(ownerA, 'A draft', evidenceScore: score), isTrue);
    expect(registry.record(ownerA, 'A complete', evidenceScore: score), isTrue);
    expect(
      registry.record(ownerA, 'A complete expanded', evidenceScore: score),
      isTrue,
    );
    expect(registry.record(ownerB, 'B complete', evidenceScore: score), isTrue);

    expect(registry.publish(ownerB), isTrue);
    expect(registry.publish(ownerA), isTrue);
    expect(
      registry.record(ownerA, 'late A complete', evidenceScore: score),
      isFalse,
    );
    expect(registry.take(ownerB), 'B complete');
    expect(registry.take(ownerB), isNull);
    expect(registry.take(ownerA), 'A complete expanded');
    expect(registry.take(ownerA), isNull);
    expect(registry.length, 2);
  });

  test('retention, disposal, and clear reject closed owner writes', () {
    var current = DateTime(2026, 7, 29);
    final registry = HiddenAssistantEvidenceRegistry(
      retention: const Duration(minutes: 1),
      now: () => current,
    );
    final nextOwnerA = ChatTurnOwner(
      conversationId: ownerA.conversationId,
      interactionGeneration: generation + 1,
    );

    expect(registry.begin(ownerA), isTrue);
    expect(registry.publish(ownerA), isTrue);
    current = current.add(const Duration(minutes: 2));
    expect(registry.length, 0);
    expect(registry.begin(ownerA), isFalse);
    expect(registry.publish(ownerB), isFalse);
    expect(registry.dispose(ownerB), isFalse);
    expect(registry.begin(ownerB), isFalse);
    expect(registry.begin(nextOwnerA), isTrue);
    registry.clear();
    expect(registry.length, 0);
    expect(registry.begin(nextOwnerA), isFalse);
  });

  test('constructor rejects a non-positive retention period', () {
    expect(
      () => HiddenAssistantEvidenceRegistry(retention: Duration.zero),
      throwsAssertionError,
    );
  });
}
