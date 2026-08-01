import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/presentation/providers/subagent_task_notifier.dart';

void main() {
  late ProviderContainer container;
  late ChatTurnOwner owner;
  late ChatTurnOwner peer;

  setUp(() {
    container = ProviderContainer();
    owner = _owner('conversation-a', 7);
    peer = _owner('conversation-b', 7);
  });

  tearDown(() => container.dispose());

  SubagentTaskNotifier notifier() =>
      container.read(subagentTaskNotifierProvider.notifier);

  SubagentTaskState state() => container.read(subagentTaskNotifierProvider);

  group('SubagentTask ownership schema', () {
    test('defaults legacy JSON to an administrative-only unowned task', () {
      final legacy = SubagentTask.fromJson({
        'id': 'legacy',
        'status': 'running',
      });
      final owned = _task(owner, 'owned');
      final nextGenerationOwner = _owner(owner.conversationId, 8);
      final nextGeneration = _task(nextGenerationOwner, 'next-generation');
      final administrativeState = SubagentTaskState.forAdministrativeView([
        legacy,
        owned,
        nextGeneration,
        _task(peer, 'peer', status: SubagentTaskStatus.completed),
      ]);

      expect(legacy.conversationId, isEmpty);
      expect(legacy.interactionGeneration, -1);
      expect(legacy.isLegacyUnowned, isTrue);
      expect(legacy.isOwnedBy(owner), isFalse);
      expect(legacy.toJson(), containsPair('conversationId', ''));
      expect(legacy.toJson(), containsPair('interactionGeneration', -1));
      expect(owned.isLegacyUnowned, isFalse);
      expect(owned.isOwnedBy(owner), isTrue);
      expect(owned.isOwnedBy(peer), isFalse);
      expect(administrativeState.tasksFor(owner).map((task) => task.id), [
        'owned',
      ]);
      expect(administrativeState.activeTasksFor(owner).map((task) => task.id), [
        'owned',
      ]);
      expect(
        administrativeState
            .tasksForConversation(' ${owner.conversationId} ')
            .map((task) => task.id),
        ['owned', 'next-generation'],
      );
      expect(administrativeState.tasksForConversation('   '), isEmpty);
      expect(
        administrativeState
            .tasksForConversation(peer.conversationId)
            .map((task) => task.id),
        ['peer'],
      );
      expect(administrativeState.administrativeView.map((task) => task.id), [
        'legacy',
        'owned',
        'next-generation',
        'peer',
      ]);
      expect(
        () => administrativeState.administrativeView.add(owned),
        throwsUnsupportedError,
      );
      expect(
        () => administrativeState.tasksFor(owner).clear(),
        throwsUnsupportedError,
      );
    });

    test('partial legacy ownership never matches an active owner', () {
      final missingConversation = SubagentTask(
        id: 'missing-conversation',
        interactionGeneration: owner.interactionGeneration,
      );
      final missingGeneration = SubagentTask(
        id: 'missing-generation',
        conversationId: owner.conversationId,
      );

      expect(missingConversation.isLegacyUnowned, isTrue);
      expect(missingGeneration.isLegacyUnowned, isTrue);
      expect(missingConversation.isOwnedBy(owner), isFalse);
      expect(missingGeneration.isOwnedBy(owner), isFalse);
    });
  });

  group('SubagentTaskNotifier', () {
    test('registers unique task identities for only their exact owner', () {
      expect(state().administrativeView, isEmpty);
      final ownerTask = _task(owner, 'shared');
      final peerTask = _task(peer, 'shared');

      expect(notifier().register(owner, ownerTask), isTrue);
      expect(notifier().register(peer, peerTask), isTrue);
      expect(notifier().register(owner, ownerTask), isFalse);
      expect(notifier().register(owner, peerTask), isFalse);
      expect(
        notifier().register(
          owner,
          const SubagentTask(id: 'legacy-registration'),
        ),
        isFalse,
      );

      expect(notifier().byId(owner, 'shared'), same(ownerTask));
      expect(notifier().byId(peer, 'shared'), same(peerTask));
      expect(notifier().byId(owner, 'missing'), isNull);
      expect(notifier().tasksFor(owner), [ownerTask]);
      expect(notifier().tasksFor(peer), [peerTask]);
      expect(notifier().activeTasks(owner), [ownerTask]);
      expect(state().administrativeView, [ownerTask, peerTask]);
    });

    test('runs an active task to completion only once', () {
      final pending = _task(owner, 'task', status: SubagentTaskStatus.pending);
      expect(notifier().register(owner, pending), isTrue);

      expect(notifier().markRunning(owner, 'task'), isTrue);
      expect(
        notifier().byId(owner, 'task')!.status,
        SubagentTaskStatus.running,
      );
      expect(
        notifier().complete(
          owner,
          'task',
          output: 'full output',
          summary: 'short summary',
        ),
        isTrue,
      );

      final completed = notifier().byId(owner, 'task')!;
      expect(completed.status, SubagentTaskStatus.completed);
      expect(completed.output, 'full output');
      expect(completed.resultSummary, 'short summary');
      expect(completed.finishedAt, isNotNull);
      expect(completed.isTerminal, isTrue);
      expect(notifier().activeTasks(owner), isEmpty);
      expect(notifier().markRunning(owner, 'task'), isFalse);
      expect(
        notifier().complete(owner, 'task', output: 'late', summary: 'late'),
        isFalse,
      );
      expect(notifier().fail(owner, 'task', 'late failure'), isFalse);
      expect(notifier().cancel(owner, 'task'), isFalse);
      expect(notifier().markRunning(owner, 'missing'), isFalse);
    });

    test('fails an active task and marks notification once', () {
      expect(notifier().register(owner, _task(owner, 'task')), isTrue);

      expect(notifier().fail(owner, 'task', 'boom'), isTrue);
      final failed = notifier().byId(owner, 'task')!;
      expect(failed.status, SubagentTaskStatus.failed);
      expect(failed.error, 'boom');
      expect(failed.finishedAt, isNotNull);
      expect(notifier().markNotified(owner, 'task'), isTrue);
      expect(notifier().byId(owner, 'task')!.notified, isTrue);
      expect(notifier().markNotified(owner, 'task'), isFalse);
      expect(notifier().markNotified(peer, 'task'), isFalse);
    });

    test('cancellation fences a late completion', () {
      expect(notifier().register(owner, _task(owner, 'task')), isTrue);

      expect(notifier().cancel(owner, 'task'), isTrue);
      expect(
        notifier().byId(owner, 'task')!.status,
        SubagentTaskStatus.cancelled,
      );
      expect(
        notifier().complete(owner, 'task', output: 'late', summary: 'late'),
        isFalse,
      );
      expect(notifier().byId(owner, 'task')!.output, isEmpty);
    });

    test('remove and clearFinished affect only the exact owner', () {
      final ownerActive = _task(owner, 'active');
      final ownerFinished = _task(
        owner,
        'finished',
        status: SubagentTaskStatus.completed,
      );
      final peerFinished = _task(
        peer,
        'finished',
        status: SubagentTaskStatus.completed,
      );
      for (final entry in [
        (owner, ownerActive),
        (owner, ownerFinished),
        (peer, peerFinished),
      ]) {
        expect(notifier().register(entry.$1, entry.$2), isTrue);
      }

      expect(notifier().remove(owner, 'missing'), isFalse);
      expect(notifier().clearFinished(owner), 1);
      expect(notifier().tasksFor(owner), [ownerActive]);
      expect(notifier().tasksFor(peer), [peerFinished]);
      expect(notifier().remove(owner, 'active'), isTrue);
      expect(notifier().remove(owner, 'active'), isFalse);
      expect(notifier().tasksFor(owner), isEmpty);
      expect(notifier().tasksFor(peer), [peerFinished]);
    });

    test('clearOwner synchronously retires late lifecycle callbacks', () async {
      final completionGate = Completer<void>();
      expect(notifier().register(owner, _task(owner, 'task')), isTrue);
      final lateCompletion = () async {
        await completionGate.future;
        return notifier().complete(
          owner,
          'task',
          output: 'late output',
          summary: 'late summary',
        );
      }();
      expect(notifier().register(peer, _task(peer, 'task')), isTrue);

      notifier().clearOwner(owner);
      completionGate.complete();

      expect(await lateCompletion, isFalse);
      expect(notifier().byId(owner, 'task'), isNull);
      expect(notifier().tasksFor(owner), isEmpty);
      expect(notifier().activeTasks(owner), isEmpty);
      expect(notifier().register(owner, _task(owner, 'new')), isFalse);
      expect(notifier().markRunning(owner, 'task'), isFalse);
      expect(
        notifier().complete(owner, 'task', output: '', summary: ''),
        isFalse,
      );
      expect(notifier().fail(owner, 'task', 'late'), isFalse);
      expect(notifier().cancel(owner, 'task'), isFalse);
      expect(notifier().markNotified(owner, 'task'), isFalse);
      expect(notifier().remove(owner, 'task'), isFalse);
      expect(notifier().clearFinished(owner), 0);
      notifier().clearOwner(owner);
      expect(notifier().tasksFor(peer).single.id, 'task');
    });
  });
}

ChatTurnOwner _owner(String conversationId, int interactionGeneration) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: interactionGeneration,
  );
}

SubagentTask _task(
  ChatTurnOwner owner,
  String id, {
  SubagentTaskStatus status = SubagentTaskStatus.running,
}) {
  return SubagentTask(
    id: id,
    conversationId: owner.conversationId,
    interactionGeneration: owner.interactionGeneration,
    status: status,
    description: 'task $id',
    isBackground: true,
  );
}
