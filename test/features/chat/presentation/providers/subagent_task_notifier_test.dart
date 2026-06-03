import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/presentation/providers/subagent_task_notifier.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  SubagentTaskNotifier notifier() =>
      container.read(subagentTaskNotifierProvider.notifier);
  List<SubagentTask> tasks() => container.read(subagentTaskNotifierProvider);

  SubagentTask runningTask(String id) => SubagentTask(
    id: id,
    status: SubagentTaskStatus.running,
    description: 'task $id',
    isBackground: true,
  );

  group('SubagentTaskNotifier', () {
    test('register adds a task', () {
      notifier().register(runningTask('a'));

      expect(tasks(), hasLength(1));
      expect(tasks().single.id, 'a');
    });

    test('complete sets status, output, and summary', () {
      notifier().register(runningTask('a'));

      notifier().complete('a', output: 'full output', summary: 'short summary');

      final task = notifier().byId('a')!;
      expect(task.status, SubagentTaskStatus.completed);
      expect(task.output, 'full output');
      expect(task.resultSummary, 'short summary');
      expect(task.isTerminal, isTrue);
    });

    test('fail records the error', () {
      notifier().register(runningTask('a'));

      notifier().fail('a', 'boom');

      expect(notifier().byId('a')!.status, SubagentTaskStatus.failed);
      expect(notifier().byId('a')!.error, 'boom');
    });

    test('cancel marks an active task but leaves terminal tasks untouched', () {
      notifier().register(runningTask('done'));
      notifier().complete('done', output: '', summary: 's');
      notifier().cancel('done');
      expect(notifier().byId('done')!.status, SubagentTaskStatus.completed);

      notifier().register(runningTask('live'));
      notifier().cancel('live');
      expect(notifier().byId('live')!.status, SubagentTaskStatus.cancelled);
    });

    test('clearFinished keeps only active tasks', () {
      notifier().register(runningTask('a'));
      notifier().register(runningTask('b'));
      notifier().complete('a', output: '', summary: 's');

      notifier().clearFinished();

      expect(tasks(), hasLength(1));
      expect(tasks().single.id, 'b');
    });

    test('activeTasks filters out terminal tasks', () {
      notifier().register(runningTask('a'));
      notifier().register(runningTask('b'));
      notifier().fail('b', 'x');

      expect(notifier().activeTasks.map((task) => task.id), ['a']);
    });

    test('markNotified flips the notified flag once', () {
      notifier().register(runningTask('a'));
      notifier().complete('a', output: '', summary: 's');

      notifier().markNotified('a');

      expect(notifier().byId('a')!.notified, isTrue);
    });

    test('remove drops a task by id', () {
      notifier().register(runningTask('a'));
      notifier().register(runningTask('b'));

      notifier().remove('a');

      expect(tasks().map((task) => task.id), ['b']);
    });

    test('byId returns null for an unknown id', () {
      notifier().register(runningTask('a'));

      expect(notifier().byId('missing'), isNull);
    });
  });
}
