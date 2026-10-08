import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/application/runtime/shell_write_observer.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/shell_write_observation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const context = LlmSessionLogContext(
    workspaceMode: WorkspaceMode.coding,
    sessionId: 'observe-test',
  );
  const tag = 'cv-1727150000-0a1b2c3d';
  late Directory root;
  late LlmSessionLogStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('shell_write_observer_');
    store = LlmSessionLogStore(rootDirectoryProvider: () async => root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<List<Map<String, dynamic>>> entries() async {
    final file = await store.fileForContext(context, create: false);
    if (!file.existsSync()) return const [];
    return file
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
  }

  Future<void> observe(
    String payload, {
    bool enabled = true,
    bool reportingConfirmed = true,
  }) => observeShellWrites(
    store: store,
    settingsEnabled: enabled,
    context: context,
    toolName: 'local_execute_command',
    renderedPayload: payload,
    toolCallId: 'call-1',
    settle: Duration.zero,
    collect: (value) async {
      expect(value, tag);
      return (
        paths: reportingConfirmed
            ? const ['/Users/me/.pub-cache/x']
            : const <String>[],
        truncated: false,
        reportingConfirmed: reportingConfirmed,
      );
    },
  );

  test('records the outside-project writes of an observed command', () async {
    await observe(
      jsonEncode({'exit_code': 0, ShellWriteObservation.payloadKey: tag}),
    );
    final written = await entries();
    expect(written, hasLength(1));
    expect(written.single['operation'], 'shell_write_observation');
    expect(written.single['shellWriteObservation'], {
      'toolName': 'local_execute_command',
      'toolCallId': 'call-1',
      'tag': tag,
      'outsideProjectWrites': ['/Users/me/.pub-cache/x'],
    });
  });

  test(
    'marks an empty observation as unknown when reports never arrived',
    () async {
      await observe(
        jsonEncode({ShellWriteObservation.payloadKey: tag}),
        reportingConfirmed: false,
      );
      final written = await entries();
      expect(written.single['shellWriteObservation'], {
        'toolName': 'local_execute_command',
        'toolCallId': 'call-1',
        'tag': tag,
        'outsideProjectWrites': <String>[],
        'reportingUnavailable': true,
      });
    },
  );

  test('writes nothing for an unobserved command', () async {
    await observe('{"exit_code":0}');
    expect(await entries(), isEmpty);
  });

  test('writes nothing when session logging is off', () async {
    await observe(
      jsonEncode({ShellWriteObservation.payloadKey: tag}),
      enabled: false,
    );
    expect(await entries(), isEmpty);
  });
}
