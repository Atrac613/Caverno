import 'dart:async';

import 'package:caverno/features/chat/data/repositories/worktree_agent_task_repository.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedRepository extends WorktreeAgentTaskRepository {
  _DelayedRepository(super.prefs);
  bool delay = false;
  final saving = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> saveAll(List<WorktreeAgentTask> tasks) async {
    if (delay) {
      delay = false;
      saving.complete();
      await release.future;
    }
    await super.saveAll(tasks);
  }
}

void main() {
  for (final mode in ['allow', 'close', 'concurrent']) {
    final closeGate = mode != 'allow';
    test(
      'held task stays unavailable during admission persistence: $mode',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repository = _DelayedRepository(
          await SharedPreferences.getInstance(),
        );
        final container = ProviderContainer(
          overrides: [
            worktreeAgentTaskRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final registry = container.read(
          worktreeAgentTaskRegistryNotifierProvider.notifier,
        );
        final task = await registry.registerTask(
          deferStart: true,
          title: 'Held',
          prompt: 'Fixture',
          branchName: 'feature/held',
          worktreePath: '/synthetic/held',
        );
        expect(
          repository.loadAll().single.status,
          WorktreeAgentTaskStatus.needsRecovery,
        );
        repository.delay = true;
        var allowed = true;
        var starts = 0;
        final admission = registry.admitHeldTask(
          task.id,
          canStart: () => allowed,
          start: () => starts++,
        );
        await repository.saving.future;
        expect(
          container
              .read(worktreeAgentTaskRegistryNotifierProvider)
              .tasks
              .where((t) => t.id == task.id)
              .single
              .status,
          WorktreeAgentTaskStatus.needsRecovery,
        );
        if (mode == 'close') allowed = false;
        if (mode == 'concurrent') {
          await registry.registerTask(
            deferStart: true,
            title: 'Other',
            prompt: 'Fixture',
            branchName: 'feature/other',
            worktreePath: '/synthetic/other',
          );
        }
        repository.release.complete();
        expect(await admission, !closeGate);
        expect(starts, closeGate ? 0 : 1);
        final expected = closeGate
            ? WorktreeAgentTaskStatus.needsRecovery
            : WorktreeAgentTaskStatus.queued;
        expect(
          repository.loadAll().where((t) => t.id == task.id).single.status,
          expected,
        );
        expect(
          container
              .read(worktreeAgentTaskRegistryNotifierProvider)
              .tasks
              .where((t) => t.id == task.id)
              .single
              .status,
          expected,
        );
        if (mode == 'concurrent') {
          expect(repository.loadAll(), hasLength(2));
        }
        if (closeGate) {
          final restored = ProviderContainer(
            overrides: [
              worktreeAgentTaskRepositoryProvider.overrideWithValue(repository),
            ],
          );
          expect(
            restored
                .read(worktreeAgentTaskRegistryNotifierProvider)
                .tasks
                .where((t) => t.id == task.id)
                .single
                .status,
            WorktreeAgentTaskStatus.needsRecovery,
          );
          restored.dispose();
        }
      },
    );
  }
}
