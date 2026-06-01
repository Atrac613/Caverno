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
      expect(prompt, contains('the files were not created yet'));
      expect(prompt, contains('When a write_file result includes'));
      expect(prompt, contains('existing file was updated or overwritten'));
      expect(prompt, contains('new file was created'));
      expect(prompt, contains('instead of emitting tool-call tags'));
      expect(prompt, contains('This final answer request cannot call tools'));
      expect(prompt, contains('Do not output JSON command arrays'));
      expect(prompt, contains('state that it remains unexecuted'));
      expect(prompt, contains('Do not restate an investigation plan'));
      expect(prompt, contains('answer from the executed tool results'));
      expect(prompt, contains('When a load_skill result contains explicit'));
      expect(prompt, contains('Do not add optional follow-up questions'));
      expect(prompt, contains('Do not convert a missing source file'));
      expect(prompt, contains('preserve that blocker'));
      expect(prompt, contains('Treat search_past_conversations'));
      expect(prompt, contains('historical context'));
      expect(prompt, contains('not verified evidence'));
      expect(prompt, contains('current application-executed tool results'));
      expect(prompt, contains('Do not treat finishReason=stream_end'));
      expect(prompt, contains('unfinished tool-call tag'));
      expect(prompt, contains('concrete transport error'));
      expect(prompt, isNot(contains('<tool_use>')));
    });

    test('marks write_file created false as an existing file update', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: const {'path': '/tmp/tokyo_weather_2026-06-02.md'},
          result: jsonEncode({
            'path': '/tmp/tokyo_weather_2026-06-02.md',
            'bytes_written': 504,
            'created': false,
          }),
        ),
      ]);

      expect(prompt, contains('[Tool: write_file]'));
      expect(prompt, contains('Arguments:'));
      expect(
        prompt,
        contains(
          'Operation note: write_file updated or overwrote an existing file',
        ),
      );
      expect(prompt, contains('/tmp/tokyo_weather_2026-06-02.md'));
      expect(
        prompt,
        contains('mention this existing-file update in the final answer'),
      );
      expect(prompt, contains('"created":false'));
    });

    test('marks write_file created true as a new file creation', () {
      final note = ToolResultPromptBuilder.buildToolOperationNote(
        ToolResultInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: const {'path': '/tmp/weather.md'},
          result: jsonEncode({
            'path': '/tmp/weather.md',
            'bytes_written': 128,
            'created': true,
          }),
        ),
      );

      expect(note, 'write_file created a new file at /tmp/weather.md.');
    });

    test('marks recalled conversation results as unverified context', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'search_past_conversations',
          arguments: const {'query': 'Android BLE data corruption'},
          result: 'assistant: The root cause is native-side byte conversion.',
        ),
        ToolResultInfo(
          id: 'tool-2',
          name: 'list_directory',
          arguments: const {'path': 'packages/universal_ble'},
          result:
              '{"error":"Directory does not exist: /workspace/packages/universal_ble"}',
        ),
      ]);

      expect(prompt, contains('[Tool: search_past_conversations]'));
      expect(
        prompt,
        contains('Scope note: This is recalled historical context'),
      );
      expect(prompt, contains('prior assistant hypotheses'));
      expect(prompt, contains('treat it as unverified'));
      expect(prompt, contains('Directory does not exist'));
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
