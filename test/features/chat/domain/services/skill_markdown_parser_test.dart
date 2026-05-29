import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/services/skill_markdown_parser.dart';
import 'package:caverno/features/chat/domain/services/skill_prompt_index_builder.dart';

void main() {
  test('parses frontmatter and keeps full markdown body', () {
    final parsed = SkillMarkdownParser.parse('''
---
name: Release Checklist
description: Prepare a release safely
whenToUse: Use before publishing a build
---

# Steps

1. Run verification.
2. Draft release notes.
''');

    expect(parsed.name, 'Release Checklist');
    expect(parsed.description, 'Prepare a release safely');
    expect(parsed.whenToUse, 'Use before publishing a build');
    expect(parsed.content, contains('Run verification.'));
  });

  test('falls back to the first markdown heading when name is omitted', () {
    final parsed = SkillMarkdownParser.parse('''
# Investigate flaky tests

Collect logs and rerun the focused test.
''');

    expect(parsed.name, 'Investigate flaky tests');
    expect(parsed.content, contains('Collect logs'));
  });

  test('builds a clipped lightweight prompt index for enabled skills', () {
    final now = DateTime(2026, 5, 29, 12);
    final index = SkillPromptIndexBuilder.build([
      Skill(
        id: 'release',
        name: 'Release Checklist',
        description: 'Prepare a release safely',
        whenToUse: 'Use before publishing a build',
        content: 'Full content',
        createdAt: now,
        updatedAt: now,
      ),
      Skill(
        id: 'disabled',
        name: 'Disabled Skill',
        enabled: false,
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    expect(index, contains('id=release'));
    expect(index, contains('Release Checklist'));
    expect(index, isNot(contains('Disabled Skill')));
    expect(index, contains('Call load_skill'));
  });
}
