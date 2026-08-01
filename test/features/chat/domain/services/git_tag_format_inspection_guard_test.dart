import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/git_tag_format_inspection_guard.dart';
import 'package:test/test.dart';

const _guard = GitTagFormatInspectionGuard();
const _ownerRoot = '/workspace/owner-a';
const _visibleRoot = '/workspace/owner-b';

ToolCallInfo _call({
  String name = 'git_execute_command',
  String command = 'tag v1.2.3',
  Map<String, dynamic> extraArguments = const {},
}) {
  return ToolCallInfo(
    id: 'tag-call',
    name: name,
    arguments: {'command': command, ...extraArguments},
  );
}

ToolResultInfo _inspection({
  String name = 'git_execute_command',
  String command = 'tag --list',
  int exitCode = 0,
  Object? workingDirectory = _ownerRoot,
  bool includeWorkingDirectory = true,
  String? rawResult,
}) {
  return ToolResultInfo(
    id: 'inspection-$command',
    name: name,
    arguments: {'command': command},
    result:
        rawResult ??
        jsonEncode({
          'exit_code': exitCode,
          if (includeWorkingDirectory) 'working_directory': workingDirectory,
          'stdout': 'v1.2.2',
        }),
  );
}

GitTagFormatInspectionInput _input({
  ToolCallInfo? toolCall,
  String command = 'tag v1.2.3',
  String workingDirectory = _ownerRoot,
  List<ToolResultInfo> executedToolResults = const [],
}) {
  return GitTagFormatInspectionInput(
    toolCall: toolCall ?? _call(command: command),
    resolvedArguments: {
      'command': command,
      'working_directory': workingDirectory,
    },
    executedToolResults: executedToolResults,
  );
}

Map<String, dynamic> _payload(McpToolResult result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}

void main() {
  test('ignores non-Git tool calls', () {
    final result = _guard.evaluate(
      _input(toolCall: _call(name: 'local_execute_command')),
    );

    expect(result, isNull);
  });

  test('blocks normalized lightweight and annotated tag creation', () {
    for (final command in [
      'tag v1.2.3',
      ' git   tag   v1.2.3 ',
      'tag -a v1.2.3 -m "Release 1.2.3"',
      'tag -f v1.2.3',
      'tag --sign v1.2.3',
    ]) {
      expect(
        _guard.evaluate(_input(command: command)),
        isNotNull,
        reason: command,
      );
    }
  });

  test('ignores read-only, deletion, and unrelated Git commands', () {
    for (final command in [
      '',
      'status',
      'tag',
      'tag --list',
      'tag -l "v1.*"',
      'tag -d v1.2.2',
      'tag --delete v1.2.2',
    ]) {
      expect(
        _guard.evaluate(_input(command: command)),
        isNull,
        reason: command,
      );
    }
  });

  test('bypasses tag creation commands containing shell controls', () {
    for (final command in [
      'tag v1.2.3 && push origin v1.2.3',
      'tag v1.2.3 & push origin v1.2.3',
      'tag v1.2.3 || push origin v1.2.3',
      'tag v1.2.3; push',
      'tag v1.2.3 | cat',
      'tag v1.2.3 < tag-message.txt',
      'tag v1.2.3 > tags.txt',
      'tag v1.2.3\nstatus',
    ]) {
      expect(
        _guard.evaluate(_input(command: command)),
        isNull,
        reason: command,
      );
    }
  });

  test('does not treat shell controls inside quotes as command controls', () {
    expect(
      _guard.evaluate(
        _input(command: 'tag -a v1.2.3 -m "release && verification"'),
      ),
      isNotNull,
    );
  });

  test('accepts every supported successful inspection command', () {
    for (final command in [
      'tag',
      'tag --list',
      'tag -l "v1.*"',
      'git for-each-ref refs/tags --format=%(refname:short)',
      'for-each-ref refs/tags/releases --format=%(refname:short)',
      'show-ref --tags',
    ]) {
      expect(
        _guard.evaluate(
          _input(executedToolResults: [_inspection(command: command)]),
        ),
        isNull,
        reason: command,
      );
    }
  });

  test('rejects unsupported, failed, malformed, and non-Git inspections', () {
    final rejected = [
      _inspection(command: ''),
      _inspection(command: 'status'),
      _inspection(command: 'tag v1.2.2'),
      _inspection(command: 'for-each-ref refs/heads'),
      _inspection(exitCode: 1),
      _inspection(rawResult: '{"exit_code":"0"}'),
      _inspection(rawResult: '{malformed'),
      _inspection(rawResult: '[]'),
      _inspection(name: 'local_execute_command'),
    ];

    for (final inspection in rejected) {
      expect(
        _guard.evaluate(_input(executedToolResults: [inspection])),
        isNotNull,
        reason: '${inspection.name}:${inspection.result}',
      );
    }
  });

  test('requires a matching string working directory when one is reported', () {
    expect(
      _guard.evaluate(
        _input(
          executedToolResults: [_inspection(workingDirectory: _visibleRoot)],
        ),
      ),
      isNotNull,
    );
    expect(
      _guard.evaluate(_input(executedToolResults: [_inspection()])),
      isNull,
    );
    expect(
      _guard.evaluate(
        _input(
          workingDirectory: ' $_ownerRoot ',
          executedToolResults: [_inspection(workingDirectory: ' $_ownerRoot ')],
        ),
      ),
      isNotNull,
    );
  });

  test('preserves missing and non-string directory compatibility', () {
    for (final inspection in [
      _inspection(includeWorkingDirectory: false),
      _inspection(workingDirectory: 42),
    ]) {
      expect(
        _guard.evaluate(_input(executedToolResults: [inspection])),
        isNull,
        reason: inspection.result,
      );
    }
    expect(
      _guard.evaluate(
        _input(
          workingDirectory: '',
          executedToolResults: [_inspection(workingDirectory: _visibleRoot)],
        ),
      ),
      isNull,
    );
  });

  test('accepts a later success after earlier failed inspections', () {
    final result = _guard.evaluate(
      _input(
        executedToolResults: [
          _inspection(exitCode: 1),
          _inspection(command: 'status'),
          _inspection(command: 'show-ref --tags'),
        ],
      ),
    );

    expect(result, isNull);
  });

  test('uses resolved arguments instead of unresolved tool-call arguments', () {
    expect(
      _guard.evaluate(
        _input(
          toolCall: _call(command: 'status'),
          command: 'tag v2.0.0',
        ),
      ),
      isNotNull,
    );
    expect(
      _guard.evaluate(
        _input(
          toolCall: _call(command: 'tag v2.0.0'),
          command: 'status',
        ),
      ),
      isNull,
    );
  });

  test('returns the exact blocked result and owner-resolved arguments', () {
    final result = _guard.evaluate(
      _input(command: ' git tag   v2.0.0 ', workingDirectory: _ownerRoot),
    )!;
    final expectedPayload = {
      'error':
          'Git tag creation requires inspecting existing tag names in this '
          'turn before creating a new tag.',
      'code': GitTagFormatInspectionGuard.blockedCode,
      'command': 'git tag v2.0.0',
      'working_directory': _ownerRoot,
      'required_action':
          'Run git_execute_command with "tag --list" or '
          '"for-each-ref refs/tags --format=%(refname:short)" first, then '
          'choose a new tag name that matches the existing repository format.',
    };

    expect(result.toolName, 'git_execute_command');
    expect(result.isSuccess, isFalse);
    expect(
      result.errorMessage,
      'Inspect existing git tag names before creating a new tag.',
    );
    expect(result.result, jsonEncode(expectedPayload));
    expect(_payload(result), expectedPayload);
  });

  test('does not accept another owner repository inspection', () {
    final visibleInspection = _inspection(workingDirectory: _visibleRoot);
    final ownerResult = _guard.evaluate(
      _input(
        workingDirectory: _ownerRoot,
        executedToolResults: [visibleInspection],
      ),
    );
    final visibleResult = _guard.evaluate(
      _input(
        workingDirectory: _visibleRoot,
        executedToolResults: [visibleInspection],
      ),
    );

    expect(ownerResult, isNotNull);
    expect(_payload(ownerResult!)['working_directory'], _ownerRoot);
    expect(ownerResult.result, isNot(contains(_visibleRoot)));
    expect(visibleResult, isNull);
  });

  test('recursively freezes resolved arguments and executed results', () {
    final metadata = <String, dynamic>{
      'paths': <Object?>[
        _ownerRoot,
        <String, Object?>{
          '7': 'owner-a',
          'tags': <Object?>['v1.2.2'],
        },
      ],
    };
    final toolCallArguments = <String, dynamic>{
      'command': 'tag v1.2.3',
      'metadata': metadata,
    };
    final resolvedArguments = <String, dynamic>{
      'command': 'tag v1.2.3',
      'working_directory': _ownerRoot,
      'metadata': metadata,
    };
    final inspectionArguments = <String, dynamic>{
      'command': 'tag --list',
      'metadata': metadata,
    };
    final executedResults = <ToolResultInfo>[
      ToolResultInfo(
        id: 'inspection',
        name: 'git_execute_command',
        arguments: inspectionArguments,
        result: jsonEncode({'exit_code': 0, 'working_directory': _ownerRoot}),
      ),
    ];
    final input = GitTagFormatInspectionInput(
      toolCall: ToolCallInfo(
        id: 'tag-call',
        name: 'git_execute_command',
        arguments: toolCallArguments,
      ),
      resolvedArguments: resolvedArguments,
      executedToolResults: executedResults,
    );

    toolCallArguments['command'] = 'status';
    resolvedArguments['command'] = 'status';
    inspectionArguments['command'] = 'tag -d v1.2.2';
    metadata['paths'] = <Object?>[_visibleRoot];
    executedResults.clear();

    expect(input.toolCall.arguments['command'], 'tag v1.2.3');
    expect(input.resolvedArguments['command'], 'tag v1.2.3');
    expect(input.executedToolResults.single.arguments['command'], 'tag --list');
    final frozenMetadata =
        input.resolvedArguments['metadata'] as Map<String, dynamic>;
    final frozenPaths = frozenMetadata['paths'] as List<Object?>;
    expect(frozenPaths.first, _ownerRoot);
    final frozenNested = frozenPaths[1] as Map;
    expect(frozenNested['7'], 'owner-a');
    final frozenTags = frozenNested['tags'] as List<Object?>;
    expect(() => frozenNested['7'] = 'late', throwsUnsupportedError);
    expect(() => frozenTags.add('v2.0.0'), throwsUnsupportedError);
    expect(() => frozenPaths.add(_visibleRoot), throwsUnsupportedError);
    expect(
      () => input.toolCall.arguments['command'] = 'status',
      throwsUnsupportedError,
    );
    expect(
      () => input.resolvedArguments['command'] = 'status',
      throwsUnsupportedError,
    );
    expect(
      () => input.executedToolResults.single.arguments['command'] = 'status',
      throwsUnsupportedError,
    );
    expect(
      () => input.executedToolResults.add(_inspection()),
      throwsUnsupportedError,
    );
  });
}
