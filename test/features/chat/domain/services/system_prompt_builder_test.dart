import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/services/system_prompt_builder.dart';

void main() {
  test('includes selected project context in coding mode prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.coding,
      languageCode: 'en',
      toolNames: const [
        'list_directory',
        'read_file',
        'local_execute_command',
        'git_execute_command',
      ],
      projectName: 'caverno',
      projectRootPath: '/Users/noguwo/Documents/Workspace/Flutter/caverno',
    );

    expect(prompt, contains('Project name: "caverno".'));
    expect(
      prompt,
      contains(
        'Project root path: /Users/noguwo/Documents/Workspace/Flutter/caverno.',
      ),
    );
    expect(
      prompt,
      contains(
        'prefer this project root as the working directory if one is not explicitly provided',
      ),
    );
    expect(
      prompt,
      contains(
        'For codebase exploration, prefer list_directory, find_files, search_files, and read_file before using local shell commands.',
      ),
    );
    expect(
      prompt,
      contains(
        'If a tool result contains permission_denied or bookmark_restore_failed',
      ),
    );
  });

  test('does not include project context in general mode prompts', () {
    final prompt = SystemPromptBuilder.build(
      now: DateTime(2026, 4, 13, 10, 30),
      assistantMode: AssistantMode.general,
      languageCode: 'en',
      projectName: 'caverno',
      projectRootPath: '/Users/noguwo/Documents/Workspace/Flutter/caverno',
    );

    expect(prompt, isNot(contains('Project root path:')));
    expect(prompt, isNot(contains('Project name: "caverno".')));
  });
}
