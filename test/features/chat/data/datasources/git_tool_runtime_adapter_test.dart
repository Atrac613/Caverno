import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/git_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/data/datasources/first_party_tool_execution_result.dart';
import 'package:caverno/features/chat/data/datasources/git_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );
  final identity = GitProcessExecutionIdentity(
    owner: owner,
    toolCallId: 'call-a',
    toolName: 'git_execute_command',
    repositoryIdentity: '/repo',
    worktreeIdentity: '/repo',
    argumentDigest: 'digest-a',
  );

  test('starts ownership at the raw command handoff', () async {
    final events = <String>[];
    var inspection = 0;
    final adapter = GitToolRuntimeAdapter(
      stateInspector: (_) async {
        events.add('inspect');
        return _inspection(inspection++ == 0 ? 'before' : 'after');
      },
      commandResultRunner:
          ({
            required command,
            required workingDirectory,
            reason,
            beforeProcessStart,
          }) async {
            events.add('runner');
            expect(beforeProcessStart!(), isTrue);
            events.add('process');
            return _commandExecution(exitCode: 0);
          },
    );

    final completion = await adapter.execute(
      _commandRequest(owner),
      GitProcessStartAuthorization(
        identity: identity,
        start: () {
          events.add('handoff');
          return GitProcessStartDisposition.started;
        },
      ),
    );

    expect(events, ['inspect', 'runner', 'handoff', 'process', 'inspect']);
    expect(completion.effectKind, GitProcessEffectKind.committed);
  });

  test('reports a preflight rejection as a launch failure', () async {
    final adapter = GitToolRuntimeAdapter(
      stateInspector: (_) async => _inspection('same'),
      commandResultRunner:
          ({
            required command,
            required workingDirectory,
            reason,
            beforeProcessStart,
          }) async => _commandExecution(exitCode: 2),
    );

    await expectLater(
      adapter.execute(
        _commandRequest(owner),
        GitProcessStartAuthorization(
          identity: identity,
          start: () => GitProcessStartDisposition.started,
        ),
      ),
      throwsA(isA<GitProcessLaunchFailure>()),
    );
  });

  test('classifies a failed unchanged mutation as no effect', () async {
    final adapter = _commandAdapter(
      before: _inspection('same'),
      after: _inspection('same'),
      exitCode: 1,
    );

    final completion = await adapter.execute(
      _commandRequest(owner),
      _started(identity),
    );

    expect(completion.result.isSuccess, isFalse);
    expect(completion.effectKind, GitProcessEffectKind.noEffect);
  });

  test('requires reconciliation after a failed changed mutation', () async {
    final adapter = _commandAdapter(
      before: _inspection('before'),
      after: _inspection('after'),
      exitCode: 1,
    );

    final completion = await adapter.execute(
      _commandRequest(owner),
      _started(identity),
    );

    expect(completion.effectKind, GitProcessEffectKind.partialOrUnknown);
    expect(completion.reconciliation?.identity, identity);
    expect(completion.effectDetails['resultSucceeded'], isFalse);
  });

  test('GitTools invokes the handoff before the target process', () async {
    var handoffCount = 0;
    final payload =
        jsonDecode(
              await GitTools.execute(
                command: 'status --short',
                workingDirectory: Directory.current.path,
                beforeProcessStart: () {
                  handoffCount += 1;
                  return false;
                },
              ),
            )
            as Map<String, dynamic>;

    expect(handoffCount, 1);
    expect(payload['exit_code'], 130);
  });
}

GitToolRuntimeAdapter _commandAdapter({
  required GitRepositoryInspection before,
  required GitRepositoryInspection after,
  required int exitCode,
}) {
  var inspection = 0;
  return GitToolRuntimeAdapter(
    stateInspector: (_) async => inspection++ == 0 ? before : after,
    commandResultRunner:
        ({
          required command,
          required workingDirectory,
          reason,
          beforeProcessStart,
        }) async {
          beforeProcessStart!();
          return _commandExecution(exitCode: exitCode);
        },
  );
}

GitProcessStartAuthorization _started(GitProcessExecutionIdentity identity) =>
    GitProcessStartAuthorization(
      identity: identity,
      start: () => GitProcessStartDisposition.started,
    );

GitCommandExecutionRequest _commandRequest(ChatTurnOwner owner) =>
    GitCommandExecutionRequest(
      source: GitToolCallInput(
        owner: owner,
        toolCallId: 'call-a',
        toolName: 'git_execute_command',
        arguments: const {
          'command': 'commit -m test',
          'working_directory': '/repo',
        },
        ownerRepositoryPath: '/repo',
        ownerWorktreePath: '/repo',
      ),
      arguments: const {
        'command': 'commit -m test',
        'working_directory': '/repo',
      },
      command: 'commit -m test',
      workingDirectory: '/repo',
    );

GitRepositoryInspection _inspection(String digest) => GitRepositoryInspection(
  available: true,
  digest: digest,
  worktreePaths: const ['/repo'],
  evidence: {'available': true, 'stateDigest': digest},
);

String _commandPayload({required int exitCode}) => jsonEncode({
  'command': 'git commit -m test',
  'working_directory': '/repo',
  'exit_code': exitCode,
  'stdout': '',
  'stderr': exitCode == 0 ? '' : 'failed',
});

FirstPartyToolExecutionResult _commandExecution({required int exitCode}) =>
    FirstPartyToolExecutionResult(
      result: _commandPayload(exitCode: exitCode),
      outcome: ToolOutcome(exitCode: exitCode),
      errorMessage: exitCode == 0
          ? null
          : 'Git command exited with code $exitCode: failed',
    );
