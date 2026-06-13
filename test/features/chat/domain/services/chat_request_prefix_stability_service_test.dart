import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/chat_request_prefix_stability_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 6, 13, 10);

  Message message({
    required String id,
    required MessageRole role,
    required String content,
  }) {
    return Message(id: id, role: role, content: content, timestamp: now);
  }

  const readFileTool = {
    'type': 'function',
    'function': {
      'name': 'read_file',
      'description': 'Read a file.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      },
    },
  };

  const readFileToolWithReorderedKeys = {
    'function': {
      'parameters': {
        'required': ['path'],
        'properties': {
          'path': {'type': 'string'},
        },
        'type': 'object',
      },
      'description': 'Read a file.',
      'name': 'read_file',
    },
    'type': 'function',
  };

  const writeFileTool = {
    'type': 'function',
    'function': {
      'name': 'write_file',
      'description': 'Write a file.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
        },
        'required': ['path', 'content'],
      },
    },
  };

  test('builds identical prefixes across appended volatile tail messages', () {
    final initialMessages = [
      message(
        id: 'system-1',
        role: MessageRole.system,
        content: 'Stable coding system prompt.',
      ),
      message(id: 'user-1', role: MessageRole.user, content: 'Update the CLI.'),
    ];
    final followUpMessages = [
      ...initialMessages,
      message(
        id: 'assistant-1',
        role: MessageRole.assistant,
        content: 'I will inspect the file.',
      ),
      message(
        id: 'user-2',
        role: MessageRole.user,
        content: 'Tool result: main.py exists.',
      ),
    ];

    final stableMessageCount =
        ChatRequestPrefixStabilityService.commonLeadingPromptMessageCount(
          initialMessages,
          followUpMessages,
        );
    final initialPrefix =
        ChatRequestPrefixStabilityService.buildPromptPrefixJson(
          messages: initialMessages,
          tools: const [readFileTool],
          stableMessageCount: stableMessageCount,
        );
    final followUpPrefix =
        ChatRequestPrefixStabilityService.buildPromptPrefixJson(
          messages: followUpMessages,
          tools: const [readFileToolWithReorderedKeys],
          stableMessageCount: stableMessageCount,
        );

    expect(stableMessageCount, 2);
    expect(followUpPrefix, initialPrefix);
  });

  test('changes the prefix when the stable tool set changes', () {
    final messages = [
      message(
        id: 'system-1',
        role: MessageRole.system,
        content: 'Stable coding system prompt.',
      ),
      message(id: 'user-1', role: MessageRole.user, content: 'Update the CLI.'),
    ];

    final readPrefix = ChatRequestPrefixStabilityService.buildPromptPrefixJson(
      messages: messages,
      tools: const [readFileTool],
      stableMessageCount: messages.length,
    );
    final writePrefix = ChatRequestPrefixStabilityService.buildPromptPrefixJson(
      messages: messages,
      tools: const [readFileTool, writeFileTool],
      stableMessageCount: messages.length,
    );

    expect(writePrefix, isNot(readPrefix));
  });

  test('stops the common prefix before the first changed prompt message', () {
    final first = [
      message(
        id: 'system-1',
        role: MessageRole.system,
        content: 'Stable coding system prompt.',
      ),
      message(id: 'user-1', role: MessageRole.user, content: 'Update the CLI.'),
    ];
    final second = [
      first.first,
      message(
        id: 'user-1-changed',
        role: MessageRole.user,
        content: 'Update the server.',
      ),
    ];

    expect(
      ChatRequestPrefixStabilityService.commonLeadingPromptMessageCount(
        first,
        second,
      ),
      1,
    );
  });
}
