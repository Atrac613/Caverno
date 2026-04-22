import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ChatRemoteDataSource dataSource;

  setUp(() {
    dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
    );
  });

  test('recovers raw assistant text from parse failures', () {
    final error = Exception(
      'StreamException: Failed to parse input at pos 13: '
      '<|channel>thought planning<channel|><tool_use>{"name":"read_file","arguments":{"path":"pubspec.yaml"}}</tool_use>',
    );

    final recovered = dataSource.tryRecoverRawAssistantTextFromError(error);

    expect(
      recovered,
      '<think> planning</think><tool_use>{"name":"read_file","arguments":{"path":"pubspec.yaml"}}</tool_use>',
    );
  });

  test('returns null when the error does not include recoverable raw text', () {
    final recovered = dataSource.tryRecoverRawAssistantTextFromError(
      Exception('Connection refused'),
    );

    expect(recovered, isNull);
  });

  test('parses embedded tool calls from recovered assistant text', () {
    const content =
        '<think>Planning</think><tool_use>{"name":"write_file","arguments":{"path":"out.txt","content":"hello"}}</tool_use>';

    final toolCalls = dataSource.parseEmbeddedToolCallsForTest(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls!.first.name, 'write_file');
    expect(toolCalls.first.arguments['path'], 'out.txt');
    expect(toolCalls.first.arguments['content'], 'hello');
    expect(toolCalls.first.id, isNotEmpty);
  });

  test('annotates successful write_file updates for LLM retries', () {
    final content = dataSource.formatToolResultContentForLlm(
      ToolResultInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {'path': 'tests/test_ping.py'},
        result:
            '{"path":"tests/test_ping.py","bytes_written":1062,"created":false}',
      ),
    );

    expect(
      content,
      contains('Interpretation: write_file succeeded and updated an existing file.'),
    );
    expect(
      content,
      contains(
        'A result with "created": false means the file already existed; it is not an error.',
      ),
    );
    expect(content, contains('Raw result:'));
  });
}
