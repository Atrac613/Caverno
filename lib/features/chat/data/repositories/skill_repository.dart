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
  SkillRepository(Box<String> box) : _box = box, _memory = null;

  SkillRepository.inMemory() : _box = null, _memory = <String, String>{};

  final Box<String>? _box;
  final Map<String, String>? _memory;

  Iterable<dynamic> get _keys => _box?.keys ?? _memory!.keys;

  String? _get(String key) => _box?.get(key) ?? _memory?[key];

  List<Skill> getAll() {
    final skills = <Skill>[];
    for (final key in _keys) {
      final json = _get(key.toString());
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
    final json = _get(id);
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
    final encoded = jsonEncode(skill.toJson());
    final box = _box;
    if (box != null) {
      await box.put(skill.id, encoded);
    } else {
      _memory![skill.id] = encoded;
    }
  }

  Future<void> delete(String id) async {
    final box = _box;
    if (box != null) {
      await box.delete(id);
    } else {
      _memory!.remove(id);
    }
  }
}
