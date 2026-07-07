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

    test('keeps get_subagent_result; only spawn_subagent is stripped', () {
      final filtered = SubagentToolPolicy.filterInheritedToolDefinitions([
        tool('get_subagent_result'),
        tool('spawn_subagent'),
        tool('read_file'),
      ]);

      final names = filtered.map(SubagentToolPolicy.toolName).toList();
      expect(names, contains('get_subagent_result'));
      expect(names, contains('read_file'));
      expect(names, isNot(contains('spawn_subagent')));
    });

    test('handles an empty inherited tool list', () {
      expect(
        SubagentToolPolicy.filterInheritedToolDefinitions(
          const <Map<String, dynamic>>[],
        ),
        isEmpty,
      );
    });

    test('curates a large inherited catalog so it fits the model context', () {
      // Above the tool-search threshold the full catalog would overflow a
      // 32768-token model and 400 every subagent request; it must be narrowed
      // to the initial selection instead.
      final large = <Map<String, dynamic>>[
        tool('spawn_subagent'),
        for (var i = 0; i < 40; i++) tool('custom_tool_$i'),
      ];

      final filtered = SubagentToolPolicy.filterInheritedToolDefinitions(large);
      final names = filtered.map(SubagentToolPolicy.toolName).toList();

      expect(names, isNot(contains('spawn_subagent')));
      expect(
        filtered.length,
        lessThan(large.length),
        reason: 'the full catalog must be curated down',
      );
      expect(
        names,
        contains('tool_search'),
        reason: 'tool-search stays available so the subagent can widen its set',
      );
    });
  });
}
