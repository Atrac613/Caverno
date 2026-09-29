import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_definitions.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/duplicate_recovery_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = DuplicateRecoveryPromptBuilder();
  final readFileCalls = [
    ToolCallInfo(
      id: 'tool-1',
      name: 'read_file',
      arguments: const {'path': 'js/main.js'},
    ),
  ];

  group('DuplicateRecoveryPromptBuilder', () {
    test('recovery narrows reads while preserving edits and the catalogue', () {
      final read = BuiltInFilesystemToolDefinitions.readFileTool;
      final edit = BuiltInFilesystemToolDefinitions.editFileTool;
      final definitions = [read, edit];
      final recovery = builder.buildToolDefinitions(
        definitions,
        toolCalls: readFileCalls,
      );
      final parameters = recovery.first['function']['parameters'] as Map;
      final properties = parameters['properties'] as Map;

      expect(parameters['required'], containsAll(['path', 'offset', 'limit']));
      expect(properties['limit']['maximum'], 120);
      expect(properties['offset']['minimum'], 1);
      expect(recovery.last, same(edit));
      expect(read['function']['parameters']['required'], ['path']);
      expect(
        read['function']['parameters']['properties']['limit'],
        isNot(contains('maximum')),
      );
      expect(
        builder.buildInspectionPrompt(
          toolCalls: readFileCalls,
          hasSavedTask: false,
        ),
        contains('at most 120 lines'),
      );
    });

    test('keeps a stricter existing read limit', () {
      final read =
          jsonDecode(jsonEncode(BuiltInFilesystemToolDefinitions.readFileTool))
              as Map<String, dynamic>;
      read['function']['parameters']['properties']['limit']['maximum'] = 40;
      final recovery = builder.buildToolDefinitions([
        read,
      ], toolCalls: readFileCalls);

      expect(
        recovery
            .single['function']['parameters']['properties']['limit']['maximum'],
        40,
      );
    });

    test('does not invent range arguments for an unrelated tool schema', () {
      final definitions = <Map<String, dynamic>>[
        {
          'function': {
            'name': 'read_file',
            'parameters': {'type': 'object'},
          },
        },
      ];

      expect(
        builder
            .buildToolDefinitions(definitions, toolCalls: readFileCalls)
            .single,
        same(definitions.single),
      );
      expect(
        builder.buildToolDefinitions(definitions, toolCalls: const []),
        same(definitions),
      );
    });

    test('keeps the plain reuse instruction when nothing was shortened', () {
      final prompt = builder.buildFollowUpPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: true,
      );

      expect(prompt, contains('Use the previous tool results'));
      expect(prompt, isNot(contains('shortened to fit the prompt budget')));
    });

    test('replaces the reuse instruction for a shortened result', () {
      // Session a0ca65b7: the guard told the model to reuse results the prompt
      // budget had cut, leaving the forbidden repeat as its only move.
      final prompt = builder.buildFollowUpPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: true,
        budgetReducedToolNames: const {'read_file'},
      );

      expect(prompt, isNot(contains('Use the previous tool results')));
      expect(
        prompt,
        contains(
          'The earlier read_file result was shortened to fit the '
          'prompt budget',
        ),
      );
      expect(prompt, contains('offset, and a small limit'));
    });

    test('adds the range-read escape to the inspection prompt', () {
      final prompt = builder.buildInspectionPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: true,
        budgetReducedToolNames: const {'read_file'},
      );

      expect(
        prompt,
        contains('Do not repeat identical read-only inspection tools'),
      );
      expect(prompt, contains('shortened to fit the prompt budget'));
      expect(prompt, contains('offset, and a small limit'));
    });

    test('ignores a shortened tool the model is not repeating', () {
      final prompt = builder.buildInspectionPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: true,
        budgetReducedToolNames: const {'search_files'},
      );

      expect(prompt, isNot(contains('shortened to fit the prompt budget')));
    });

    test('a review outranks a saved task in both forms', () {
      // Session e3a9f3f0: a /review in a thread whose saved task was done was
      // told to "modify a saved target file".
      for (final prompt in [
        builder.buildInspectionPrompt(
          toolCalls: readFileCalls,
          hasSavedTask: true,
          readOnlyReview: true,
        ),
        builder.buildFollowUpPrompt(
          toolCalls: readFileCalls,
          hasSavedTask: true,
          readOnlyReview: true,
        ),
      ]) {
        expect(prompt, isNot(contains('saved')));
        expect(prompt, contains('read-only review'));
        expect(prompt, contains('Write the review now'));
      }
    });

    test('a shortened result still gets its narrow-read hint in a review', () {
      final prompt = builder.buildInspectionPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: false,
        readOnlyReview: true,
        budgetReducedToolNames: const {'read_file'},
      );

      expect(prompt, contains('shortened to fit the prompt budget'));
    });
  });
}
