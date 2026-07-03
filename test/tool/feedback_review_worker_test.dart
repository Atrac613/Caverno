import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/feedback_review_worker.dart';

void main() {
  group('feedback review worker', () {
    test('processes a sample SQS review job without AWS calls', () async {
      final directory = Directory.systemTemp.createTempSync(
        'feedback-review-worker-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      final payloadFile = File('${directory.path}/payload.json')
        ..writeAsStringSync(
          jsonEncode({
            'schemaName': 'caverno_feedback_submission',
            'submissionId': 'feedback-1',
            'feedback': {'text': 'The model ignored the error.'},
            'context': {'workspaceMode': 'chat'},
            'conversation': {'title': 'Debug thread'},
            'sessionLog': {'content': 'request\\nresponse\\n'},
          }),
        );
      final messageFile = File('${directory.path}/message.json')
        ..writeAsStringSync(
          jsonEncode({
            'schemaName': 'caverno_feedback_review_job',
            'schemaVersion': 1,
            'submissionId': 'feedback-1',
            'payload': {
              'bucket': 'feedback-bucket',
              'key': 'feedback/2026/07/03/feedback-1.json',
              'localPath': payloadFile.path,
            },
            'repo': {
              'owner': 'Atrac613',
              'name': 'Caverno',
              'defaultBranch': 'main',
            },
            'createdAt': '2026-07-03T00:00:00Z',
          }),
        );

      final result = await runFeedbackReviewWorker(
        options: FeedbackReviewWorkerOptions.parse([
          '--sample-message',
          messageFile.path,
          '--jobs-dir',
          '${directory.path}/jobs',
        ]),
        processRunner: _failingProcessRunner,
      );

      expect(result.receivedCount, 1);
      expect(result.failedCount, 0);
      expect(result.jobs.single.status, 'auto_fix_pending');
      expect(result.jobs.single.classification, 'autoFixCandidate');

      final jobDir = Directory('${directory.path}/jobs/feedback-1');
      expect(File('${jobDir.path}/payload.json').existsSync(), isTrue);
      expect(File('${jobDir.path}/classification.json').existsSync(), isTrue);
      final prompt = File('${jobDir.path}/codex_prompt.md').readAsStringSync();
      expect(prompt, contains('The model ignored the error.'));
      expect(prompt, contains('Do not commit, push, or create a pull request'));
    });

    test('classifies positive feedback as no action', () {
      final classification = FeedbackReviewClassifier.classify({
        'feedback': {'text': 'Thanks, this works well.'},
      });

      expect(classification.kind, FeedbackReviewClassificationKind.noAction);
      expect(classification.statusWhenCodexDisabled, 'no_action');
    });

    test('skips Codex for redelivered auto-fix jobs', () async {
      final directory = Directory.systemTemp.createTempSync(
        'feedback-review-worker-redelivery-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      final payloadFile = File('${directory.path}/payload.json')
        ..writeAsStringSync(
          jsonEncode({
            'schemaName': 'caverno_feedback_submission',
            'submissionId': 'feedback-2',
            'feedback': {'text': 'Bug: the command failed with an error.'},
            'context': {'workspaceMode': 'chat'},
            'conversation': {'title': 'Debug thread'},
            'sessionLog': {'content': 'request\\nresponse\\n'},
          }),
        );
      final reviewJob = {
        'schemaName': 'caverno_feedback_review_job',
        'schemaVersion': 1,
        'submissionId': 'feedback-2',
        'payload': {
          'bucket': 'feedback-bucket',
          'key': 'feedback/2026/07/03/feedback-2.json',
          'localPath': payloadFile.path,
        },
        'repo': {
          'owner': 'Atrac613',
          'name': 'Caverno',
          'defaultBranch': 'main',
        },
        'createdAt': '2026-07-03T00:00:00Z',
      };
      final calls = <List<String>>[];

      final result = await runFeedbackReviewWorker(
        options: FeedbackReviewWorkerOptions.parse([
          '--queue-url',
          'https://sqs.example.com/123/review',
          '--jobs-dir',
          '${directory.path}/jobs',
          '--enable-codex',
          '--repo-root',
          directory.path,
        ]),
        processRunner: (executable, arguments, {workingDirectory}) async {
          calls.add([executable, ...arguments]);
          if (executable != 'aws') {
            throw StateError('Unexpected process call: $executable');
          }
          if (arguments.length >= 2 &&
              arguments[0] == 'sqs' &&
              arguments[1] == 'receive-message') {
            return ProcessResult(
              0,
              0,
              jsonEncode({
                'Messages': [
                  {
                    'Body': jsonEncode(reviewJob),
                    'ReceiptHandle': 'receipt-1',
                    'Attributes': {'ApproximateReceiveCount': '2'},
                  },
                ],
              }),
              '',
            );
          }
          if (arguments.length >= 2 &&
              arguments[0] == 'sqs' &&
              arguments[1] == 'delete-message') {
            return ProcessResult(0, 0, '', '');
          }
          throw StateError('Unexpected aws call: ${arguments.join(' ')}');
        },
      );

      expect(result.failedCount, 0);
      expect(result.jobs.single.status, 'needs_manual_review');
      expect(result.jobs.single.classification, 'autoFixCandidate');
      expect(result.jobs.single.error, contains('ApproximateReceiveCount=2'));
      expect(
        calls.where(
          (call) =>
              call.length >= 3 &&
              call[0] == 'aws' &&
              call[1] == 'sqs' &&
              call[2] == 'delete-message',
        ),
        isNotEmpty,
      );

      final jobDir = Directory('${directory.path}/jobs/feedback-2');
      final retryDecision = File(
        '${jobDir.path}/retry_decision.json',
      ).readAsStringSync();
      expect(retryDecision, contains('manual_review'));
    });
  });
}

Future<ProcessResult> _failingProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  throw StateError(
    'Unexpected process call: $executable ${arguments.join(' ')}',
  );
}
