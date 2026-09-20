import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/services/skill_prompt_index_builder.dart';
import 'package:flutter_test/flutter_test.dart';

Skill _skill({
  required String id,
  required String name,
  String description = '',
  String content = '',
  bool enabled = true,
}) => Skill(
  id: id,
  name: name,
  description: description,
  content: content,
  enabled: enabled,
  createdAt: DateTime(2026, 9, 20),
  updatedAt: DateTime(2026, 9, 20),
);

const _releaseContent = '''
# Caverno Version Bump

### 4. リリースノートを作成

`docs/releases/caverno-{new-version}.md` を作成する。
''';

void main() {
  final release = _skill(
    id: 'skill-release',
    name: 'Caverno Version Bump',
    description: 'Version bump, release notes, commit and tag',
    content: _releaseContent,
  );
  final other = _skill(
    id: 'skill-other',
    name: 'Another Skill',
    description: 'Something else',
    content: 'unrelated instructions',
  );

  test('without a carried skill it is the clipped index it always was', () {
    final prompt = SkillPromptIndexBuilder.build([release, other])!;

    expect(prompt, contains('Available user skills'));
    expect(prompt, contains('id=skill-release'));
    // The instruction that names the path is what the model needed and did not
    // have; an index alone must not be read as carrying it.
    expect(prompt, isNot(contains('docs/releases/caverno-{new-version}.md')));
  });

  test('the carried skill arrives with its instructions', () {
    // Session fd153d88: load_skill ran in turn 2 and the write ran in turn 4,
    // by which point only the name survived.
    final prompt = SkillPromptIndexBuilder.build(
      [release, other],
      carriedSkillId: release.id,
      loadedSkillIds: {release.id},
    )!;

    expect(prompt, contains('docs/releases/caverno-{new-version}.md'));
    expect(prompt, contains('Skill in use'));
    // Carried once, not also as an index row. The carried header names the
    // id too, so the row's leading bullet is what distinguishes them.
    expect(prompt, isNot(contains('- id=skill-release')));
    expect(prompt, contains('- id=skill-other'));
  });

  test('its line breaks survive, because the document is the instruction', () {
    final prompt = SkillPromptIndexBuilder.build(
      [release],
      carriedSkillId: release.id,
    )!;

    expect(prompt, contains('# Caverno Version Bump'));
    expect(prompt, contains('\n### 4. リリースノートを作成'));
  });

  test('a skill loaded earlier says its instructions are gone', () {
    // Only one skill is carried, so the rest need to know they are stale --
    // the index's standing "call load_skill" reads as already satisfied to a
    // model that did call it, two turns ago.
    final prompt = SkillPromptIndexBuilder.build(
      [release, other],
      carriedSkillId: other.id,
      loadedSkillIds: {release.id, other.id},
    )!;

    expect(prompt, contains('unrelated instructions'));
    expect(prompt, contains('id=skill-release'));
    expect(prompt, contains('call load_skill again before relying on them'));
    // The carried one is not also marked as missing.
    expect('call load_skill again'.allMatches(prompt).length, 1);
  });

  test('a skill never loaded carries no marker', () {
    final prompt = SkillPromptIndexBuilder.build([release, other])!;

    expect(prompt, isNot(contains('call load_skill again')));
  });

  test('a long index cannot evict the carried skill', () {
    final many = [
      for (var i = 0; i < 80; i++)
        _skill(
          id: 'filler-$i',
          name: 'Filler $i',
          description: 'x' * 200,
          content: 'filler',
        ),
      release,
    ];

    final prompt = SkillPromptIndexBuilder.build(
      many,
      carriedSkillId: release.id,
    )!;

    expect(prompt, contains('docs/releases/caverno-{new-version}.md'));
    expect(prompt, contains('omitted from this clipped index'));
  });

  test('a long carried skill is clipped rather than unbounded', () {
    final huge = _skill(
      id: 'skill-huge',
      name: 'Huge',
      content: 'y' * (SkillPromptIndexBuilder.defaultMaxCarriedSkillChars * 3),
    );

    final prompt = SkillPromptIndexBuilder.build(
      [huge],
      carriedSkillId: huge.id,
    )!;

    expect(prompt, contains('...'));
    expect(
      prompt.length,
      lessThan(SkillPromptIndexBuilder.defaultMaxCarriedSkillChars + 600),
    );
  });

  test('a skill disabled since it was loaded carries nothing', () {
    final gone = _skill(
      id: 'skill-gone',
      name: 'Gone',
      content: 'disabled-skill-body',
      enabled: false,
    );

    final prompt = SkillPromptIndexBuilder.build(
      [release, gone],
      carriedSkillId: gone.id,
    )!;

    expect(prompt, isNot(contains('disabled-skill-body')));
    expect(prompt, contains('- id=skill-release'));
  });
}
