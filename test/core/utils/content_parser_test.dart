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
  });

  test('extractCompletedToolCalls accepts flat tool_use payloads', () {
    const content =
        'Reading file...\n<tool_use>{"name":"read_file","path":"pubspec.yaml"}</tool_use>';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'read_file');
    expect(toolCalls.first.arguments['path'], 'pubspec.yaml');
  });
}
