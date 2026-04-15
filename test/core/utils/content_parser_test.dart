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

  test('extractCompletedToolCalls parses control-token tool calls', () {
    const content =
        'Planning...\n<|tool_call>call:read_file{"path":"pubspec.yaml"}';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'read_file');
    expect(toolCalls.first.arguments['path'], 'pubspec.yaml');
  });

  test('extractCompletedToolCalls parses bare tool calls at message end', () {
    const content =
        'Sorry, retrying with the staged file. call:git_execute_command{command:"git status",working_directory:"/tmp/project"}';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'git_execute_command');
    expect(toolCalls.first.arguments['command'], 'git status');
    expect(toolCalls.first.arguments['working_directory'], '/tmp/project');
  });

  test(
    'extractCompletedToolCalls strips model control tokens from command args',
    () {
      const content =
          'call:local_execute_command{command:<|"|>pip install psutil<|"|>,working_directory:"/tmp/project"}';

      final toolCalls = ContentParser.extractCompletedToolCalls(content);

      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.name, 'local_execute_command');
      expect(toolCalls.first.arguments['command'], 'pip install psutil');
      expect(toolCalls.first.arguments['working_directory'], '/tmp/project');
    },
  );

  test('extractCompletedToolCalls tolerates nested quotes in bare call args', () {
    const content =
        'call:git_execute_command{command:"git commit -m "Add tokyo_weather_next_week.csv"",working_directory:"/Users/noguwo/Documents/Workspace/tmp"}';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'git_execute_command');
    expect(
      toolCalls.first.arguments['command'],
      'git commit -m "Add tokyo_weather_next_week.csv"',
    );
    expect(
      toolCalls.first.arguments['working_directory'],
      '/Users/noguwo/Documents/Workspace/tmp',
    );
  });

  test('parse strips model control tokens from streaming think content', () {
    const content = '<think> <channel|>flutter pub get was executed.';

    final result = ContentParser.parse(content);

    expect(result.hasIncompleteTag, isTrue);
    expect(result.incompleteTagType, 'thinking');
    expect(result.incompleteTagContent, 'flutter pub get was executed.');
  });

  test('parse treats thought tags as thinking blocks', () {
    const content = '<thought>Need to inspect the config first.</thought>Done.';

    final result = ContentParser.parse(content);

    expect(result.segments, hasLength(2));
    expect(result.segments.first.type, ContentType.thinking);
    expect(result.segments.first.content, 'Need to inspect the config first.');
    expect(result.segments.last.type, ContentType.text);
    expect(result.segments.last.content, 'Done.');
  });

  test('parse handles incomplete thought tags', () {
    const content = '<thought>Waiting for tool results';

    final result = ContentParser.parse(content);

    expect(result.hasIncompleteTag, isTrue);
    expect(result.incompleteTagType, 'thinking');
    expect(result.incompleteTagContent, 'Waiting for tool results');
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

  test('parse hides control-token tool call payloads from text output', () {
    const content =
        'Working...\n<|tool_call>call:git_execute_command{"command":"git status"}';

    final result = ContentParser.parse(content);
    final text = result.segments
        .where((segment) => segment.type == ContentType.text)
        .map((segment) => segment.content)
        .join();

    expect(result.hasIncompleteTag, isTrue);
    expect(result.incompleteTagType, 'tool_call');
    expect(text, 'Working...\n');
    expect(text, isNot(contains('<|tool_call>')));
    expect(text, isNot(contains('call:git_execute_command')));
  });

  test('parse hides bare tool call payloads from text output', () {
    const content =
        'Retrying with the staged file. call:git_execute_command{command:"git commit -m "Add tokyo_weather_next_week.csv"",working_directory:"/Users/noguwo/Documents/Workspace/tmp"}';

    final result = ContentParser.parse(content);
    final text = result.segments
        .where((segment) => segment.type == ContentType.text)
        .map((segment) => segment.content)
        .join();
    final toolSegment = result.segments.firstWhere(
      (segment) => segment.type == ContentType.toolCall,
    );

    expect(text, 'Retrying with the staged file. ');
    expect(text, isNot(contains('call:git_execute_command')));
    expect(toolSegment.toolCall?.name, 'git_execute_command');
    expect(
      toolSegment.toolCall?.arguments['command'],
      'git commit -m "Add tokyo_weather_next_week.csv"',
    );
  });

  test('parse extracts tool_result display blocks', () {
    const content =
        'Working...\n<tool_result>{"name":"list_directory","summary":"3 item(s)","details":["[dir] lib","[file] pubspec.yaml"]}</tool_result>';

    final result = ContentParser.parse(content);

    expect(result.segments, hasLength(2));
    expect(result.segments.last.type, ContentType.toolResult);
    expect(result.segments.last.toolCall?.name, 'list_directory');
    expect(result.segments.last.toolCall?.arguments['summary'], '3 item(s)');
    expect(result.segments.last.toolCall?.arguments['details'], [
      '[dir] lib',
      '[file] pubspec.yaml',
    ]);
  });
}
