import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/subagent_tool_policy.dart';

void main() {
  Map<String, dynamic> tool(String name) => {
    'type': 'function',
    'function': {'name': name, 'description': 'desc for $name'},
  };

  group('SubagentToolPolicy', () {
    test('removes spawn_subagent so children cannot nest', () {
      final filtered = SubagentToolPolicy.filterInheritedToolDefinitions([
        tool('read_file'),
        tool('spawn_subagent'),
        tool('web_search'),
      ]);

      final names = filtered.map(SubagentToolPolicy.toolName).toList();
      expect(names, isNot(contains('spawn_subagent')));
      expect(names, containsAll(<String>['read_file', 'web_search']));
    });

    test('keeps inherited tools and dedupes by name', () {
      final filtered = SubagentToolPolicy.filterInheritedToolDefinitions([
        tool('read_file'),
        tool('read_file'),
      ]);

      expect(filtered, hasLength(1));
      expect(SubagentToolPolicy.toolName(filtered.single), 'read_file');
    });

    test('toolName reads the OpenAI function name', () {
      expect(SubagentToolPolicy.toolName(tool('ping')), 'ping');
      expect(SubagentToolPolicy.toolName(const {}), '');
    });
  });
}
