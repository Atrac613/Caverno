import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/worktree_agent_task.dart';

final worktreeAgentTaskRepositoryProvider =
    Provider<WorktreeAgentTaskRepository>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return WorktreeAgentTaskRepository(prefs);
    });

class WorktreeAgentTaskRepository {
  WorktreeAgentTaskRepository(this._prefs);

  static const storageKey = 'll13_worktree_agent_tasks';

  final SharedPreferences _prefs;

  List<WorktreeAgentTask> loadAll() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => WorktreeAgentTask.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<WorktreeAgentTask> tasks) {
    final encoded = jsonEncode(tasks.map((task) => task.toJson()).toList());
    return _prefs.setString(storageKey, encoded);
  }
}
