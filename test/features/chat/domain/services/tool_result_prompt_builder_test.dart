import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';

void main() {
  group('ToolResultPromptBuilder', () {
    test('dedupes tool definitions by name', () {
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'web_search',
            'description': 'Search the web',
            'parameters': const <String, dynamic>{},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'web_search',
            'description': 'Duplicate entry',
            'parameters': const <String, dynamic>{},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'read_file',
            'description': 'Read a file',
            'parameters': const <String, dynamic>{},
          },
        },
      ];

      final deduped = ToolResultPromptBuilder.dedupeToolsByName(tools);

      expect(deduped, hasLength(2));
      expect(
        deduped
            .map((tool) => (tool['function'] as Map<String, dynamic>)['name'])
            .toList(),
        ['web_search', 'read_file'],
      );
    });

    test('builds an answer prompt with tool descriptions and arguments', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt(
        [
          ToolResultInfo(
            id: 'tool-1',
            name: 'wifi_scan',
            arguments: const {'interface': 'wlan0'},
            result: '{"ssid":"Office"}',
          ),
        ],
        descriptionsByName: const {'wifi_scan': 'Scan nearby Wi-Fi networks.'},
      );

      expect(prompt, contains('Please answer the user\'s question'));
      expect(prompt, contains('[Tool: wifi_scan]'));
      expect(prompt, contains('Description: Scan nearby Wi-Fi networks.'));
      expect(prompt, contains('Arguments: {"interface":"wlan0"}'));
      expect(prompt, contains('Result:'));
      expect(prompt, contains('Scope note:'));
    });
  });
}
