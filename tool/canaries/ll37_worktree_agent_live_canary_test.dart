import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/mesh_secondary_completion_runner.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_executor.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_verification_runner.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled =
      Platform.environment['CAVERNO_LL37_WORKTREE_AGENT_LIVE_CANARY'] == '1';

  test(
    'records a controlled LL13 correct and known-broken pair',
    () async {
      final env = _LiveCanaryEnvironment.fromEnvironment();
      final outputDirectory = Directory(env.outputDirectoryPath);
      if (outputDirectory.existsSync()) {
        throw StateError('LL37 live canary output directory already exists.');
      }
      await outputDirectory.create(recursive: true);
      final scratchDirectory = Directory(
        '${outputDirectory.path}/private_scratch',
      );
      await scratchDirectory.create();

      final correct = await _runArm(
        env: env,
        id: 'll37-worktree-correct',
        worktreeDirectory: Directory('${scratchDirectory.path}/correct'),
        disableWriteTools: false,
      );
      final broken = await _runArm(
        env: env,
        id: 'll37-worktree-broken',
        worktreeDirectory: Directory('${scratchDirectory.path}/broken'),
        disableWriteTools: true,
      );

      expect(correct.status, WorktreeAgentTaskStatus.completed);
      expect(correct.verifiedGreen, isTrue);
      expect(correct.changedFiles, isNotEmpty);
      expect(correct.changedFileEvidenceTruncated, isFalse);
      expect(broken.status, WorktreeAgentTaskStatus.completed);
      expect(broken.verifiedGreen, isFalse);
      expect(broken.changedFiles, isEmpty);

      await File('${outputDirectory.path}/tasks.json').writeAsString(
        '${const JsonEncoder.withIndent(' ').convert([correct.toJson(), broken.toJson()])}\n',
      );
      await File('${outputDirectory.path}/selection.json').writeAsString(
        '${const JsonEncoder.withIndent(' ').convert({
          'schemaName': 'caverno_ll37_worktree_agent_history_selection',
          'schemaVersion': 1,
          'pairId': 'll37-worktree-agent-live-${DateTime.now().toUtc().millisecondsSinceEpoch}',
          'correctTaskId': correct.id,
          'brokenTaskId': broken.id,
          'evidenceClass': 'controlled_live_canary',
          'correctCaptureProvenance': 'production LL13 delegate with normal worktree-scoped file tools',
          'brokenCaptureProvenance': 'production LL13 delegate with write tools disabled as a known-broken control',
          'acceptanceCriteria': const ['greeting() returns the exact text hello world.', 'The verification command exits successfully for the correct implementation.'],
          'consent': const {'explicitUserConsent': true, 'scope': 'personal_eval_case_recording'},
        })}\n',
      );
      await File(
        '${outputDirectory.path}/canary_capture_summary.json',
      ).writeAsString(
        '${const JsonEncoder.withIndent(' ').convert({
          'schemaName': 'caverno_ll37_worktree_agent_live_canary_capture',
          'schemaVersion': 1,
          'model': env.model,
          'correct': {'verifiedGreen': correct.verifiedGreen, 'changedFileCount': correct.changedFiles.length},
          'broken': {'verifiedGreen': broken.verifiedGreen, 'changedFileCount': broken.changedFiles.length, 'control': 'write_tools_disabled'},
        })}\n',
      );
    },
    skip: enabled
        ? false
        : 'Set CAVERNO_LL37_WORKTREE_AGENT_LIVE_CANARY=1 and the required '
              'LLM/evidence environment variables to run.',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<WorktreeAgentTask> _runArm({
  required _LiveCanaryEnvironment env,
  required String id,
  required Directory worktreeDirectory,
  required bool disableWriteTools,
}) async {
  await _prepareFixture(worktreeDirectory);
  final startedAt = DateTime.now().toUtc();
  final task = WorktreeAgentTask(
    id: id,
    status: WorktreeAgentTaskStatus.running,
    title: 'Update the greeting implementation',
    prompt:
        'Change greeting() to return the exact text hello world. '
        'Use the worktree-scoped file tools, make no unrelated changes, and '
        'finish with a concise summary.',
    branchName: 'feature/$id',
    worktreePath: worktreeDirectory.path,
    verificationCommand: 'dart tool/verify.dart',
    createdAt: startedAt,
    updatedAt: startedAt,
    startedAt: startedAt,
  );
  final settings = AppSettings.defaults().copyWith(
    baseUrl: env.baseUrl,
    apiKey: env.apiKey,
    model: env.model,
    subagentModel: env.model,
    temperature: 0,
    maxTokens: 2048,
    mcpEnabled: false,
  );
  final primaryDataSource = ChatRemoteDataSource(
    baseUrl: env.baseUrl,
    apiKey: env.apiKey,
  );
  final meshRunner = MeshSecondaryCompletionRunner<ChatDataSource>(
    router: const MeshEndpointRouter(),
    health: EndpointHealthTracker(),
    buildEndpointDataSource: (baseUrl, apiKey) =>
        ChatRemoteDataSource(baseUrl: baseUrl, apiKey: apiKey),
  );
  final disabledTools = disableWriteTools
      ? const {'write_file', 'edit_file', 'delete_file'}
      : const <String>{};
  final delegate = WorktreeAgentLlmExecutionDelegate(
    settings: settings,
    primaryDataSource: primaryDataSource,
    meshRunner: meshRunner,
    toolService: McpToolService(disabledBuiltInTools: disabledTools),
    verificationRunner: const WorktreeAgentVerificationRunner(
      timeout: Duration(seconds: 30),
    ),
  );
  final outcome = await delegate.execute(
    WorktreeAgentTaskExecutionContext(task: task),
  );
  final finishedAt = DateTime.now().toUtc();
  return task.copyWith(
    status: WorktreeAgentTaskStatus.completed,
    resultSummary: outcome.resultSummary,
    verifiedGreen: outcome.verifiedGreen,
    verificationSummary: outcome.verificationSummary,
    changedFiles: outcome.changedFiles,
    changedFileEvidenceTruncated: outcome.changedFileEvidenceTruncated,
    finishedAt: finishedAt,
    updatedAt: finishedAt,
  );
}

Future<void> _prepareFixture(Directory directory) async {
  if (directory.existsSync()) {
    throw StateError('LL37 live canary fixture already exists.');
  }
  await Directory('${directory.path}/lib').create(recursive: true);
  await Directory('${directory.path}/tool').create();
  await File(
    '${directory.path}/lib/greeting.dart',
  ).writeAsString("String greeting() => 'hello';\n");
  await File('${directory.path}/tool/verify.dart').writeAsString('''
import 'dart:io';

void main() {
  final source = File('lib/greeting.dart').readAsStringSync().trim();
  const expected = "String greeting() => 'hello world';";
  if (source == expected) {
    stdout.writeln('Greeting verification passed.');
    return;
  }
  stderr.writeln('Expected the exact hello world implementation.');
  exitCode = 1;
}
''');
}

final class _LiveCanaryEnvironment {
  const _LiveCanaryEnvironment({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.outputDirectoryPath,
  });

  factory _LiveCanaryEnvironment.fromEnvironment() {
    if (_requiredEnv('CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT') != '1') {
      throw StateError(
        'CAVERNO_LL37_PERSONAL_EVAL_RECORDING_CONSENT=1 is required.',
      );
    }
    return _LiveCanaryEnvironment(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      outputDirectoryPath: _requiredEnv(
        'CAVERNO_LL37_WORKTREE_AGENT_CAPTURE_DIR',
      ),
    );
  }

  final String baseUrl;
  final String apiKey;
  final String model;
  final String outputDirectoryPath;
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    throw StateError('$name is required for the LL37 worktree-agent canary.');
  }
  return value;
}
