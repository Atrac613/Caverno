import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/analysis_options_lint_edit_guard.dart';

void main() {
  const guard = AnalysisOptionsLintEditGuard();

  test('blocks a lint override absent from current Dart diagnostics', () {
    final issue = guard.detectIssue(
      toolCall: _edit('''
include: package:lints/recommended.yaml

linter:
  rules:
    prefer_typing_uninitialized_variables: false
'''),
      executedToolResults: [
        _diagnostics(['prefer_initializing_formals']),
      ],
    );

    expect(issue, isNotNull);
    expect(issue!.ungroundedRules, ['prefer_typing_uninitialized_variables']);
    expect(issue.observedDiagnosticCodes, ['prefer_initializing_formals']);
    expect(
      issue.toJson(),
      containsPair('code', AnalysisOptionsLintEditIssue.code),
    );
    expect(issue.instruction, contains('Fix the reported code'));
  });

  test('allows an override matching a current structured diagnostic', () {
    final issue = guard.detectIssue(
      toolCall: _edit('''
linter:
  rules:
    prefer_initializing_formals: false
'''),
      executedToolResults: [
        _diagnostics(['PREFER_INITIALIZING_FORMALS']),
      ],
    );

    expect(issue, isNull);
  });

  test('does not treat the edit reason as diagnostic evidence', () {
    final issue = guard.detectIssue(
      toolCall: _edit('''
linter:
  rules:
    avoid_unused_constructor_parameters: false
''', reason: 'Suppress unused_element reported by the analyzer'),
      executedToolResults: const [],
    );

    expect(issue, isNotNull);
    expect(issue!.ungroundedRules, ['avoid_unused_constructor_parameters']);
    expect(issue.observedDiagnosticCodes, isEmpty);
  });

  test('allows ordinary non-lint analysis options edits', () {
    final issue = guard.detectIssue(
      toolCall: _edit('''
include: package:lints/core.yaml

analyzer:
  exclude:
    - build/**
  language:
    strict-casts: true
'''),
      executedToolResults: const [],
    );

    expect(issue, isNull);
  });

  test('allows preserving an existing ungrounded rule', () {
    final issue = guard.detectIssue(
      toolCall: ToolCallInfo(
        id: 'edit-1',
        name: 'edit_file',
        arguments: const {
          'path': 'analysis_options.yaml',
          'old_text': '''
linter:
  rules:
    avoid_print: false
''',
          'new_text': '''
linter:
  rules:
    avoid_print: false

analyzer:
  exclude:
    - generated/**
''',
        },
      ),
      executedToolResults: const [],
    );

    expect(issue, isNull);
  });

  test('blocks changing an existing rule from enabled to disabled', () {
    final issue = guard.detectIssue(
      toolCall: ToolCallInfo(
        id: 'edit-1',
        name: 'edit_file',
        arguments: const {
          'path': 'analysis_options.yaml',
          'old_text': '    avoid_print: true',
          'new_text': '    avoid_print: false',
        },
      ),
      executedToolResults: const [],
    );

    expect(issue, isNotNull);
    expect(issue!.ungroundedRules, ['avoid_print']);
  });

  test('allows a targeted rule-line edit with matching evidence', () {
    final issue = guard.detectIssue(
      toolCall: ToolCallInfo(
        id: 'edit-1',
        name: 'edit_file',
        arguments: const {
          'path': 'analysis_options.yaml',
          'old_text': '    avoid_print: true',
          'new_text': '    avoid_print: false',
        },
      ),
      executedToolResults: [
        _diagnostics(['avoid_print']),
      ],
    );

    expect(issue, isNull);
  });

  test('allows lint enablement while blocking analyzer suppression', () {
    final issue = guard.detectIssue(
      toolCall: _edit('''
linter:
  rules:
    - avoid_print
analyzer:
  errors:
    unused_element: ignore
'''),
      executedToolResults: const [],
    );

    expect(issue, isNotNull);
    expect(issue!.ungroundedRules, ['unused_element']);
  });

  test('allows enabling a lint without diagnostic evidence', () {
    final issue = guard.detectIssue(
      toolCall: _edit('''
linter:
  rules:
    avoid_print: true
'''),
      executedToolResults: const [],
    );

    expect(issue, isNull);
  });

  test('blocks downgrading an analyzer error to a warning', () {
    final issue = guard.detectIssue(
      toolCall: ToolCallInfo(
        id: 'edit-1',
        name: 'edit_file',
        arguments: const {
          'path': 'analysis_options.yaml',
          'old_text': '    unused_element: error',
          'new_text': '    unused_element: warning',
        },
      ),
      executedToolResults: const [],
    );

    expect(issue, isNotNull);
    expect(issue!.ungroundedRules, ['unused_element']);
  });

  test('accepts a code printed by an executed dart analyze command', () {
    final issue = guard.detectIssue(
      toolCall: _edit('''
linter:
  rules: {prefer_final_locals: false}
'''),
      executedToolResults: [
        ToolResultInfo(
          id: 'analyze-1',
          name: 'local_execute_command',
          arguments: const {'command': 'dart analyze lib'},
          result: jsonEncode({
            'command': 'dart analyze lib',
            'exit_code': 1,
            'stdout':
                'info - lib/main.dart:2:3 - Prefer final for variable declarations. - prefer_final_locals',
            'stderr': '',
          }),
        ),
      ],
    );

    expect(issue, isNull);
  });

  test('ignores diagnostic-looking output from unrelated commands', () {
    final issue = guard.detectIssue(
      toolCall: _edit('''
linter:
  rules:
    avoid_print: false
'''),
      executedToolResults: [
        ToolResultInfo(
          id: 'echo-1',
          name: 'local_execute_command',
          arguments: const {'command': 'echo avoid_print'},
          result: jsonEncode({
            'command': 'echo avoid_print',
            'exit_code': 0,
            'stdout': 'info - lib/main.dart:1:1 - message - avoid_print',
          }),
        ),
      ],
    );

    expect(issue, isNotNull);
    expect(issue!.observedDiagnosticCodes, isEmpty);
  });

  test('guards complete write_file replacements', () {
    final issue = guard.detectIssue(
      toolCall: ToolCallInfo(
        id: 'write-1',
        name: 'write_file',
        arguments: const {
          'path': '/tmp/project/analysis_options.yaml',
          'content': '''
linter:
  rules:
    avoid_print: false
''',
        },
      ),
      executedToolResults: const [],
    );

    expect(issue, isNotNull);
    expect(issue!.ungroundedRules, ['avoid_print']);
  });

  test('ignores edits outside analysis_options.yaml', () {
    final issue = guard.detectIssue(
      toolCall: ToolCallInfo(
        id: 'edit-1',
        name: 'edit_file',
        arguments: const {
          'path': 'lib/options.dart',
          'old_text': '',
          'new_text': 'linter:\n  rules:\n    avoid_print: false',
        },
      ),
      executedToolResults: const [],
    );

    expect(issue, isNull);
  });
}

ToolCallInfo _edit(String newText, {String? reason}) {
  return ToolCallInfo(
    id: 'edit-1',
    name: 'edit_file',
    arguments: {
      'path': '/tmp/project/analysis_options.yaml',
      'old_text': 'include: package:lints/recommended.yaml',
      'new_text': newText,
      'reason': ?reason,
    },
  );
}

ToolResultInfo _diagnostics(List<String> codes) {
  return ToolResultInfo(
    id: 'diagnostics-1',
    name: 'dart_analyze_feedback',
    arguments: const {},
    result: jsonEncode({
      'diagnostics': [
        for (final code in codes) {'code': code},
      ],
    }),
  );
}
