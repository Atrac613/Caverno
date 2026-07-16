import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/build_info.dart';
import '../../chat/application/persistence/caverno_chat_memory_mutation_coordinator.dart';
import '../../chat/application/persistence/caverno_persistence_bootstrap.dart';
import '../../chat/application/runtime/caverno_runtime_event.dart';
import '../../chat/data/datasources/session_logging_chat_datasource.dart';
import '../../chat/data/repositories/chat_memory_repository.dart';
import '../../chat/data/repositories/coding_project_repository.dart';
import '../../chat/data/repositories/conversation_repository.dart';
import '../../chat/data/datasources/app_database.dart';
import '../../chat/data/repositories/skill_repository.dart';
import '../../chat/presentation/providers/caverno_execution_runtime_provider.dart';
import '../../chat/presentation/providers/conversations_notifier.dart';
import '../../chat/presentation/providers/semantic_search_provider.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../../routines/data/routine_repository.dart';
import '../application/caverno_cli_application.dart';
import '../application/caverno_cli_arguments.dart';
import '../application/caverno_cli_coding_project_repository.dart';
import '../application/caverno_cli_contract.dart';
import '../application/caverno_cli_input.dart';
import '../application/caverno_cli_persistence.dart';
import '../application/caverno_cli_routine_repository.dart';
import '../application/caverno_cli_session_logging.dart';
import '../application/caverno_conversation_query.dart';
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
      terminal.writeStdout(
        _usage(invocation.command, invocation.conversationCommand),
      );
      await terminal.flush();
      return CavernoCliExitCode.success;
    case CavernoCliInvocationAction.version:
      terminal.writeStdout('Caverno ${BuildInfo.version}\n');
      await terminal.flush();
      return CavernoCliExitCode.success;
    case CavernoCliInvocationAction.run:
    case CavernoCliInvocationAction.conversationResume:
    case CavernoCliInvocationAction.conversationList:
    case CavernoCliInvocationAction.conversationShow:
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
    if (resolvedDataDirectory != null) {
      migrationBox = await Hive.openBox<bool>(cavernoCliMigrationBoxName);
    }
    final preferences = await SharedPreferences.getInstance();
    final runtimeDataRoot = await resolveCavernoDataRoot(
      explicitDataDirectory: resolvedDataDirectory,
    );
    final migrationStatus = resolveCavernoCliMigrationStatus(
      dataDirectory: resolvedDataDirectory,
      preferences: preferences,
      migrationBox: migrationBox,
    );
    final isConversationQuery =
        invocation.action == CavernoCliInvocationAction.conversationList ||
        invocation.action == CavernoCliInvocationAction.conversationShow;
    if (!migrationStatus.conversationsMigrated) {
      conversationBox = await Hive.openBox<String>('conversations');
    }
    if (!migrationStatus.chatMemoryMigrated) {
      memoryBox = await Hive.openBox<String>('chat_memory');
    }
    persistenceStorage = await openCavernoCliPersistence(
      dataDirectory: resolvedDataDirectory,
      preferences: preferences,
      conversationBox: conversationBox,
      memoryBox: memoryBox,
      migrationBox: migrationBox,
      mutationCoordinator: CavernoChatMemoryMutationCoordinator(
        dataRoot: runtimeDataRoot,
        frontend: CavernoRuntimeSurface.terminal.name,
      ),
    );
    await conversationBox?.close();
    conversationBox = null;
    await memoryBox?.close();
    memoryBox = null;
    await migrationBox?.close();
    migrationBox = null;
    final redactor = CavernoCliRedactor(
      secrets: <String>[
        invocation.apiKey ?? '',
        resolvedEnvironment['CAVERNO_LLM_API_KEY'] ?? '',
      ],
    );
    if (isConversationQuery) {
      final result = CavernoConversationQuery(
        repository: persistenceStorage.conversationRepository,
        output: terminal,
        redactor: redactor,
      ).run(invocation);
      await terminal.flush();
      return result;
    }

    final persistedApiKey = SettingsRepository(preferences).load().apiKey;
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (conversationBox != null)
          conversationBoxProvider.overrideWithValue(conversationBox),
        if (memoryBox != null)
          chatMemoryBoxProvider.overrideWithValue(memoryBox),
        conversationRepositoryProvider.overrideWithValue(
          persistenceStorage.conversationRepository,
        ),
        chatMemoryRepositoryProvider.overrideWithValue(
          persistenceStorage.chatMemoryRepository,
        ),
        llmSessionLogStoreProvider.overrideWithValue(
          createCavernoCliSessionLogStore(
            dataDirectory: resolvedDataDirectory,
            environment: resolvedEnvironment,
          ),
        ),
        codingProjectRepositoryProvider.overrideWithValue(
          createCavernoCliCodingProjectRepository(
            dataDirectory: resolvedDataDirectory,
            preferences: preferences,
          ),
        ),
        routineRepositoryProvider.overrideWithValue(
          createCavernoCliRoutineRepository(
            dataDirectory: resolvedDataDirectory,
            preferences: preferences,
          ),
        ),
        skillRepositoryProvider.overrideWithValue(SkillRepository.inMemory()),
        appDatabaseProvider.overrideWithValue(persistenceStorage.database),
        cavernoRuntimeSurfaceProvider.overrideWithValue(
          CavernoRuntimeSurface.terminal,
        ),
        cavernoRuntimeDataRootProvider.overrideWithValue(runtimeDataRoot),
        if (invocation.action == CavernoCliInvocationAction.conversationResume)
          deferInitialConversationCreationProvider.overrideWithValue(true),
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
    final runtimeRedactor = CavernoCliRedactor(
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
      redactor: runtimeRedactor,
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

String _usage(
  CavernoCliCommand? command,
  CavernoCliConversationCommand? conversationCommand,
) {
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
  if (conversationCommand != null) {
    return switch (conversationCommand) {
      CavernoCliConversationCommand.list =>
        '''Usage: caverno conversations list [options]

Options:
  --limit <count>       Return 1 through 200 conversations (default: 20)
  --json                Emit one caverno_cli_event JSON Line
  --data-dir <path>     Override CAVERNO_HOME
''',
      CavernoCliConversationCommand.show =>
        '''Usage: caverno conversations show <conversation-id> [options]

Options:
  --json                Emit one caverno_cli_event JSON Line
  --data-dir <path>     Override CAVERNO_HOME
''',
      CavernoCliConversationCommand.resume =>
        '''Usage: caverno conversations resume <conversation-id> [input options] [prompt]
$common''',
    };
  }
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
  caverno conversations list [--limit <count>] [--json]
  caverno conversations show <conversation-id> [--json]
  caverno conversations resume <conversation-id> [input options] [prompt]
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
