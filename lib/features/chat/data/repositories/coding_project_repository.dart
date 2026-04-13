import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/coding_project.dart';

final codingProjectRepositoryProvider = Provider<CodingProjectRepository>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return CodingProjectRepository(prefs);
});

class CodingProjectRepository {
  CodingProjectRepository(this._prefs);

  static const _storageKey = 'coding_projects';

  final SharedPreferences _prefs;

  List<CodingProject> loadAll() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => CodingProject.fromJson(item as Map<String, dynamic>))
          .toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<CodingProject> projects) {
    final encoded = jsonEncode(
      projects.map((project) => project.toJson()).toList(),
    );
    return _prefs.setString(_storageKey, encoded);
  }
}
