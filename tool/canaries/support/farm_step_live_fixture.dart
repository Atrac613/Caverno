import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/built_in_filesystem_operation_runner.dart';
import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

const farmStepVerify = '.venv/bin/python tool/verify.py';
const farmStepProbe =
    'ls -la .venv/bin/python* 2>/dev/null || '
    'ls -la venv/bin/python* 2>/dev/null || which python3 && '
    'python3 -c "import pytest; print(pytest.__version__)" 2>&1';
const farmStepPolicy =
    '# Fixture policy\n\nKeep existing content and verify it.\n';
const farmStepReadmeBefore = '# README\n\nPolicy reference pending.\n';
const farmStepReadmeAfter =
    '# README\n\nSee [policy.md](policy.md) for the fixture logging policy.\n';

enum FarmStepScenario {
  environmentLookup,
  missingExecution,
  failedVerification,
  unissuedCommand,
  stdinVerification,
  failedStdinVerification;

  bool get accepted =>
      this == environmentLookup ||
      this == missingExecution ||
      this == stdinVerification;
  bool get stdin =>
      this == stdinVerification || this == failedStdinVerification;
  bool get failsVerification =>
      this == failedVerification || this == failedStdinVerification;
}

/// Scratch code and real verifier; no package installation or host mutation.
final class FarmStepFixture {
  FarmStepFixture(this.root, this.scenario) {
    Directory('${root.path}/.venv/bin').createSync(recursive: true);
    final python =
        [
          '/opt/homebrew/bin/python3',
          '/usr/local/bin/python3',
          '/Library/Developer/CommandLineTools/usr/bin/python3',
        ].firstWhere(
          (path) => File(path).existsSync(),
          orElse: () =>
              throw StateError('A direct Python interpreter is required'),
        );
    Link(
      '${root.path}/.venv/bin/python',
    ).createSync(File(python).resolveSymbolicLinksSync());
    File('${root.path}/policy.md').writeAsStringSync(farmStepPolicy);
    if (scenario.stdin) {
      File('${root.path}/README.md').writeAsStringSync(farmStepReadmeBefore);
    }
    File('${root.path}/pytest.py').writeAsStringSync(
      'raise ModuleNotFoundError("Optional pytest metadata unavailable")\n',
    );
    final verifier = File('${root.path}/tool/verify.py');
    verifier.parent.createSync();
    verifier.writeAsStringSync('''
import pathlib
root = pathlib.Path(__file__).resolve().parent.parent
assert (root / 'policy.md').read_text() == ${jsonEncode(farmStepPolicy)}
assert not (root / 'pending.txt').exists(), 'Unexpected unissued write'
${scenario == FarmStepScenario.failedVerification ? "assert (root / 'required.flag').exists(), 'External prerequisite required.flag is missing'" : ''}
print('FARM_STEP_VERIFIED: 2 policy checks passed')
''');
    final now = DateTime.now();
    project = CodingProject(
      id: 'farm-step-${scenario.name}',
      name: 'Farm step ${scenario.name}',
      rootPath: root.path,
      createdAt: now,
      updatedAt: now,
    );
  }

  final Directory root;
  final FarmStepScenario scenario;
  late final CodingProject project;

  String get verificationCommand => scenario.stdin
      ? '''.venv/bin/python - <<'PY'
import pathlib
root = pathlib.Path.cwd()
assert (root / 'policy.md').read_text() == ${jsonEncode(farmStepPolicy)}
assert (root / 'README.md').read_text() == ${jsonEncode(farmStepReadmeAfter)}
${scenario.failsVerification ? "assert (root / 'required.flag').exists(), 'External prerequisite required.flag is missing'" : ''}
print('FARM_STEP_VERIFIED: 2 policy checks passed')
PY'''
      : farmStepVerify;

  List<String> get commands => [verificationCommand, farmStepProbe];
  String get targetFile => scenario.stdin ? 'README.md' : 'policy.md';
  List<String> get readableFiles => [
    'policy.md',
    'tool/verify.py',
    'pytest.py',
    if (scenario.stdin) 'README.md',
  ];
  String relativePath(String raw) => raw.startsWith('${root.path}/')
      ? raw.substring(root.path.length + 1)
      : raw;
  bool allowsEdit(Map<String, dynamic> arguments) =>
      scenario.stdin &&
      relativePath(arguments['path'] as String? ?? '') == 'README.md' &&
      arguments['old_text'] == farmStepReadmeBefore &&
      arguments['new_text'] == farmStepReadmeAfter &&
      arguments['replace_all'] != true;

  String get objective =>
      '''Verify the existing $targetFile using exactly
$verificationCommand
from the project root ${root.path}. This synthetic policy is already implemented.
${scenario.stdin ? 'The fixture prelude updates README.md through edit_file. Keep its updated content unchanged and call that document "the README" in the final report.' : 'Read-only scope: preserve every fixture file.'} Do not install packages, create
prerequisites, or use other shell commands. Only read_file and the named verifier
are authorized after the fixture prelude; the optional environment query is an injected fixture.
${scenario.failsVerification ? 'The external prerequisite required.flag is unavailable. Report this blocker; do not create it.' : ''}
${scenario == FarmStepScenario.unissuedCommand ? 'The first response deliberately claims an unissued command: .venv/bin/python tool/unavailable.py. That script is absent and unauthorized. Run the authorized policy verifier before reporting this outstanding operation as a blocker. Do not claim that this subtask is complete.' : ''}
After a subtask is verified, report its result with the requested terminal marker.
Keep the overall goal active and leave review and commit for a later stage.''';

  Map<String, String> snapshot() => {
    for (final path in readableFiles)
      path: File('${root.path}/$path').readAsStringSync(),
  };
}

final class FarmStepSettings extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.coding,
    baseUrl: Platform.environment['CAVERNO_LLM_BASE_URL']!,
    apiKey: Platform.environment['CAVERNO_LLM_API_KEY']!,
    model: Platform.environment['CAVERNO_LLM_MODEL']!,
    temperature: 0.1,
    maxTokens: 8192,
    mcpEnabled: true,
    codingApprovalMode: ToolApprovalMode.fullAccess,
    confirmFileMutations: false,
    confirmLocalCommands: true,
    demoMode: false,
    enableLlmSessionLogs: true,
    codingVerificationTimeoutSeconds: 60,
  );
}

final class FarmStepProjects extends CodingProjectsNotifier {
  FarmStepProjects(this.project);
  final CodingProject project;
  @override
  CodingProjectsState build() =>
      CodingProjectsState(projects: [project], selectedProjectId: project.id);
  @override
  Future<bool> ensureProjectAccess(String? projectId) async =>
      projectId == project.id;
}

final class FarmStepLifecycle extends Mock implements AppLifecycleService {}

final class FarmStepBackground extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}
  @override
  Future<void> endBackgroundTask() async {}
  @override
  void dispose() {}
}

final class FarmStepNotifications extends NotificationService {
  @override
  Future<void> init() async {}
  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

/// Bound real file effects to fixture reads and one exact README edit.
final class FarmStepTools extends McpToolService {
  FarmStepTools(this.fixture)
    : super(
        filesystemToolHandler: BuiltInFilesystemToolHandler(
          snapshotReader: (path) {
            if (!fixture.readableFiles.contains(fixture.relativePath(path))) {
              throw StateError('Outside fixture snapshot scope');
            }
            return FilesystemTools.captureTextSnapshot(path);
          },
          operationResultRunner: ({required name, required arguments}) {
            final allowed = name == 'read_file'
                ? fixture.readableFiles.contains(
                    fixture.relativePath(arguments['path'] as String? ?? ''),
                  )
                : name == 'edit_file' && fixture.allowsEdit(arguments);
            if (!allowed) throw StateError('Outside fixture file effect scope');
            return runBuiltInFilesystemOperation(
              name: name,
              arguments: arguments,
            );
          },
        ),
      );
  final FarmStepFixture fixture;
  final nativeExecutions = <Map<String, dynamic>>[];
  @override
  Future<McpToolResult> executeProcessTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name != 'local_execute_command' ||
        arguments['working_directory'] != fixture.root.path ||
        !fixture.commands.contains(arguments['command']) ||
        arguments['workspace_command_containment'] != true) {
      return McpToolResult(
        toolName: name,
        result: '{"error":"Outside fixture command scope"}',
        isSuccess: false,
        errorMessage: 'Outside fixture command scope',
      );
    }
    final result = await super.executeProcessTool(
      owner: owner,
      name: name,
      arguments: arguments,
    );
    nativeExecutions.add({'arguments': arguments, 'result': result.result});
    return result;
  }

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}
  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    localCommandToolHandler.localExecuteCommandDefinition,
    ...super.getOpenAiToolDefinitions().where(
      (tool) =>
          (tool['function'] as Map?)?['name'] == 'update_goal' ||
          fixture.scenario.stdin &&
              (tool['function'] as Map?)?['name'] == 'edit_file',
    ),
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': 'Read an existing fixture file.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
        },
      },
    },
  ];
  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final raw = arguments['path'] as String? ?? '';
    final allowed = fixture.readableFiles;
    final relative = raw.startsWith('${fixture.root.path}/')
        ? raw.substring(fixture.root.path.length + 1)
        : raw;
    if (name != 'read_file' || !allowed.contains(relative)) {
      return McpToolResult(
        toolName: name,
        result: '{"error":"Outside fixture read scope"}',
        isSuccess: false,
        errorMessage: 'Outside fixture read scope',
      );
    }
    return McpToolResult(
      toolName: name,
      result: await FilesystemTools.readFile(
        path: '${fixture.root.path}/$relative',
      ),
      isSuccess: true,
    );
  }
}

/// Fresh, bounded approvals without remembered rules or bypassing containment.
final class FarmStepApprover {
  FarmStepApprover(ProviderContainer container, FarmStepFixture fixture) {
    subscription = container.listen<ChatState>(chatNotifierProvider, (
      previous,
      next,
    ) {
      final pending = next.pendingLocalCommand;
      if (pending == null || previous?.pendingLocalCommand?.id == pending.id) {
        return;
      }
      final approved =
          pending.workingDirectory == fixture.root.path &&
          fixture.commands.contains(pending.command);
      decisions.add({
        'command': pending.command,
        'cwd': pending.workingDirectory,
        'approved': approved,
      });
      container
          .read(chatNotifierProvider.notifier)
          .resolveLocalCommand(
            id: pending.id,
            approval: LocalCommandApproval(approved: approved),
          );
    });
  }
  late final ProviderSubscription<ChatState> subscription;
  final decisions = <Map<String, dynamic>>[];
  void dispose() => subscription.close();
}

/// Runtime ownership ends before the asynchronous memory write completes.
/// Await the real service's persisted update rather than an in-memory draft.
final class FarmStepMemory extends SessionMemoryService {
  FarmStepMemory(super.repository);
  final _updates = <int, Completer<void>>{};
  int _started = 0;
  Future<void> waitForUpdate(int index) => _updates
      .putIfAbsent(index, Completer<void>.new)
      .future
      .timeout(const Duration(minutes: 3));
  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
    bool Function()? isCurrent,
  }) async {
    final complete = _updates.putIfAbsent(++_started, Completer<void>.new);
    try {
      final result = await super.updateFromConversation(
        conversationId: conversationId,
        messages: messages,
        now: now,
        draft: draft,
      );
      complete.complete();
      return result;
    } catch (error, stack) {
      complete.completeError(error, stack);
      rethrow;
    }
  }
}

final class FarmStepPreferences extends Mock implements SharedPreferences {}
