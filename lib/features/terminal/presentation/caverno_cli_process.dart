import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/build_info.dart';
import '../../chat/application/persistence/caverno_persistence_bootstrap.dart';
import '../../chat/application/runtime/caverno_runtime_event.dart';
import '../../chat/data/repositories/chat_memory_repository.dart';
import '../../chat/data/repositories/conversation_repository.dart';
import '../../chat/data/repositories/skill_repository.dart';
import '../../chat/presentation/providers/caverno_execution_runtime_provider.dart';
import '../../chat/presentation/providers/semantic_search_provider.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../application/caverno_cli_application.dart';
import '../application/caverno_cli_arguments.dart';
import '../application/caverno_cli_contract.dart';
import '../application/caverno_cli_input.dart';
import '../application/caverno_cli_persistence.dart';
import 'caverno_cli_redactor.dart';
import 'caverno_terminal_presenter.dart';
import 'providers/caverno_terminal_runtime_adapter.dart';

Future<int> runCavernoCliProcess(
  List<String> arguments, {
  Map<String, String>? environment,
  Stdin? input,
  Stdout? output,
  Stdout? diagnostics,
}) async {
  final resolvedEnvironment = environment ?? Platform.environment;
  final terminal = _SystemTerminal(
    input: input ?? stdin,
    output: output ?? stdout,
    diagnostics: diagnostics ?? stderr,
  );
  CavernoCliInvocation invocation;
  try {
    invocation = CavernoCliInvocation.parse(arguments);
  } on CavernoCliFailure catch (failure) {
    _presentEarlyFailure(
      failure,
      json: arguments.contains('--json'),
      terminal: terminal,
      secrets: <String>[resolvedEnvironment['CAVERNO_LLM_API_KEY'] ?? ''],
    );
    await terminal.flush();
    return failure.exitCode;
  }

  switch (invocation.action) {
    case CavernoCliInvocationAction.help:
      terminal.writeStdout(_usage(invocation.command));
      await terminal.flush();
      return CavernoCliExitCode.success;
    case CavernoCliInvocationAction.version:
      terminal.writeStdout('Caverno ${BuildInfo.version}\n');
      await terminal.flush();
      return CavernoCliExitCode.success;
    case CavernoCliInvocationAction.run:
      break;
  }

  final dataDirectory = _firstNonEmpty(<String?>[
    invocation.dataDirectory,
    resolvedEnvironment['CAVERNO_HOME'],
  ]);
  final resolvedDataDirectory = dataDirectory.isEmpty
      ? null
      : Directory(dataDirectory).absolute;
  Box<String>? conversationBox;
  Box<String>? memoryBox;
  Box<String>? skillBox;
  Box<bool>? migrationBox;
  CavernoPersistenceStorage? persistenceStorage;
  ProviderContainer? container;
  try {
    if (resolvedDataDirectory == null) {
      await Hive.initFlutter();
    } else {
      await resolvedDataDirectory.create(recursive: true);
      Hive.init(resolvedDataDirectory.path);
    }
    conversationBox = await Hive.openBox<String>('conversations');
    memoryBox = await Hive.openBox<String>('chat_memory');
    skillBox = await Hive.openBox<String>('skills');
    if (resolvedDataDirectory != null) {
      migrationBox = await Hive.openBox<bool>(cavernoCliMigrationBoxName);
    }
    final preferences = await SharedPreferences.getInstance();
    final persistedApiKey = SettingsRepository(preferences).load().apiKey;
    persistenceStorage = await openCavernoCliPersistence(
      dataDirectory: resolvedDataDirectory,
      preferences: preferences,
      conversationBox: conversationBox,
      memoryBox: memoryBox,
      migrationBox: migrationBox,
    );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        conversationBoxProvider.overrideWithValue(conversationBox),
        chatMemoryBoxProvider.overrideWithValue(memoryBox),
        skillBoxProvider.overrideWithValue(skillBox),
        conversationRepositoryProvider.overrideWithValue(
          persistenceStorage.conversationRepository,
        ),
        chatMemoryRepositoryProvider.overrideWithValue(
          persistenceStorage.chatMemoryRepository,
        ),
        appDatabaseProvider.overrideWithValue(persistenceStorage.database),
        cavernoRuntimeSurfaceProvider.overrideWithValue(
          CavernoRuntimeSurface.terminal,
        ),
        cavernoRuntimeFrontendDiagnosticsProvider
            .overrideWithValue(<String, String>{
              'approvalMode': 'manual',
              'outputMode': invocation.outputMode.name,
              'dataDirectory': resolvedDataDirectory == null
                  ? 'application_default'
                  : resolvedDataDirectory.path,
            }),
      ],
    );
    final runtime = CavernoTerminalRuntimeAdapter(
      container: container,
      environment: resolvedEnvironment,
    );
    final redactor = CavernoCliRedactor(
      secrets: <String>[
        invocation.apiKey ?? '',
        resolvedEnvironment['CAVERNO_LLM_API_KEY'] ?? '',
        persistedApiKey,
      ],
    );
    final application = CavernoCliApplication(
      input: terminal,
      output: terminal,
      runtime: runtime,
      cancellationSignals: ProcessSignal.sigint.watch().map((_) {}),
      redactor: redactor,
    );
    final result = await application.run(invocation);
    await terminal.flush();
    return result;
  } on CavernoCliFailure catch (failure) {
    _presentEarlyFailure(
      failure,
      json: invocation.isJson,
      terminal: terminal,
      secrets: <String>[invocation.apiKey ?? ''],
    );
    await terminal.flush();
    return failure.exitCode;
  } on Object catch (error) {
    const exitCode = CavernoCliExitCode.persistence;
    _presentEarlyFailure(
      CavernoCliFailure(
        code: 'bootstrap_failed',
        message: error.toString(),
        exitCode: exitCode,
      ),
      json: invocation.isJson,
      terminal: terminal,
      secrets: <String>[invocation.apiKey ?? ''],
    );
    await terminal.flush();
    return exitCode;
  } finally {
    container?.dispose();
    await persistenceStorage?.close();
    await migrationBox?.close();
    await skillBox?.close();
    await memoryBox?.close();
    await conversationBox?.close();
  }
}

void _presentEarlyFailure(
  CavernoCliFailure failure, {
  required bool json,
  required _SystemTerminal terminal,
  required List<String> secrets,
}) {
  CavernoTerminalPresenter(
    outputMode: json ? CavernoCliOutputMode.json : CavernoCliOutputMode.human,
    output: terminal,
    redactor: CavernoCliRedactor(secrets: secrets),
  ).present(
    CavernoRuntimeRunFailed(
      sequence: 1,
      timestamp: DateTime.now().toUtc(),
      turnId: 'cli',
      code: failure.code,
      message: failure.message,
      exitCode: failure.exitCode,
    ),
  );
}

String _usage(CavernoCliCommand? command) {
  const common = '''
Input options:
  --prompt <text>       Use a literal prompt
  --prompt-file <path>  Read a UTF-8 prompt file
  --json                Emit caverno_cli_event JSON Lines

Configuration options:
  --base-url <url>      Override CAVERNO_LLM_BASE_URL
  --model <name>        Override CAVERNO_LLM_MODEL
  --api-key <value>     Override CAVERNO_LLM_API_KEY
  --data-dir <path>     Override CAVERNO_HOME
''';
  if (command != null) {
    final project = command == CavernoCliCommand.chat
        ? ''
        : ' --project <path>';
    return 'Usage: caverno ${command.name}$project [input options] [prompt]\n'
        '$common';
  }
  return '''Usage:
  caverno chat [input options] [prompt]
  caverno coding --project <path> [input options] [prompt]
  caverno plan --project <path> [input options] [prompt]
$common''';
}

String _firstNonEmpty(List<String?> candidates) {
  for (final candidate in candidates) {
    final value = candidate?.trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

final class _SystemTerminal
    implements
        CavernoCliInputPort,
        CavernoTerminalOutputPort,
        CavernoCliDiagnosticPort {
  _SystemTerminal({
    required this.input,
    required this.output,
    required this.diagnostics,
  });

  final Stdin input;
  final Stdout output;
  final Stdout diagnostics;
  StreamIterator<String>? _lines;

  @override
  bool get isTerminal => input.hasTerminal;

  @override
  Future<String> readFile(String path) => File(path).readAsString();

  @override
  Future<String?> readLine() async {
    final lines = _lines ??= StreamIterator<String>(
      input.transform(utf8.decoder).transform(const LineSplitter()),
    );
    return await lines.moveNext() ? lines.current : null;
  }

  @override
  Future<String> readToEnd() => input.transform(utf8.decoder).join();

  @override
  void writeDiagnostic(String value) {
    diagnostics.write(value);
  }

  @override
  void writeStderr(String value) {
    diagnostics.write(value);
  }

  @override
  void writeStdout(String value) {
    output.write(value);
  }

  Future<void> flush() async {
    await output.flush();
    await diagnostics.flush();
  }
}
