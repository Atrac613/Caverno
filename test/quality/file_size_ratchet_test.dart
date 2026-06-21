import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F1 line-count ratchet (docs/local_llm_agent_roadmap.md).
///
/// Each budgeted file may only shrink. When a refactor slice reduces a file,
/// lower its budget here in the same PR so growth cannot creep back. Never
/// raise a budget to make this test pass; extract code instead, following
/// docs/large_file_refactor_plan.md.
const Map<String, int> _lineBudgets = {
  'lib/features/chat/presentation/providers/chat_notifier.dart': 15300,
  'lib/features/chat/presentation/pages/chat_page.dart': 8120,
  'lib/features/chat/data/datasources/mcp_tool_service.dart': 5200,
  'lib/features/settings/presentation/pages/computer_use_settings_page.dart':
      3300,
  'lib/features/settings/presentation/pages/computer_use_debug_page.dart': 2900,
  'lib/features/chat/data/datasources/network_tools.dart': 2600,
  'test/features/chat/presentation/providers/chat_notifier_test.dart': 18810,
};

void main() {
  group('file size ratchet', () {
    for (final entry in _lineBudgets.entries) {
      test('${entry.key} stays within ${entry.value} lines', () {
        final file = File(entry.key);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              '${entry.key} is budgeted but missing. If it was split or '
              'renamed, update _lineBudgets in this test.',
        );

        final lineCount = file.readAsLinesSync().length;
        expect(
          lineCount,
          lessThanOrEqualTo(entry.value),
          reason:
              '${entry.key} has $lineCount lines, over its ratchet budget of '
              '${entry.value}. Do not raise the budget. Extract code per '
              'docs/large_file_refactor_plan.md and '
              'docs/local_llm_agent_roadmap.md (F1).',
        );
      });
    }
  });
}
