import 'dart:convert';

import 'package:caverno/features/chat/application/runtime/read_only_review_scope.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:test/test.dart';

ToolCallInfo _call(String name, [Map<String, dynamic> arguments = const {}]) =>
    ToolCallInfo(id: 'call-$name', name: name, arguments: arguments);

ToolCallInfo _command(String command) =>
    _call('local_execute_command', {'command': command});

ToolCallInfo _git(String command) =>
    _call('git_execute_command', {'command': command});

void main() {
  const scope = ReadOnlyReviewScope();

  group('offers', () {
    test('keeps readers, command tools and the named exceptions', () {
      for (final name in [
        'read_file',
        'list_directory',
        'local_execute_command',
        'git_execute_command',
        'tool_search',
      ]) {
        expect(scope.offers(name), isTrue, reason: name);
      }
    });

    test('drops every file editor', () {
      for (final name in ['write_file', 'edit_file', 'delete_file']) {
        expect(scope.offers(name), isFalse, reason: name);
      }
    });
  });

  test('initial review catalog contains repository and URL readers only', () {
    for (final name in [
      'git_execute_command',
      'list_directory',
      'read_file',
      'inspect_file',
      'find_files',
      'search_files',
      'local_execute_command',
      'run_tests',
      'http_get',
      'search_web',
      'load_skill',
    ]) {
      expect(scope.offersInitially(name), isTrue, reason: name);
    }
    for (final name in [
      'tool_search',
      'ask_user_question',
      'get_subagent_result',
      'wifi_scan',
      'get_wan_status',
      'search_images',
      'process_wait',
      'write_file',
    ]) {
      expect(scope.offersInitially(name), isFalse, reason: name);
    }
  });

  test('the review catalog does not retain general diagnostic tools', () {
    final names = [
      'git_execute_command',
      'read_file',
      'local_execute_command',
      'http_get',
      'search_web',
      'load_skill',
      'wifi_scan',
      'get_wan_status',
      'search_images',
      'tool_search',
      'write_file',
    ];
    final available = [
      for (final name in names)
        {
          'type': 'function',
          'function': {
            'name': name,
            'description': name,
            'parameters': {'type': 'object'},
          },
        },
    ];
    final allowed = available.where((definition) {
      final function = definition['function']! as Map<String, Object>;
      return scope.offersInitially(function['name']! as String);
    }).toList();
    final selection = ToolDefinitionSearchService.buildInitialSelection(
      allowed,
    );

    expect(selection.toolSearchEnabled, isFalse);
    expect(
      ToolDefinitionSearchService.toolNamesFromDefinitions(
        selection.toolDefinitions,
      ),
      {
        'git_execute_command',
        'read_file',
        'local_execute_command',
        'http_get',
        'search_web',
        'load_skill',
      },
    );
  });

  group('evaluate', () {
    test('lets inspection and verification through', () {
      for (final call in [
        _call('read_file', {'path': 'lib/main.dart'}),
        _git('diff --cached'),
        _git('status --short'),
        // The tool strips a leading `git`, so the scope must too.
        _git('git diff HEAD'),
        _command('python3 -m pytest -q'),
      ]) {
        expect(scope.evaluate(call), isNull, reason: call.arguments.toString());
      }
    });

    test('refuses package installs and venv creation', () {
      // Session 80dc7079: a project-task review ran exactly this compound.
      for (final command in [
        'python3 -m venv .venv && .venv/bin/pip install pytest && '
            '.venv/bin/python -m pytest -q',
        '.venv/bin/pip install pytest',
        'python3 -m venv .venv',
      ]) {
        expect(scope.evaluate(_command(command)), isNotNull, reason: command);
      }
      expect(scope.evaluate(_command('.venv/bin/python -m pytest -q')), isNull);
    });

    test('refuses a file edit with a review-shaped instruction', () {
      final refusal = scope.evaluate(
        _call('edit_file', {
          'path': 'lib/main.dart',
          'old_text': 'a',
          'new_text': 'b',
        }),
      );

      expect(refusal, isNotNull);
      expect(refusal!.isSuccess, isFalse);
      final body = jsonDecode(refusal.result) as Map<String, dynamic>;
      expect(body['code'], ReadOnlyReviewScope.refusedCode);
      expect(body['required_action'], contains('as a finding'));
    });

    test('refuses Git state changes and unclassified commands', () {
      for (final call in [
        _git('commit -m "fix"'),
        _git('git commit -m "fix"'),
        _git('push origin main'),
        _command('rm -rf build'),
        _command('./scripts/deploy.sh'),
      ]) {
        expect(
          scope.evaluate(call),
          isNotNull,
          reason: call.arguments.toString(),
        );
      }
    });
  });

  test('the review carry holds a working set the default drops', () {
    expect(
      ReadOnlyReviewScope.readResultCarry.budgetBytes,
      greaterThanOrEqualTo(23 * 1024),
    );
  });
}
