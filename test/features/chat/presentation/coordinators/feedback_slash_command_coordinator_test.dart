import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/feedback_submission_service.dart';
import 'package:caverno/features/chat/presentation/coordinators/feedback_slash_command_coordinator.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 7, 17, 15);

class _FakeLogStore extends LlmSessionLogStore {
  _FakeLogStore(this.file)
    : super(rootDirectoryProvider: () async => Directory.systemTemp);

  final File file;
  final contexts = <LlmSessionLogContext>[];

  @override
  Future<File> fileForContext(
    LlmSessionLogContext context, {
    bool create = true,
  }) async {
    contexts.add(context);
    return file;
  }
}

class _FakeFeedbackClient implements FeedbackSubmissionClient {
  final inputs = <FeedbackSubmissionInput>[];
  Object? error;

  @override
  Future<FeedbackSubmissionResult> submit(FeedbackSubmissionInput input) async {
    inputs.add(input);
    if (error case final error?) throw error;
    return FeedbackSubmissionResult(
      submissionId: 'submission-1',
      objectKey: 'feedback/result.json',
      uri: Uri.parse('https://feedback.example.com/result.json'),
      payloadBytes: 20,
      submittedBytes: 15,
      sessionLogBytes: 10,
    );
  }
}

class _Harness {
  _Harness()
    : store = _FakeLogStore(File('/tmp/caverno-feedback-test.jsonl')),
      client = _FakeFeedbackClient() {
    coordinator = FeedbackSlashCommandCoordinator(
      sessionLogStore: store,
      feedbackSubmissionClient: client,
      text: _text,
    );
  }

  final _FakeLogStore store;
  final _FakeFeedbackClient client;
  late final FeedbackSlashCommandCoordinator coordinator;
}

void main() {
  test('rejects feedback when upload is disabled', () async {
    final harness = _Harness();

    final result = await harness.coordinator.handle(
      settings: _settings(feedbackUploadEnabled: false),
      currentConversation: _conversation(),
      feedbackText: 'Issue',
    );

    _expectRejected(result, 'chat.slash_feedback_disabled');
    expect(harness.store.contexts, isEmpty);
    expect(harness.client.inputs, isEmpty);
  });

  test('rejects feedback when endpoint is not configured', () async {
    final harness = _Harness();

    final result = await harness.coordinator.handle(
      settings: _settings(endpointUrl: ''),
      currentConversation: _conversation(),
      feedbackText: 'Issue',
    );

    _expectRejected(result, 'chat.slash_feedback_not_configured');
  });

  test('rejects feedback without a current conversation', () async {
    final harness = _Harness();

    final result = await harness.coordinator.handle(
      settings: _settings(),
      currentConversation: null,
      feedbackText: 'Issue',
    );

    _expectRejected(result, 'chat.slash_feedback_no_session');
  });

  test('rejects feedback when logging is unavailable', () async {
    final harness = _Harness();

    final result = await harness.coordinator.handle(
      settings: _settings(enableLogs: false),
      currentConversation: _conversation(),
      feedbackText: 'Issue',
    );

    _expectRejected(result, 'chat.slash_feedback_requires_logs');
  });

  test(
    'submits the resolved conversation log and reports its object key',
    () async {
      final harness = _Harness();
      final conversation = _conversation();

      final result = await harness.coordinator.handle(
        settings: _settings(),
        currentConversation: conversation,
        feedbackText: 'The model missed the failure.',
      );

      expect(result.clearInput, isTrue);
      expect(
        result.feedbackMessage,
        'chat.slash_feedback_sent(key=feedback/result.json)',
      );
      expect(harness.store.contexts, hasLength(1));
      final context = harness.store.contexts.single;
      expect(context.workspaceMode, WorkspaceMode.coding);
      expect(context.sessionId, conversation.id);
      expect(context.sessionTitle, conversation.title);
      expect(context.conversationId, conversation.id);
      expect(context.phase, 'feedback');
      final input = harness.client.inputs.single;
      expect(input.endpointUrl, 'https://feedback.example.com/upload');
      expect(input.authToken, 'secret');
      expect(input.feedbackText, 'The model missed the failure.');
      expect(input.sessionLogFile.path, harness.store.file.path);
      expect(input.conversationMessageCount, 1);
    },
  );

  test('maps a missing-log exception to dedicated feedback', () async {
    final harness = _Harness();
    harness.client.error = const FeedbackSubmissionException(
      FeedbackSubmissionService.missingSessionLogMessage,
    );

    final result = await harness.coordinator.handle(
      settings: _settings(),
      currentConversation: _conversation(),
      feedbackText: 'Issue',
    );

    _expectRejected(result, 'chat.slash_feedback_no_session_log');
  });

  test('maps other typed failures to generic failure feedback', () async {
    final harness = _Harness();
    harness.client.error = const FeedbackSubmissionException('Upload failed');

    final result = await harness.coordinator.handle(
      settings: _settings(),
      currentConversation: _conversation(),
      feedbackText: 'Issue',
    );

    _expectRejected(result, 'chat.slash_feedback_failed(error=Upload failed)');
  });

  test('maps unexpected failures to generic failure feedback', () async {
    final harness = _Harness();
    harness.client.error = StateError('socket closed');

    final result = await harness.coordinator.handle(
      settings: _settings(),
      currentConversation: _conversation(),
      feedbackText: 'Issue',
    );

    expect(result.clearInput, isFalse);
    expect(result.feedbackMessage, contains('socket closed'));
    expect(result.feedbackMessage, startsWith('chat.slash_feedback_failed'));
  });
}

AppSettings _settings({
  bool feedbackUploadEnabled = true,
  bool enableLogs = true,
  String endpointUrl = 'https://feedback.example.com/upload',
}) => AppSettings.defaults().copyWith(
  feedbackUploadEnabled: feedbackUploadEnabled,
  enableLlmSessionLogs: enableLogs,
  feedbackEndpointUrl: endpointUrl,
  feedbackEndpointAuthToken: 'secret',
  demoMode: false,
);

Conversation _conversation() => Conversation(
  id: 'conversation-1',
  title: 'Feedback session',
  messages: [
    Message(
      id: 'message-1',
      content: 'Hello',
      role: MessageRole.user,
      timestamp: _now,
    ),
  ],
  createdAt: _now,
  updatedAt: _now,
  workspaceMode: WorkspaceMode.coding,
  projectId: 'project-1',
);

void _expectRejected(dynamic result, String feedback) {
  expect(result.clearInput, isFalse);
  expect(result.feedbackMessage, feedback);
}

String _text(String key, {Map<String, String>? namedArgs}) {
  if (namedArgs == null || namedArgs.isEmpty) return key;
  final values = namedArgs.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return '$key(${values.map((entry) => '${entry.key}=${entry.value}').join(',')})';
}
