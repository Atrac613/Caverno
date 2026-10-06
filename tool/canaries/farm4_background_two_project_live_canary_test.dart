import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/mesh_secondary_completion_runner.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_executor.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_verification_runner.dart';
import 'package:caverno/features/project_farm/application/background_task_runner.dart';
import 'package:caverno/features/project_farm/domain/entities/project_farm_policy.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// FARM4 slice 4c live canary: two projects' background tasks at once.
///
/// Each project gets the FARM4 prompt (`backgroundTaskPrompt`) and a command
/// its own policy allows. They run concurrently through the production LL13
/// execution delegate against scratch directories (no git, nothing of the
/// user's). Passing means each run is verified green, changed only its own
/// file, and wrote only its own marker: nothing crossed between projects.
///
/// ```bash
/// CAVERNO_FARM4_LIVE_CANARY=1 \
/// CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 \
/// tool/with_live_llm_loopback.sh -- \
///   fvm flutter test tool/canaries/farm4_background_two_project_live_canary_test.dart
/// ```
void main() {
  final enabled = Platform.environment['CAVERNO_FARM4_LIVE_CANARY'] == '1';
  final baseUrl = Platform.environment['CAVERNO_LLM_BASE_URL'] ?? '';
  final apiKey = Platform.environment['CAVERNO_LLM_API_KEY'] ?? 'none';
  final model = Platform.environment['CAVERNO_LLM_MODEL'] ?? 'qwen3.8-27b-exl3';

  test(
    'two projects run in the background without crossing',
    () async {
      final scratch = await Directory.systemTemp.createTemp('farm4_canary_');
      addTearDown(() => scratch.delete(recursive: true));
      final projects = {'alpha': 'hello from alpha', 'beta': 'hello from beta'};

      final outcomes = await Future.wait([
        for (final entry in projects.entries)
          _runProject(
            directory: Directory('${scratch.path}/${entry.key}'),
            projectId: entry.key,
            marker: entry.value,
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
          ),
      ]);

      for (final (index, entry) in projects.entries.indexed) {
        final outcome = outcomes[index];
        final other = projects.values.firstWhere((m) => m != entry.value);
        final greeting = File(
          '${scratch.path}/${entry.key}/lib/greeting.dart',
        ).readAsStringSync();
        stdout.writeln(
          '[farm4-probe] ${entry.key}: green=${outcome.verifiedGreen} '
          'changed=${outcome.changedFiles.map((f) => f.path).toList()} '
          'greeting=${greeting.trim()}',
        );
        expect(
          outcome.verifiedGreen,
          isTrue,
          reason: outcome.verificationSummary,
        );
        expect(outcome.changedFiles.map((f) => f.path), ['lib/greeting.dart']);
        expect(greeting, contains(entry.value));
        expect(greeting, isNot(contains(other)));
      }
    },
    skip: enabled ? false : 'Set CAVERNO_FARM4_LIVE_CANARY=1',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<WorktreeAgentTaskExecutionOutcome> _runProject({
  required Directory directory,
  required String projectId,
  required String marker,
  required String baseUrl,
  required String apiKey,
  required String model,
}) async {
  await Directory('${directory.path}/lib').create(recursive: true);
  await Directory('${directory.path}/tool').create();
  await File(
    '${directory.path}/lib/greeting.dart',
  ).writeAsString("String greeting() => 'hello';\n");
  await File('${directory.path}/tool/verify.dart').writeAsString('''
import 'dart:io';

void main() {
  final source = File('lib/greeting.dart').readAsStringSync().trim();
  if (source == "String greeting() => '$marker';") return;
  stderr.writeln('Expected greeting() to return "$marker".');
  exitCode = 1;
}
''');

  const command = 'dart tool/verify.dart';
  final policy = ProjectFarmPolicy(
    projectId: projectId,
    allowedVerificationCommands: const [command],
    updatedAt: DateTime.now(),
  );
  expect(policy.allows(command), isTrue);
  final item = RoadmapItemSnapshot(
    id: 'GR1',
    title: 'Greeting text',
    quote:
        "Next: GR1, change greeting() in lib/greeting.dart to return '$marker'.",
    line: 1,
  );
  final now = DateTime.now().toUtc();
  final task = WorktreeAgentTask(
    id: 'farm4-$projectId',
    status: WorktreeAgentTaskStatus.running,
    title: 'GR1: Greeting text',
    prompt: backgroundTaskPrompt(item, 'docs/roadmap.md'),
    branchName: 'agent/farm4-$projectId',
    worktreePath: directory.path,
    verificationCommand: command,
    codingProjectId: projectId,
    createdAt: now,
    updatedAt: now,
    startedAt: now,
  );
  final settings = AppSettings.defaults().copyWith(
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    subagentModel: model,
    temperature: 0,
    maxTokens: 2048,
    mcpEnabled: false,
  );
  return WorktreeAgentLlmExecutionDelegate(
    settings: settings,
    primaryDataSource: ChatRemoteDataSource(baseUrl: baseUrl, apiKey: apiKey),
    meshRunner: MeshSecondaryCompletionRunner<ChatDataSource>(
      router: const MeshEndpointRouter(),
      health: EndpointHealthTracker(),
      buildEndpointDataSource: (url, key) =>
          ChatRemoteDataSource(baseUrl: url, apiKey: key),
    ),
    toolService: McpToolService(),
    verificationRunner: const WorktreeAgentVerificationRunner(
      timeout: Duration(seconds: 60),
    ),
  ).execute(WorktreeAgentTaskExecutionContext(task: task));
}
