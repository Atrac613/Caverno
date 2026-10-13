import 'package:caverno/features/chat/presentation/providers/chat_error_message_builder.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart';

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
      SqliteException(
        extendedResultCode: 14,
        message: 'unable to open database file 401',
        causingStatement:
            'INSERT INTO "conversations" ..., parameters: '
            '$payload',
      ),
      baseUrl: baseUrl,
    );
    expect(message, startsWith('Could not save the conversation'));
    expect(message, isNot(contains('API key')));
    expect(message.length, lessThan(ChatErrorText.maxDetailChars + 300));
    expect(message, contains('more characters omitted'));
  });

  test('the headline follows the status code, not the message text', () {
    expect(
      ChatErrorMessageBuilder.build(
        const AuthenticationException(message: 'invalid api key'),
        baseUrl: baseUrl,
      ),
      startsWith('Authentication failed'),
    );
    expect(
      ChatErrorMessageBuilder.build(
        const InternalServerException(
          message: 'upstream said HTTP 401 unauthorized',
          statusCode: 503,
        ),
        baseUrl: baseUrl,
      ),
      startsWith('An error occurred on the LLM server'),
    );
  });

  test('an untyped error passes through without a guessed headline', () {
    expect(
      ChatErrorMessageBuilder.build(
        'HTTP 401: something odd',
        baseUrl: baseUrl,
      ),
      'HTTP 401: something odd',
    );
  });

  test('a server-requested delay and request id reach the text', () {
    final message = ChatErrorMessageBuilder.build(
      const RateLimitException(
        message: 'slow down',
        requestId: 'req_123',
        retryAfter: Duration(seconds: 20),
      ),
      baseUrl: baseUrl,
    );
    expect(
      message,
      startsWith('Too many requests. The server asked to wait 20s'),
    );
    expect(message, endsWith('(request id: req_123)'));
  });
}
