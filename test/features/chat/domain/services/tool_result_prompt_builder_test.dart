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

    test('adds exact preservation guidance for raw tool result values', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'diagnostic_exact_value',
          arguments: const {'field': 'product_label'},
          result: 'Raw result:\n{"product_label":"ZX-900_\\u03b1 2026-06-12"}',
        ),
      ]);

      expect(prompt, contains('TOOL RESULT EXACT PRESERVATION:'));
      expect(prompt, contains('copy those values character-for-character'));
      expect(prompt, contains('Do not summarize, translate, normalize'));
      expect(prompt, contains('If a tool result includes "Raw result:"'));
      expect(prompt, contains('source of truth'));
      expect(prompt, contains('ZX-900_\\u03b1 2026-06-12'));
    });

    test(
      'blocks completion claims when the bounded tool loop dropped a tool call',
      () {
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          ToolResultInfo(
            id: 'tool-1',
            name: 'edit_file',
            arguments: const {
              'path': '/tmp/prime_numbers.dart',
              'old_text': "import 'dart:math';",
              'new_text': "import 'dart:math' show sqrt;",
            },
            result: jsonEncode({
              'code': 'tool_call_not_executed',
              'error':
                  'Tool call was requested after the bounded tool loop stopped '
                  'and was not executed before the final answer.',
              'reason': 'bounded_tool_loop_exhausted',
              'tool_name': 'edit_file',
            }),
          ),
        ]);

        expect(prompt, contains('TASK NOT COMPLETE:'));
        expect(prompt, contains('the bounded tool loop stopped'));
        expect(prompt, contains('edit_file'));
        expect(prompt, contains('remains unexecuted'));
        // The guardrail must precede the tool-result payload so a weak model
        // sees it before the dropped call.
        expect(
          prompt.indexOf('TASK NOT COMPLETE:'),
          lessThan(prompt.indexOf('[Tool: edit_file]')),
        );
      },
    );

    test(
      'blocks completion claims when analyzer errors remain unresolved',
      () {
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          ToolResultInfo(
            id: 'tool-1',
            name: 'dart_analyze_feedback',
            arguments: const {
              'project_root': '/tmp',
              'changed_paths': ['prime_numbers.dart'],
            },
            result: jsonEncode({
              'schema': 'caverno_dart_analyze_feedback',
              'current_diagnostic_count': 3,
              'diagnostics': [
                {
                  'relative_path': 'prime_numbers.dart',
                  'severity': 'Error',
                  'code': 'UNDEFINED_METHOD',
                  'message': "The method 'sqrt' isn't defined for the type "
                      "'double'.",
                },
                {
                  'relative_path': 'prime_numbers.dart',
                  'severity': 'Error',
                  'code': 'NOT_ENOUGH_POSITIONAL_ARGUMENTS',
                  'message':
                      "1 positional argument expected by 'print', but 0 found.",
                },
                {
                  'relative_path': 'prime_numbers.dart',
                  'severity': 'Warning',
                  'code': 'UNUSED_IMPORT',
                  'message': "Unused import: 'dart:math'.",
                },
              ],
            }),
          ),
        ]);

        expect(prompt, contains('TASK NOT COMPLETE:'));
        expect(
          prompt,
          contains('2 unresolved Error-severity diagnostic(s)'),
        );
        expect(prompt, contains('prime_numbers.dart'));
        expect(prompt, contains('does not pass analysis'));
      },
    );

    test(
      'does not inject completion blockers for clean tool results',
      () {
        final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
          ToolResultInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {'path': '/tmp/ok.dart'},
            result: '{"path":"/tmp/ok.dart","bytes_written":12,"created":true}',
          ),
        ]);

        expect(prompt, isNot(contains('TASK NOT COMPLETE:')));
      },
    );

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
      expect(prompt, contains('code=unexecuted_file_save'));
      expect(prompt, contains('If the user requested local file changes'));
      expect(prompt, contains('the files were not created yet'));
      expect(prompt, contains('When a write_file result includes'));
      expect(prompt, contains('existing file was updated or overwritten'));
      expect(prompt, contains('new file was created'));
      expect(prompt, contains('instead of emitting tool-call tags'));
      expect(prompt, contains('This final answer request cannot call tools'));
      expect(prompt, contains('Do not output JSON command arrays'));
      expect(prompt, contains('state that it remains unexecuted'));
      expect(prompt, contains('When browser_snapshot returns page elements'));
      expect(
        prompt,
        contains('refs are valid only for the current page snapshot'),
      );
      expect(prompt, contains('Do not invent or renumber browser refs'));
      expect(prompt, contains('element_not_found or a stale target'));
      expect(prompt, contains('fresh browser_snapshot before retrying'));
      expect(prompt, contains('Only say a browser action'));
      expect(prompt, contains('corresponding browser tool result succeeded'));
      expect(prompt, contains('code=unexecuted_browser_action'));
      expect(prompt, contains('For browser_click results'));
      expect(prompt, contains('target label, name'));
      expect(prompt, contains('navigated fields'));
      expect(prompt, contains('what was actually clicked'));
      expect(prompt, contains('browser_submit retry'));
      expect(prompt, contains('When browser_save_data succeeds'));
      expect(prompt, contains('tool result path field exactly'));
      expect(prompt, contains('trust the result path'));
      expect(prompt, contains('Do not restate an investigation plan'));
      expect(prompt, contains('answer from the executed tool results'));
      expect(
        prompt,
        contains(
          'When the provided tool results already satisfy the user\'s requested local action or saved coding goal',
        ),
      );
      expect(prompt, contains('end after the concise completion evidence'));
      expect(
        prompt,
        contains(
          'Do not add optional follow-up questions, offers, or suggestions',
        ),
      );
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

    test('adds Open-Meteo WMO weather code interpretation notes', () {
      final prompt = ToolResultPromptBuilder.buildAnswerPrompt([
        ToolResultInfo(
          id: 'tool-1',
          name: 'http_get',
          arguments: const {'url': 'https://api.open-meteo.com/v1/forecast'},
          result: jsonEncode({
            'url': 'https://api.open-meteo.com/v1/forecast',
            'status_code': 200,
            'content_type': 'application/json; charset=utf-8',
            'body': jsonEncode({
              'daily_units': {'weathercode': 'wmo code'},
              'daily': {
                'time': ['2026-06-03'],
                'weathercode': [65],
              },
            }),
          }),
        ),
      ]);

      expect(prompt, contains('Interpretation note:'));
      expect(
        prompt,
        contains(
          'Open-Meteo daily 2026-06-03 weather code 65 = Rain: Heavy intensity.',
        ),
      );
      expect(
        prompt,
        contains(
          'drizzle codes are 51, 53, and 55, while rain codes are 61, 63, and 65',
        ),
      );
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

    test('does not stub stale tool results in normal budget mode', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'read-old',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'old content',
        ),
        ToolResultInfo(
          id: 'read-new',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'new content',
        ),
      ]);

      expect(budgeted.first.result, 'old content');
      expect(budgeted.last.result, 'new content');
    });

    test('stubs stale tool results in compact budget mode', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults([
        ToolResultInfo(
          id: 'read-old',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'old content',
        ),
        ToolResultInfo(
          id: 'read-new',
          name: 'read_file',
          arguments: const {'path': 'lib/main.dart'},
          result: 'new content',
        ),
      ], mode: ToolResultPromptBudgetMode.compact);

      expect(budgeted.first.result, contains('stale tool result omitted'));
      expect(budgeted.first.result, contains('newer read_file'));
      expect(budgeted.last.result, 'new content');
    });

    test('keeps protected stale tool results in compact budget mode', () {
      final budgeted = ToolResultPromptBuilder.budgetToolResults(
        [
          ToolResultInfo(
            id: 'read-old',
            name: 'read_file',
            arguments: const {'path': '/workspace/lib/main.dart'},
            result: 'old content',
          ),
          ToolResultInfo(
            id: 'read-new',
            name: 'read_file',
            arguments: const {'path': '/workspace/lib/main.dart'},
            result: 'new content',
          ),
        ],
        mode: ToolResultPromptBudgetMode.compact,
        protectedPaths: const {'lib/main.dart'},
      );

      expect(budgeted.first.result, 'old content');
      expect(budgeted.last.result, 'new content');
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
