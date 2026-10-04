import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/mesh_secondary_completion_runner.dart';
import 'package:caverno/features/chat/data/repositories/coding_project_repository.dart';
import 'package:caverno/features/chat/data/repositories/worktree_agent_task_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_executor.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_launcher.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_orchestrator.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_verification_runner.dart';
import 'package:caverno/features/project_farm/application/farm_unattended_runner.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/farm_unattended_maintenance_probe.dart';
import 'support/farm_unattended_proposal_probe.dart';
import 'support/farm_unattended_snapshot_probe.dart';
import 'support/farm_unattended_support.dart';

void main() {
  final originalHttpOverrides = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = originalHttpOverrides;
  final env = Platform.environment;
  test(
    'live unattended Farm dispatch creates and verifies a real worktree',
    () async {
      expect(Platform.isMacOS, isTrue);
      expect(env['CAVERNO_LIVE_LLM_DATA_EXPORT_ACK'], '1');
      final report = Directory(env['CAVERNO_FARM_UNATTENDED_REPORT_DIR']!);
      await report.create(recursive: true);
      final scratch = await Directory.systemTemp.createTemp('farm_unattended_');
      final root = await Directory('${scratch.path}/project').create();
      final client = FarmFixtureClient();
      final proposalClient = FarmFixtureClient();
      final snapshotClient = FarmFixtureClient();
      FarmUnattendedSnapshotProbe? snapshots;
      ProviderContainer? container;
      FarmUnattendedMaintenanceProbe? maintenance;
      WorktreeAgentTask? task;
      var passed = false;
      final evidence = <String, Object?>{'schemaVersion': 4, 'passed': false};
      try {
        await File('${root.path}/greeting.txt').writeAsString('hello\n');
        await File('${root.path}/roadmap.md').writeAsString(
          '# Synthetic roadmap\n\nNext: GR1\n\n- [ ] GR1: Set greeting.txt to exactly hello from unattended followed by a newline. Edit only greeting.txt; preserve verify.py, python and roadmap.md.\n',
        );
        const verifier = '''from pathlib import Path
assert Path("greeting.txt").read_text() == "hello from unattended\\n"
print("UNATTENDED_ORACLE_OK")
''';
        await File('${root.path}/verify.py').writeAsString(verifier);
        final python = [
          '/opt/homebrew/bin/python3',
          '/usr/local/bin/python3',
          '/Library/Developer/CommandLineTools/usr/bin/python3',
        ].firstWhere((p) => File(p).existsSync());
        const command = './python verify.py';
        await Link(
          '${root.path}/python',
        ).create(File(python).resolveSymbolicLinksSync());
        await farmFixtureGit(root.path, ['init', '-b', 'main']);
        await farmFixtureGit(root.path, ['config', 'user.name', 'Canary']);
        await farmFixtureGit(root.path, [
          'config',
          'user.email',
          'canary@example.invalid',
        ]);
        await farmFixtureGit(root.path, ['config', 'commit.gpgsign', 'false']);
        await farmFixtureGit(root.path, [
          'config',
          'core.hooksPath',
          '/dev/null',
        ]);
        await farmFixtureGit(root.path, [
          'add',
          '--',
          'greeting.txt',
          'roadmap.md',
          'verify.py',
          'python',
        ]);
        await farmFixtureGit(root.path, [
          'commit',
          '-m',
          'test: initialize synthetic fixture',
        ]);
        final initialHead = await farmFixtureGit(root.path, [
          'rev-parse',
          'HEAD',
        ]);
        // This Flutter test lives under tool/canaries rather than test/.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final now = FarmIdleEnvironment().now();
        final project = CodingProject(
          id: 'synthetic',
          name: 'synthetic',
          rootPath: root.path,
          createdAt: now,
          updatedAt: now,
        );
        await CodingProjectRepository(prefs).saveAll([project]);
        final repository = RoadmapSnapshotRepository(prefs);
        await repository.savePolicy(
          ProjectFarmPolicy(
            projectId: project.id,
            allowedVerificationCommands: [command],
            unattendedCommands: [command],
            autoRunEnabled: true,
            dailyRunLimit: 1,
            updatedAt: now,
          ),
        );
        final settings = AppSettings.defaults().copyWith(
          baseUrl: env['CAVERNO_LLM_BASE_URL']!,
          apiKey: env['CAVERNO_LLM_API_KEY']!,
          model: env['CAVERNO_LLM_MODEL']!,
          subagentModel: env['CAVERNO_LLM_MODEL']!,
          temperature: 0,
          maxTokens: 2048,
          mcpEnabled: false,
        );
        final delegate = WorktreeAgentLlmExecutionDelegate(
          settings: settings,
          primaryDataSource: ChatRemoteDataSource(
            baseUrl: settings.baseUrl,
            apiKey: settings.apiKey,
            httpClient: client,
          ),
          meshRunner: MeshSecondaryCompletionRunner<ChatDataSource>(
            router: const MeshEndpointRouter(),
            health: EndpointHealthTracker(),
            buildEndpointDataSource: (_, _) =>
                throw StateError('Fixture must use the selected endpoint'),
          ),
          toolService: McpToolService(),
          verificationRunner: const WorktreeAgentVerificationRunner(
            timeout: Duration(seconds: 30),
          ),
        );
        container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            worktreeAgentTaskExecutionDelegateProvider.overrideWithValue(
              delegate.execute,
            ),
          ],
        );
        final active = container;
        snapshots = FarmUnattendedSnapshotProbe(
          repository: repository,
          source: ChatRemoteDataSource(
            baseUrl: settings.baseUrl,
            apiKey: settings.apiKey,
            httpClient: snapshotClient,
          ),
          model: settings.model,
          scratchRoot: scratch.path,
          now: now,
        );
        final snapshotProbe = snapshots;
        final proposals = FarmUnattendedProposalProbe(
          repository: repository,
          source: ChatRemoteDataSource(
            baseUrl: settings.baseUrl,
            apiKey: settings.apiKey,
            httpClient: proposalClient,
          ),
          model: settings.model,
          now: now,
          snapshots: snapshotProbe,
        );
        final runs = <Future<WorktreeAgentTaskRunResult>>[];
        final farm = FarmUnattendedRunner(
          repository: repository,
          projects: () => [project],
          refreshSnapshot: snapshotProbe.refresh,
          refreshProposal: proposals.refresh,
          tasks: () =>
              active.read(worktreeAgentTaskRegistryNotifierProvider).tasks,
          enqueue:
              ({
                required title,
                required prompt,
                required codingProjectId,
                required projectRootPath,
                required verificationCommand,
                required acceptanceCriteria,
              }) async =>
                  (await active
                          .read(worktreeAgentTaskLauncherProvider)
                          .enqueue(
                            WorktreeAgentTaskLaunchRequest(
                              title: title,
                              prompt: prompt,
                              codingProjectId: codingProjectId,
                              projectRootPath: projectRootPath,
                              worktreeRootPath: '${scratch.path}/worktrees',
                              verificationCommand: verificationCommand,
                              objectiveAcceptanceCriteria: acceptanceCriteria,
                            ),
                          ))
                      .task,
          startReady: (root) {
            runs.add(
              active
                  .read(worktreeAgentTaskOrchestratorProvider)
                  .startAndExecuteReady(
                    WorktreeAgentTaskRunRequest(
                      fallbackProjectRootPath: root,
                      maxStarts: 1,
                    ),
                  ),
            );
          },
          now: () => now,
        );
        maintenance = FarmUnattendedMaintenanceProbe(farm);
        await maintenance.openAfterForegroundCheck();
        expect(runs, hasLength(1));
        final result = await runs.single;
        evidence['proposalProbe'] = await proposals.checkHumanGate(project);
        evidence['proposalHttpCalls'] = proposalClient.successfulCalls;
        expect(result.schedule.failed, isEmpty);
        expect(result.schedule.started, hasLength(1));
        task = active
            .read(worktreeAgentTaskRegistryNotifierProvider)
            .tasks
            .single;
        evidence.addAll({
          'successfulHttpCalls': client.successfulCalls,
          'task': task.toJson(),
          'executionError': result.executions.single.errorMessage,
          'initialHead': initialHead,
          'finalHead': await farmFixtureGit(root.path, ['rev-parse', 'HEAD']),
          'worktreeHead': await farmFixtureGit(task.worktreePath, [
            'rev-parse',
            'HEAD',
          ]),
          'worktreeStatus': await farmFixtureGit(task.worktreePath, [
            'status',
            '--porcelain',
          ]),
          'dispatchCount': runs.length,
          'ledger': repository.farmRuns().map((r) => r.toJson()).toList(),
        });
        expect(
          result.executions.single.success,
          isTrue,
          reason: result.executions.single.errorMessage,
        );
        expect(task.status, WorktreeAgentTaskStatus.completed);
        expect(task.verifiedGreen, isTrue, reason: task.verificationSummary);
        expect(task.verificationSummary, contains('UNATTENDED_ORACLE_OK'));
        expect(client.successfulCalls, greaterThan(0));
        expect(task.changedFiles.map((f) => f.path), ['greeting.txt']);
        expect(
          File('${task.worktreePath}/greeting.txt').readAsStringSync(),
          'hello from unattended\n',
        );
        expect(
          File('${task.worktreePath}/verify.py').readAsStringSync(),
          verifier,
        );
        expect(
          File('${task.worktreePath}/roadmap.md').readAsStringSync(),
          File('${root.path}/roadmap.md').readAsStringSync(),
        );
        expect(
          await farmFixtureGit(task.worktreePath, [
            'rev-parse',
            '--abbrev-ref',
            'HEAD',
          ]),
          task.branchName,
        );
        expect(
          await farmFixtureGit(task.worktreePath, ['rev-parse', 'HEAD']),
          initialHead,
        );
        expect(
          await farmFixtureGit(root.path, ['rev-parse', 'HEAD']),
          initialHead,
        );
        expect(
          await farmFixtureGit(root.path, ['status', '--porcelain']),
          isEmpty,
        );
        expect(
          (await farmFixtureGit(root.path, [
            'worktree',
            'list',
            '--porcelain',
          ])).split('\n').where((l) => l.startsWith('worktree ')),
          hasLength(2),
        );
        final persisted = WorktreeAgentTaskRepository(prefs).loadAll().single;
        expect(persisted.status, WorktreeAgentTaskStatus.completed);
        expect(persisted.verifiedGreen, isTrue);
        await maintenance.checkNoRepeatAndResume();
        expect(runs, hasLength(1));
        final limit = await farm.run(isCancelled: () => false);
        expect(limit.started, 0);
        expect(limit.skipped, 1);
        expect(repository.farmRuns().last.detail, 'daily_limit');
        evidence.addAll({
          'successfulHttpCalls': client.successfulCalls,
          'task': persisted.toJson(),
          'ledger': repository.farmRuns().map((r) => r.toJson()).toList(),
          'initialHead': initialHead,
          'finalHead': await farmFixtureGit(root.path, ['rev-parse', 'HEAD']),
          'worktreeHead': await farmFixtureGit(task.worktreePath, [
            'rev-parse',
            'HEAD',
          ]),
          'worktreeStatus': await farmFixtureGit(task.worktreePath, [
            'status',
            '--porcelain',
          ]),
          'dispatchCount': runs.length,
        });
        passed = true;
      } finally {
        maintenance?.dispose();
        container?.dispose();
        client.close();
        proposalClient.close();
        snapshotClient.close();
        // This removes only worktrees owned by the disposable synthetic repo.
        final listing = await farmFixtureGit(root.path, [
          'worktree',
          'list',
          '--porcelain',
        ]);
        for (final line
            in listing.split('\n').where((l) => l.startsWith('worktree '))) {
          final path = line.substring(9);
          if (path != root.path && path.startsWith('${scratch.path}/')) {
            await farmFixtureGit(root.path, [
              'worktree',
              'remove',
              '--force',
              path,
            ]);
          }
        }
        await scratch.delete(recursive: true);
        evidence.addAll({
          'passed': passed,
          'scratchRemoved': !scratch.existsSync(),
          'wireToolCalls': client.wireToolCalls,
          'maintenanceProbe': maintenance?.evidence,
          'snapshotProbe': snapshots?.evidence,
          'snapshotResponses': snapshotClient.wireMessages,
          'snapshotHttpCalls': snapshotClient.successfulCalls,
          'proposalResponses': proposalClient.wireMessages,
          'proposalHttpCalls': proposalClient.successfulCalls,
        });
        await File(
          '${report.path}/evidence.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
      }
    },
    skip: env['CAVERNO_FARM_UNATTENDED_LIVE_CANARY'] == '1'
        ? false
        : 'Enable the synthetic unattended live canary',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
