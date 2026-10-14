import 'package:caverno/features/chat/data/datasources/system_prompt_section_registry.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('looks sections up by prompt and evicts the oldest', () {
    final registry = SystemPromptSectionRegistry(capacity: 2);
    const a = [SystemPromptSection('core_principles', 3)];
    const b = [SystemPromptSection('tools', 4)];
    const c = [SystemPromptSection('git_tool', 5)];

    registry
      ..record('prompt a', a)
      ..record('prompt b', b);
    expect(registry.sectionsFor('prompt a'), a);

    // Re-recording refreshes 'a', so 'b' is the oldest when 'c' arrives.
    registry
      ..record('prompt a', a)
      ..record('prompt c', c);
    expect(registry.sectionsFor('prompt b'), isNull);
    expect(registry.sectionsFor('prompt a'), a);
    expect(registry.sectionsFor('prompt c'), c);
  });
}
