import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/skill.dart';

final skillBoxProvider = Provider<Box<String>>((ref) {
  throw UnimplementedError('skillBoxProvider must be overridden');
});

final skillRepositoryProvider = Provider<SkillRepository>((ref) {
  return SkillRepository(ref.watch(skillBoxProvider));
});

class SkillRepository {
  SkillRepository(this._box);

  final Box<String> _box;

  List<Skill> getAll() {
    final skills = <Skill>[];
    for (final key in _box.keys) {
      final json = _box.get(key);
      if (json == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        skills.add(Skill.fromJson(decoded));
      } catch (error) {
        appLog('[SkillRepository] Failed to parse skill: $error');
      }
    }
    skills.sort(
      (a, b) => a.normalizedName.toLowerCase().compareTo(
        b.normalizedName.toLowerCase(),
      ),
    );
    return skills;
  }

  Skill? getById(String id) {
    final json = _box.get(id);
    if (json == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return Skill.fromJson(decoded);
    } catch (error) {
      appLog('[SkillRepository] Failed to parse skill: $error');
      return null;
    }
  }

  Skill? findByIdOrName(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    final byId = getById(value.trim());
    if (byId != null) {
      return byId;
    }
    for (final skill in getAll()) {
      if (skill.normalizedName.toLowerCase() == normalized) {
        return skill;
      }
    }
    return null;
  }

  Future<void> save(Skill skill) async {
    await _box.put(skill.id, jsonEncode(skill.toJson()));
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
  }
}
