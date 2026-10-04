import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_data_source_provider.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/project_farm/application/project_task_commit_turn_evidence.dart';
import 'package:caverno/features/project_farm/application/project_task_review_turn_runner.dart';
import 'package:caverno/features/project_farm/application/project_task_review_workflow.dart';
import 'package:caverno/features/project_farm/application/project_task_step_turn_runner.dart';
import 'package:caverno/features/project_farm/data/project_git_status_reader.dart';
import 'package:caverno/features/project_farm/data/project_task_commit_reader.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_commit_scope.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'support/farm_completion_fixture.dart';
import 'support/farm_completion_source.dart';
import 'support/farm_completion_tools.dart';
import 'support/farm_step_live_fixture.dart';

void main() {
  final preflight =
      Platform.environment['CAVERNO_FARM_COMPLETION_OFFLINE_PREFLIGHT'] == '1';
  final enabled =
      Platform.environment['CAVERNO_FARM_COMPLETION_LIVE_CANARY'] == '1';
  for (final scenario in FarmCompletionScenario.values) {
    test(
      '${preflight ? 'offline' : 'live'} Farm completion: ${scenario.name}',
      () async {
        for (final key in [
          'CAVERNO_LLM_BASE_URL',
          'CAVERNO_LLM_API_KEY',
          'CAVERNO_LLM_MODEL',
          'CAVERNO_FARM_COMPLETION_REPORT_DIR',
        ]) {
          expect(
            Platform.environment[key],
            isNotEmpty,
            reason: '$key is required',
          );
        }
        expect(Platform.isMacOS, isTrue);
        final report = Directory(
          '${Platform.environment['CAVERNO_FARM_COMPLETION_REPORT_DIR']}/${scenario.name}',
        )..createSync(recursive: true);
        final temporary = Directory.systemTemp.createTempSync(
          'caverno-farm-completion-',
        );
        final root = Directory(temporary.resolveSymbolicLinksSync());
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        final fixture = FarmCompletionFixture(root, scenario);
        await fixture.initialize();
        final persistence = '${report.path}/persistence';
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
        final source = FarmCompletionSource(
          ChatRemoteDataSource(
            baseUrl: Platform.environment['CAVERNO_LLM_BASE_URL']!,
            apiKey: Platform.environment['CAVERNO_LLM_API_KEY']!,
          ),
          fixture,
          preflight: preflight,
        );
        final lifecycle = FarmStepLifecycle();
        when(() => lifecycle.isInBackground).thenReturn(false);
        final tools = FarmCompletionTools(fixture);
        final container = ProviderContainer(
          overrides: [
            settingsNotifierProvider.overrideWith(FarmCompletionSettings.new),
            sharedPreferencesProvider.overrideWithValue(FarmStepPreferences()),
            conversationRepositoryProvider.overrideWithValue(repository),
            chatMemoryRepositoryProvider.overrideWithValue(memory),
            sessionMemoryServiceProvider.overrideWithValue(memoryService),
            codingProjectsNotifierProvider.overrideWith(
              () => FarmStepProjects(fixture.project),
            ),
            chatRemoteDataSourceProvider.overrideWithValue(source),
            primaryRouteEndpointDataSourceFactoryProvider.overrideWithValue(({
              required baseUrl,
              required apiKey,
              required endpointId,
            }) {
              if (baseUrl != Platform.environment['CAVERNO_LLM_BASE_URL'] ||
                  endpointId != 'fixture-review' ||
                  apiKey != Platform.environment['CAVERNO_LLM_API_KEY']) {
                throw StateError('Outside fixture review endpoint');
              }
              return source;
            }),
            mcpToolServiceProvider.overrideWithValue(tools),
            appLifecycleServiceProvider.overrideWithValue(lifecycle),
            backgroundTaskServiceProvider.overrideWithValue(
              FarmStepBackground(),
            ),
            notificationServiceProvider.overrideWithValue(
              FarmStepNotifications(),
            ),
          ],
        );
        FarmCompletionApprover? approver;
        String? conversationId;
        String? stopReason;
        String? outcome;
        final turns = <Map<String, dynamic>>[];
        final phases = <String>[];
        final preparationSnapshots = <Map<String, dynamic>>[];
        Map<String, dynamic>? commitPermit;
        final commitChecks = <Map<String, dynamic>>[];
        final commitPermits = <Map<String, dynamic>>[];
        Map<String, dynamic> snapshotEvidence(
          ProjectTaskCommitSnapshot snapshot,
        ) {
          String relative(String file) => file.substring(root.path.length + 1);
          return {
            'head': snapshot.head,
            'indexFingerprint': snapshot.indexFingerprint,
            'fileFingerprints': {
              for (final entry in snapshot.fileFingerprints.entries)
                relative(entry.key): entry.value,
            },
            'stagedPaths': snapshot.stagedPaths.map(relative).toList()..sort(),
            'taskUnstagedPaths': snapshot.unstagedPaths
                .where(
                  (file) =>
                      file == '${root.path}/fixture.py' ||
                      file == '${root.path}/roadmap.md',
                )
                .map(relative)
                .toList(),
            'roadmapComplete': snapshot.roadmapAlreadyDone,
          };
        }

        Map<String, dynamic>? oracle;
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
              id: 'synthetic-goal',
              objective: fixture.objective,
              projectTaskAutoReview: true,
              tokenBudget: 90000,
              turnBudget: 9,
              createdAt: now,
              updatedAt: now,
            ),
          );
          conversationId = conversation.id;
          conversations.selectConversation(conversation.id);
          final notifier = container.read(chatNotifierProvider.notifier);
          approver = FarmCompletionApprover(container, tools);
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
          Future<void> wait(ChatTurnOwner owner) async {
            await notifier
                .waitForTurnCompletion(owner)
                .timeout(const Duration(minutes: 7));
            await memoryService.waitForUpdate(++completedTurns);
            await Future<void>.delayed(Duration.zero);
            await conversationBox.flush();
            await memoryBox.flush();
            final saved = repository.getById(conversation.id)!;
            const statusPrefix = 'Recorded project task status: ';
            final statusLine = source.memoryInputs.last
                .split('\n')
                .firstWhere(
                  (line) => line.startsWith(statusPrefix),
                  orElse: () => '',
                );
            turns.add({
              'stage': source.stage,
              'livePrimaryCalls': source.currentTurnLiveCalls,
              'answer': saved.messages
                  .lastWhere((message) => message.role == MessageRole.assistant)
                  .content,
              'goalStatus': saved.goal!.status.name,
              'taskStatus': statusLine.isEmpty
                  ? null
                  : jsonDecode(statusLine.substring(statusPrefix.length)),
              'fixtureCode': File('${root.path}/fixture.py').readAsStringSync(),
              'head': await fixture.git(['rev-parse', 'HEAD']),
              'roadmap': File('${root.path}/roadmap.md').readAsStringSync(),
              'memoryInput': source.memoryInputs.last,
              'memory': memory.loadSessionSummaries().single.toJson(),
            });
          }

          final runner = ProjectTaskReviewTurnRunner(
            readConversation: readTask,
            isSelected: selected,
            isWaitingForUser: waiting,
            reactivate: () => conversations.markCurrentGoalStatus(
              status: ConversationGoalStatus.active,
            ),
            sendTurn: (prompt, {required codeReview}) => notifier.sendMessage(
              prompt,
              languageCode: 'en',
              bypassPlanMode: true,
              purpose: codeReview
                  ? PrimaryTurnPurpose.codeReview
                  : PrimaryTurnPurpose.projectTaskImplementation,
            ),
            waitForCompletion: wait,
          );
          ProjectTaskCommitTurnEvidence? commitTurnEvidence;
          ProjectTaskStepTurnRunner commitRunner(
            ProjectTaskCommitScope scope,
            bool preparing,
          ) => ProjectTaskStepTurnRunner(
            readConversation: readTask,
            isSelected: selected,
            isWaitingForUser: waiting,
            admits: ProjectTaskStepTurnRunner.completedGoal,
            sendTurn: (prompt) => notifier.sendProjectTaskCommit(
              prompt,
              scope,
              languageCode: 'en',
              purpose: preparing
                  ? PrimaryTurnPurpose.projectTaskCommitPreparation
                  : PrimaryTurnPurpose.projectTaskCommit,
            ),
            waitForCompletion: (owner) async {
              await wait(owner);
              commitTurnEvidence = notifier.takeProjectTaskCommitTurnEvidence(
                owner,
              );
              turns.last['phaseEvidence'] = commitTurnEvidence == null
                  ? null
                  : {
                      'completedNormally':
                          commitTurnEvidence!.completedNormally,
                      'mutationAttempted':
                          commitTurnEvidence!.mutationAttempted,
                      'failed': commitTurnEvidence!.failed,
                    };
            },
          );
          const gitReader = ProjectGitStatusReader();
          var implementing = 0;
          final workflow = ProjectTaskReviewWorkflow(
            conversationId: conversation.id,
            readConversation: readTask,
            isSelected: selected,
            isWaitingForUser: waiting,
            send: (prompt, {required codeReview}) {
              final stage = codeReview
                  ? 'review'
                  : implementing++ == 0
                  ? 'implementation'
                  : 'repair';
              source.beginTurn(stage);
              tools.scope.stage = stage;
              return runner.send(prompt, codeReview: codeReview);
            },
            projectRoot: root.path,
            readCommitTurnEvidence: () => commitTurnEvidence,
            readCommitSnapshot: (scope) async {
              final snapshot = await const ProjectTaskCommitReader().read(
                scope,
              );
              if (snapshot != null) {
                (scope.prepared == null ? preparationSnapshots : commitChecks)
                    .add(snapshotEvidence(snapshot));
              }
              return snapshot;
            },
            prepareCommit: (prompt, scope) {
              commitTurnEvidence = null;
              source.beginTurn('prepare');
              tools.scope.stage = 'prepare';
              return commitRunner(scope, true).send(prompt);
            },
            commit: (prompt, scope) {
              commitTurnEvidence = null;
              commitPermit = snapshotEvidence(scope.prepared!);
              commitPermits.add(commitPermit!);
              source.beginTurn('commit');
              tools.scope.stage = 'commit';
              return commitRunner(scope, false).send(prompt);
            },
            readGitState: (paths) => gitReader.readTaskState(root.path, paths),
            readTaskPatch: (paths) => gitReader.readTaskPatch(root.path, paths),
            onProgress: (progress) =>
                phases.add('${progress.phase.name}:${progress.outcome.name}'),
          );
          final result = await workflow.run();
          outcome = result.name;
          stopReason = workflow.stopReason;
          final failed = scenario == FarmCompletionScenario.failedVerification;
          expect(
            result,
            failed
                ? ProjectTaskReviewResult.stopped
                : ProjectTaskReviewResult.committed,
            reason: stopReason,
          );
          final implementation = turns
              .where(
                (turn) => ['implementation', 'repair'].contains(turn['stage']),
              )
              .toList();
          final reviews = turns
              .where((turn) => turn['stage'] == 'review')
              .toList();
          final acceptedReviews = reviews.where((turn) {
            final last = ContentParser.stripModelHistoryArtifacts(
              turn['answer'] as String,
            ).trimRight().split('\n').last.trim();
            return last == 'PROJECT_TASK_REVIEW_CLEAN' ||
                last == 'PROJECT_TASK_REVIEW_FINDINGS';
          }).toList();
          if (!preflight) {
            for (final review in acceptedReviews) {
              final latestEvidence = (review['memoryInput'] as String)
                  .split(
                    'Application-executed tool results for the latest turn:',
                  )
                  .last
                  .split('Output rules:')
                  .first;
              expect(latestEvidence, contains('- read_file:'));
              expect(latestEvidence, contains('/fixture.py'));
              expect(
                latestEvidence,
                isNot(contains('unverified_read_only_inspection_claim')),
              );
            }
          }
          expect(
            implementation,
            hasLength(scenario == FarmCompletionScenario.reviewRepair ? 2 : 1),
          );
          expect(
            acceptedReviews,
            hasLength(
              failed
                  ? 0
                  : scenario == FarmCompletionScenario.reviewRepair
                  ? 2
                  : 1,
            ),
          );
          expect(reviews.length, lessThanOrEqualTo(acceptedReviews.length * 2));
          expect(
            turns.where((turn) => turn['stage'] == 'prepare'),
            hasLength(failed ? 0 : inInclusiveRange(1, 2)),
          );
          expect(
            turns.where((turn) => turn['stage'] == 'commit'),
            hasLength(failed ? 0 : inInclusiveRange(1, 2)),
          );
          if (!preflight) {
            expect(source.livePrimaryCalls, greaterThan(0));
            expect(source.liveMemoryCalls, turns.length);
            for (final turn in turns) {
              if (scenario == FarmCompletionScenario.reviewRepair &&
                  turn['stage'] == 'implementation') {
                continue;
              }
              expect(
                turn['livePrimaryCalls'],
                greaterThan(0),
                reason: 'Every real turn, including recovery, must use HTTP.',
              );
            }
            for (final stage
                in turns.map((turn) => turn['stage'] as String).toSet()) {
              if (scenario == FarmCompletionScenario.reviewRepair &&
                  stage == 'implementation') {
                continue;
              }
              expect(
                source.callsByStage[stage],
                greaterThan(0),
                reason: '$stage must use HTTP',
              );
            }
          }
          String? reviewedCode;
          for (final turn in turns) {
            if (['implementation', 'repair'].contains(turn['stage'])) {
              reviewedCode = turn['fixtureCode'] as String;
            }
            if (turn['stage'] == 'review') {
              expect(
                turn['fixtureCode'],
                reviewedCode,
                reason: 'Review must leave code unchanged',
              );
              expect(turn['head'], fixture.initialHead);
            }
            expect(turn['answer'], isNot(contains('[Tool dispatch error:')));
            if (!['prepare', 'commit'].contains(turn['stage'])) {
              expect(turn['roadmap'], farmCompletionRoadmap);
            }
          }
          expect(source.memoryResponses, hasLength(turns.length));
          expect(tools.nativeExecutions, isNotEmpty);
          for (final execution in tools.nativeExecutions) {
            expect(
              (execution['arguments'] as Map)['workspace_command_containment'],
              true,
            );
            expect(
              jsonDecode(execution['result'] as String)['exit_code'],
              failed ? isNot(0) : 0,
            );
          }
          if (failed) {
            expect(readTask()!.goal!.status, ConversationGoalStatus.blocked);
            expect(
              ContentParser.stripModelHistoryArtifacts(
                turns.single['answer'] as String,
              ),
              isNot(endsWith('PROJECT_TASK_READY_FOR_REVIEW')),
            );
            expect(
              turns.single['memoryInput'],
              allOf(
                contains('"completionAccepted":false'),
                contains('"status":"blockerLogged"'),
              ),
            );
            expect(
              (turns.single['taskStatus'] as Map)['gaps'],
              isNot(contains('the tool loop stopped before the work converged')),
            );
            expect(
              tools.gitExecutions.where((entry) => entry['mutation'] != false),
              isEmpty,
            );
            expect(
              await fixture.git(['rev-parse', 'HEAD']),
              fixture.initialHead,
            );
            expect(
              File('${root.path}/roadmap.md').readAsStringSync(),
              farmCompletionRoadmap,
            );
            expect(File('${root.path}/required.flag').existsSync(), isFalse);
          } else {
            for (final turn in implementation) {
              expect(turn['goalStatus'], 'completed');
              expect(
                ContentParser.stripModelHistoryArtifacts(
                  turn['answer'] as String,
                ),
                endsWith('PROJECT_TASK_READY_FOR_REVIEW'),
              );
              expect(
                turn['memoryInput'],
                contains('"completionAccepted":true'),
              );
              expect(turn['head'], fixture.initialHead);
            }
            expect(
              ContentParser.stripModelHistoryArtifacts(
                reviews.last['answer'] as String,
              ),
              endsWith('PROJECT_TASK_REVIEW_CLEAN'),
            );
            if (scenario == FarmCompletionScenario.reviewRepair) {
              expect(source.preludeUsed || preflight, isTrue);
              expect(
                implementation.first['fixtureCode'],
                farmCompletionBadCode,
              );
              expect(
                ContentParser.stripModelHistoryArtifacts(
                  acceptedReviews.first['answer'] as String,
                ),
                endsWith('PROJECT_TASK_REVIEW_FINDINGS'),
              );
              expect(phases, contains('repair:running'));
            }
            final oracleResult = await LocalShellTools.executeResult(
              command: '.venv/bin/python tool/oracle.py',
              workingDirectory: root.path,
              projectRoot: root.path,
              containmentRoot: root.path,
            );
            oracle = jsonDecode(oracleResult.result) as Map<String, dynamic>;
            expect(oracle['exit_code'], 0);
            expect(
              oracle['stdout'],
              contains('FARM_COMPLETION_ORACLE: 7 checks passed'),
            );
            expect(await fixture.git(['rev-list', '--count', 'HEAD']), '2');
            expect(
              await fixture.git([
                'diff-tree',
                '--no-commit-id',
                '--name-only',
                '-r',
                'HEAD',
              ]),
              'fixture.py\nroadmap.md',
            );
            expect(
              await fixture.git(['status', '--porcelain']),
              ' M unrelated.txt',
            );
            expect(
              File('${root.path}/roadmap.md').readAsStringSync(),
              farmCompletionRoadmap.replaceFirst('[ ]', '[x]'),
            );
            expect(
              tools.gitExecutions.where(
                (entry) => (entry['arguments'] as Map)['command']
                    .toString()
                    .startsWith('commit '),
              ),
              hasLength(1),
            );
            expect(
              approver.decisions.where(
                (decision) =>
                    decision['kind'] == 'git' && decision['approved'] == true,
              ),
              hasLength(greaterThanOrEqualTo(2)),
            );
          }
          for (final denial in approver.decisions.where(
            (decision) => decision['approved'] == false,
          )) {
            if (denial['kind'] == 'local') {
              expect(
                tools.nativeExecutions.where(
                  (entry) =>
                      (entry['arguments'] as Map)['command'] ==
                          denial['command'] &&
                      entry['stage'] == denial['stage'],
                ),
                isEmpty,
                reason:
                    'A denied model command must never reach native execution',
              );
            } else if (denial['kind'] == 'git') {
              expect(
                tools.gitExecutions.where(
                  (entry) =>
                      (entry['arguments'] as Map)['command'] ==
                          denial['command'] &&
                      entry['stage'] == denial['stage'],
                ),
                isEmpty,
                reason: 'A denied Git operation must never execute',
              );
            }
          }
          for (final entry in fixture.initialFiles.entries.where(
            (entry) => ![
              'fixture.py',
              'roadmap.md',
              'unrelated.txt',
            ].contains(entry.key),
          )) {
            expect(
              File('${root.path}/${entry.key}').readAsStringSync(),
              entry.value,
            );
          }
          expect(
            File('${root.path}/unrelated.txt').readAsStringSync(),
            'Unrelated pre-existing change.\n',
          );
          for (final response in source.memoryResponses) {
            expect(
              MemoryExtractionDraftService.parseDraft(response),
              isNotNull,
            );
          }
          passed = true;
        } finally {
          approver?.dispose();
          container.dispose();
          await conversationBox.close();
          await memoryBox.close();
          final reopened = await Hive.openBox<String>(
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
                : ConversationRepository(reopened).getById(conversationId);
            final summaries = ChatMemoryRepository.fromBox(
              reopenedMemory,
            ).loadSessionSummaries();
            if (passed) {
              expect(
                saved!.messages
                    .lastWhere(
                      (message) => message.role == MessageRole.assistant,
                    )
                    .content,
                turns.last['answer'],
              );
              expect(saved.goal!.status.name, turns.last['goalStatus']);
              expect(summaries.single.toJson(), turns.last['memory']);
            }
            File('${report.path}/evidence.json').writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert({
                'scenario': scenario.name,
                'passed': passed,
                'liveHttp': !preflight,
                'result': outcome,
                'stopReason': stopReason,
                'phases': phases,
                'fixtureRoot': root.path,
                'initialHead': fixture.initialHead,
                'finalHead': await fixture.git(['rev-parse', 'HEAD']),
                'finalStatus': await fixture.git(['status', '--porcelain']),
                'lastCommit': await fixture.git(['log', '-1', '--format=%B']),
                'changedFiles': await fixture.git([
                  'diff-tree',
                  '--no-commit-id',
                  '--name-only',
                  '-r',
                  'HEAD',
                ]),
                'faultPreludeUsed': source.preludeUsed,
                'livePrimaryCalls': source.livePrimaryCalls,
                'liveMemoryCalls': source.liveMemoryCalls,
                'callsByStage': source.callsByStage,
                'turns': turns,
                'nativeExecutions': tools.nativeExecutions,
                'gitExecutions': tools.gitExecutions,
                'preparationSnapshots': preparationSnapshots,
                'commitPermit': commitPermit,
                'commitPermits': commitPermits,
                'commitChecks': commitChecks,
                'approvals': approver?.decisions,
                'oracle': oracle,
                'persistedConversation': saved?.toJson(),
                'persistedMemory': summaries
                    .map((item) => item.toJson())
                    .toList(),
                'memoryResponses': source.memoryResponses,
                'liveResponses': source.liveResponses,
                'toolResults': source.results.values
                    .map(
                      (item) => {
                        'id': item.id,
                        'name': item.name,
                        'arguments': item.arguments,
                        'result': item.result,
                      },
                    )
                    .toList(),
                'outboundRequests': source.outboundRequests,
              }),
            );
          } finally {
            await reopened.close();
            await reopenedMemory.close();
            await root.delete(recursive: true);
          }
        }
      },
      skip: enabled || preflight
          ? false
          : 'Set CAVERNO_FARM_COMPLETION_LIVE_CANARY=1 and CAVERNO_LLM_*.',
      timeout: const Timeout(Duration(minutes: 20)),
    );
  }
}
