import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/presentation/providers/settings_notifier.dart';
import '../domain/entities/routine.dart';

final routineRepositoryProvider = Provider<RoutineRepository>((ref) {
  return RoutineRepository(ref.watch(sharedPreferencesProvider));
});

class RoutineRepository {
  RoutineRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _storageKey = 'routines';

  List<Routine> loadAll() {
    final json = _prefs.getString(_storageKey);
    if (json == null) {
      return const [];
    }

    try {
      final decoded = jsonDecode(json) as List<dynamic>;
      return decoded
          .map((item) => Routine.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<Routine> routines) async {
    await _prefs.setString(
      _storageKey,
      jsonEncode(routines.map((routine) => routine.toJson()).toList()),
    );
  }
}
