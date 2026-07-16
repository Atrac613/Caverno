import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/terminal/application/caverno_cli_session_logging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application-default composition retains the shared log root', () {
    expect(
      resolveCavernoCliSessionLogRoot(
        dataDirectory: null,
        environment: const <String, String>{},
      ),
      isNull,
    );
  });

  test('explicit data roots own their session log directory', () async {
    final dataRoot = await Directory.systemTemp.createTemp(
      'caverno_cli_session_logs_',
    );
    addTearDown(() => dataRoot.delete(recursive: true));

    final store = createCavernoCliSessionLogStore(
      dataDirectory: dataRoot,
      environment: const <String, String>{},
    );
    final file = await store.fileForContext(
      const LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'session-1',
        phase: 'execution',
      ),
      create: false,
    );

    expect(file.path, '${dataRoot.path}/session_logs/coding/session-1.jsonl');
    expect(await file.parent.exists(), isFalse);
  });

  test('dedicated log override wins over the data root', () async {
    final dataRoot = await Directory.systemTemp.createTemp(
      'caverno_cli_data_root_',
    );
    final logRoot = await Directory.systemTemp.createTemp(
      'caverno_cli_log_root_',
    );
    addTearDown(() => dataRoot.delete(recursive: true));
    addTearDown(() => logRoot.delete(recursive: true));

    final store = createCavernoCliSessionLogStore(
      dataDirectory: dataRoot,
      environment: <String, String>{
        'CAVERNO_SESSION_LOG_DIR': logRoot.path,
        'CAVERNO_SESSION_LOG_MAX_AGE_DAYS': '2',
      },
    );
    final file = await store.fileForContext(
      const LlmSessionLogContext(
        workspaceMode: WorkspaceMode.chat,
        sessionId: 'session-2',
        phase: 'execution',
      ),
      create: false,
    );

    expect(file.path, '${logRoot.path}/chat/session-2.jsonl');
    expect(file.path, isNot(startsWith(dataRoot.path)));
  });
}
