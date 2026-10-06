import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mesh_secondary_completion_runner.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_executor.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_verification_runner.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Source extends Mock implements ChatDataSource {}

void main() {
  registerFallbackValue(<Message>[]);
  for (final scenario in [
    'repair',
    'stillFailed',
    'timeout',
    'unavailable',
    'cancelled',
  ]) {
    test(
      'verification repair is bounded and evidence gated: $scenario',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'worktree_repair_test_',
        );
        addTearDown(() => root.delete(recursive: true));
        final source = _Source();
        final prompts = <String>[];
        when(
          () => source.createChatCompletion(
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            maxTokens: any(named: 'maxTokens'),
          ),
        ).thenAnswer((call) async {
          final messages = call.namedArguments[#messages] as List<Message>;
          prompts.add(messages.last.content);
          return ChatCompletionResult(
            content: 'Implementation updated.',
            finishReason: 'stop',
          );
        });
        var cancelled = false;
        final commands = <WorktreeAgentVerificationCommand>[];
        final delegate = WorktreeAgentLlmExecutionDelegate(
          settings: AppSettings.defaults(),
          primaryDataSource: source,
          meshRunner: MeshSecondaryCompletionRunner<ChatDataSource>(
            router: const MeshEndpointRouter(),
            health: EndpointHealthTracker(),
            buildEndpointDataSource: (_, _) =>
                throw StateError('Unexpected endpoint'),
          ),
          toolService: null,
          verificationRunner: WorktreeAgentVerificationRunner(
            commandRunner: (command, _) async {
              commands.add(command);
              if (scenario == 'cancelled') cancelled = true;
              return WorktreeAgentVerificationCommandOutput(
                exitCode: scenario == 'repair' && commands.length == 2 ? 0 : 1,
                stderr: 'Expected a newline.',
                timedOut: scenario == 'timeout',
                startError: scenario == 'unavailable'
                    ? 'Containment unavailable'
                    : null,
              );
            },
          ),
        );
        final now = DateTime.now();
        final outcome = await delegate.execute(
          WorktreeAgentTaskExecutionContext(
            task: WorktreeAgentTask(
              id: 'repair-test',
              prompt: 'Fix greeting.txt only.',
              branchName: 'feature/repair-test',
              worktreePath: root.path,
              verificationCommand: 'python verify.py',
              createdAt: now,
              updatedAt: now,
            ),
            isCancelled: () => cancelled,
          ),
        );
        final retried = scenario == 'repair' || scenario == 'stillFailed';
        expect(prompts, hasLength(retried ? 2 : 1));
        expect(commands, hasLength(retried ? 2 : 1));
        expect(outcome.verifiedGreen, scenario == 'repair');
        for (final command in commands) {
          expect(command.executable, 'python');
          expect(command.arguments, ['verify.py']);
          expect(command.workingDirectory, root.path);
        }
        if (retried) {
          expect(prompts.last, contains('Expected a newline.'));
          expect(prompts.last, contains('Fix greeting.txt only.'));
          expect(
            outcome.verificationSummary,
            contains('Initial verification:'),
          );
          expect(outcome.verificationSummary, contains('After one repair:'));
        }
      },
    );
  }
}
