import 'dart:io';

import 'package:caverno/features/chat/application/runtime/turn_runtime_owner_lease_registry.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:test/test.dart';

void main() {
  group('TurnRuntimeOwnerLeaseRegistry', () {
    test('rejects every owner before mount', () {
      final registry = TurnRuntimeOwnerLeaseRegistry();

      expect(registry.isCurrent(_owner('conversation-a')), isFalse);
    });

    test('accepts an owner when visible and selected conversations match', () {
      final registry = TurnRuntimeOwnerLeaseRegistry()
        ..mount(
          visibleConversationId: 'conversation-a',
          selectedConversationId: 'conversation-a',
        );

      expect(registry.isCurrent(_owner('conversation-a')), isTrue);
      expect(
        registry.isCurrent(_owner('conversation-a', generation: 4)),
        isTrue,
        reason: 'active-response registration ends before continuation',
      );
      expect(registry.isCurrent(_owner('conversation-b')), isFalse);
    });

    test('rejects an owner when the visible conversation diverges', () {
      final registry = _mountedRegistry();

      registry.updateVisibleConversation('conversation-b');

      expect(registry.isCurrent(_owner('conversation-a')), isFalse);
    });

    test('rejects an owner when the selected conversation diverges', () {
      final registry = _mountedRegistry();

      registry.updateSelectedConversation('conversation-b');

      expect(registry.isCurrent(_owner('conversation-a')), isFalse);
    });

    test('rejects an owner when either conversation becomes null', () {
      final registry = _mountedRegistry();
      registry.updateSelectedConversation(null);
      expect(registry.isCurrent(_owner('conversation-a')), isFalse);

      registry
        ..updateSelectedConversation('conversation-a')
        ..updateVisibleConversation(null);
      expect(registry.isCurrent(_owner('conversation-a')), isFalse);
    });

    test('retires owners and supports a later rebuild mount', () {
      final registry = _mountedRegistry();

      registry.retire();
      expect(registry.isCurrent(_owner('conversation-a')), isFalse);

      registry.mount(
        visibleConversationId: 'conversation-b',
        selectedConversationId: 'conversation-b',
      );
      expect(registry.isCurrent(_owner('conversation-b')), isTrue);
    });
  });

  test('registry has no presentation or callback dependency', () {
    final source = File(
      'lib/features/chat/application/runtime/'
      'turn_runtime_owner_lease_registry.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ChatNotifier')));
    expect(source, isNot(contains('ChatState')));
    expect(source, isNot(contains('flutter_riverpod')));
    expect(source, isNot(matches(RegExp(r'\bRef\b'))));
    expect(source, isNot(contains('typedef ')));
    expect(source, isNot(contains('Function(')));
    expect(source, isNot(contains('ActiveResponseRegistry')));
  });

  test('chat notifier synchronizes the lease at lifecycle boundaries', () {
    final source = File(
      'lib/features/chat/presentation/providers/chat_notifier.dart',
    ).readAsStringSync();
    final goalAutoContinueSource = File(
      'lib/features/chat/presentation/providers/'
      'chat_notifier_goal_auto_continue.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('_turnRuntimeOwnerLease.updateVisibleConversation(value);'),
    );
    expect(
      source,
      contains(
        '_turnRuntimeOwnerLease.updateSelectedConversation(conversationId);',
      ),
    );
    expect(source, contains('_turnRuntimeOwnerLease.mount('));
    expect(source, contains('_turnRuntimeOwnerLease.retire();'));
    expect(
      source,
      contains('_turnRuntimeOwnerLease.isConversationCurrent(effectiveOwner)'),
    );
    expect(source, contains('_turnRuntimeOwnerLease.isCurrent(turnOwner)'));
    expect(
      goalAutoContinueSource,
      contains('_turnRuntimeOwnerLease.isCurrent(owner)'),
    );
    expect(goalAutoContinueSource, isNot(contains('ref.mounted &&')));
  });
}

TurnRuntimeOwnerLeaseRegistry _mountedRegistry() =>
    TurnRuntimeOwnerLeaseRegistry()..mount(
      visibleConversationId: 'conversation-a',
      selectedConversationId: 'conversation-a',
    );

ChatTurnOwner _owner(String conversationId, {int generation = 3}) =>
    ChatTurnOwner(
      conversationId: conversationId,
      interactionGeneration: generation,
    );
