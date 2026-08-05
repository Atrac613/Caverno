import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the corpus contamination measured on 2026-08-05: 1,569
/// of 1,740 files under `~/.caverno/session_logs` were written by the test
/// suite, not by real sessions, because every test exercising the production
/// provider built a default [LlmSessionLogStore].
void main() {
  group('writesEnabledFor', () {
    test('outside flutter test the default destination still writes', () {
      expect(
        LlmSessionLogStore.writesEnabledFor(
          hasExplicitRoot: false,
          isFlutterTest: false,
          directoryOverride: null,
        ),
        isTrue,
      );
    });

    test('under flutter test the default destination is a no-op', () {
      expect(
        LlmSessionLogStore.writesEnabledFor(
          hasExplicitRoot: false,
          isFlutterTest: true,
          directoryOverride: null,
        ),
        isFalse,
      );
    });

    test('an injected root re-enables writing under flutter test', () {
      expect(
        LlmSessionLogStore.writesEnabledFor(
          hasExplicitRoot: true,
          isFlutterTest: true,
          directoryOverride: null,
        ),
        isTrue,
      );
    });

    test('the directory override re-enables writing for live canaries', () {
      // The canary scripts run `flutter test` with CAVERNO_SESSION_LOG_DIR set
      // and read the logs back afterwards, so this branch must keep writing.
      expect(
        LlmSessionLogStore.writesEnabledFor(
          hasExplicitRoot: false,
          isFlutterTest: true,
          directoryOverride: '/tmp/canary-session-logs',
        ),
        isTrue,
      );
    });

    test('a blank override does not count as a deliberate destination', () {
      expect(
        LlmSessionLogStore.writesEnabledFor(
          hasExplicitRoot: false,
          isFlutterTest: true,
          directoryOverride: '   ',
        ),
        isFalse,
      );
    });
  });

  group('store', () {
    const context = LlmSessionLogContext(
      workspaceMode: WorkspaceMode.chat,
      sessionId: 'write-gate-probe',
      phase: 'chat_turn',
    );

    test('a default store writes nothing under flutter test', () async {
      final store = LlmSessionLogStore();

      await store.recordTurnExit(
        context: context,
        reason: 'text_response',
        noVisibleAnswer: false,
        finalAnswerRecoveryDecision: 'none',
        at: DateTime.utc(2026, 8, 5),
      );

      // fileForContext resolves against the real default root, so asserting on
      // absence here is what proves the developer's corpus stays untouched.
      final file = await store.fileForContext(context, create: false);
      expect(file.existsSync(), isFalse);
    });

    test('an injected root still records the entry', () async {
      final root = await Directory.systemTemp.createTemp('caverno-log-gate');
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      final store = LlmSessionLogStore(rootDirectoryProvider: () async => root);

      await store.recordTurnExit(
        context: context,
        reason: 'text_response',
        noVisibleAnswer: false,
        finalAnswerRecoveryDecision: 'none',
        at: DateTime.utc(2026, 8, 5),
      );

      final file = await store.fileForContext(context, create: false);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('turn_exit'));
    });
  });
}
