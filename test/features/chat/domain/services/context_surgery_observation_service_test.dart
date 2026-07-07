import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/context_surgery_observation_service.dart';

void main() {
  test('observes tagged prompt blocks and coarse prompt sections', () {
    final observations = ContextSurgeryObservationService.observeSystemPrompt(
      '''
Core rules.
Repository map for the active project.
<repo_map>
lib/main.dart
  main()
</repo_map>
The following AGENTS.md from the project root contains project-specific guidance.
<agents_md>
Use focused tests.
</agents_md>
Approved plan document for this coding thread (source of truth while implementing):
# Plan
- Ship the slice.

Current workflow stage for this coding thread: implement.
Saved tasks:
1. [pending] Add tests.

Use the following context from past conversations to maintain continuity when helpful.
[Retrieved Memories]
- User prefers local models.
''',
    );

    expect(observations.first.kind, ContextSurgeryBlockKind.systemPrompt);
    expect(observations.first.label, 'system_prompt');
    expect(observations.first.estimatedTokens, greaterThan(0));
    expect(_charCountFor(observations, ContextSurgeryBlockKind.repoMap), 22);
    expect(
      _charCountFor(observations, ContextSurgeryBlockKind.agentsMarkdown),
      18,
    );
    expect(
      observations.map((observation) => observation.kind),
      containsAll([
        ContextSurgeryBlockKind.planDocument,
        ContextSurgeryBlockKind.workflowProjection,
        ContextSurgeryBlockKind.memory,
      ]),
    );
  });

  test('classifies tool result context blocks', () {
    final observations = ContextSurgeryObservationService.observeToolResults([
      _toolResult(name: 'read_file', arguments: {'path': 'lib/main.dart'}),
      _toolResult(name: 'search_files', arguments: {'query': 'ChatNotifier'}),
      _toolResult(name: 'local_execute_command', result: 'exit_code=0'),
      _toolResult(name: 'write_file', arguments: {'path': 'lib/new.dart'}),
      _toolResult(name: 'recall_memory'),
    ]);

    expect(observations.map((observation) => observation.kind).toList(), [
      ContextSurgeryBlockKind.fileReadToolResult,
      ContextSurgeryBlockKind.fileSearchToolResult,
      ContextSurgeryBlockKind.commandToolResult,
      ContextSurgeryBlockKind.sideEffectToolResult,
      ContextSurgeryBlockKind.toolResult,
    ]);
    expect(observations.first.sourceIndex, 0);
    expect(observations.first.identifier, 'lib/main.dart');
  });

  test('buckets tool definitions into system and mcp schema sections', () {
    final systemTool = <String, dynamic>{
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': 'Read a file.',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    };
    final mcpTool = <String, dynamic>{
      'type': 'function',
      'function': {
        'name': 'notion_search',
        'description': 'Search Notion.',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    };

    final observations =
        ContextSurgeryObservationService.observeToolDefinitions(
          [systemTool, mcpTool],
          mcpToolNames: {'notion_search'},
        );

    expect(observations.map((observation) => observation.kind).toList(), [
      ContextSurgeryBlockKind.systemToolSchema,
      ContextSurgeryBlockKind.mcpToolSchema,
    ]);
    expect(observations.first.label, 'read_file');
    // Sizing uses the serialized JSON length so it stays comparable with the
    // char/4 estimate used for every other section.
    expect(observations.first.charCount, jsonEncode(systemTool).length);

    final snapshot = ContextSurgeryObservationService.buildSnapshot(
      toolDefinitions: [systemTool, mcpTool],
      mcpToolNames: {'notion_search'},
    );
    expect(
      snapshot.section(ContextSurgeryBlockKind.systemToolSchema)?.blockCount,
      1,
    );
    expect(
      snapshot.section(ContextSurgeryBlockKind.systemToolSchema)?.label,
      'System tools',
    );
    expect(
      snapshot.section(ContextSurgeryBlockKind.mcpToolSchema)?.charCount,
      jsonEncode(mcpTool).length,
    );
  });

  test('builds a section snapshot with stale candidate pressure', () {
    final snapshot = ContextSurgeryObservationService.buildSnapshot(
      systemPrompt: '''
System rules.
<repo_map>
lib/main.dart
</repo_map>
''',
      toolResults: [
        _toolResult(
          id: 'read-old',
          name: 'read_file',
          arguments: {'path': 'lib/main.dart'},
          result: 'old content',
        ),
        _toolResult(
          id: 'read-new',
          name: 'read_file',
          arguments: {'path': 'lib/main.dart'},
          result: 'new content',
        ),
      ],
    );

    expect(snapshot.hasData, isTrue);
    expect(
      snapshot.section(ContextSurgeryBlockKind.systemPrompt)?.blockCount,
      1,
    );
    expect(snapshot.section(ContextSurgeryBlockKind.repoMap)?.charCount, 13);
    expect(
      snapshot.section(ContextSurgeryBlockKind.fileReadToolResult)?.blockCount,
      2,
    );
    expect(snapshot.staleToolResultCandidateCount, 1);
    expect(snapshot.staleToolResultEstimatedTokens, 3);
  });

  test('marks older duplicate file reads as stale candidates', () {
    final candidates =
        ContextSurgeryObservationService.findStaleToolResultCandidates([
          _toolResult(
            id: 'read-old',
            name: 'read_file',
            arguments: {'path': 'lib/main.dart'},
            result: 'old content',
          ),
          _toolResult(
            id: 'read-other',
            name: 'read_file',
            arguments: {'path': 'lib/other.dart'},
            result: 'other content',
          ),
          _toolResult(
            id: 'read-new',
            name: 'read_file',
            arguments: {'path': 'lib/main.dart'},
            result: 'new content',
          ),
        ]);

    expect(candidates, hasLength(1));
    expect(candidates.single.index, 0);
    expect(candidates.single.replacedByIndex, 2);
    expect(
      candidates.single.reason,
      ContextSurgeryCandidateReason.supersededFileRead,
    );
    expect(candidates.single.identifier, 'lib/main.dart');
    expect(candidates.single.replacementStub, contains('newer read_file'));
  });

  test('protects paths that the current task still references', () {
    final candidates =
        ContextSurgeryObservationService.findStaleToolResultCandidates(
          [
            _toolResult(
              id: 'read-old',
              name: 'read_file',
              arguments: {'path': 'lib/main.dart'},
            ),
            _toolResult(
              id: 'read-new',
              name: 'read_file',
              arguments: {'path': 'lib/main.dart'},
            ),
          ],
          protectedPaths: {'lib/main.dart'},
        );

    expect(candidates, isEmpty);
  });

  test('protects relative paths that match absolute tool arguments', () {
    final candidates =
        ContextSurgeryObservationService.findStaleToolResultCandidates(
          [
            _toolResult(
              id: 'read-old',
              name: 'read_file',
              arguments: {'path': '/workspace/lib/main.dart'},
            ),
            _toolResult(
              id: 'read-new',
              name: 'read_file',
              arguments: {'path': '/workspace/lib/main.dart'},
            ),
          ],
          protectedPaths: {'lib/main.dart'},
        );

    expect(candidates, isEmpty);
  });

  test(
    'only stubs unprotected duplicates when protected evidence is mixed',
    () {
      final results =
          ContextSurgeryObservationService.applyStaleToolResultStubs(
            [
              _toolResult(
                id: 'protected-old',
                name: 'read_file',
                arguments: {'path': '/workspace/lib/main.dart'},
                result: 'protected old content',
              ),
              _toolResult(
                id: 'unprotected-old',
                name: 'read_file',
                arguments: {'path': '/workspace/lib/old.dart'},
                result: 'unprotected old content',
              ),
              _toolResult(
                id: 'protected-new',
                name: 'read_file',
                arguments: {'path': '/workspace/lib/main.dart'},
                result: 'protected new content',
              ),
              _toolResult(
                id: 'unprotected-new',
                name: 'read_file',
                arguments: {'path': '/workspace/lib/old.dart'},
                result: 'unprotected new content',
              ),
            ],
            protectedPaths: {'lib/main.dart'},
          );

      expect(results[0].result, 'protected old content');
      expect(results[1].result, contains('stale tool result omitted'));
      expect(results[2].result, 'protected new content');
      expect(results[3].result, 'unprotected new content');
    },
  );

  test('applies stale result stubs while retaining the newest evidence', () {
    final results = ContextSurgeryObservationService.applyStaleToolResultStubs([
      _toolResult(
        id: 'read-old',
        name: 'read_file',
        arguments: {'path': 'lib/main.dart'},
        result: 'old content',
      ),
      _toolResult(
        id: 'read-new',
        name: 'read_file',
        arguments: {'path': 'lib/main.dart'},
        result: 'new content',
      ),
    ]);

    expect(results, hasLength(2));
    expect(results.first.id, 'read-old');
    expect(results.first.name, 'read_file');
    expect(results.first.arguments, {'path': 'lib/main.dart'});
    expect(results.first.result, contains('stale tool result omitted'));
    expect(results.first.result, contains('tool result index 1'));
    expect(results.last.result, 'new content');
  });

  test('never stubs command or side-effect tool results', () {
    final results = ContextSurgeryObservationService.applyStaleToolResultStubs([
      _toolResult(
        id: 'command-old',
        name: 'local_execute_command',
        arguments: {'command': 'flutter test'},
        result: 'first command result',
      ),
      _toolResult(
        id: 'command-new',
        name: 'local_execute_command',
        arguments: {'command': 'flutter test'},
        result: 'second command result',
      ),
      _toolResult(
        id: 'write-old',
        name: 'write_file',
        arguments: {'path': 'lib/main.dart'},
        result: 'first write result',
      ),
      _toolResult(
        id: 'write-new',
        name: 'write_file',
        arguments: {'path': 'lib/main.dart'},
        result: 'second write result',
      ),
    ]);

    expect(results.map((result) => result.result), [
      'first command result',
      'second command result',
      'first write result',
      'second write result',
    ]);
  });

  test('marks repeated search results but never side-effect evidence', () {
    final candidates =
        ContextSurgeryObservationService.findStaleToolResultCandidates([
          _toolResult(
            id: 'search-old',
            name: 'search_files',
            arguments: {'query': 'ChatNotifier', 'path': 'lib'},
          ),
          _toolResult(
            id: 'write',
            name: 'write_file',
            arguments: {'path': 'lib/main.dart'},
          ),
          _toolResult(
            id: 'search-new',
            name: 'search_files',
            arguments: {'path': 'lib', 'query': 'ChatNotifier'},
          ),
          _toolResult(
            id: 'command',
            name: 'local_execute_command',
            arguments: {'command': 'flutter test'},
          ),
        ]);

    expect(candidates, hasLength(1));
    expect(candidates.single.index, 0);
    expect(
      candidates.single.reason,
      ContextSurgeryCandidateReason.supersededFileSearch,
    );
    expect(candidates.single.replacedByIndex, 2);
  });
}

int _charCountFor(
  List<ContextSurgeryBlockObservation> observations,
  ContextSurgeryBlockKind kind,
) {
  return observations
      .singleWhere((observation) => observation.kind == kind)
      .charCount;
}

ToolResultInfo _toolResult({
  String id = 'tool',
  String name = 'read_file',
  Map<String, dynamic> arguments = const {},
  String result = 'result',
}) {
  return ToolResultInfo(
    id: id,
    name: name,
    arguments: arguments,
    result: result,
  );
}
