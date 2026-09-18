part of 'chat_domain_services_test.dart';

void _runMemoryUpdateAndSkillLookup() {
  test('MemoryUpdateToolUse wraps the extraction counts', () {
    const result = MemoryUpdateResult(
      summaryUpdated: true,
      addedMemoryCount: 1,
      updatedMemoryCount: 0,
      queuedReviewCount: 0,
      suppressedCandidateCount: 0,
      profileUpdated: false,
      generationMethod: MemoryGenerationMethod.llm,
    );

    expect(
      MemoryUpdateToolUse.build(result),
      contains('"name":"memory_update"'),
    );
    expect(MemoryUpdateToolUse.build(result), contains('"added":1'));
  });

  test('EnabledSkillNamedInText matches a usable skill name', () {
    final skills = [
      Skill(
        id: 's1',
        name: 'deploy',
        createdAt: DateTime(2026, 9, 8),
        updatedAt: DateTime(2026, 9, 8),
      ),
    ];

    expect(
      EnabledSkillNamedInText.find('please load deploy', skills)?.id,
      's1',
    );
    expect(EnabledSkillNamedInText.find('nothing here', skills), isNull);
  });
}
