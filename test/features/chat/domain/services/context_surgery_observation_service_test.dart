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
