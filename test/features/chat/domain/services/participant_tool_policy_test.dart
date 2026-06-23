import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/participant_tool_policy.dart';

void main() {
  const policy = ParticipantToolPolicy();

  group('ParticipantToolPolicy', () {
    test('keeps only participant-safe tool definitions', () {
      final definitions = [
        _toolDefinition('web_search'),
        _toolDefinition('get_current_datetime'),
        _toolDefinition('search_past_conversations'),
        _toolDefinition('read_file'),
        _toolDefinition('write_file'),
        _toolDefinition('local_execute_command'),
        _toolDefinition('spawn_subagent'),
        _toolDefinition('read_file'),
      ];

      final filtered = policy.filterDefinitions(definitions);

      expect(_toolNames(filtered), [
        'web_search',
        'get_current_datetime',
        'search_past_conversations',
        'read_file',
      ]);
    });

    test('allows read-only participant tools', () {
      for (final name in ParticipantToolPolicy.allowedToolNames) {
        final result = policy.enforce(_toolCall(name));

        expect(result, isNull, reason: name);
      }
    });

    test('blocks write and orchestration tools', () {
      final result = policy.enforce(_toolCall('write_file'));

      expect(result, isNotNull);
      expect(result!.isSuccess, isFalse);
      expect(result.toolName, 'write_file');
      expect(
        jsonDecode(result.result),
        containsPair('reason', 'participant_tools_require_read_only_allowlist'),
      );
    });
  });
}

ToolCallInfo _toolCall(String name) {
  return ToolCallInfo(id: 'call_$name', name: name, arguments: const {});
}

Map<String, dynamic> _toolDefinition(String name) {
  return {
    'type': 'function',
    'function': {'name': name, 'description': '$name tool'},
  };
}

List<String> _toolNames(List<Map<String, dynamic>> definitions) {
  return definitions
      .map(ParticipantToolPolicy.toolNameFromDefinition)
      .nonNulls
      .toList(growable: false);
}
