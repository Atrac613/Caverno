import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/turn_steering_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: 7,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'thread-b',
    interactionGeneration: 7,
  );
  final laterTurnOfA = ChatTurnOwner(
    conversationId: 'thread-a',
    interactionGeneration: 8,
  );

  QueuedChatMessage message(String id, String content) => QueuedChatMessage(
    id: id,
    content: content,
    imageBase64: null,
    imageMimeType: null,
    languageCode: 'en',
    isVoiceMode: false,
    bypassPlanMode: false,
    conversationId: 'thread-a',
  );

  TurnSteeringEntry entry(String id, String content, {int minute = 0}) =>
      TurnSteeringEntry(
        message: message(id, content),
        receivedAt: DateTime(2026, 8, 7, 10, minute),
      );

  test('claiming hands over pending steers exactly once', () {
    final registry = TurnSteeringRegistry();

    expect(registry.isEmpty, isTrue);
    expect(registry.claimPending(ownerA), isEmpty);

    registry
      ..add(ownerA, entry('one', 'first interruption'))
      ..add(ownerA, entry('two', 'second interruption', minute: 1));

    expect(registry.pendingCount(ownerA), 2);
    expect(registry.hasCarried(ownerA), isFalse);

    final claimed = registry.claimPending(ownerA);
    expect(claimed.map((e) => e.content), [
      'first interruption',
      'second interruption',
    ]);

    // The second claim is what a context retry does: it rebuilds the same
    // request, and must not re-commit messages the first build already took.
    expect(registry.claimPending(ownerA), isEmpty);
    expect(registry.pendingCount(ownerA), 0);
    expect(registry.carriedCount(ownerA), 2);
    expect(registry.hasCarried(ownerA), isTrue);
  });

  test('owners do not see each others steers', () {
    final registry = TurnSteeringRegistry()
      ..add(ownerA, entry('a', 'for a'))
      ..add(ownerB, entry('b', 'for b'));

    expect(registry.claimPending(ownerB).map((e) => e.content), ['for b']);
    expect(registry.pendingCount(ownerA), 1);
    expect(registry.carriedCount(ownerA), 0);
  });

  test('a later turn of the same thread starts clean', () {
    final registry = TurnSteeringRegistry()..add(ownerA, entry('a', 'for a'));

    expect(registry.contains(laterTurnOfA), isFalse);
    expect(registry.pendingCount(laterTurnOfA), 0);
    expect(registry.claimPending(laterTurnOfA), isEmpty);
  });

  test('dispose returns only what no request carried', () {
    final registry = TurnSteeringRegistry()
      ..add(ownerA, entry('carried', 'already sent'))
      ..claimPending(ownerA)
      ..add(ownerA, entry('stranded', 'never sent', minute: 2));

    final returned = registry.dispose(ownerA);

    expect(returned.map((e) => e.content), ['never sent']);
    expect(registry.isEmpty, isTrue);
    // Carried steers are user turns in the transcript by then, so handing them
    // back to the queue would send the same message twice.
    expect(returned.map((e) => e.content), isNot(contains('already sent')));
  });

  test('withdrawing a pending steer finds its owner', () {
    final registry = TurnSteeringRegistry()
      ..add(ownerA, entry('keep', 'keep me'))
      ..add(ownerB, entry('drop', 'withdraw me'));

    expect(registry.removePendingAnywhere('drop'), ownerB);
    expect(registry.pendingCount(ownerB), 0);
    expect(registry.pendingCount(ownerA), 1);
    expect(registry.removePendingAnywhere('drop'), isNull);

    // A carried steer is gone from pending, so there is nothing to withdraw.
    registry.claimPending(ownerA);
    expect(registry.removePendingAnywhere('keep'), isNull);
  });

  test('pending for a conversation is ordered by arrival', () {
    final registry = TurnSteeringRegistry()
      ..add(laterTurnOfA, entry('late', 'typed second', minute: 5))
      ..add(ownerA, entry('early', 'typed first', minute: 1))
      ..add(ownerB, entry('other', 'other thread', minute: 2));

    expect(registry.pendingForConversation('thread-a').map((e) => e.content), [
      'typed first',
      'typed second',
    ]);
  });

  test('clear drops every owner', () {
    final registry = TurnSteeringRegistry()
      ..add(ownerA, entry('a', 'for a'))
      ..add(ownerB, entry('b', 'for b'))
      ..clear();

    expect(registry.isEmpty, isTrue);
    expect(registry.length, 0);
  });
}
