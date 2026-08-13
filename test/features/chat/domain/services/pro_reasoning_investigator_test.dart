import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_investigator.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_models.dart';

void main() {
  const investigator = ProReasoningInvestigator();

  test(
    'filters mutation and external definitions from the research surface',
    () {
      final definitions = [
        _definition('read_file'),
        _definition('write_file'),
        _definition('web_search', external: true),
        <String, dynamic>{'type': 'function'},
      ];

      final filtered = investigator.readOnlyDefinitions(definitions);

      expect(filtered, hasLength(1));
      expect(
        (filtered.single['function'] as Map<String, dynamic>)['name'],
        'read_file',
      );
      expect(
        definitions,
        hasLength(4),
        reason: 'the source list is not mutated',
      );
    },
  );

  test(
    'dispatches only defined read-only calls and reports denials to the LLM',
    () async {
      final dataSource = _ScriptedInvestigationDataSource([
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'read-1',
              name: 'read_file',
              arguments: {'path': 'README.md'},
            ),
            ToolCallInfo(
              id: 'write-1',
              name: 'write_file',
              arguments: {'path': 'out.txt', 'content': 'unsafe'},
            ),
          ],
        ),
        ChatCompletionResult(
          content: 'The README establishes the supported behavior.',
          finishReason: 'stop',
        ),
      ]);
      final dispatched = <String>[];
      var observedCalls = 0;
      final now = DateTime.utc(2026, 8, 13, 10);

      final evidence = await ProReasoningInvestigator(clock: () => now)
          .investigate(
            dataSource: dataSource,
            model: 'research-model',
            question: 'What behavior is supported?',
            frame: const ProReasoningFrame(
              subQuestions: ['What does the README say?'],
              investigationSteps: ['Inspect the README'],
              successCriteria: ['Cite local evidence'],
              requiresInvestigation: true,
            ),
            maxIterations: 2,
            deadline: now.add(const Duration(minutes: 1)),
            isCancelled: () => false,
            toolDefinitions: [
              _definition('read_file'),
              _definition('write_file'),
              _definition('web_search', external: true),
            ],
            runTool: (toolCall) async {
              dispatched.add(toolCall.name);
              return McpToolResult(
                toolName: toolCall.name,
                result: 'README evidence',
                isSuccess: true,
              );
            },
            onLlmCall:
                ({
                  required messages,
                  required tools,
                  required result,
                  required startedAt,
                  required finishedAt,
                }) {
                  observedCalls++;
                },
          );

      expect(dispatched, ['read_file']);
      expect(observedCalls, 2);
      expect(dataSource.calls, hasLength(2));
      for (final call in dataSource.calls) {
        expect(call.model, 'research-model');
        expect(call.temperature, 0.1);
        expect(call.maxTokens, 1200);
        expect(call.toolNames, ['read_file']);
      }
      final feedback = dataSource.calls[1].messages.last.content;
      expect(feedback, contains('write_file'));
      expect(
        feedback,
        contains('denied by the Pro Reasoning read-only policy'),
      );
      expect(evidence, contains('README evidence'));
      expect(evidence, contains('Investigator summary'));
      expect(evidence, contains('supported behavior'));
    },
  );

  test(
    'marks linked sources unverified when web tools are unavailable',
    () async {
      final dataSource = _ScriptedInvestigationDataSource([
        ChatCompletionResult(
          content: 'No matching local files were found.',
          finishReason: 'stop',
        ),
      ]);
      final now = DateTime.utc(2026, 8, 13, 10);

      final evidence = await ProReasoningInvestigator(clock: () => now)
          .investigate(
            dataSource: dataSource,
            model: 'research-model',
            question: 'Inspect https://example.com/model.',
            frame: const ProReasoningFrame(
              subQuestions: ['Does the linked model exist?'],
              investigationSteps: ['Inspect the linked model'],
              successCriteria: ['Verify the external source'],
              requiresInvestigation: true,
            ),
            maxIterations: 1,
            deadline: now.add(const Duration(minutes: 1)),
            isCancelled: () => false,
            toolDefinitions: [_definition('search_files')],
            runTool: (_) async => throw StateError('No tool call expected'),
          );

      expect(
        dataSource.calls.single.messages.last.content,
        contains('External source verification status: unavailable'),
      );
      expect(evidence, contains('Local file results cannot establish'));
      expect(evidence, contains('No matching local files were found.'));
    },
  );

  test(
    'omits the linked-source limitation when web search is available',
    () async {
      final dataSource = _ScriptedInvestigationDataSource([
        ChatCompletionResult(content: 'Verified.', finishReason: 'stop'),
      ]);
      final now = DateTime.utc(2026, 8, 13, 10);

      final evidence = await ProReasoningInvestigator(clock: () => now)
          .investigate(
            dataSource: dataSource,
            model: 'research-model',
            question: 'Inspect https://example.com/model.',
            frame: const ProReasoningFrame(
              subQuestions: ['Does the linked model exist?'],
              investigationSteps: ['Inspect the linked model'],
              successCriteria: ['Verify the external source'],
              requiresInvestigation: true,
            ),
            maxIterations: 1,
            deadline: now.add(const Duration(minutes: 1)),
            isCancelled: () => false,
            toolDefinitions: [_definition('web_search')],
            runTool: (_) async => throw StateError('No tool call expected'),
          );

      expect(
        dataSource.calls.single.messages.last.content,
        isNot(contains('External source verification status: unavailable')),
      );
      expect(evidence, isNot(contains('Local file results cannot establish')));
    },
  );

  test('stops after repeated external verification failures', () async {
    final toolCallResult = ChatCompletionResult(
      content: '',
      finishReason: 'tool_calls',
      toolCalls: [
        ToolCallInfo(
          id: 'search',
          name: 'web_search',
          arguments: {'query': 'linked model'},
        ),
      ],
    );
    final dataSource = _ScriptedInvestigationDataSource([
      toolCallResult,
      toolCallResult,
      toolCallResult,
    ]);
    final dispatched = <String>[];
    final now = DateTime.utc(2026, 8, 13, 10);

    final evidence = await ProReasoningInvestigator(clock: () => now)
        .investigate(
          dataSource: dataSource,
          model: 'research-model',
          question: 'Inspect https://example.com/model.',
          frame: const ProReasoningFrame(
            subQuestions: ['Does the linked model exist?'],
            investigationSteps: ['Inspect the linked model'],
            successCriteria: ['Verify the external source'],
            requiresInvestigation: true,
          ),
          maxIterations: 10,
          deadline: now.add(const Duration(minutes: 1)),
          isCancelled: () => false,
          toolDefinitions: [_definition('web_search')],
          runTool: (toolCall) async {
            dispatched.add(toolCall.name);
            return McpToolResult(
              toolName: toolCall.name,
              result: '',
              isSuccess: false,
              errorMessage: 'SearXNG search failed: 404',
            );
          },
        );

    expect(dataSource.calls, hasLength(2));
    expect(dispatched, ['web_search', 'web_search']);
    expect(evidence, contains('SearXNG search failed: 404'));
    expect(
      evidence,
      contains('Do not infer that a linked resource is missing'),
    );
    expect(evidence, contains('existence and contents as unverified'));
  });
}

Map<String, dynamic> _definition(String name, {bool external = false}) => {
  'type': 'function',
  if (external) McpToolEntity.openAiExternalToolKey: true,
  'function': <String, dynamic>{
    'name': name,
    'description': '$name description',
    'parameters': <String, dynamic>{'type': 'object'},
  },
};

final class _InvestigationCall {
  const _InvestigationCall({
    required this.messages,
    required this.toolNames,
    required this.model,
    required this.temperature,
    required this.maxTokens,
  });

  final List<Message> messages;
  final List<String> toolNames;
  final String? model;
  final double? temperature;
  final int? maxTokens;
}

final class _ScriptedInvestigationDataSource extends ChatDataSource {
  _ScriptedInvestigationDataSource(List<ChatCompletionResult> results)
    : _results = List<ChatCompletionResult>.of(results);

  final List<ChatCompletionResult> _results;
  final List<_InvestigationCall> calls = [];

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    calls.add(
      _InvestigationCall(
        messages: List<Message>.of(messages),
        toolNames: [
          for (final tool in tools ?? const <Map<String, dynamic>>[])
            ((tool['function'] as Map)['name'] as String),
        ],
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    return _results.removeAt(0);
  }

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(const Stream<String>.empty());

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => const Stream<String>.empty();

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => throw UnimplementedError();
}
