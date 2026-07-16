import 'dart:convert';

import '../../chat/data/repositories/conversation_repository_api.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/message.dart';
import '../presentation/caverno_cli_redactor.dart';
import '../presentation/caverno_terminal_presenter.dart';
import 'caverno_cli_arguments.dart';
import 'caverno_cli_contract.dart';

final class CavernoConversationQuery {
  CavernoConversationQuery({
    required ConversationRepositoryApi repository,
    required CavernoTerminalOutputPort output,
    CavernoCliRedactor? redactor,
    DateTime Function()? now,
  }) : _repository = repository,
       _output = output,
       _redactor = redactor ?? CavernoCliRedactor(),
       _now = now ?? DateTime.now;

  final ConversationRepositoryApi _repository;
  final CavernoTerminalOutputPort _output;
  final CavernoCliRedactor _redactor;
  final DateTime Function() _now;

  int run(CavernoCliInvocation invocation) {
    return switch (invocation.action) {
      CavernoCliInvocationAction.conversationList => _list(invocation),
      CavernoCliInvocationAction.conversationShow => _show(invocation),
      _ => throw ArgumentError.value(
        invocation.action,
        'invocation.action',
        'Expected a read-only conversation action.',
      ),
    };
  }

  int _list(CavernoCliInvocation invocation) {
    final conversations = _repository
        .getAll()
        .take(invocation.conversationLimit)
        .toList(growable: false);
    if (invocation.isJson) {
      _writeJsonEvent(
        type: 'conversation_list',
        payload: <String, Object?>{
          'count': conversations.length,
          'limit': invocation.conversationLimit,
          'conversations': conversations
              .map(_conversationSummary)
              .toList(growable: false),
        },
      );
      return CavernoCliExitCode.success;
    }

    if (conversations.isEmpty) {
      _output.writeStdout('No conversations found.\n');
      return CavernoCliExitCode.success;
    }
    final buffer = StringBuffer('ID\tUPDATED\tMODE\tMESSAGES\tTITLE\n');
    for (final conversation in conversations) {
      buffer
        ..write(conversation.id)
        ..write('\t')
        ..write(_timestamp(conversation.updatedAt))
        ..write('\t')
        ..write(conversation.workspaceMode.name)
        ..write('\t')
        ..write(conversation.messages.length)
        ..write('\t')
        ..writeln(_singleLine(conversation.title));
    }
    _output.writeStdout(_redactor.redact(buffer.toString()));
    return CavernoCliExitCode.success;
  }

  int _show(CavernoCliInvocation invocation) {
    final conversationId = invocation.conversationId!;
    final conversation = _repository.getById(conversationId);
    if (conversation == null) {
      throw CavernoCliFailure(
        code: 'conversation_not_found',
        message: 'Conversation not found: $conversationId',
        exitCode: CavernoCliExitCode.input,
      );
    }
    if (invocation.isJson) {
      _writeJsonEvent(
        type: 'conversation_detail',
        conversationId: conversation.id,
        payload: <String, Object?>{
          'conversation': _conversationDetail(conversation),
        },
      );
      return CavernoCliExitCode.success;
    }

    final buffer = StringBuffer()
      ..writeln('Conversation: ${conversation.id}')
      ..writeln('Title: ${_singleLine(conversation.title)}')
      ..writeln('Workspace: ${conversation.workspaceMode.name}')
      ..writeln('Created: ${_timestamp(conversation.createdAt)}')
      ..writeln('Updated: ${_timestamp(conversation.updatedAt)}')
      ..writeln('Messages: ${conversation.messages.length}');
    if (conversation.projectId.trim().isNotEmpty) {
      buffer.writeln('Project: ${conversation.projectId.trim()}');
    }
    for (final message in conversation.messages) {
      buffer
        ..writeln()
        ..writeln('[${_timestamp(message.timestamp)}] ${message.role.name}')
        ..writeln(message.content);
    }
    _output.writeStdout(_redactor.redact(buffer.toString()));
    return CavernoCliExitCode.success;
  }

  Map<String, Object?> _conversationSummary(Conversation conversation) =>
      <String, Object?>{
        'id': conversation.id,
        'title': _singleLine(conversation.title),
        'workspaceMode': conversation.workspaceMode.name,
        'messageCount': conversation.messages.length,
        'createdAt': _timestamp(conversation.createdAt),
        'updatedAt': _timestamp(conversation.updatedAt),
        if (conversation.projectId.trim().isNotEmpty)
          'projectId': conversation.projectId.trim(),
      };

  Map<String, Object?> _conversationDetail(Conversation conversation) =>
      <String, Object?>{
        ..._conversationSummary(conversation),
        'executionMode': conversation.executionMode.name,
        'workflowStage': conversation.workflowStage.name,
        'messages': conversation.messages
            .map(_messageDetail)
            .toList(growable: false),
      };

  Map<String, Object?> _messageDetail(Message message) => <String, Object?>{
    'id': message.id,
    'role': message.role.name,
    'timestamp': _timestamp(message.timestamp),
    'content': message.content,
  };

  void _writeJsonEvent({
    required String type,
    required Map<String, Object?> payload,
    String? conversationId,
  }) {
    final event = <String, Object?>{
      'schema': 'caverno_cli_event',
      'schemaVersion': 1,
      'sequence': 1,
      'timestamp': _timestamp(_now()),
      'type': type,
      'conversationId': ?conversationId,
      'payload': payload,
    };
    _output.writeStdout('${jsonEncode(_redactor.redactJson(event))}\n');
  }

  String _timestamp(DateTime value) => value.toUtc().toIso8601String();

  String _singleLine(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
}
