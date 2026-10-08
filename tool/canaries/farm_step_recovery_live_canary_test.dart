import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/turn_diff.dart';
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';
import 'package:caverno/features/chat/domain/services/project_task/project_task_terminal_status.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/project_farm/application/project_task_review_workflow.dart';
import 'package:caverno/features/project_farm/application/project_task_step_turn_runner.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'support/farm_step_live_datasource.dart';
import 'support/farm_step_live_fixture.dart';
import 'support/farm_step_preflight_datasource.dart';

void main() {
  final preflight =
      Platform.environment['CAVERNO_FARM_STEP_OFFLINE_PREFLIGHT'] == '1';
  final enabled = Platform.environment['CAVERNO_FARM_STEP_LIVE_CANARY'] == '1';
  for (final scenario in FarmStepScenario.values) {
    test(
      '${preflight ? 'offline' : 'live'} Farm step recovery: ${scenario.name}',
      () async {
        for (final key in [
          'CAVERNO_LLM_BASE_URL',
          'CAVERNO_LLM_API_KEY',
          'CAVERNO_LLM_MODEL',
          'CAVERNO_FARM_STEP_REPORT_DIR',
        ]) {
          expect(
            Platform.environment[key],
            isNotEmpty,
            reason: '$key is required',
          );
        }
        expect(
          Platform.isMacOS,
          isTrue,
          reason: 'Native containment is a macOS route',
        );
        final report = Directory(
          Platform.environment['CAVERNO_FARM_STEP_REPORT_DIR']!,
        );
        report.createSync(recursive: true);
        final scratch = Directory('${report.path}/${scenario.name}')
          ..createSync();
        final temporary = Directory.systemTemp.createTempSync(
          'caverno-farm-step-',
        );
        final root = Directory(temporary.resolveSymbolicLinksSync());
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        final fixture = FarmStepFixture(root, scenario);
        final beforeFiles = fixture.snapshot();
        final persistence = '${scratch.path}/persistence';
        final conversationBox = await Hive.openBox<String>(
          'conversations',
          path: persistence,
        );
        final memoryBox = await Hive.openBox<String>(
          'memory',
          path: persistence,
        );
        final repository = ConversationRepository(conversationBox);
        final memory = ChatMemoryRepository.fromBox(memoryBox);
        final memoryService = FarmStepMemory(memory);
        final source = FarmStepLiveDataSource(
          preflight
              ? FarmStepPreflightDataSource(fixture)
              : ChatRemoteDataSource(
                  baseUrl: Platform.environment['CAVERNO_LLM_BASE_URL']!,
                  apiKey: Platform.environment['CAVERNO_LLM_API_KEY']!,
                ),
          fixture,
        );
        final lifecycle = FarmStepLifecycle();
        when(() => lifecycle.isInBackground).thenReturn(false);
        final toolService = FarmStepTools(fixture);
        final container = ProviderContainer(
          overrides: [
            settingsNotifierProvider.overrideWith(FarmStepSettings.new),
            sharedPreferencesProvider.overrideWithValue(FarmStepPreferences()),
            conversationRepositoryProvider.overrideWithValue(repository),
            chatMemoryRepositoryProvider.overrideWithValue(memory),
            sessionMemoryServiceProvider.overrideWithValue(memoryService),
            codingProjectsNotifierProvider.overrideWith(
              () => FarmStepProjects(fixture.project),
            ),
            chatRemoteDataSourceProvider.overrideWithValue(source),
            mcpToolServiceProvider.overrideWithValue(toolService),
            appLifecycleServiceProvider.overrideWithValue(lifecycle),
            backgroundTaskServiceProvider.overrideWithValue(
              FarmStepBackground(),
            ),
            notificationServiceProvider.overrideWithValue(
              FarmStepNotifications(),
            ),
          ],
        );
        FarmStepApprover? approver;
        final observations = <Map<String, dynamic>>[];
        final marked = <String>[];
        var finalBoundary = 0;
        String? conversationId;
        var passed = false;
        try {
          final conversations = container.read(
            conversationsNotifierProvider.notifier,
          );
          final now = DateTime.now();
          final conversation = conversations.addBackgroundConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: fixture.project.id,
            goal: ConversationGoal(
              id: 'fixture-goal',
              objective: fixture.objective,
              projectTaskAutoReview: true,
              projectTaskInheritedPaths: ['policy.md'],
              tokenBudget: 60000,
              turnBudget: 8,
              createdAt: now,
              updatedAt: now,
            ),
          );
          conversationId = conversation.id;
          conversations.selectConversation(conversation.id);
          final notifier = container.read(chatNotifierProvider.notifier);
          approver = FarmStepApprover(container, fixture);
          Conversation? readTask() => container
              .read(conversationsNotifierProvider)
              .conversationForId(conversation.id);
          bool selected() =>
              notifier.conversationId == conversation.id &&
              container
                      .read(conversationsNotifierProvider)
                      .currentConversationId ==
                  conversation.id;
          bool waiting() =>
              notifier.isConversationBusy(conversation.id) ||
              notifier.isConversationAwaitingApproval(conversation.id) ||
              container
                      .read(chatNotifierProvider)
                      .pendingAskUserQuestion
                      ?.conversationId ==
                  conversation.id;
          var completedTurns = 0;
          final step = ProjectTaskStepTurnRunner(
            readConversation: readTask,
            isSelected: selected,
            isWaitingForUser: waiting,
            admits: ProjectTaskStepTurnRunner.activeGoal,
            sendTurn: (prompt) => notifier.sendMessage(
              prompt,
              bypassPlanMode: true,
              languageCode: 'en',
              purpose: PrimaryTurnPurpose.projectTaskStep,
            ),
            waitForCompletion: (owner) async {
              await notifier
                  .waitForTurnCompletion(owner)
                  .timeout(const Duration(minutes: 7));
              await memoryService.waitForUpdate(++completedTurns);
            },
          );
          final tasks = [
            ConversationWorkflowTask(
              id: 'first',
              title: 'Verify existing policy and settle the injected fault',
              targetFiles: [fixture.targetFile],
              validationCommand: scenario == FarmStepScenario.unissuedCommand
                  ? ''
                  : fixture.verificationCommand,
            ),
            ConversationWorkflowTask(
              id: 'second',
              title:
                  'Read ${fixture.targetFile} and independently rerun the same verifier',
              targetFiles: [fixture.targetFile],
              validationCommand: fixture.verificationCommand,
            ),
            const ConversationWorkflowTask(
              id: 'final',
              title: 'Final implementation boundary (outside this canary)',
            ),
          ];
          final workflow = ProjectTaskReviewWorkflow(
            conversationId: conversation.id,
            readConversation: readTask,
            isSelected: selected,
            isWaitingForUser: waiting,
            decompose: (objective) async {
              await conversations.updateCurrentWorkflow(
                conversationId: conversation.id,
                workflowStage: ConversationWorkflowStage.implement,
                workflowSpec: ConversationWorkflowSpec(
                  goal: objective,
                  tasks: tasks,
                ),
              );
              return tasks;
            },
            sendStep: (prompt) async {
              final result = await step.send(prompt);
              await conversationBox.flush();
              await memoryBox.flush();
              final saved = repository.getById(conversation.id)!;
              final summary = memory.loadSessionSummaries().single;
              observations.add({
                'sendAccepted': result,
                'answer': saved.messages
                    .lastWhere(
                      (message) => message.role == MessageRole.assistant,
                    )
                    .content,
                'goalStatus': saved.goal!.status.name,
                'memory': summary.toJson(),
                'memoryInput': source.memoryInputs.last,
                'nativeResults': [
                  for (final tool in source.results.values)
                    if (tool.name == 'local_execute_command')
                      {
                        'id': tool.id,
                        'name': tool.name,
                        'arguments': tool.arguments,
                        'result': tool.result,
                      },
                ],
              });
              return result;
            },
            markSubtaskDone: (id) async {
              marked.add(id);
              await conversations.updateCurrentExecutionTaskProgress(
                conversationId: conversation.id,
                taskId: id,
                status: ConversationWorkflowTaskStatus.completed,
                lastRunAt: DateTime.now(),
                eventType: ConversationExecutionTaskEventType.completed,
                eventTimestamp: DateTime.now(),
              );
            },
            inheritedFiles: const [
              TurnDiffFile(filePath: 'policy.md', linesAdded: 3),
            ],
            send: (prompt, {required codeReview}) async {
              finalBoundary++;
              return false;
            },
            commit: (_, _) async =>
                throw StateError('Commit is outside this canary'),
            readGitState: (_) async =>
                throw StateError('Git is outside this canary'),
          );
          await workflow.run();
          expect(source.preludeUsed && source.preludeFollowupUsed, isTrue);
          expect(source.livePrimaryCalls, greaterThan(0));
          expect(source.liveMemoryCalls, scenario.accepted ? 2 : 1);
          expect(source.memoryResponses, hasLength(source.liveMemoryCalls));
          for (final response in source.memoryResponses) {
            expect(
              MemoryExtractionDraftService.parseDraft(response),
              isNotNull,
              reason: 'The model must return parseable memory JSON',
            );
          }
          expect(observations, hasLength(scenario.accepted ? 2 : 1));
          expect(marked, scenario.accepted ? ['first', 'second'] : isEmpty);
          expect(finalBoundary, scenario.accepted ? 1 : 0);
          if (scenario != FarmStepScenario.environmentLookup) {
            expect(source.faultAnswerUsed, isTrue);
            if (!scenario.accepted) {
              expect(source.recoveryCalls, greaterThan(0));
            }
          } else {
            expect(
              source.recoveryCalls,
              0,
              reason:
                  'Optional failed lookup must not force verification recovery',
            );
            expect(
              jsonDecode(source.results['fixture-probe']!.result)['exit_code'],
              isNot(0),
            );
          }
          final natives = source.results.values.where(
            (result) => result.name == 'local_execute_command',
          );
          expect(natives, isNotEmpty);
          final verifiers = natives
              .where(
                (result) =>
                    result.arguments['command'] == fixture.verificationCommand,
              )
              .toList();
          expect(verifiers, isNotEmpty);
          for (final verifier in verifiers) {
            final payload = jsonDecode(verifier.result) as Map;
            expect(
              payload['exit_code'],
              scenario.failsVerification ? isNot(0) : 0,
            );
            if (!scenario.failsVerification) {
              expect(payload['stdout'], contains('FARM_STEP_VERIFIED'));
            }
            expect(toolService.nativeExecutions, isNotEmpty);
            expect(
              toolService.nativeExecutions.every(
                (execution) =>
                    (execution['arguments']
                        as Map)['workspace_command_containment'] ==
                    true,
              ),
              isTrue,
            );
          }
          if (scenario == FarmStepScenario.missingExecution) {
            expect(
              source.results.values.any(
                (result) => result.result.contains('unexecuted_command_action'),
              ),
              isTrue,
            );
          }
          if (scenario.stdin) {
            expect(source.readmeShorthandPreludeUsed, isTrue);
            final edit = source.results['fixture-edit']!;
            expect(edit.outcome!.fileMutations.single.changed, isTrue);
            expect(
              edit.outcome!.fileMutations.single.path,
              '${root.path}/README.md',
            );
            expect(
              File('${root.path}/README.md').readAsStringSync(),
              farmStepReadmeAfter,
            );
            final ordered = source.results.values.toList();
            expect(
              ordered.indexOf(verifiers.first),
              greaterThan(ordered.indexOf(edit)),
            );
            if (scenario.accepted) {
              expect(verifiers.length, greaterThanOrEqualTo(2));
              for (final observation in observations) {
                expect(
                  observation['answer'],
                  isNot(contains('Deliverable claim check:')),
                );
                expect(
                  observation['memoryInput'],
                  isNot(contains('"code":"unexecuted_command_action"')),
                );
                expect(
                  observation['memoryInput'],
                  isNot(
                    contains(
                      'Required subtask tool actions remain unexecuted.',
                    ),
                  ),
                );
              }
            }
          }
          if (scenario == FarmStepScenario.unissuedCommand) {
            expect(
              source.results.values.any(
                (result) =>
                    result.result.contains('structured_project_subtask') &&
                    result.result.contains('tool/unavailable.py'),
              ),
              isTrue,
            );
            expect(
              observations.first['answer'],
              contains('Required subtask tool actions remain unexecuted.'),
            );
          }
          for (final observation in observations) {
            final terminal = ProjectTaskTerminalStatus.subtask(
              taskId: 'fixture',
              accepted: scenario.accepted,
            );
            final answer = ContentParser.stripModelHistoryArtifacts(
              observation['answer'] as String,
            );
            expect(
              answer,
              scenario.accepted
                  ? endsWith('PROJECT_TASK_SUBTASK_DONE')
                  : isNot(endsWith('PROJECT_TASK_SUBTASK_DONE')),
            );
            expect(
              (observation['memory'] as Map)['summary'],
              terminal.memorySummary,
            );
            expect(
              (observation['memory'] as Map)['openLoops'],
              contains(terminal.memoryNextStep),
            );
            expect(observation['memoryInput'], contains('"scope":"subtask"'));
            expect(
              observation['memoryInput'],
              contains('"completionAccepted":${scenario.accepted}'),
            );
            expect(
              observation['goalStatus'],
              scenario.accepted ? 'active' : isNot('completed'),
            );
          }
          for (final entry in beforeFiles.entries) {
            expect(
              File('${root.path}/${entry.key}').readAsStringSync(),
              scenario.stdin && entry.key == 'README.md'
                  ? farmStepReadmeAfter
                  : entry.value,
            );
          }
          expect(File('${root.path}/pending.txt').existsSync(), isFalse);
          expect(File('${root.path}/required.flag').existsSync(), isFalse);
          if (scenario.accepted) {
            expect(
              approver.decisions.where(
                (decision) => decision['approved'] == false,
              ),
              isEmpty,
            );
          }
          passed = true;
        } finally {
          approver?.dispose();
          container.dispose();
          await conversationBox.close();
          await memoryBox.close();
          // Reopen actual persistence to prove the result survives container disposal.
          final reopenedConversation = await Hive.openBox<String>(
            'conversations',
            path: persistence,
          );
          final reopenedMemory = await Hive.openBox<String>(
            'memory',
            path: persistence,
          );
          try {
            final saved = conversationId == null
                ? null
                : ConversationRepository(
                    reopenedConversation,
                  ).getById(conversationId);
            final summary = ChatMemoryRepository.fromBox(
              reopenedMemory,
            ).loadSessionSummaries();
            if (passed) {
              expect(
                saved!.projectedExecutionTasks
                    .where(
                      (task) =>
                          task.status ==
                          ConversationWorkflowTaskStatus.completed,
                    )
                    .map((task) => task.id)
                    .toList(),
                marked,
              );
              expect(
                saved.messages
                    .lastWhere(
                      (message) => message.role == MessageRole.assistant,
                    )
                    .content,
                observations.last['answer'],
              );
              expect(summary.single.toJson(), observations.last['memory']);
            }
            File('${scratch.path}/evidence.json').writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert({
                'scenario': scenario.name,
                'liveHttp': !preflight,
                'passed': passed,
                'faultPreludeUsed': source.preludeUsed,
                'faultAnswerUsed': source.faultAnswerUsed,
                'livePrimaryCalls': source.livePrimaryCalls,
                'liveMemoryCalls': source.liveMemoryCalls,
                'recoveryCalls': source.recoveryCalls,
                if (scenario.stdin)
                  'stdinEvidence': {
                    'readmeShorthandPreludeUsed':
                        source.readmeShorthandPreludeUsed,
                    'changedPath': 'README.md',
                    'changed': source
                        .results['fixture-edit']
                        ?.outcome
                        ?.fileMutations
                        .single
                        .changed,
                    'verificationAfterMutation':
                        source.results.containsKey('fixture-edit') &&
                        source.results.values.toList().indexWhere(
                              (result) =>
                                  result.arguments['command'] ==
                                  fixture.verificationCommand,
                            ) >
                            source.results.keys.toList().indexOf(
                              'fixture-edit',
                            ),
                    'verificationCommand': fixture.verificationCommand,
                    'exitCodes': [
                      for (final execution in toolService.nativeExecutions)
                        if ((execution['arguments'] as Map)['command'] ==
                            fixture.verificationCommand)
                          (jsonDecode(execution['result'] as String)
                              as Map)['exit_code'],
                    ],
                  },
                'completedSubtasks': marked,
                'finalBoundaryReached': finalBoundary,
                'stopReason': observations.isEmpty ? 'No saved turn' : null,
                'approvals': approver?.decisions,
                'nativeExecutions': toolService.nativeExecutions,
                'observations': observations,
                'persistedConversation': saved?.toJson(),
                'persistedMemory': summary
                    .map((item) => item.toJson())
                    .toList(),
                'toolResults': source.results.values
                    .map(
                      (item) => {
                        'id': item.id,
                        'name': item.name,
                        'arguments': item.arguments,
                        'result': item.result,
                        'outcome': item.outcome?.toJson(),
                      },
                    )
                    .toList(),
                'liveResponses': source.liveResponses,
                'memoryResponses': source.memoryResponses,
                'outboundRequests': source.outboundRequests,
              }),
            );
          } finally {
            await reopenedConversation.close();
            await reopenedMemory.close();
            await root.delete(recursive: true);
          }
        }
      },
      skip: enabled || preflight
          ? false
          : 'Set CAVERNO_FARM_STEP_LIVE_CANARY=1 and CAVERNO_LLM_*.',
      timeout: const Timeout(Duration(minutes: 15)),
    );
  }
}
