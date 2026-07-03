import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/services/feedback_submission_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeedbackSubmissionService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('feedback_upload_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'posts gzipped feedback and the session log to the endpoint',
      () async {
        final logFile = File('${tempDir.path}/conversation-1.jsonl');
        await logFile.writeAsString('{"operation":"createChatCompletion"}\n');
        final requests = <http.Request>[];
        final service = FeedbackSubmissionService(
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(
              '{"objectKey":"feedback/2026/07/02/feedback-id.json"}',
              200,
            );
          }),
          clock: () => DateTime.utc(2026, 7, 2, 3, 4, 5),
          idFactory: () => 'feedback-id',
        );

        final result = await service.submit(
          FeedbackSubmissionInput(
            endpointUrl: 'https://feedback.example.com/caverno',
            authToken: '',
            feedbackText: 'The model ignored the test failure.',
            sessionLogFile: logFile,
            context: const LlmSessionLogContext(
              workspaceMode: WorkspaceMode.coding,
              sessionId: 'conversation/1',
              sessionTitle: 'Broken test run',
              conversationId: 'conversation/1',
            ),
            conversationMessageCount: 3,
          ),
        );

        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://feedback.example.com/caverno');
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['content-encoding'], 'gzip');
        expect(request.headers['x-caverno-feedback-id'], 'feedback-id');
        expect(request.headers, isNot(contains('x-caverno-feedback-token')));

        final payload =
            jsonDecode(utf8.decode(gzip.decode(request.bodyBytes)))
                as Map<String, dynamic>;
        expect(payload['schemaName'], 'caverno_feedback_submission');
        expect(payload['submissionId'], 'feedback-id');
        expect(
          payload['feedback']['text'],
          'The model ignored the test failure.',
        );
        expect(payload['context']['workspaceMode'], 'coding');
        expect(payload['conversation']['messageCount'], 3);
        expect(
          payload['sessionLog']['content'],
          '{"operation":"createChatCompletion"}\n',
        );
        expect(result.objectKey, 'feedback/2026/07/02/feedback-id.json');
        expect(result.payloadBytes, greaterThan(0));
        expect(result.submittedBytes, greaterThan(0));
        expect(result.sessionLogBytes, greaterThan(0));
      },
    );

    test('sends the configured feedback auth token header', () async {
      final logFile = File('${tempDir.path}/conversation-1.jsonl');
      await logFile.writeAsString('{"operation":"createChatCompletion"}\n');
      final requests = <http.Request>[];
      final service = FeedbackSubmissionService(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"objectKey":"feedback/2026/07/02/feedback-id.json"}',
            200,
          );
        }),
        clock: () => DateTime.utc(2026, 7, 2, 3, 4, 5),
        idFactory: () => 'feedback-id',
      );

      await service.submit(
        FeedbackSubmissionInput(
          endpointUrl: 'https://feedback.example.com/caverno',
          authToken: ' release-token ',
          feedbackText: 'The model ignored the test failure.',
          sessionLogFile: logFile,
          context: const LlmSessionLogContext(
            workspaceMode: WorkspaceMode.coding,
            sessionId: 'conversation/1',
            sessionTitle: 'Broken test run',
            conversationId: 'conversation/1',
          ),
          conversationMessageCount: 3,
        ),
      );

      expect(
        requests.single.headers['x-caverno-feedback-token'],
        'release-token',
      );
    });

    test(
      'redacts secrets from feedback text and session log payloads',
      () async {
        final logFile = File('${tempDir.path}/conversation-1.jsonl');
        await logFile.writeAsString(
          [
            jsonEncode({
              'operation': 'createChatCompletion',
              'request': {
                'apiKey': 'sk-abcdefghijklmnopqrstuvwxyz123456',
                'messages': [
                  {
                    'content':
                        'Authorization: Bearer plain-secret-token and '
                        'https://user:pass@example.com/path?token=secret-token',
                  },
                ],
              },
              'response': {
                'content': 'GitHub token ghp_abcdefghijklmnopqrstuvwxyz123456',
              },
            }),
            'TOKEN=secret-token',
          ].join('\n'),
        );
        await logFile.writeAsString('\n', mode: FileMode.append);
        final requests = <http.Request>[];
        final service = FeedbackSubmissionService(
          client: MockClient((request) async {
            requests.add(request);
            return http.Response('{"objectKey":"feedback/redacted.json"}', 200);
          }),
          clock: () => DateTime.utc(2026, 7, 2, 3, 4, 5),
          idFactory: () => 'feedback-id',
        );

        await service.submit(
          FeedbackSubmissionInput(
            endpointUrl: 'https://feedback.example.com/caverno',
            authToken: '',
            feedbackText:
                'The issue mentions sk-abcdefghijklmnopqrstuvwxyz123456.',
            sessionLogFile: logFile,
            context: const LlmSessionLogContext(
              workspaceMode: WorkspaceMode.coding,
              sessionId: 'conversation/1',
              sessionTitle: 'Bearer title-secret-token',
              conversationId: 'conversation/1',
            ),
            conversationMessageCount: 3,
          ),
        );

        final payload =
            jsonDecode(utf8.decode(gzip.decode(requests.single.bodyBytes)))
                as Map<String, dynamic>;
        final encodedPayload = jsonEncode(payload);
        expect(encodedPayload, isNot(contains('plain-secret-token')));
        expect(encodedPayload, isNot(contains('secret-token')));
        expect(encodedPayload, isNot(contains('user:pass')));
        expect(
          encodedPayload,
          isNot(contains('ghp_abcdefghijklmnopqrstuvwxyz')),
        );
        expect(
          encodedPayload,
          isNot(contains('sk-abcdefghijklmnopqrstuvwxyz')),
        );
        expect(
          payload['feedback']['text'],
          'The issue mentions sk-[redacted].',
        );
        expect(payload['context']['sessionTitle'], 'Bearer [redacted]');
        expect(payload['sessionLog']['content'], contains('[redacted]'));
        expect(
          payload['sessionLog']['content'],
          contains('[redacted-github-token]'),
        );
      },
    );

    test('rejects non-HTTPS endpoints outside loopback', () async {
      final logFile = File('${tempDir.path}/conversation-1.jsonl');
      await logFile.writeAsString('{}\n');
      final service = FeedbackSubmissionService(
        client: MockClient((request) async => http.Response('', 200)),
        clock: () => DateTime.utc(2026, 7, 2),
        idFactory: () => 'feedback-id',
      );

      await expectLater(
        service.submit(
          FeedbackSubmissionInput(
            endpointUrl: 'http://feedback.example.com/caverno',
            authToken: '',
            feedbackText: 'Bad response',
            sessionLogFile: logFile,
            context: const LlmSessionLogContext(
              workspaceMode: WorkspaceMode.chat,
              sessionId: 'conversation-1',
            ),
            conversationMessageCount: 1,
          ),
        ),
        throwsA(isA<FeedbackSubmissionException>()),
      );
    });
  });
}
