// Live canary for thread independence: two coding threads, two projects, both
// drafting a plan at the same time against a real model.
//
// The unit tests fake the interleaving; this one makes it happen for real, and
// asserts the properties the 2026-07-25/26 incidents violated — each thread
// prompting for its own project, logging under its own session, resolving tool
// paths inside its own root, and keeping its own plan.
//
// The overlap itself is asserted first: a canary that runs the two threads
// sequentially would pass every other check while proving nothing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

/// Distinct tokens planted in each thread's history. A proposal request that
/// carries the other thread's token is reading the visible thread's messages.
const _alphaToken = 'ALPHA-THREAD-TOKEN-7f3c';
const _betaToken = 'BETA-THREAD-TOKEN-9a2d';

const _specDocument = '''
# TODO app

Build a small command-line TODO app.

1. add <text> appends an undone task and prints its id.
2. list prints every task with id and a done marker.
3. done <id> marks a task complete; unknown ids exit non-zero.
4. State persists to a local file and survives fresh runs.
''';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_MULTI_THREAD_LIVE_CANARY'] == '1';

  test(
    'two threads drafting at once keep their own project, log and plan',
    () async {
      final env = _LiveEnv.fromEnvironment();
      final workspace = Directory.systemTemp.createTempSync(
        'caverno-multi-thread-canary',
      );
      final sessionLogRoot = Directory('${workspace.path}/session_logs')
        ..createSync(recursive: true);
      final runtimeDataRoot = Directory('${workspace.path}/runtime')
        ..createSync(recursive: true);
      final alpha = _project('alpha', workspace);
      final beta = _project('beta', workspace);

      // Must be the concrete ChatRemoteDataSource: _withChatSessionLogging
      // passes anything else straight through, which would silently disable
      // the session logs this canary reads.
      final dataSource = ChatRemoteDataSource(
        baseUrl: env.baseUrl,
        apiKey: env.apiKey,
      );
      final toolService = _WorkspaceToolService();
      final container = _buildContainer(
        env: env,
        projects: [alpha, beta],
        dataSource: dataSource,
        toolService: toolService,
        logStore: LlmSessionLogStore(
          rootDirectoryProvider: () async => sessionLogRoot,
        ),
        runtimeDataRoot: runtimeDataRoot,
      );
      addTearDown(() {
        _expectEveryThreadHandedBack(container);
        container.dispose();
        workspace.deleteSync(recursive: true);
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: alpha.id,
      );
      final alphaThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      await notifier.sendMessage('Remember the token $_alphaToken.');

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: beta.id,
      );
      final betaThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      await notifier.sendMessage('Remember the token $_betaToken.');

      conversations.selectConversation(alphaThread);
      final alphaRun = notifier.generatePlanProposal();

      // Only open the second thread once the first is genuinely in flight,
      // otherwise the two runs can end up sequential and prove nothing.
      await _waitUntil(
        () => container.read(chatNotifierProvider).isGeneratingWorkflowProposal,
        timeout: const Duration(minutes: 2),
        describe: 'the first thread to start drafting',
      );
      conversations.selectConversation(betaThread);
      final betaRun = notifier.generatePlanProposal();

      // A plan flow may stop to ask the user something. Nobody is here to
      // answer, so decline and let it proceed rather than hanging the canary.
      final decisionPump = Timer.periodic(const Duration(milliseconds: 200), (
        _,
      ) {
        final pending = container
            .read(chatNotifierProvider)
            .pendingWorkflowDecision;
        if (pending == null) return;
        // Answer rather than decline: declining aborts the flow, and a canary
        // that never reaches a plan cannot check where the plan lands.
        final option = pending.decision.options.firstOrNull;
        notifier.resolveWorkflowDecision(
          id: pending.id,
          answer: option == null
              ? null
              : WorkflowPlanningDecisionAnswer(
                  decisionId: pending.id,
                  question: pending.decision.question,
                  optionId: option.id,
                  optionLabel: option.label,
                ),
        );
      });
      try {
        await Future.wait([
          alphaRun,
          betaRun,
        ]).timeout(const Duration(minutes: 12));
      } finally {
        decisionPump.cancel();
      }

      // The store writes asynchronously, so settle before reading it.
      final logs = <String, _SessionLog>{};
      await _waitUntil(
        () {
          for (final threadId in [alphaThread, betaThread]) {
            final file = File('${sessionLogRoot.path}/coding/$threadId.jsonl');
            if (!file.existsSync()) return false;
            final parsed = _SessionLog.parse(file);
            if (parsed.requests.isEmpty) return false;
            logs[threadId] = parsed;
            // The exit entry is appended after the last request, so wait for
            // it rather than racing the append.
            if (!parsed.entries.any(
              (entry) => entry['operation'] == 'turn_exit',
            )) {
              return false;
            }
          }
          return logs.length == 2;
        },
        timeout: const Duration(minutes: 2),
        describe: 'both session logs to be written, each with an exit reason',
      );

      // 1. The runs really overlapped.
      expect(
        _overlapped(logs[alphaThread]!, logs[betaThread]!),
        isTrue,
        reason:
            'the two threads never had a request in flight at the same time, '
            'so this run proves nothing about interference:\n'
            '${logs[alphaThread]!.describe('alpha')}\n'
            '${logs[betaThread]!.describe('beta')}',
      );

      // 2. Neither thread prompted for the other's project.
      for (final threadId in [alphaThread, betaThread]) {
        final owner = threadId == alphaThread ? alpha : beta;
        final foreign = threadId == alphaThread ? beta : alpha;
        expect(
          logs[threadId]!.mentions(foreign.rootPath),
          isFalse,
          reason:
              'thread $threadId sent or logged a request describing the other '
              'project; this is the 2026-07-25 cross-thread failure:\n'
              '${logs[threadId]!.attribute(foreign.rootPath)}',
        );
        expect(
          logs[threadId]!.mentions(owner.rootPath),
          isTrue,
          reason: 'thread $threadId logged nothing of its own',
        );
        final foreignToken = threadId == alphaThread ? _betaToken : _alphaToken;
        expect(
          logs[threadId]!.mentions(foreignToken),
          isFalse,
          reason:
              'thread $threadId sent a request carrying the other thread\'s '
              'history:\n${logs[threadId]!.attribute(foreignToken)}',
        );
      }

      // 3. No tool call reached out of its own project.
      for (final path in toolService.resolvedPaths) {
        expect(
          path.startsWith(alpha.rootPath) || path.startsWith(beta.rootPath),
          isTrue,
          reason: 'a tool resolved a path outside both projects: $path',
        );
      }

      // 4. Each thread kept its own plan.
      final stored = container
          .read(conversationsNotifierProvider)
          .conversations;
      for (final threadId in [alphaThread, betaThread]) {
        final conversation = stored.firstWhere((c) => c.id == threadId);
        expect(
          conversation.planArtifact?.hasContent ?? false,
          isTrue,
          reason:
              'thread $threadId drafted a plan but does not hold it; a plan '
              'that lands on the other thread is the 2026-07-26 failure',
        );
      }

      // 5. Both turns reported why they ended. Plan drafting ended through
      // _completeRuntimeTurn without ever classifying an exit reason, so it
      // left no record at all — `unknown` is a finding, silence is not.
      for (final threadId in [alphaThread, betaThread]) {
        expect(
          logs[threadId]!.entries.where(
            (entry) => entry['operation'] == 'turn_exit',
          ),
          isNotEmpty,
          reason:
              'thread $threadId ended without recording a turn-exit reason, '
              'so it is invisible to tool/triage_session_logs.py',
        );
      }

      // 6. Both threads were handed back. Plan drafting registered an active
      // response per draft and completed the runtime turn without releasing
      // it, so both threads stayed listed as busy and a switch back to either
      // showed the one-message snapshot taken at drafting time under a spinner
      // that only an app restart cleared.
      expect(
        container.read(chatNotifierProvider).busyConversationIds,
        isEmpty,
        reason:
            'both plan drafts finished, so neither thread may still be held: '
            'a registration that outlives its turn is what a thread switch '
            'shows instead of the persisted transcript',
      );
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_MULTI_THREAD_LIVE_CANARY=1 and CAVERNO_LLM_* to run. '
              'On macOS point CAVERNO_LLM_BASE_URL at a loopback relay: the '
              'test binary cannot reach a LAN address.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
  test(
    'two coding turns at once keep their own messages',
    () async {
      // Covers the paths repaired on 2026-07-26 after the plan work: content
      // tool results were appended to the visible thread's last message, the
      // recovery passes read the visible thread's last message, and the
      // verification builders judged themselves against the visible project.
      // Each project's spec carries its own marker, so an answer quoting the
      // other marker means a tool result crossed threads.
      final env = _LiveEnv.fromEnvironment();
      final workspace = Directory.systemTemp.createTempSync(
        'caverno-multi-thread-coding-canary',
      );
      final sessionLogRoot = Directory('${workspace.path}/session_logs')
        ..createSync(recursive: true);
      final runtimeDataRoot = Directory('${workspace.path}/runtime')
        ..createSync(recursive: true);
      final alpha = _project('alpha', workspace);
      final beta = _project('beta', workspace);

      final toolService = _WorkspaceToolService();
      final container = _buildContainer(
        env: env,
        projects: [alpha, beta],
        dataSource: ChatRemoteDataSource(
          baseUrl: env.baseUrl,
          apiKey: env.apiKey,
        ),
        toolService: toolService,
        logStore: LlmSessionLogStore(
          rootDirectoryProvider: () async => sessionLogRoot,
        ),
        runtimeDataRoot: runtimeDataRoot,
        assistantMode: AssistantMode.coding,
      );
      addTearDown(() {
        _expectEveryThreadHandedBack(container);
        container.dispose();
        workspace.deleteSync(recursive: true);
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);
      const prompt =
          'Read todo_app.md in this project and reply with the Marker value '
          'written in requirement 1, exactly as it appears.';

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: alpha.id,
      );
      final alphaThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final alphaRun = notifier.sendMessage(prompt);

      await _waitUntil(
        () => container.read(chatNotifierProvider).isLoading,
        timeout: const Duration(minutes: 2),
        describe: 'the first coding turn to start',
      );
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: beta.id,
      );
      final betaThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final betaRun = notifier.sendMessage(prompt);

      await Future.wait([
        alphaRun,
        betaRun,
      ]).timeout(const Duration(minutes: 12));

      final logs = <String, _SessionLog>{};
      await _waitUntil(
        () {
          for (final threadId in [alphaThread, betaThread]) {
            final file = File('${sessionLogRoot.path}/coding/$threadId.jsonl');
            if (!file.existsSync()) return false;
            final parsed = _SessionLog.parse(file);
            if (parsed.requests.isEmpty) return false;
            logs[threadId] = parsed;
          }
          return logs.length == 2;
        },
        timeout: const Duration(minutes: 2),
        describe: 'both session logs to be written',
      );
      // The exit entry is appended after the last request, so re-parse until
      // it lands rather than racing the append.
      await _waitUntil(
        () {
          for (final threadId in [alphaThread, betaThread]) {
            final parsed = _SessionLog.parse(
              File('${sessionLogRoot.path}/coding/$threadId.jsonl'),
            );
            logs[threadId] = parsed;
            if (!parsed.entries.any(
              (entry) => entry['operation'] == 'turn_exit',
            )) {
              return false;
            }
          }
          return true;
        },
        timeout: const Duration(minutes: 2),
        describe:
            'both turns to record an exit reason (a background turn that '
            'records none is invisible to tool/triage_session_logs.py)',
      );

      expect(
        _overlapped(logs[alphaThread]!, logs[betaThread]!),
        isTrue,
        reason:
            'the two coding turns never overlapped, so this run proves nothing:\n'
            '${logs[alphaThread]!.describe('alpha')}\n'
            '${logs[betaThread]!.describe('beta')}',
      );

      for (final path in toolService.resolvedPaths) {
        expect(
          path.startsWith(alpha.rootPath) || path.startsWith(beta.rootPath),
          isTrue,
          reason: 'a tool resolved a path outside both projects: $path',
        );
      }

      final stored = container
          .read(conversationsNotifierProvider)
          .conversations;
      for (final threadId in [alphaThread, betaThread]) {
        final owner = threadId == alphaThread ? _alphaToken : _betaToken;
        final foreign = threadId == alphaThread ? _betaToken : _alphaToken;
        final transcript = stored
            .firstWhere((conversation) => conversation.id == threadId)
            .messages
            .map((message) => message.content)
            .join('\n');
        expect(
          transcript.contains(foreign),
          isFalse,
          reason:
              'thread $threadId holds the other project\'s marker, so a tool '
              'result or a recovery pass wrote across threads:\n$transcript',
        );
        expect(
          transcript.contains(owner),
          isTrue,
          reason:
              'thread $threadId never read its own project; the run proves '
              'nothing about isolation:\n$transcript',
        );
        // A turn that finishes while the user is reading the other thread ends
        // on the detached path, which used to record no exit reason at all —
        // so the triage tooling's exit-reason distribution silently omitted
        // every background turn, which under two threads is most of them.
        expect(
          logs[threadId]!.entries.where(
            (entry) => entry['operation'] == 'turn_exit',
          ),
          isNotEmpty,
          reason:
              'thread $threadId finished without recording a turn-exit reason, '
              'so it is invisible to tool/triage_session_logs.py',
        );
      }
    },
    skip: liveEnabled ? false : 'See the plan canary for the required env.',
    timeout: const Timeout(Duration(minutes: 15)),
  );

  test(
    'a message queued behind a running turn still runs',
    () async {
      // Live 2026-07-26: an approval queued behind a running turn drained two
      // milliseconds after run_completed and died on the lease the finished turn
      // had not yet handed back — a red error bar, and the approval gone. The
      // runtime regression test covers the signal; this covers the whole path.
      final env = _LiveEnv.fromEnvironment();
      final workspace = Directory.systemTemp.createTempSync(
        'caverno-queued-turn-canary',
      );
      final sessionLogRoot = Directory('${workspace.path}/session_logs')
        ..createSync(recursive: true);
      final runtimeDataRoot = Directory('${workspace.path}/runtime')
        ..createSync(recursive: true);
      final alpha = _project('alpha', workspace);

      final container = _buildContainer(
        env: env,
        projects: [alpha],
        dataSource: ChatRemoteDataSource(
          baseUrl: env.baseUrl,
          apiKey: env.apiKey,
        ),
        toolService: _WorkspaceToolService(),
        logStore: LlmSessionLogStore(
          rootDirectoryProvider: () async => sessionLogRoot,
        ),
        runtimeDataRoot: runtimeDataRoot,
        assistantMode: AssistantMode.coding,
      );
      addTearDown(() {
        _expectEveryThreadHandedBack(container);
        container.dispose();
        workspace.deleteSync(recursive: true);
      });

      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: alpha.id,
          );
      final threadId = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      final notifier = container.read(chatNotifierProvider.notifier);

      List<Message> transcript() => container
          .read(conversationsNotifierProvider)
          .conversations
          .firstWhere((conversation) => conversation.id == threadId)
          .messages;

      final firstRun = notifier.sendMessage(
        'Read todo_app.md and summarise requirement 1 in one sentence.',
      );
      await _waitUntil(
        () => container.read(chatNotifierProvider).isLoading,
        timeout: const Duration(minutes: 2),
        describe: 'the first turn to start',
      );

      // Typed while the thread is busy: this is the message that used to be
      // accepted, queued, and then thrown away by an ownership conflict.
      unawaited(notifier.sendMessage('Reply with exactly: QUEUED-OK'));
      await firstRun.timeout(const Duration(minutes: 8));

      await _waitUntil(
        () => transcript().any(
          (message) => message.content.contains('QUEUED-OK'),
        ),
        timeout: const Duration(minutes: 8),
        describe: 'the queued turn to run and answer',
      );

      expect(
        transcript().where((message) => message.role == MessageRole.assistant),
        isNotEmpty,
        reason:
            'the queued turn produced no answer, which is what an ownership '
            'conflict looked like from the user side',
      );
    },
    skip: liveEnabled ? false : 'See the plan canary for the required env.',
    timeout: const Timeout(Duration(minutes: 20)),
  );

  test(
    'a thread the user left mid-turn comes back finished',
    () async {
      // Live 2026-07-26 on 08199a3b: the user sent on one thread, opened
      // another, and came back to find the transcript frozen at the moment
      // they left, under a spinner and a stop button, while the conversation
      // store already held the finished answer. Quitting and relaunching the
      // app healed it, because startup reads the store whereas a thread switch
      // prefers the active-response registration and derives the spinner from
      // it existing.
      //
      // The CLI cannot cover this: it runs one turn per process and has no
      // visible thread. It needs one notifier serving two threads, which is
      // what this canary is.
      final env = _LiveEnv.fromEnvironment();
      final workspace = Directory.systemTemp.createTempSync(
        'caverno-thread-handback-canary',
      );
      final sessionLogRoot = Directory('${workspace.path}/session_logs')
        ..createSync(recursive: true);
      final runtimeDataRoot = Directory('${workspace.path}/runtime')
        ..createSync(recursive: true);
      final alpha = _project('alpha', workspace);
      final beta = _project('beta', workspace);

      final container = _buildContainer(
        env: env,
        projects: [alpha, beta],
        dataSource: ChatRemoteDataSource(
          baseUrl: env.baseUrl,
          apiKey: env.apiKey,
        ),
        toolService: _WorkspaceToolService(),
        logStore: LlmSessionLogStore(
          rootDirectoryProvider: () async => sessionLogRoot,
        ),
        runtimeDataRoot: runtimeDataRoot,
        assistantMode: AssistantMode.coding,
      );
      addTearDown(() {
        _expectEveryThreadHandedBack(container);
        container.dispose();
        workspace.deleteSync(recursive: true);
      });

      final conversations = container.read(
        conversationsNotifierProvider.notifier,
      );
      final notifier = container.read(chatNotifierProvider.notifier);

      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: alpha.id,
      );
      final alphaThread = container
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      List<Message> storedAlpha() => container
          .read(conversationsNotifierProvider)
          .conversations
          .firstWhere((conversation) => conversation.id == alphaThread)
          .messages;

      final alphaRun = notifier.sendMessage(
        'Read todo_app.md in this project and reply with the Marker value '
        'written in requirement 1, exactly as it appears.',
      );
      await _waitUntil(
        () => container.read(chatNotifierProvider).isLoading,
        timeout: const Duration(minutes: 2),
        describe: 'the first coding turn to start',
      );

      // The user opens another thread while that turn is still working.
      conversations.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: beta.id,
      );
      await alphaRun.timeout(const Duration(minutes: 12));
      await _waitUntil(
        () => storedAlpha().any(
          (message) => message.role == MessageRole.assistant,
        ),
        timeout: const Duration(minutes: 5),
        describe: 'the background turn to persist its answer',
      );

      // ...and comes back to it.
      conversations.selectConversation(alphaThread);
      await _waitUntil(
        () => container.read(chatNotifierProvider).messages.isNotEmpty,
        timeout: const Duration(minutes: 1),
        describe: 'the thread to open',
      );

      final visible = container.read(chatNotifierProvider);
      expect(
        visible.messages.where((message) =>
            message.role == MessageRole.assistant &&
            message.content.trim().isNotEmpty),
        isNotEmpty,
        reason:
            'the turn finished while this thread was in the background and the '
            'store holds its answer, so opening the thread must show it rather '
            'than the snapshot taken when the user left',
      );
      expect(
        visible.isLoading,
        isFalse,
        reason:
            'nothing is running on this thread, so it must not come back under '
            'a spinner and a stop button that only an app restart clears',
      );
      expect(
        visible.busyConversationIds,
        isNot(contains(alphaThread)),
        reason: 'a finished turn must not leave its thread listed as busy',
      );
    },
    skip: liveEnabled ? false : 'See the plan canary for the required env.',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

/// The lifecycle gate every scenario ends on.
///
/// A turn holds an active-response registration while it runs, and that
/// registration — not the conversation store — is what a thread switch renders
/// and what the thread's spinner is derived from. One left behind therefore
/// strands its thread on the snapshot taken when the user walked away, under a
/// spinner nothing but an app restart clears, and it does so silently: session
/// logs are written per request and a stranded registration issues none. Plan
/// drafting leaked one per draft until 2026-07-27.
void _expectEveryThreadHandedBack(ProviderContainer container) {
  expect(
    container.read(chatNotifierProvider).busyConversationIds,
    isEmpty,
    reason:
        'the scenario is over, so no thread may still be held busy; see the '
        '[ActiveResponse] register/release lines for the generation that never '
        'came back',
  );
}

String _specFor(String token) => _specDocument.replaceFirst(
  '1. add <text> appends an undone task and prints its id.',
  '1. add <text> appends an undone task and prints its id. Marker: $token.',
);

CodingProject _project(String name, Directory workspace) {
  final root = Directory('${workspace.path}/$name')
    ..createSync(recursive: true);
  File(
    '${root.path}/todo_app.md',
  ).writeAsStringSync(_specFor(name == 'alpha' ? _alphaToken : _betaToken));
  File('${root.path}/pubspec.yaml').writeAsStringSync(
    'name: ${name}_todo\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
  );
  Directory('${root.path}/bin').createSync(recursive: true);
  File('${root.path}/bin/todo.dart').writeAsStringSync(
    "void main(List<String> args) {\n  print('todo: not implemented yet');\n}\n",
  );
  final now = DateTime.now();
  return CodingProject(
    id: 'project-$name',
    name: name,
    rootPath: root.path,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _waitUntil(
  bool Function() condition, {
  required Duration timeout,
  required String describe,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for $describe.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// One thread's session log, read back from disk.
class _SessionLog {
  const _SessionLog(this.requests, this.raw, this.entries);

  final List<_LoggedRequest> requests;
  final String raw;
  final List<Map<String, dynamic>> entries;

  /// Which logged operations carry [rootPath], so a failure names the culprit
  /// instead of only reporting that one exists.
  String attribute(String rootPath) {
    final hits = <String>[];
    for (final entry in entries) {
      if (!jsonEncode(entry).contains(rootPath)) continue;
      final ids =
          ((entry['request'] as Map<String, dynamic>?)?['messages'] as List?)
              ?.map((m) => (m as Map)['id'])
              .whereType<String>()
              .take(2)
              .join(',') ??
          '';
      final encoded = jsonEncode(entry);
      final at = encoded.indexOf(rootPath);
      final from = at - 90 < 0 ? 0 : at - 90;
      final to = at + rootPath.length + 90;
      final snippet = encoded.substring(
        from,
        to > encoded.length ? encoded.length : to,
      );
      hits.add(
        '${entry['operation']}@${entry['timestamp']} [$ids]\n      …$snippet…',
      );
    }
    return hits.isEmpty ? '(none)' : hits.join('\n');
  }

  static _SessionLog parse(File file) {
    final requests = <_LoggedRequest>[];
    final entries = <Map<String, dynamic>>[];
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final Map<String, dynamic> entry;
      try {
        entry = jsonDecode(line) as Map<String, dynamic>;
      } on FormatException {
        continue;
      }
      // Every entry, not only the timed ones: turn_exit and execution_shadow
      // carry no startedAt, and dropping them made them invisible to every
      // assertion written against `entries`.
      entries.add(entry);
      final startedAt = DateTime.tryParse('${entry['startedAt']}');
      final finishedAt = DateTime.tryParse('${entry['finishedAt']}');
      if (startedAt == null || finishedAt == null) continue;
      requests.add(_LoggedRequest(startedAt, finishedAt));
    }
    return _SessionLog(requests, file.readAsStringSync(), entries);
  }

  bool mentions(String rootPath) => raw.contains(rootPath);

  String describe(String label) {
    return requests
        .map(
          (request) =>
              '$label ${request.startedAt.toIso8601String()} -> '
              '${request.finishedAt.toIso8601String()}',
        )
        .join('\n');
  }
}

class _LoggedRequest {
  const _LoggedRequest(this.startedAt, this.finishedAt);

  final DateTime startedAt;
  final DateTime finishedAt;
}

/// Whether any request of one thread was in flight while the other's was.
bool _overlapped(_SessionLog left, _SessionLog right) {
  for (final a in left.requests) {
    for (final b in right.requests) {
      if (a.startedAt.isBefore(b.finishedAt) &&
          b.startedAt.isBefore(a.finishedAt)) {
        return true;
      }
    }
  }
  return false;
}

/// Serves the read-only tools the planning research pass uses, over the real
/// temp projects, and records every path it was asked for.
class _WorkspaceToolService extends McpToolService {
  final List<String> resolvedPaths = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  // Real schemas: a parameterless {'type': 'object'} leaves the model unable
  // to know that `path` exists, and it answers by calling read_file with {}.
  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    _definition(
      'read_file',
      'Read a file in the project.',
      const {
        'path': {'type': 'string', 'description': 'File path to read.'},
      },
      const ['path'],
    ),
    _definition(
      'list_directory',
      'List a directory in the project.',
      const {
        'path': {'type': 'string', 'description': 'Directory to list.'},
      },
      const ['path'],
    ),
    _definition(
      'find_files',
      'Find files by glob pattern.',
      const {
        'path': {'type': 'string', 'description': 'Directory to search.'},
        'pattern': {'type': 'string', 'description': 'Glob pattern.'},
      },
      const ['path', 'pattern'],
    ),
    _definition(
      'search_files',
      'Search file contents.',
      const {
        'path': {'type': 'string', 'description': 'Directory to search.'},
        'query': {'type': 'string', 'description': 'Text to find.'},
      },
      const ['path', 'query'],
    ),
  ];

  Map<String, dynamic> _definition(
    String name,
    String description,
    Map<String, dynamic> properties,
    List<String> required,
  ) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
      },
    },
  };

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final path = (arguments['path'] as String?)?.trim() ?? '';
    if (path.isNotEmpty) {
      resolvedPaths.add(path);
    }
    // Delegate to the production implementation: the planning research pass
    // parses these payloads, and hand-rolled text made it collect nothing,
    // which pushed the model into asking a clarifying question instead of
    // proposing a plan.
    final result = switch (name) {
      'read_file' => await FilesystemTools.readFile(path: path),
      'find_files' => await FilesystemTools.findFiles(
        path: path,
        pattern: (arguments['pattern'] as String?)?.trim() ?? '*',
      ),
      'search_files' => await FilesystemTools.searchFiles(
        path: path,
        query: (arguments['query'] as String?)?.trim() ?? '',
      ),
      _ => await FilesystemTools.listDirectory(path: path),
    };
    return McpToolResult(toolName: name, result: result, isSuccess: true);
  }
}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _NoopNotificationService extends NotificationService {}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService() : super(ChatMemoryRepository.fromBox(_MockBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) => null;

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async => const MemoryUpdateResult.none();

  @override
  UserMemoryProfile loadProfile() => UserMemoryProfile.empty();
}

class _MockBox extends Mock implements Box<String> {}

/// With a runtime data root the runtime refreshes the conversation from the
/// authoritative store before each turn. The canary's store is in memory, so
/// refresh has to answer for it or no turn ever starts.
class _LiveConversationsNotifier extends ConversationsNotifier {
  @override
  Future<bool> refreshConversationForExecution(String id) async => true;
}

class _InMemoryConversationRepository extends ConversationRepository {
  _InMemoryConversationRepository() : super(_MockBox());

  final Map<String, Conversation> _store = {};

  @override
  List<Conversation> getAll() {
    final conversations = _store.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<void> deleteAll() async => _store.clear();
}

class _LiveProjectsNotifier extends CodingProjectsNotifier {
  _LiveProjectsNotifier(this.projects);

  final List<CodingProject> projects;

  @override
  CodingProjectsState build() => CodingProjectsState(
    projects: projects,
    selectedProjectId: projects.first.id,
  );

  @override
  Future<bool> ensureProjectAccess(String? projectId) async => true;
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier(this.env, this.assistantMode);

  final _LiveEnv env;
  final AssistantMode assistantMode;

  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: assistantMode,
    baseUrl: env.baseUrl,
    apiKey: env.apiKey,
    model: env.model,
    temperature: env.temperature,
    maxTokens: env.maxTokens,
    mcpEnabled: true,
    enableLlmSessionLogs: true,
    demoMode: false,
  );
}

ProviderContainer _buildContainer({
  required _LiveEnv env,
  required List<CodingProject> projects,
  required ChatDataSource dataSource,
  required McpToolService toolService,
  required LlmSessionLogStore logStore,
  AssistantMode assistantMode = AssistantMode.plan,
  Directory? runtimeDataRoot,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      // Without a data root the ownership port is a noop, and the workspace
      // lease — the thing two concurrent turns actually contend on — is never
      // exercised.
      cavernoRuntimeDataRootProvider.overrideWithValue(runtimeDataRoot),
      settingsNotifierProvider.overrideWith(
        () => _LiveSettingsNotifier(env, assistantMode),
      ),
      conversationsNotifierProvider.overrideWith(
        _LiveConversationsNotifier.new,
      ),
      conversationRepositoryProvider.overrideWithValue(
        _InMemoryConversationRepository(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _LiveProjectsNotifier(projects),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      mcpToolServiceProvider.overrideWithValue(toolService),
      llmSessionLogStoreProvider.overrideWithValue(logStore),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

class _LiveEnv {
  const _LiveEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.temperature,
    required this.maxTokens,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final int maxTokens;

  static _LiveEnv fromEnvironment() => _LiveEnv(
    baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
    apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
    model: _requiredEnv('CAVERNO_LLM_MODEL'),
    temperature:
        double.tryParse(
          Platform.environment['CAVERNO_MULTI_THREAD_LIVE_TEMPERATURE'] ?? '',
        ) ??
        0.2,
    maxTokens:
        int.tryParse(
          Platform.environment['CAVERNO_MULTI_THREAD_LIVE_MAX_TOKENS'] ?? '',
        ) ??
        4096,
  );
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for the multi-thread live canary.');
  }
  return value;
}
