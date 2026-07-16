import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/repositories/skill_repository.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';

void main() {
  test('in-memory repository supports a non-persistent frontend', () async {
    final repository = SkillRepository.inMemory();
    final now = DateTime.utc(2026, 7, 16);
    final skill = Skill(
      id: 'skill-1',
      name: 'Release',
      description: 'Prepare a release',
      whenToUse: 'Before publishing',
      content: 'Run the release checks.',
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );

    await repository.save(skill);

    expect(repository.getAll(), [skill]);
    expect(repository.getById(skill.id), skill);
    expect(repository.findByIdOrName('release'), skill);

    await repository.delete(skill.id);
    expect(repository.getAll(), isEmpty);
  });
}
