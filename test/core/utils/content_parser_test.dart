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

  test('parse strips model control tokens from streaming think content', () {
    const content = '<think> <channel|>flutter pub get was executed.';

    final result = ContentParser.parse(content);

    expect(result.hasIncompleteTag, isTrue);
    expect(result.incompleteTagType, 'thinking');
    expect(result.incompleteTagContent, 'flutter pub get was executed.');
  });

  test('parse strips stray structural tags from text segments', () {
    const content = 'Done. <think>Hidden</think> Visible <channel|>text';

    final result = ContentParser.parse(content);
    final text = result.segments
        .where((segment) => segment.type == ContentType.text)
        .map((segment) => segment.content)
        .join();

    expect(text, 'Done.  Visible text');
  });

  test('parse extracts tool_result display blocks', () {
    const content =
        'Working...\n<tool_result>{"name":"list_directory"}</tool_result>';

    final result = ContentParser.parse(content);

    expect(result.segments, hasLength(2));
    expect(result.segments.last.type, ContentType.toolResult);
    expect(result.segments.last.toolCall?.name, 'list_directory');
  });
}
