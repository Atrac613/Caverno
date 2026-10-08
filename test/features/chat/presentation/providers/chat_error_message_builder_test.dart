import 'package:caverno/features/chat/presentation/providers/chat_error_message_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseUrl = 'http://localhost:1234/v1';

  test('a storage failure carrying a payload is not an auth error', () {
    // Session 7171235a: the SQLite error embedded the conversation, a digit
    // run in it matched "401", and the whole payload filled the screen.
    final payload = List.filled(
      400,
      '{"id":"7171235a","created":1791424033401}',
    ).join(',');
    final message = ChatErrorMessageBuilder.build(
      'SqliteException(14): while executing statement, unable to open '
      'database file, unable to open database file (code 14) Causing '
      'statement: INSERT INTO "conversations" ..., parameters: $payload',
      baseUrl: baseUrl,
    );
    expect(message, startsWith('Could not save the conversation'));
    expect(message, isNot(contains('API key')));
    expect(message.length, lessThan(ChatErrorText.maxDetailChars + 300));
    expect(message, contains('more characters omitted'));
  });

  test('status codes match whole numbers in the error head', () {
    expect(
      ChatErrorMessageBuilder.build(
        'HTTP 401: invalid api key',
        baseUrl: baseUrl,
      ),
      startsWith('Authentication failed'),
    );
    expect(
      ChatErrorMessageBuilder.build(
        'request 1791424033401 failed for an unknown reason',
        baseUrl: baseUrl,
      ),
      isNot(startsWith('Authentication failed')),
    );
    expect(
      ChatErrorMessageBuilder.build('HTTP 503 upstream', baseUrl: baseUrl),
      startsWith('An error occurred on the LLM server'),
    );
  });

  test('a short error passes through unchanged', () {
    expect(
      ChatErrorMessageBuilder.build('something odd', baseUrl: baseUrl),
      'something odd',
    );
  });
}
