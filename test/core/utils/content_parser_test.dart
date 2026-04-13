import 'package:caverno/core/utils/content_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extractCompletedToolCalls parses tool_use payloads', () {
    const content =
        'Analyzing...\n<tool_use>{"name":"local_execute_command","arguments":{"command":"ls -R","cwd":"."}}</tool_use>';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'local_execute_command');
    expect(toolCalls.first.arguments['command'], 'ls -R');
    expect(toolCalls.first.arguments['cwd'], '.');
    expect(toolCalls.first.occurrenceId, isNotNull);
  });

  test('extractCompletedToolCalls accepts flat tool_use payloads', () {
    const content =
        'Reading file...\n<tool_use>{"name":"read_file","path":"pubspec.yaml"}</tool_use>';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'read_file');
    expect(toolCalls.first.arguments['path'], 'pubspec.yaml');
  });

  test('extractCompletedToolCalls ignores display-only memory_update', () {
    const content =
        '<tool_use>{"name":"memory_update","status":"updated"}</tool_use>';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, isEmpty);
  });

  test('extractCompletedToolCalls assigns unique occurrence ids', () {
    const content =
        '<tool_use>{"name":"read_file","path":"a.txt"}</tool_use>\n'
        '<tool_use>{"name":"read_file","path":"a.txt"}</tool_use>';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(2));
    expect(toolCalls.first.occurrenceId, isNotNull);
    expect(toolCalls.last.occurrenceId, isNotNull);
    expect(toolCalls.first.occurrenceId, isNot(toolCalls.last.occurrenceId));
  });
}
