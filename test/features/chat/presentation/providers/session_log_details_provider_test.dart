import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/chat/presentation/providers/session_log_details_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this._settings);

  final AppSettings _settings;

  @override
  AppSettings build() => _settings;
}

ProviderContainer _container({
  required Directory root,
  required AppSettings settings,
}) {
  final container = ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _FixedSettingsNotifier(settings),
      ),
      llmSessionLogStoreProvider.overrideWithValue(
        LlmSessionLogStore(rootDirectoryProvider: () async => root),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('session_log_details_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('formattedSize renders human-readable units', () {
    SessionLogFileDetails details(int bytes) => SessionLogFileDetails(
      path: '/tmp/log.jsonl',
      fileName: 'log.jsonl',
      exists: true,
      sizeBytes: bytes,
      loggingEnabled: true,
    );

    expect(details(512).formattedSize, '512 B');
    expect(details(1024).formattedSize, '1.0 KB');
    expect(details(1536).formattedSize, '1.5 KB');
    expect(details(5 * 1024 * 1024).formattedSize, '5.0 MB');
  });

  test('resolves size and path when logging is enabled and file exists', () async {
    final logFile = File('${tempRoot.path}/chat/thread-1.jsonl');
    logFile.parent.createSync(recursive: true);
    const payload = '{"hello":"world"}\n';
    logFile.writeAsStringSync(payload);

    final container = _container(
      root: tempRoot,
      settings: AppSettings.defaults().copyWith(
        enableLlmSessionLogs: true,
        demoMode: false,
      ),
    );

    final details = await container.read(
      sessionLogDetailsProvider((
        workspaceMode: WorkspaceMode.chat,
        sessionId: 'thread-1',
      )).future,
    );

    expect(details.loggingEnabled, isTrue);
    expect(details.exists, isTrue);
    expect(details.fileName, 'thread-1.jsonl');
    expect(details.path, logFile.path);
    expect(details.sizeBytes, payload.length);
    expect(details.modifiedAt, isNotNull);
  });

  test('reports a missing log without creating the workspace directory', () async {
    final container = _container(
      root: tempRoot,
      settings: AppSettings.defaults().copyWith(
        enableLlmSessionLogs: true,
        demoMode: false,
      ),
    );

    final details = await container.read(
      sessionLogDetailsProvider((
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'thread-2',
      )).future,
    );

    expect(details.loggingEnabled, isTrue);
    expect(details.exists, isFalse);
    expect(details.sizeBytes, 0);
    expect(details.fileName, 'thread-2.jsonl');
    expect(details.path, '${tempRoot.path}/coding/thread-2.jsonl');
    // create: false must not materialize the workspace directory.
    expect(Directory('${tempRoot.path}/coding').existsSync(), isFalse);
  });

  test('marks logging disabled when settings disable session logs', () async {
    final container = _container(
      root: tempRoot,
      settings: AppSettings.defaults().copyWith(
        enableLlmSessionLogs: false,
        demoMode: false,
      ),
    );

    final details = await container.read(
      sessionLogDetailsProvider((
        workspaceMode: WorkspaceMode.chat,
        sessionId: 'thread-3',
      )).future,
    );

    expect(details.loggingEnabled, isFalse);
  });
}
