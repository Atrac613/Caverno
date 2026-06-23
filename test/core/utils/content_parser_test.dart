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

  test('extractRecoverableIncompleteToolCalls parses unclosed tool_use', () {
    const content =
        'Gathering data.\n<tool_use>{"name":"arp","arguments":{"ip_version":"all"}}';

    final toolCalls = ContentParser.extractRecoverableIncompleteToolCalls(
      content,
    );

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'arp');
    expect(toolCalls.first.arguments['ip_version'], 'all');
  });

  test('extractToolResultMarkers parses assistant-authored tool results', () {
    const content =
        '<tool_result>{"name":"arp","summary":"Completed","details":["entries: 15"]}</tool_result>';

    final toolResults = ContentParser.extractToolResultMarkers(content);

    expect(toolResults, hasLength(1));
    expect(toolResults.first.name, 'arp');
    expect(toolResults.first.arguments['summary'], 'Completed');
  });

  test('stripToolArtifacts removes calls, results, and incomplete tags', () {
    const content =
        'Checking clients.\n'
        '<tool_use>{"name":"get_wifi_health","arguments":{"minutes":60}}</tool_use>\n'
        '<tool_result>{"name":"get_wifi_health","summary":"Completed"}</tool_result>\n'
        'Next step.\n'
        '<tool_use>{"name":"arp","arguments":{"ip_version":"all"}}';

    final stripped = ContentParser.stripToolArtifacts(content);

    expect(stripped, contains('Checking clients.'));
    expect(stripped, contains('Next step.'));
    expect(stripped, isNot(contains('<tool_use>')));
    expect(stripped, isNot(contains('<tool_result>')));
    expect(stripped, isNot(contains('arp')));
  });

  test('stripModelHistoryArtifacts removes thinking and tool artifacts', () {
    const content =
        '<think>Hidden planning with private notes.</think>\n'
        'Visible answer.\n'
        '<tool_call>{"name":"read_file","arguments":{"path":"README.md"}}</tool_call>';

    final stripped = ContentParser.stripModelHistoryArtifacts(content);

    expect(stripped, 'Visible answer.');
    expect(stripped, isNot(contains('Hidden planning')));
    expect(stripped, isNot(contains('read_file')));
  });

  test('extractCompletedToolCalls parses legacy malformed closing tokens', () {
    const content =
        '<|tool_call>call:write_file{path:"lan_devices.json",contents:"[]"}<tool_call|>';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'write_file');
    expect(toolCalls.first.arguments['path'], 'lan_devices.json');
    expect(toolCalls.first.arguments['contents'], '[]');
  });

  test('extractCompletedToolCalls parses model-quoted JSON array values', () {
    const content = '''
<|tool_call>call:write_file{contents:<|"|>[
  "192.168.100.1",
  "192.168.100.8"
]
<|"|>,path:<|"|>lan_devices.json<|"|>}<tool_call|>''';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'write_file');
    expect(toolCalls.first.arguments['path'], 'lan_devices.json');
    expect(toolCalls.first.arguments['contents'], [
      '192.168.100.1',
      '192.168.100.8',
    ]);
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

  test('extractCompletedToolCalls parses bare tool calls inside text', () {
    const content =
        'まずは、ファイルの存在確認から始めます。call:find_files{pattern:"connection.py"} その後で内容を確認します。';

    final toolCalls = ContentParser.extractCompletedToolCalls(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls.first.name, 'find_files');
    expect(toolCalls.first.arguments['pattern'], 'connection.py');
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

  test(
    'extractCompletedToolCalls ignores tool calls inside thinking blocks',
    () {
      const content = '''
<think>
I should call this tool later.
<tool_call>{"name":"echo_marker","arguments":{"marker":"reasoning-only"}}</tool_call>
</think>
Done.''';

      final toolCalls = ContentParser.extractCompletedToolCalls(content);

      expect(toolCalls, isEmpty);
    },
  );

  test(
    'extractCompletedToolCalls keeps visible calls after thinking blocks',
    () {
      const content = '''
<think>
I might call the wrong tool first.
<tool_call>{"name":"emcho_marker","arguments":{"marker":"wrong"}}</tool_call>
</think>
<tool_call>{"name":"echo_marker","arguments":{"marker":"visible"}}</tool_call>''';

      final toolCalls = ContentParser.extractCompletedToolCalls(content);

      expect(toolCalls, hasLength(1));
      expect(toolCalls.first.name, 'echo_marker');
      expect(toolCalls.first.arguments['marker'], 'visible');
    },
  );

  test(
    'extractCompletedToolCalls ignores calls inside unfinished thinking',
    () {
      const content =
          '<think>Still reasoning. call:echo_marker{marker:"hidden"}';

      final toolCalls = ContentParser.extractCompletedToolCalls(content);

      expect(toolCalls, isEmpty);
    },
  );

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

  test('parse hides bare tool call payloads inside text output', () {
    const content =
        'まずは、ファイルの存在確認から始めます。call:find_files{pattern:"connection.py"} その後で内容を確認します。';

    final result = ContentParser.parse(content);
    final text = result.segments
        .where((segment) => segment.type == ContentType.text)
        .map((segment) => segment.content)
        .join();
    final toolSegment = result.segments.firstWhere(
      (segment) => segment.type == ContentType.toolCall,
    );

    expect(text, 'まずは、ファイルの存在確認から始めます。 その後で内容を確認します。');
    expect(text, isNot(contains('call:find_files')));
    expect(toolSegment.toolCall?.name, 'find_files');
    expect(toolSegment.toolCall?.arguments['pattern'], 'connection.py');
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
