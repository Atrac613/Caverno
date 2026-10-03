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
import 'package:caverno/features/maintenance/domain/entities/idle_maintenance_config.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_environment.dart';
import 'package:caverno/features/maintenance/domain/services/idle_maintenance_scheduler.dart';
import 'package:caverno/features/project_farm/application/farm_unattended_runner.dart';
import 'package:caverno/features/project_farm/data/roadmap_snapshot_repository.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/domain/entities/project_proposal.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _IdleEnvironment implements IdleMaintenanceEnvironment {
  @override
  DateTime now() => DateTime(2026, 10, 4, 3);
  @override
  Duration idleFor() => const Duration(hours: 1);
  @override
  bool onAcPower() => true;
}

class _FixtureClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  int successfulCalls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final text = utf8.decode(body);
    for (final forbidden in ['/Users/', 'Caverno agent guide', '.caverno/']) {
      if (text.contains(forbidden)) {
        throw StateError('Non-fixture HTTP payload');
      }
    }
    final forwarded = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = body;
    final response = await _inner.send(forwarded);
    if (response.statusCode == 200) successfulCalls++;
    return response;
  }

  @override
  void close() => _inner.close();
}

Future<String> _git(String root, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('Fixture Git failed: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}

void main() {
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
      final client = _FixtureClient();
      ProviderContainer? container;
      IdleMaintenanceScheduler? scheduler;
      WorktreeAgentTask? task;
      var passed = false;
      final evidence = <String, Object?>{'schemaVersion': 1, 'passed': false};
      try {
        await File('${root.path}/greeting.txt').writeAsString('hello\n');
        await File('${root.path}/roadmap.md').writeAsString(
          '- [ ] GR1: Set greeting.txt to hello from unattended.\n',
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
        await _git(root.path, ['init', '-b', 'main']);
        await _git(root.path, ['config', 'user.name', 'Canary']);
        await _git(root.path, [
          'config',
          'user.email',
          'canary@example.invalid',
        ]);
        await _git(root.path, ['config', 'commit.gpgsign', 'false']);
        await _git(root.path, ['config', 'core.hooksPath', '/dev/null']);
        await _git(root.path, [
          'add',
          '--',
          'greeting.txt',
          'roadmap.md',
          'verify.py',
          'python',
        ]);
        await _git(root.path, [
          'commit',
          '-m',
          'test: initialize synthetic fixture',
        ]);
        final initialHead = await _git(root.path, ['rev-parse', 'HEAD']);
        // This Flutter test lives under tool/canaries rather than test/.
        // ignore: invalid_use_of_visible_for_testing_member
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final now = _IdleEnvironment().now();
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
        final runs = <Future<WorktreeAgentTaskRunResult>>[];
        final farm = FarmUnattendedRunner(
          repository: repository,
          projects: () => [project],
          refreshSnapshot: (_) async => RoadmapSnapshot(
            projectId: project.id,
            roadmapPath: 'roadmap.md',
            contentSha256: 'fixture',
            extractorVersion: 1,
            model: 'fixed-fixture',
            extractedAt: now,
            status: RoadmapSnapshotStatus.verified,
            recommended: const RoadmapItemSnapshot(
              id: 'GR1',
              title: 'Greeting',
              quote:
                  'Set greeting.txt to exactly hello from unattended followed by a newline. Edit only greeting.txt; preserve verify.py, python and roadmap.md.',
              line: 1,
            ),
          ),
          refreshProposal: (_, _) async => ProjectProposal(
            projectId: project.id,
            inputHash: 'fixture',
            proposedAt: now,
            taskId: 'GR1',
            automatability: 'unattended',
          ),
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
        scheduler = IdleMaintenanceScheduler(
          environment: _IdleEnvironment(),
          configProvider: () => const IdleMaintenanceConfig(
            enabled: true,
            windowStartMinutes: 120,
            windowEndMinutes: 360,
            minIdle: Duration(minutes: 10),
            requireAcPower: true,
          ),
          run: (handle) async {
            await farm.run(isCancelled: () => handle.isCancelled);
          },
        );
        await scheduler.tick();
        await scheduler.drain();
        expect(runs, hasLength(1));
        final result = await runs.single;
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
          'finalHead': await _git(root.path, ['rev-parse', 'HEAD']),
          'worktreeHead': await _git(task.worktreePath, ['rev-parse', 'HEAD']),
          'worktreeStatus': await _git(task.worktreePath, [
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
          await _git(task.worktreePath, ['rev-parse', '--abbrev-ref', 'HEAD']),
          task.branchName,
        );
        expect(
          await _git(task.worktreePath, ['rev-parse', 'HEAD']),
          initialHead,
        );
        expect(await _git(root.path, ['rev-parse', 'HEAD']), initialHead);
        expect(await _git(root.path, ['status', '--porcelain']), isEmpty);
        expect(
          (await _git(root.path, [
            'worktree',
            'list',
            '--porcelain',
          ])).split('\n').where((l) => l.startsWith('worktree ')),
          hasLength(2),
        );
        final persisted = WorktreeAgentTaskRepository(prefs).loadAll().single;
        expect(persisted.status, WorktreeAgentTaskStatus.completed);
        expect(persisted.verifiedGreen, isTrue);
        await scheduler.tick();
        await scheduler.drain();
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
          'finalHead': await _git(root.path, ['rev-parse', 'HEAD']),
          'worktreeHead': await _git(task.worktreePath, ['rev-parse', 'HEAD']),
          'worktreeStatus': await _git(task.worktreePath, [
            'status',
            '--porcelain',
          ]),
          'dispatchCount': runs.length,
        });
        passed = true;
      } finally {
        scheduler?.stop();
        container?.dispose();
        client.close();
        // This removes only worktrees owned by the disposable synthetic repo.
        final listing = await _git(root.path, [
          'worktree',
          'list',
          '--porcelain',
        ]);
        for (final line
            in listing.split('\n').where((l) => l.startsWith('worktree '))) {
          final path = line.substring(9);
          if (path != root.path && path.startsWith('${scratch.path}/')) {
            await _git(root.path, ['worktree', 'remove', '--force', path]);
          }
        }
        await scratch.delete(recursive: true);
        evidence.addAll({
          'passed': passed,
          'scratchRemoved': !scratch.existsSync(),
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
