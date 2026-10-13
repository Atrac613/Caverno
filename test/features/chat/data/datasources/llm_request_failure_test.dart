import 'dart:async';
import 'dart:io';

import 'package:caverno/core/services/apple_foundation_models_platform_client.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_transport.dart';
import 'package:caverno/features/chat/data/datasources/llm_request_failure.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart' show HiveError;
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart';

LlmRequestFailureCode codeOf(Object error) =>
    LlmRequestFailure.from(error).code;

void main() {
  group('local storage is classified before the provider', () {
    test('a SQLite failure embedding 401 and a context phrase', () {
      final error = SqliteException(
        extendedResultCode: 14,
        message: 'unable to open database file',
        causingStatement:
            'INSERT INTO "messages" VALUES (\'HTTP 401 maximum context '
            'length exceeded\')',
      );
      final failure = LlmRequestFailure.from(error);
      expect(failure.code, LlmRequestFailureCode.localStorage);
      expect(failure.isContextOverflow, isFalse);
      expect(failure.runtimeClassification?.code, 'persistence_failed');
    });

    test('Hive and file system errors', () {
      expect(
        codeOf(HiveError('box closed')),
        LlmRequestFailureCode.localStorage,
      );
      expect(
        codeOf(const FileSystemException('write failed', '/tmp/x')),
        LlmRequestFailureCode.localStorage,
      );
    });
  });

  group('provider status codes', () {
    final cases = <int, LlmRequestFailureCode>{
      400: LlmRequestFailureCode.invalidRequest,
      401: LlmRequestFailureCode.auth,
      403: LlmRequestFailureCode.permissionDenied,
      404: LlmRequestFailureCode.notFound,
      408: LlmRequestFailureCode.timeout,
      422: LlmRequestFailureCode.invalidRequest,
      429: LlmRequestFailureCode.rateLimit,
      500: LlmRequestFailureCode.server,
      503: LlmRequestFailureCode.server,
    };
    for (final MapEntry(key: status, value: code) in cases.entries) {
      test('$status -> ${code.name}', () {
        final error = createApiException(
          statusCode: status,
          message: 'provider message',
        );
        final failure = LlmRequestFailure.from(error);
        expect(failure.code, code);
        expect(failure.statusCode, status);
      });
    }

    test('a 400 whose payload text contains 401 is not auth', () {
      expect(
        codeOf(
          const BadRequestException(
            message: 'bad field in {"created":1791424033401,"code":401}',
          ),
        ),
        LlmRequestFailureCode.invalidRequest,
      );
    });

    test('rate limit keeps retry-after and request id', () {
      final failure = LlmRequestFailure.from(
        const RateLimitException(
          message: 'slow down',
          requestId: 'req_1',
          retryAfter: Duration(seconds: 7),
        ),
      );
      expect(failure.code, LlmRequestFailureCode.rateLimit);
      expect(failure.retryAfter, const Duration(seconds: 7));
      expect(failure.requestId, 'req_1');
    });

    test('llama.cpp slot transport status', () {
      expect(
        codeOf(const SlotChatTransportException(statusCode: 401, body: '{}')),
        LlmRequestFailureCode.auth,
      );
    });
  });

  group('context overflow', () {
    test('OpenAI structured code', () {
      expect(
        codeOf(
          const BadRequestException(
            message: 'too large',
            code: 'context_length_exceeded',
          ),
        ),
        LlmRequestFailureCode.contextOverflow,
      );
    });

    test('provider message on any status', () {
      expect(
        codeOf(
          const InternalServerException(
            message: 'the request exceeds the maximum context length',
            statusCode: 500,
          ),
        ),
        LlmRequestFailureCode.contextOverflow,
      );
      expect(
        codeOf(
          const SlotChatTransportException(
            statusCode: 400,
            body: 'prompt too long for context window',
          ),
        ),
        LlmRequestFailureCode.contextOverflow,
      );
      expect(
        codeOf(const StreamException(message: 'context length exceeded')),
        LlmRequestFailureCode.contextOverflow,
      );
    });

    test('untyped error text keeps the compaction retry reachable', () {
      expect(
        LlmRequestFailure.from(
          Exception('maximum context length is 32768 tokens'),
        ).isContextOverflow,
        isTrue,
      );
    });
  });

  group('transport and response', () {
    test('timeouts', () {
      expect(
        codeOf(TimeoutException('no response')),
        LlmRequestFailureCode.timeout,
      );
      expect(
        codeOf(const RequestTimeoutException(message: 'slow')),
        LlmRequestFailureCode.timeout,
      );
    });

    test('connection failures', () {
      expect(
        codeOf(const SocketException('Failed host lookup')),
        LlmRequestFailureCode.transport,
      );
      expect(
        codeOf(const ConnectionException(message: 'refused')),
        LlmRequestFailureCode.transport,
      );
      expect(
        codeOf(http.ClientException('reset')),
        LlmRequestFailureCode.transport,
      );
      expect(
        codeOf(const StreamException(message: 'stream ended')),
        LlmRequestFailureCode.transport,
      );
    });

    test('unparseable responses', () {
      expect(
        codeOf(const ParseException(message: 'bad json')),
        LlmRequestFailureCode.invalidResponse,
      );
      expect(
        codeOf(const FormatException('Expected a JSON object response.')),
        LlmRequestFailureCode.invalidResponse,
      );
    });

    test('text-only input rejection', () {
      expect(
        codeOf(
          const BadRequestException(
            message: "Only 'text' content type is supported.",
          ),
        ),
        LlmRequestFailureCode.unsupportedInput,
      );
    });

    test('cancellation', () {
      expect(
        codeOf(const ChatCompletionStreamCancelledException()),
        LlmRequestFailureCode.cancelled,
      );
    });

    test('Apple Foundation Models', () {
      expect(
        codeOf(
          const AppleFoundationModelsException(
            'model not ready',
            code: 'foundation_models_unavailable',
          ),
        ),
        LlmRequestFailureCode.providerUnavailable,
      );
      expect(
        codeOf(
          const AppleFoundationModelsException('unsupportedLanguageOrLocale'),
        ),
        LlmRequestFailureCode.unsupportedLocale,
      );
    });

    test('an untyped error stays unknown', () {
      final failure = LlmRequestFailure.from('HTTP 401 unauthorized');
      expect(failure.code, LlmRequestFailureCode.unknown);
      expect(failure.runtimeClassification, isNull);
    });
  });
}
