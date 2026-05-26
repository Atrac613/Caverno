import 'dart:convert';

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

    test('guards against unverified local file side-effect claims', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'http_get',
          arguments: const {'url': 'https://example.com/weather'},
          result: '{"status_code":200,"body":"Weather data"}',
        ),
      ]);

      expect(prompt, contains('Only claim that a local file was created'));
      expect(prompt, contains('If the user requested local file changes'));
      expect(prompt, contains('<tool_use>...</tool_use>'));
      expect(prompt, contains('write_file or edit_file'));
    });

    test('redacts screenshot base64 from answer prompts', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'computer_screenshot',
          arguments: const {},
          result:
              '{"imageBase64":"large-payload","imageMimeType":"image/png","width":800,"height":600}',
        ),
      ]);

      expect(prompt, isNot(contains('large-payload')));
      expect(prompt, contains('[attached as image content]'));
      expect(prompt, contains('"width":800'));
    });

    test('reduces oversized read_file content for prompt budget', () {
      final largeContent = '${'A' * 9000}\nneedle\n${'B' * 9000}';
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'tool-1',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: jsonEncode({
            'path': '/workspace/lib/main.dart',
            'content': largeContent,
            'size_bytes': largeContent.length,
            'start_line': 1,
            'line_count': 400,
            'total_lines': 800,
          }),
        ),
      ], mode: ToolResultPromptBudgetMode.compact);

      final decoded =
          jsonDecode(budgeted.single.result) as Map<String, dynamic>;

      expect(decoded['content'], isNot(contains('needle')));
      expect(decoded['content_reduced_for_prompt_budget'], isTrue);
      expect(decoded['read_more_hint'], contains('read_file'));
      expect(
        (decoded['content'] as String).length,
        lessThan(largeContent.length),
      );
    });

    test('reduces search result lists and exposes the next offset', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'tool-1',
          name: 'search_files',
          arguments: const {'query': 'TODO'},
          result: jsonEncode({
            'path': '/workspace',
            'query': 'TODO',
            'matches': List<String>.generate(
              60,
              (index) => 'lib/file_$index.dart:${index + 1}: TODO',
            ),
            'match_count': 60,
            'offset': 20,
          }),
        ),
      ], mode: ToolResultPromptBudgetMode.compact);

      final decoded =
          jsonDecode(budgeted.single.result) as Map<String, dynamic>;

      expect(decoded['matches'], hasLength(40));
      expect(decoded['matches_reduced_for_prompt_budget'], isTrue);
      expect(decoded['omitted_matches_count'], 20);
      expect(decoded['next_offset'], 60);
    });

    test('keeps only the latest compact image attachment payload', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'tool-1',
          name: 'computer_screenshot',
          arguments: const {},
          result:
              '{"imageBase64":"first-image","imageMimeType":"image/png","width":800}',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'computer_screenshot_window',
          arguments: const {},
          result:
              '{"imageBase64":"latest-image","imageMimeType":"image/png","width":600}',
        ),
      ], mode: ToolResultPromptBudgetMode.compact);

      final first = jsonDecode(budgeted.first.result) as Map<String, dynamic>;
      final second = jsonDecode(budgeted.last.result) as Map<String, dynamic>;

      expect(first['imageBase64'], isNot('first-image'));
      expect(first['image_omitted_for_prompt_budget'], isTrue);
      expect(second['imageBase64'], 'latest-image');
    });
  });
}
