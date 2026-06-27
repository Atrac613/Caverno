// Deterministic characterization of the unverified-read-only-inspection guard.
//
// The guard appends a "your file/project-state claim is unverified" notice when
// the assistant claims it inspected local state but no *successful read-only
// inspection tool result* is available. This test pins down exactly which
// tool-result inputs the guard accepts as verification — in particular whether a
// successful `git_execute_command` (a read-only repo inspection) is recognized.
//
// Guard logic under test lives in
// `chat_notifier_unexecuted_action_recovery.dart`
// (`_buildUnverifiedReadOnlyInspectionClaimToolResult` + predicates), exercised
// through the `*ForTest` seams.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() =>
      AppSettings.defaults().copyWith(mcpEnabled: false, demoMode: false);
}

class _Conversations extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();
}

class _Box extends Mock implements Box<String> {}

class _Memory extends SessionMemoryService {
  _Memory() : super(ChatMemoryRepository.fromBox(_Box()));
}

class _DataSource extends Mock implements ChatDataSource {}

class _Lifecycle extends Mock implements AppLifecycleService {}

class _Background extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}
  @override
  Future<void> endBackgroundTask() async {}
  @override
  void dispose() {}
}

ToolResultInfo _result(String name, String result) =>
    ToolResultInfo(id: 't', name: name, arguments: const {}, result: result);

// A claim that reads as a completed read-only inspection of repo/project state:
// "repository" is a target marker, "i checked" is a completed marker, and there
// is no negation token — so the claim half of the trigger is satisfied.
const _repoClaim = 'I checked the repository: the latest commit is c7d4341.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ChatNotifier notifier;

  setUp(() {
    final lifecycle = _Lifecycle();
    when(() => lifecycle.isInBackground).thenReturn(false);
    container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_Settings.new),
        conversationsNotifierProvider.overrideWith(_Conversations.new),
        chatRemoteDataSourceProvider.overrideWithValue(_DataSource()),
        sessionMemoryServiceProvider.overrideWithValue(_Memory()),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(lifecycle),
        backgroundTaskServiceProvider.overrideWithValue(_Background()),
      ],
    );
    notifier = container.read(chatNotifierProvider.notifier);
  });

  tearDown(() => container.dispose());

  group('unverified read-only inspection guard characterization', () {
    test(
      'does NOT fire when a project-state claim is backed by a successful '
      'local_execute_command (e.g. flutter analyze)',
      () {
        final fired =
            notifier.buildUnverifiedReadOnlyInspectionClaimToolResultForTest(
          candidateResponse:
              'I ran flutter analyze on the project: no issues found.',
          toolResults: [
            _result(
              'local_execute_command',
              '{"exit_code":0,"stdout":"No issues found!"}',
            ),
          ],
        );
        expect(fired, isNull);
      },
    );

    test(
      'does NOT fire when a project-state claim is backed by a successful '
      'process_wait (commands run in the background via process_start)',
      () {
        // Real-world "fvm flutter clean/pub get/analyze" runs go through
        // process_start + process_wait. A completed process result is only
        // "successful" when it carries ok=true, status=exited AND exit_code 0
        // (see ToolCallExecutionPolicy.toolResultHasSuccessfulExit) — mirror
        // that exact shape so this path counts as inspection verification.
        final fired =
            notifier.buildUnverifiedReadOnlyInspectionClaimToolResultForTest(
          candidateResponse:
              'fvm flutter analyze finished for the project: no issues found.',
          toolResults: [
            _result(
              'process_wait',
              '{"ok":true,"status":"exited","exit_code":0,'
                  '"stdout_tail":"No issues found!"}',
            ),
          ],
        );
        expect(fired, isNull);
      },
    );

    test('does NOT fire when backed by a successful read_file', () {
      final fired =
          notifier.buildUnverifiedReadOnlyInspectionClaimToolResultForTest(
        candidateResponse: 'I read the pubspec file; it exists.',
        toolResults: [_result('read_file', '{"content":"name: caverno"}')],
      );
      expect(fired, isNull);
    });

    test('fires (true positive) when an inspection claim has no backing tool '
        'result at all', () {
      final fired =
          notifier.buildUnverifiedReadOnlyInspectionClaimToolResultForTest(
        candidateResponse: _repoClaim,
        toolResults: const [],
      );
      expect(fired, isNotNull);
    });

    test(
      'does NOT fire when a repo-state claim is backed by a successful '
      'git_execute_command (regression: the git false positive)',
      () {
        final gitResult = _result(
          'git_execute_command',
          '{"exit_code":0,"stdout":"c7d4341 chore: bump version"}',
        );

        // A successful git_execute_command now counts as a read-only inspection
        // result, in line with the canonical command-tool set. (Before the fix
        // this returned false and the guard fired on a genuine git inspection.)
        expect(
          notifier.hasSuccessfulReadOnlyInspectionResultForTest([gitResult]),
          isTrue,
          reason: 'git_execute_command is recognized as a command execution',
        );
        // The claim half of the trigger is still satisfied for a repo summary,
        // so this proves the fix is on the verification side, not the wording.
        expect(
          notifier.looksLikeCompletedReadOnlyInspectionClaimForTest(_repoClaim),
          isTrue,
        );
        final fired =
            notifier.buildUnverifiedReadOnlyInspectionClaimToolResultForTest(
          candidateResponse: _repoClaim,
          toolResults: [gitResult],
        );
        expect(
          fired,
          isNull,
          reason: 'git-backed inspection must not be flagged unverified',
        );
      },
    );
  });
}
