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
