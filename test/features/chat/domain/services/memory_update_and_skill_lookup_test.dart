import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/services/enabled_skill_named_in_text.dart';
import 'package:caverno/features/chat/domain/services/memory_update_tool_use.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
