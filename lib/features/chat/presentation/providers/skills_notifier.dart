import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/skill_repository.dart';
import '../../domain/entities/skill.dart';
import '../../domain/services/skill_markdown_parser.dart';

class SkillsState {
  const SkillsState({required this.skills});

  final List<Skill> skills;

  factory SkillsState.initial() => const SkillsState(skills: []);

  List<Skill> get enabledSkills =>
      skills.where((skill) => skill.isUsable).toList(growable: false);
}

final skillsNotifierProvider = NotifierProvider<SkillsNotifier, SkillsState>(
  SkillsNotifier.new,
);

class SkillsNotifier extends Notifier<SkillsState> {
  late final SkillRepository _repository;
  final _uuid = const Uuid();

  @override
  SkillsState build() {
    _repository = ref.read(skillRepositoryProvider);
    return SkillsState(skills: _repository.getAll());
  }

  Future<Skill> upsertMarkdown({
    String? existingId,
    required String markdown,
    bool enabled = true,
  }) async {
    final parsed = SkillMarkdownParser.parse(markdown);
    final now = DateTime.now();
    final existing = existingId == null
        ? null
        : _repository.getById(existingId);
    final skill = Skill(
      id: existing?.id ?? _uuid.v4(),
      name: parsed.name,
      description: parsed.description,
      whenToUse: parsed.whenToUse,
      content: parsed.content,
      enabled: existing?.enabled ?? enabled,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _repository.save(skill);
    _reload();
    return skill;
  }

  Future<void> toggleSkill(String id, bool enabled) async {
    final skill = _repository.getById(id);
    if (skill == null || skill.enabled == enabled) {
      return;
    }
    await _repository.save(
      skill.copyWith(enabled: enabled, updatedAt: DateTime.now()),
    );
    _reload();
  }

  Future<void> deleteSkill(String id) async {
    await _repository.delete(id);
    _reload();
  }

  void _reload() {
    state = SkillsState(skills: _repository.getAll());
  }
}
