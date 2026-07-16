import 'dart:convert';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/terminal/application/caverno_cli_arguments.dart';
import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/application/caverno_conversation_query.dart';
import 'package:caverno/features/terminal/presentation/caverno_cli_redactor.dart';
import 'package:caverno/features/terminal/presentation/caverno_terminal_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final older = _conversation(
    id: 'older-id',
    title: 'Older conversation',
    updatedAt: DateTime.utc(2026, 7, 15),
  );
  final newer = _conversation(
    id: 'newer-id',
    title: 'Newer\nsecret conversation',
    updatedAt: DateTime.utc(2026, 7, 16),
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-1',
    messages: <Message>[
      Message(
        id: 'message-1',
        content: 'Use secret safely.',
        role: MessageRole.user,
        timestamp: DateTime.utc(2026, 7, 16, 1),
        imageBase64: 'binary-image-data',
        originalImagePath: '/private/image.png',
        responseMetrics: const MessageResponseMetrics(totalTokens: 42),
      ),
    ],
  );

  test('lists recent conversations with a limit and redaction', () {
    final output = _RecordingOutput();
    final query = CavernoConversationQuery(
      repository: _FakeConversationRepository(<Conversation>[newer, older]),
      output: output,
      redactor: CavernoCliRedactor(secrets: const ['secret']),
    );

    final exitCode = query.run(
      CavernoCliInvocation.parse(const [
        'conversations',
        'list',
        '--limit',
        '1',
      ]),
    );

    expect(exitCode, CavernoCliExitCode.success);
    expect(output.stdout, contains('newer-id'));
    expect(output.stdout, isNot(contains('older-id')));
    expect(output.stdout, contains('Newer [REDACTED] conversation'));
    expect(output.stdout, isNot(contains('\nsecret')));
    expect(output.stderr, isEmpty);
  });

  test('reports an explicit empty human list', () {
    final output = _RecordingOutput();
    final query = CavernoConversationQuery(
      repository: _FakeConversationRepository(const <Conversation>[]),
      output: output,
    );

    query.run(CavernoCliInvocation.parse(const ['conversations', 'list']));

    expect(output.stdout, 'No conversations found.\n');
  });

  test('shows text messages without attachment or response internals', () {
    final output = _RecordingOutput();
    final query = CavernoConversationQuery(
      repository: _FakeConversationRepository(<Conversation>[newer]),
      output: output,
      redactor: CavernoCliRedactor(secrets: const ['secret']),
    );

    query.run(
      CavernoCliInvocation.parse(const [
        'conversations',
        'show',
        'newer-id',
        '--json',
      ]),
    );

    final event = jsonDecode(output.stdout) as Map<String, dynamic>;
    expect(event['schema'], 'caverno_cli_event');
    expect(event['schemaVersion'], 1);
    expect(event['sequence'], 1);
    expect(event['type'], 'conversation_detail');
    expect(event['conversationId'], 'newer-id');
    final payload = event['payload'] as Map<String, dynamic>;
    final conversation = payload['conversation'] as Map<String, dynamic>;
    final messages = conversation['messages'] as List<dynamic>;
    final message = messages.single as Map<String, dynamic>;
    expect(message['content'], 'Use [REDACTED] safely.');
    expect(message.keys, <String>{'id', 'role', 'timestamp', 'content'});
    expect(output.stdout, isNot(contains('binary-image-data')));
    expect(output.stdout, isNot(contains('/private/image.png')));
    expect(output.stdout, isNot(contains('totalTokens')));
  });

  test('emits one stable JSON list event', () {
    final output = _RecordingOutput();
    final query = CavernoConversationQuery(
      repository: _FakeConversationRepository(<Conversation>[newer, older]),
      output: output,
      now: () => DateTime.utc(2026, 7, 16, 2),
    );

    query.run(
      CavernoCliInvocation.parse(const ['conversations', 'list', '--json']),
    );

    final lines = const LineSplitter()
        .convert(output.stdout)
        .where((line) => line.isNotEmpty)
        .toList();
    expect(lines, hasLength(1));
    final event = jsonDecode(lines.single) as Map<String, dynamic>;
    expect(event['type'], 'conversation_list');
    expect(event['timestamp'], '2026-07-16T02:00:00.000Z');
    final payload = event['payload'] as Map<String, dynamic>;
    expect(payload['count'], 2);
    expect(payload['limit'], 20);
  });

  test('fails with an input error when an exact ID is absent', () {
    final query = CavernoConversationQuery(
      repository: _FakeConversationRepository(const <Conversation>[]),
      output: _RecordingOutput(),
    );

    expect(
      () => query.run(
        CavernoCliInvocation.parse(const [
          'conversations',
          'show',
          'missing-id',
        ]),
      ),
      throwsA(
        isA<CavernoCliFailure>()
            .having((error) => error.code, 'code', 'conversation_not_found')
            .having(
              (error) => error.exitCode,
              'exitCode',
              CavernoCliExitCode.input,
            ),
      ),
    );
  });
}

Conversation _conversation({
  required String id,
  required String title,
  required DateTime updatedAt,
  WorkspaceMode workspaceMode = WorkspaceMode.chat,
  String projectId = '',
  List<Message> messages = const <Message>[],
}) => Conversation(
  id: id,
  title: title,
  messages: messages,
  createdAt: updatedAt.subtract(const Duration(hours: 1)),
  updatedAt: updatedAt,
  workspaceMode: workspaceMode,
  projectId: projectId,
);

final class _FakeConversationRepository implements ConversationRepositoryApi {
  _FakeConversationRepository(this.conversations);

  final List<Conversation> conversations;

  @override
  List<Conversation> getAll() => conversations;

  @override
  Conversation? getById(String id) {
    for (final conversation in conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  @override
  Future<Conversation?> refresh(String id) async => getById(id);

  @override
  Future<void> delete(String id) => throw UnimplementedError();

  @override
  Future<void> deleteAll() => throw UnimplementedError();

  @override
  Future<void> save(Conversation conversation) => throw UnimplementedError();

  @override
  Future<List<Conversation>> search(String query) => throw UnimplementedError();
}

final class _RecordingOutput implements CavernoTerminalOutputPort {
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();

  String get stdout => stdoutBuffer.toString();
  String get stderr => stderrBuffer.toString();

  @override
  void writeStdout(String value) => stdoutBuffer.write(value);

  @override
  void writeStderr(String value) => stderrBuffer.write(value);
}
