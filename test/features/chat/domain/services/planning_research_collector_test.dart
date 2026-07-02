import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/planning_research_collector.dart';

void main() {
  group('PlanningResearchCollector', () {
    test(
      'builds phrase and keyword queries from conversation context',
      () async {
        final runner = _RecordingPlanningResearchToolRunner();
        final collector = PlanningResearchCollector(runTool: runner.call);

        await collector.collect(
          currentConversation: _conversation(
            userMessage: 'Need planning state support',
          ),
        );

        final searchQueries = runner.calls
            .where((call) => call.name == 'search_files')
            .map((call) => call.arguments['query'])
            .toList(growable: false);
        expect(searchQueries, ['need planning', 'planning state']);

        final recursiveFindPatterns = runner.calls
            .where(
              (call) =>
                  call.name == 'find_files' &&
                  call.arguments['recursive'] == true,
            )
            .map((call) => call.arguments['pattern'])
            .toList(growable: false);
        expect(recursiveFindPatterns, ['*planning*']);
      },
    );

    test('synthesizes planning risks when research finds no context', () async {
      final runner = _RecordingPlanningResearchToolRunner();
      final collector = PlanningResearchCollector(runTool: runner.call);

      final context = await collector.collect(
        currentConversation: _conversation(
          userMessage: 'Need planning state support',
        ),
      );

      expect(
        context.risks,
        contains(
          'The selected project root looked empty during planning, so the first slice may need a new scaffold.',
        ),
      );
      expect(
        context.risks,
        contains(
          'No existing files matched the main request keywords, so the plan may rely on net-new files or inferred architecture.',
        ),
      );
      expect(
        context.risks,
        contains(
          'No common manifest or README was found at the project root, so setup and validation commands may need manual verification.',
        ),
      );
    });

    test('extracts highlights from candidate file content', () async {
      final runner = _RecordingPlanningResearchToolRunner(
        handler: (toolCall) {
          if (toolCall.name == 'list_directory') {
            return _jsonResult(toolCall.name, {
              'entries': ['[file] pubspec.yaml (1 KB)'],
            });
          }
          if (toolCall.name == 'find_files' &&
              toolCall.arguments['pattern'] == 'pubspec.yaml') {
            return _jsonResult(toolCall.name, {
              'matches': ['pubspec.yaml'],
            });
          }
          if (toolCall.name == 'read_file') {
            return _jsonResult(toolCall.name, {
              'content':
                  'name: caverno\n'
                  'Planning state service persists per thread.\n'
                  'class ChatNotifier extends Notifier<ChatState> {}\n',
            });
          }
          return null;
        },
      );
      final collector = PlanningResearchCollector(runTool: runner.call);

      final context = await collector.collect(
        currentConversation: _conversation(
          userMessage: 'Need planning state support',
        ),
      );

      expect(context.fileNotes, hasLength(1));
      expect(context.fileNotes.single.path, 'pubspec.yaml');
      expect(
        context.fileNotes.single.highlights,
        contains('Planning state service persists per thread.'),
      );
    });

    test('degrades gracefully when a tool returns non-JSON text', () async {
      final runner = _RecordingPlanningResearchToolRunner(
        handler: (toolCall) {
          if (toolCall.name == 'list_directory') {
            return const McpToolResult(
              toolName: 'list_directory',
              result: 'plain text is not JSON',
              isSuccess: true,
            );
          }
          if (toolCall.name == 'find_files' &&
              toolCall.arguments['pattern'] == 'pubspec.yaml') {
            return _jsonResult(toolCall.name, {
              'matches': ['pubspec.yaml'],
            });
          }
          return null;
        },
      );
      final collector = PlanningResearchCollector(runTool: runner.call);

      final context = await collector.collect(
        currentConversation: _conversation(
          userMessage: 'Need planning state support',
        ),
      );

      expect(context.rootEntries, isEmpty);
      expect(context.keyFiles, ['pubspec.yaml']);
    });
  });
}

typedef _PlanningResearchToolHandler =
    McpToolResult? Function(ToolCallInfo toolCall);

class _RecordingPlanningResearchToolRunner {
  _RecordingPlanningResearchToolRunner({_PlanningResearchToolHandler? handler})
    : _handler = handler;

  final _PlanningResearchToolHandler? _handler;
  final List<ToolCallInfo> calls = [];

  Future<McpToolResult> call(ToolCallInfo toolCall) async {
    calls.add(toolCall);
    final handled = _handler?.call(toolCall);
    if (handled != null) {
      return handled;
    }
    return switch (toolCall.name) {
      'list_directory' => _jsonResult(toolCall.name, {'entries': []}),
      'find_files' => _jsonResult(toolCall.name, {'matches': []}),
      'search_files' => _jsonResult(toolCall.name, {'matches': []}),
      'read_file' => _jsonResult(toolCall.name, {'content': ''}),
      _ => _jsonResult(toolCall.name, const <String, dynamic>{}),
    };
  }
}

Conversation _conversation({required String userMessage}) {
  final now = DateTime(2026);
  return Conversation(
    id: 'conversation-1',
    title: 'Planning',
    messages: [
      Message(
        id: 'message-1',
        content: userMessage,
        role: MessageRole.user,
        timestamp: now,
      ),
    ],
    createdAt: now,
    updatedAt: now,
    workflowSpec: const ConversationWorkflowSpec(
      goal: 'Add explicit planning state',
      acceptanceCriteria: ['Planning is stored per thread'],
    ),
  );
}

McpToolResult _jsonResult(String toolName, Map<String, dynamic> payload) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode(payload),
    isSuccess: true,
  );
}
