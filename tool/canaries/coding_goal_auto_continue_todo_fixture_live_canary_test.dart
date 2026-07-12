import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/constants/build_info.dart';
import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _verifyCommand = 'dart run tool/verify_todo_app.dart';
const _wordFrequencyVerifyCommand =
    'dart run tool/verify_word_frequency_cli.dart';
const _markdownTocVerifyCommand = 'dart run tool/verify_markdown_toc.dart';
const _stagedFailureTurns = 2;
const _postSuccessMutationCode = 'todo_post_success_mutation';
const _minimalPrompt =
    'todo_app.md の要件に従って、DartでMVPを実装してください。'
    '記載された受け入れ基準を実際に確認し、すべて通るまで修正してください。';

void main() {
  final autoContinueEnabled =
      Platform.environment['CAVERNO_CODING_GOAL_TODO_AUTO_CONTINUE_CANARY'] ==
      '1';
  final mvpEnabled =
      Platform.environment['CAVERNO_CODING_TODO_APP_MVP_LIVE_CANARY'] == '1';
  final minimalPromptEnabled =
      Platform
          .environment['CAVERNO_CODING_TODO_APP_MINIMAL_PROMPT_LIVE_CANARY'] ==
      '1';
  final wordFrequencyEnabled =
      Platform.environment['CAVERNO_CODING_WORD_FREQUENCY_LIVE_CANARY'] == '1';
  final markdownTocEnabled =
      Platform.environment['CAVERNO_CODING_MARKDOWN_TOC_LIVE_CANARY'] == '1';

  test('TODO fixture blocks mutations after verifier success', () async {
    final root = Directory.systemTemp.createTempSync(
      'todo_post_success_mutation_',
    );
    try {
      final service = _TodoToolService(root, stagedFailureTurns: 0);
      final target = File('${root.path}/bin/todo_cli.dart');

      final initialWrite = await service.executeTool(
        name: 'write_file',
        arguments: {'path': target.path, 'content': 'void main() {}\n'},
      );
      expect(initialWrite.isSuccess, isTrue);

      service.executedCalls.add(
        _TodoToolCall(
          name: 'local_execute_command',
          arguments: const {'command': _verifyCommand},
          result: jsonEncode({
            'canary': 'todo_app',
            'command': _verifyCommand,
            'exit_code': 0,
            'diagnostics': const [],
          }),
          success: true,
        ),
      );

      final blockedWrite = await service.executeTool(
        name: 'write_file',
        arguments: {
          'path': target.path,
          'content': 'void main() { throw StateError("regression"); }\n',
        },
      );
      final blockedEdit = await service.executeTool(
        name: 'edit_file',
        arguments: {
          'path': target.path,
          'old_text': 'void main() {}',
          'new_text': 'void main() { throw StateError("regression"); }',
        },
      );
      final blockedDelete = await service.executeTool(
        name: 'delete_file',
        arguments: {'path': target.path},
      );

      expect(blockedWrite.isSuccess, isFalse);
      expect(blockedEdit.isSuccess, isFalse);
      expect(blockedDelete.isSuccess, isFalse);
      expect(
        _tryDecodeObject(blockedWrite.result)['code'],
        _postSuccessMutationCode,
      );
      expect(
        _tryDecodeObject(blockedEdit.result)['code'],
        _postSuccessMutationCode,
      );
      expect(target.readAsStringSync(), 'void main() {}\n');
      expect(service.postSuccessMutationAttempts, hasLength(3));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('TODO verifier copies source without prior runtime state', () {
    final root = Directory.systemTemp.createTempSync(
      'todo_verification_source_',
    );
    try {
      Directory('${root.path}/bin').createSync(recursive: true);
      Directory('${root.path}/lib').createSync(recursive: true);
      Directory('${root.path}/tool').createSync(recursive: true);
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
      File(
        '${root.path}/bin/todo_cli.dart',
      ).writeAsStringSync('void main() {}');
      File(
        '${root.path}/lib/helper.dart',
      ).writeAsStringSync('const value = 1;');
      File(
        '${root.path}/tool/verify_todo_app.dart',
      ).writeAsStringSync('void main() {}');
      File('${root.path}/.unexpected_state.json').writeAsStringSync('{}');

      final service = _TodoToolService(root, stagedFailureTurns: 0);
      final verificationRoot = service.createVerificationRoot();
      try {
        expect(
          File('${verificationRoot.path}/pubspec.yaml').existsSync(),
          true,
        );
        expect(
          File('${verificationRoot.path}/bin/todo_cli.dart').existsSync(),
          true,
        );
        expect(
          File('${verificationRoot.path}/lib/helper.dart').existsSync(),
          true,
        );
        expect(
          File(
            '${verificationRoot.path}/tool/verify_todo_app.dart',
          ).existsSync(),
          false,
        );
        expect(
          File('${verificationRoot.path}/.unexpected_state.json').existsSync(),
          false,
        );
      } finally {
        verificationRoot.deleteSync(recursive: true);
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'TODO verifier rejects and can remove an unexpected entrypoint',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'todo_unexpected_entrypoint_',
      );
      try {
        Directory('${root.path}/bin').createSync(recursive: true);
        File('${root.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
        File(
          '${root.path}/bin/todo_cli.dart',
        ).writeAsStringSync('void main() {}');
        final unexpected = File('${root.path}/bin/todo.dart')
          ..writeAsStringSync('void main() {}');
        final service = _TodoToolService(root, stagedFailureTurns: 0);

        final verification = await service.verifyTodoApp();

        expect(
          verification.diagnostics.map((item) => item['code']),
          contains('todo_cli_unexpected_entrypoint'),
        );
        final deletion = await service.executeTool(
          name: 'delete_file',
          arguments: {'path': 'bin/todo.dart'},
        );
        expect(deletion.isSuccess, isTrue);
        expect(unexpected.existsSync(), isFalse);
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('word-frequency verifier accepts the canonical Dart behavior', () async {
    final fixture = _TodoFixture.create(null);
    try {
      _configureWordFrequencyFixture(fixture.root);
      File('${fixture.root.path}/bin/word_frequency.dart').writeAsStringSync(
        r'''
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: word_frequency <file> [count]');
    exitCode = 64;
    return;
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('Cannot read ${args.first}');
    exitCode = 66;
    return;
  }
  final limit = args.length > 2 && args[1] == '--top'
      ? int.parse(args[2])
      : 10;
  final counts = <String, int>{};
  for (final raw in file.readAsStringSync().split(RegExp(r'\s+'))) {
    final word = raw.toLowerCase().replaceAll(
      RegExp(r'^[^a-z0-9]+|[^a-z0-9]+$'),
      '',
    );
    if (word.isNotEmpty) counts[word] = (counts[word] ?? 0) + 1;
  }
  final rows = counts.entries.toList()
    ..sort((a, b) {
      final count = b.value.compareTo(a.value);
      return count != 0 ? count : a.key.compareTo(b.key);
    });
  for (final row in rows.take(limit)) {
    stdout.writeln('${row.key} ${row.value}');
  }
}
''',
      );
      final service = _WordFrequencyToolService(fixture.root);

      final verification = await service.verifyWordFrequency();

      expect(
        verification.diagnostics,
        isEmpty,
        reason: verification.transcript,
      );
    } finally {
      fixture.dispose();
    }
  });

  test('Markdown TOC verifier accepts the canonical Dart behavior', () async {
    final fixture = _TodoFixture.create(null);
    try {
      _configureMarkdownTocFixture(fixture.root);
      File('${fixture.root.path}/bin/markdown_toc.dart').writeAsStringSync(r'''
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: markdown_toc <file>');
    exitCode = 64;
    return;
  }
  final headings = <(int, String)>[];
  String? fence;
  for (final line in File(args.first).readAsLinesSync()) {
    final fenceMatch = RegExp(r'^\s*(```|~~~)').firstMatch(line);
    if (fenceMatch != null) {
      final marker = fenceMatch.group(1)!;
      fence = fence == null ? marker : (fence == marker ? null : fence);
      continue;
    }
    if (fence != null) continue;
    final match = RegExp(r'^(#{1,6}) (.+)$').firstMatch(line);
    if (match != null) headings.add((match.group(1)!.length, match.group(2)!));
  }
  if (headings.isEmpty) return;
  final base = headings.map((item) => item.$1).reduce((a, b) => a < b ? a : b);
  final slugs = <String, int>{};
  for (final heading in headings) {
    final plain = heading.$2.replaceAll(RegExp(r'[^A-Za-z0-9\- ]'), '');
    final root = plain.toLowerCase().replaceAll(' ', '-');
    final duplicate = slugs[root] ?? 0;
    slugs[root] = duplicate + 1;
    final slug = duplicate == 0 ? root : '$root-$duplicate';
    stdout.writeln('${'  ' * (heading.$1 - base)}- [${heading.$2}](#$slug)');
  }
}
''');
      final service = _MarkdownTocToolService(fixture.root);

      final verification = await service.verifyMarkdownToc();

      expect(
        verification.diagnostics,
        isEmpty,
        reason: verification.transcript,
      );
      final result = await service.executeTool(
        name: 'local_execute_command',
        arguments: {
          'command': _markdownTocVerifyCommand,
          'working_directory': fixture.root.path,
        },
      );
      expect(
        result.isSuccess,
        isTrue,
        reason: '${result.errorMessage}\n${result.result}',
      );
      expect(_tryDecodeObject(result.result)['terminal_success'], isTrue);
    } finally {
      fixture.dispose();
    }
  });

  test('Markdown TOC verifier diagnoses an unclosed fence precisely', () async {
    final fixture = _TodoFixture.create(null);
    try {
      _configureMarkdownTocFixture(fixture.root);
      File('${fixture.root.path}/bin/markdown_toc.dart').writeAsStringSync(r'''
void main() {
  print('- [API Reference!](#api-reference)');
  print('  - [Setup](#setup)');
}
''');
      final service = _MarkdownTocToolService(fixture.root);

      final verification = await service.verifyMarkdownToc();
      final codes = verification.diagnostics
          .map((diagnostic) => diagnostic['code'])
          .toSet();

      expect(codes, contains('markdown_toc_fence_close_failed'));
      expect(codes, contains('markdown_toc_row_count_failed'));
      expect(codes, isNot(contains('markdown_toc_heading_or_slug_failed')));
    } finally {
      fixture.dispose();
    }
  });

  test('Markdown TOC verifier rejects reordered headings', () async {
    final fixture = _TodoFixture.create(null);
    try {
      _configureMarkdownTocFixture(fixture.root);
      File('${fixture.root.path}/bin/markdown_toc.dart').writeAsStringSync(r'''
void main() {
  print('- [API Reference!](#api-reference)');
  print('  - [Setup](#setup)');
  print('  - [Notes](#notes-1)');
  print('  - [Notes](#notes)');
  print('    - [Detail](#detail)');
}
''');
      final service = _MarkdownTocToolService(fixture.root);

      final verification = await service.verifyMarkdownToc();
      final codes = verification.diagnostics
          .map((diagnostic) => diagnostic['code'])
          .toSet();

      expect(codes, contains('markdown_toc_sequence_failed'));
    } finally {
      fixture.dispose();
    }
  });

  test(
    'live LLM auto-continues the todo_app.md MVP fixture from diagnostic evidence',
    () async {
      final env = _TodoFixtureEnv.fromEnvironment();
      final fixture = _TodoFixture.create(env.workspaceRoot);
      final sessionLogRoot = Directory(env.sessionLogRoot)
        ..createSync(recursive: true);
      final logStore = LlmSessionLogStore(
        rootDirectoryProvider: () async => sessionLogRoot,
      );
      final dataSource = _TodoAutoContinueDataSource(
        env,
        stagedFailureTurns: _stagedFailureTurns,
      );
      final toolService = _TodoToolService(
        fixture.root,
        stagedFailureTurns: _stagedFailureTurns,
      );
      final container = _buildContainer(
        env: env,
        fixture: fixture,
        dataSource: dataSource,
        toolService: toolService,
        logStore: logStore,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: fixture.project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Build the TODO app from docs/coding_mvp_fixtures/todo_app.md '
              'in this scratch project. Use a Dart command-line program at '
              'bin/todo_cli.dart. The goal is complete only after '
              'local_execute_command runs "$_verifyCommand" and it exits with '
              'code 0.',
          enabled: true,
          autoContinue: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 60000,
          turnBudget: 5,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          [
            'Direct-build the TODO MVP fixture in the selected scratch '
                'project. This is the compact builder spec derived from '
                'docs/coding_mvp_fixtures/todo_app.md.',
            '',
            _builderSpec(),
            '',
            'Implementation constraints for this live check:',
            '- Use write_file to create the runnable Dart CLI at '
                'bin/todo_cli.dart.',
            '- The verifier stub already exists at tool/verify_todo_app.dart; '
                'do not inspect or edit it.',
            '- Verify by calling local_execute_command with command '
                '"$_verifyCommand" from the project root.',
            '- Do not end a turn by asking whether to continue; keep using the '
                'available tools until the verifier exits with code 0, a clear '
                'blocker is reached, or the goal budget stops you.',
            '- Continue until that verifier exits with code 0, or state a '
                'clear blocker if you cannot make progress.',
          ].join('\n'),
          bypassPlanMode: true,
        );

        await _waitForGoalTerminalOrIdle(container);

        final conversation = container
            .read(conversationsNotifierProvider)
            .currentConversation!;
        final logFile = await logStore.fileForContext(
          LlmSessionLogContext(
            workspaceMode: WorkspaceMode.coding,
            sessionId: conversation.id,
            conversationId: conversation.id,
          ),
          create: false,
        );
        final entries = await _readSessionLogEntries(logFile);
        final autoContinueEntries = entries
            .where((entry) => entry['operation'] == 'goal_auto_continue')
            .toList(growable: false);
        final turnExitIndices = _operationIndices(entries, 'turn_exit');
        final autoContinueIndices = _operationIndices(
          entries,
          'goal_auto_continue',
        );
        final continuationRequestIndices = entries
            .asMap()
            .entries
            .where((entry) => _isContinuationRequest(entry.value))
            .map((entry) => entry.key)
            .toList(growable: false);
        final unresolvedCounts = autoContinueEntries
            .map(_unresolvedErrorCount)
            .whereType<int>()
            .where((count) => count > 0)
            .toList(growable: false);
        final goal = conversation.goal;
        final terminalEnough =
            goal?.status == ConversationGoalStatus.completed ||
            goal?.status == ConversationGoalStatus.blocked ||
            (goal?.turnBudgetExceeded ?? false);

        expect(
          entries.first['schemaVersion'],
          LlmSessionLogStore.schemaVersion,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          entries.first['build']['commit'],
          BuildInfo.commit,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          autoContinueEntries.length,
          greaterThanOrEqualTo(2),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          unresolvedCounts.length,
          greaterThanOrEqualTo(2),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          _hasStrictDecrease(unresolvedCounts) ||
              _hasTerminalVerifierSuccess(entries),
          isTrue,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          _hasOrderedTriple(
            turnExitIndices,
            autoContinueIndices,
            continuationRequestIndices,
          ),
          isTrue,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          terminalEnough,
          isTrue,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: autoContinueEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_TODO_AUTO_CONTINUE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    'live LLM assembles the todo_app.md MVP as a Dart CLI',
    () => _runTodoMvpLiveScenario(_detailedMvpPrompt()),
    skip: mvpEnabled
        ? false
        : 'Set CAVERNO_CODING_TODO_APP_MVP_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    'live LLM assembles the todo_app.md MVP from the minimal Japanese prompt',
    () => _runTodoMvpLiveScenario(_minimalPrompt),
    skip: minimalPromptEnabled
        ? false
        : 'Set CAVERNO_CODING_TODO_APP_MINIMAL_PROMPT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    'live LLM assembles the word_frequency_cli.md MVP from a short prompt',
    _runWordFrequencyLiveScenario,
    skip: wordFrequencyEnabled
        ? false
        : 'Set CAVERNO_CODING_WORD_FREQUENCY_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    'live LLM assembles the markdown_toc_generator.md MVP from a short prompt',
    _runMarkdownTocLiveScenario,
    skip: markdownTocEnabled
        ? false
        : 'Set CAVERNO_CODING_MARKDOWN_TOC_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<void> _runMarkdownTocLiveScenario() async {
  final env = _TodoFixtureEnv.fromEnvironment();
  final fixture = _TodoFixture.create(env.workspaceRoot);
  _configureMarkdownTocFixture(fixture.root);
  final sessionLogRoot = Directory(env.sessionLogRoot)
    ..createSync(recursive: true);
  final dataSource = _TodoAutoContinueDataSource(env, stagedFailureTurns: 0);
  final toolService = _MarkdownTocToolService(fixture.root);
  final container = _buildContainer(
    env: env,
    fixture: fixture,
    dataSource: dataSource,
    toolService: toolService,
    logStore: LlmSessionLogStore(
      rootDirectoryProvider: () async => sessionLogRoot,
    ),
  );
  const prompt =
      'markdown_toc_generator.md の要件に従って、DartでMVPを実装してください。'
      '記載された受け入れ基準を実際に確認し、すべて通るまで修正してください。';

  try {
    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: fixture.project.id,
    );
    await conversations.saveCurrentGoal(
      objective: prompt,
      enabled: true,
      autoContinue: true,
      status: ConversationGoalStatus.active,
      tokenBudget: 60000,
      turnBudget: 5,
    );
    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage(prompt, bypassPlanMode: true);
    await _waitForGoalTerminalOrIdle(container);

    final verification = await toolService.verifyMarkdownToc();
    final diagnostic = _diagnostic(container, dataSource, toolService, fixture);
    expect(
      File('${fixture.root.path}/bin/markdown_toc.dart').existsSync(),
      isTrue,
      reason: diagnostic,
    );
    expect(
      Directory(
        '${fixture.root.path}/bin',
      ).listSync().whereType<File>().map((file) => file.uri.pathSegments.last),
      unorderedEquals(const ['markdown_toc.dart']),
      reason: diagnostic,
    );
    expect(toolService.hasSuccessfulVerifierCall, isTrue, reason: diagnostic);
    final finalGoal = container
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.goal;
    expect(
      finalGoal?.status,
      isNot(ConversationGoalStatus.blocked),
      reason: '$diagnostic\nA verified goal must not be marked blocked.',
    );
    expect(
      toolService.postSuccessMutationAttempts,
      isEmpty,
      reason: diagnostic,
    );
    expect(
      verification.diagnostics,
      isEmpty,
      reason: '$diagnostic\n${verification.transcript}',
    );
  } finally {
    container.dispose();
    fixture.dispose();
  }
}

Future<void> _runWordFrequencyLiveScenario() async {
  final env = _TodoFixtureEnv.fromEnvironment();
  final fixture = _TodoFixture.create(env.workspaceRoot);
  _configureWordFrequencyFixture(fixture.root);
  final sessionLogRoot = Directory(env.sessionLogRoot)
    ..createSync(recursive: true);
  final logStore = LlmSessionLogStore(
    rootDirectoryProvider: () async => sessionLogRoot,
  );
  final dataSource = _TodoAutoContinueDataSource(env, stagedFailureTurns: 0);
  final toolService = _WordFrequencyToolService(fixture.root);
  final container = _buildContainer(
    env: env,
    fixture: fixture,
    dataSource: dataSource,
    toolService: toolService,
    logStore: logStore,
  );
  const prompt =
      'word_frequency_cli.md の要件に従って、DartでMVPを実装してください。'
      '記載された受け入れ基準を実際に確認し、すべて通るまで修正してください。';

  try {
    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: fixture.project.id,
    );
    await conversations.saveCurrentGoal(
      objective: prompt,
      enabled: true,
      autoContinue: true,
      status: ConversationGoalStatus.active,
      tokenBudget: 60000,
      turnBudget: 5,
    );

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage(prompt, bypassPlanMode: true);
    await _waitForGoalTerminalOrIdle(container);

    final verification = await toolService.verifyWordFrequency();
    final diagnostic = _diagnostic(container, dataSource, toolService, fixture);
    expect(
      File('${fixture.root.path}/bin/word_frequency.dart').existsSync(),
      isTrue,
      reason: diagnostic,
    );
    expect(
      Directory(
        '${fixture.root.path}/bin',
      ).listSync().whereType<File>().map((file) => file.uri.pathSegments.last),
      unorderedEquals(const ['word_frequency.dart']),
      reason: diagnostic,
    );
    expect(toolService.hasSuccessfulVerifierCall, isTrue, reason: diagnostic);
    expect(
      toolService.postSuccessMutationAttempts,
      isEmpty,
      reason: diagnostic,
    );
    expect(
      verification.diagnostics,
      isEmpty,
      reason: '$diagnostic\n${verification.transcript}',
    );
  } finally {
    container.dispose();
    fixture.dispose();
  }
}

void _configureWordFrequencyFixture(Directory root) {
  File('${root.path}/todo_app.md').deleteSync();
  File('${root.path}/tool/verify_todo_app.dart').deleteSync();
  final source = File('docs/coding_mvp_fixtures/word_frequency_cli.md');
  if (!source.existsSync()) {
    throw StateError('word_frequency_cli.md fixture is required.');
  }
  File(
    '${root.path}/word_frequency_cli.md',
  ).writeAsStringSync(source.readAsStringSync());
  File('${root.path}/tool/verify_word_frequency_cli.dart').writeAsStringSync('''
// Live canary placeholder. The harness intercepts this verifier command.
void main() {}
''');
}

void _configureMarkdownTocFixture(Directory root) {
  File('${root.path}/todo_app.md').deleteSync();
  File('${root.path}/tool/verify_todo_app.dart').deleteSync();
  final source = File('docs/coding_mvp_fixtures/markdown_toc_generator.md');
  if (!source.existsSync()) {
    throw StateError('markdown_toc_generator.md fixture is required.');
  }
  File(
    '${root.path}/markdown_toc_generator.md',
  ).writeAsStringSync(source.readAsStringSync());
  File('${root.path}/tool/verify_markdown_toc.dart').writeAsStringSync('''
// Live canary placeholder. The harness intercepts this verifier command.
void main() {}
''');
}

Future<void> _runTodoMvpLiveScenario(String prompt) async {
  final env = _TodoFixtureEnv.fromEnvironment();
  final fixture = _TodoFixture.create(env.workspaceRoot);
  final sessionLogRoot = Directory(env.sessionLogRoot)
    ..createSync(recursive: true);
  final logStore = LlmSessionLogStore(
    rootDirectoryProvider: () async => sessionLogRoot,
  );
  final dataSource = _TodoAutoContinueDataSource(env, stagedFailureTurns: 0);
  final toolService = _TodoToolService(fixture.root, stagedFailureTurns: 0);
  final container = _buildContainer(
    env: env,
    fixture: fixture,
    dataSource: dataSource,
    toolService: toolService,
    logStore: logStore,
  );

  try {
    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: fixture.project.id,
    );
    await conversations.saveCurrentGoal(
      objective: prompt,
      enabled: true,
      autoContinue: true,
      status: ConversationGoalStatus.active,
      tokenBudget: 60000,
      turnBudget: 5,
    );

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage(prompt, bypassPlanMode: true);

    await _waitForGoalTerminalOrIdle(container);
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation!;
    final independentVerification = await toolService.verifyTodoApp();
    final diagnostic = _diagnostic(container, dataSource, toolService, fixture);

    expect(
      File('${fixture.root.path}/bin/todo_cli.dart').existsSync(),
      isTrue,
      reason: diagnostic,
    );
    expect(
      Directory(
        '${fixture.root.path}/bin',
      ).listSync().whereType<File>().map((file) => file.uri.pathSegments.last),
      unorderedEquals(const ['todo_cli.dart']),
      reason: diagnostic,
    );
    expect(conversation.goal, isNotNull, reason: diagnostic);
    expect(
      conversation.effectiveWorkflowSpec.sources.map((source) => source.kind),
      containsAll(<ConversationContractSourceKind>{
        ConversationContractSourceKind.userMessage,
        ConversationContractSourceKind.specificationFile,
      }),
      reason: diagnostic,
    );
    final specificationSource = conversation.effectiveWorkflowSpec.sources
        .singleWhere(
          (source) =>
              source.kind == ConversationContractSourceKind.specificationFile,
        );
    expect(specificationSource.locator, 'todo_app.md', reason: diagnostic);
    expect(specificationSource.contentHash, isNotEmpty, reason: diagnostic);
    expect(
      conversation.effectiveWorkflowSpec.provenance,
      isNotEmpty,
      reason: diagnostic,
    );
    expect(
      toolService.verificationAttempts,
      greaterThanOrEqualTo(1),
      reason: diagnostic,
    );
    expect(toolService.hasSuccessfulVerifierCall, isTrue, reason: diagnostic);
    expect(
      toolService.postSuccessMutationAttempts,
      isEmpty,
      reason: '$diagnostic\npostSuccessMutationCode=$_postSuccessMutationCode',
    );
    expect(
      independentVerification.diagnostics,
      isEmpty,
      reason:
          '$diagnostic\nindependentVerification='
          '${jsonEncode(independentVerification.diagnostics)}\n'
          '${independentVerification.transcript}',
    );
  } finally {
    container.dispose();
    fixture.dispose();
  }
}

String _detailedMvpPrompt() {
  return [
    'Direct-build the MVP from todo_app.md in this empty scratch project.',
    '',
    'Language and layout are fixed for this controlled Live LLM canary:',
    '- Implement a Dart command-line program at bin/todo_cli.dart.',
    '- Use only the Dart SDK; do not add Flutter, a GUI, a web server, or a database.',
    '',
    _builderSpec(),
    '',
    'Verification requirements:',
    '- The verifier stub already exists at tool/verify_todo_app.dart; do not inspect or edit it.',
    '- Run local_execute_command with command "$_verifyCommand" from the project root.',
    '- The verifier runs every check in a fresh isolated copy of the Dart sources. '
        'Do not prepend or append rm, cat, shell operators, or any other command.',
    '- Use the verifier diagnostics to repair the implementation and rerun it '
        'until it exits with code 0 or a concrete blocker prevents progress.',
    '- Read the current implementation with read_file and prefer edit_file for '
        'focused repairs instead of rewriting the whole file.',
    '- Do not claim completion unless that verifier exits with code 0.',
    '- After the verifier exits with code 0, do not call any more tools or '
        'modify files. Return the final answer immediately.',
  ].join('\n');
}

ProviderContainer _buildContainer({
  required _TodoFixtureEnv env,
  required _TodoFixture fixture,
  required _TodoAutoContinueDataSource dataSource,
  required _TodoToolService toolService,
  required LlmSessionLogStore logStore,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(() => _LiveSettingsNotifier(env)),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _LiveCodingProjectsNotifier(fixture.project),
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

String _builderSpec() {
  return '''
Build a small command-line TODO app.

Functional requirements:
1. add <text> appends an undone task and prints the created task with a stable id.
2. list prints every task with id and done/undone marker; an empty list prints a friendly no-tasks message.
3. done <id> marks a task complete; unknown ids print a clear error and exit non-zero.
4. delete <id> removes a task; unknown ids print a clear error and exit non-zero.
5. State persists to a local file and survives fresh process runs. Missing or empty state is an empty list.
6. No arguments or help prints usage.

Acceptance criteria:
- Adding two tasks then listing shows both with distinct ids.
- done persists completion for one task while the other stays undone.
- delete removes only the requested task.
- A fresh list process after edits reflects persisted state.
- Unknown id for done/delete exits non-zero with a clear message, not a stack trace.
- First-ever run with no state file does not crash.
- Do not add features outside this CLI scope.
''';
}

Future<void> _waitForGoalTerminalOrIdle(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 28),
}) async {
  final deadline = DateTime.now().add(timeout);
  var stableIdleChecks = 0;
  var lastAssistantCount = -1;
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(chatNotifierProvider);
    final conversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (state.error?.trim().isNotEmpty ?? false) {
      throw StateError(
        'Chat state entered an error during TODO auto-continue canary.\n'
        '${_diagnostic(container, null, null, null)}',
      );
    }
    final goal = conversation?.goal;
    final assistantCount = state.messages
        .where((message) => message.role == MessageRole.assistant)
        .length;
    final terminalEnough =
        goal?.status == ConversationGoalStatus.completed ||
        goal?.status == ConversationGoalStatus.blocked ||
        (goal?.turnBudgetExceeded ?? false);
    if (!state.isLoading && terminalEnough) {
      return;
    }
    if (!state.isLoading && assistantCount == lastAssistantCount) {
      stableIdleChecks += 1;
      if (stableIdleChecks >= 15 && assistantCount >= 1) {
        return;
      }
    } else {
      stableIdleChecks = 0;
      lastAssistantCount = assistantCount;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  throw TimeoutException(
    'Timed out waiting for TODO auto-continue live canary completion.\n'
    '${_diagnostic(container, null, null, null)}',
  );
}

Future<List<Map<String, dynamic>>> _readSessionLogEntries(File file) async {
  if (!file.existsSync()) {
    throw StateError('Session log file was not written: ${file.path}');
  }
  final entries = <Map<String, dynamic>>[];
  for (final line in await file.readAsLines()) {
    if (line.trim().isEmpty) {
      continue;
    }
    entries.add(jsonDecode(line) as Map<String, dynamic>);
  }
  return entries;
}

List<int> _operationIndices(
  List<Map<String, dynamic>> entries,
  String operation,
) {
  return entries
      .asMap()
      .entries
      .where((entry) => entry.value['operation'] == operation)
      .map((entry) => entry.key)
      .toList(growable: false);
}

bool _isContinuationRequest(Map<String, dynamic> entry) {
  final request = entry['request'];
  if (request is! Map) {
    return false;
  }
  final messages = request['messages'];
  if (messages is! List) {
    return false;
  }
  return messages.any((message) {
    if (message is! Map) {
      return false;
    }
    return message['role'] == 'user' &&
        (message['content'] as String? ?? '').contains(
          'Automatic goal continuation',
        );
  });
}

int? _unresolvedErrorCount(Map<String, dynamic> entry) {
  final marker = entry['goalAutoContinue'];
  if (marker is! Map) {
    return null;
  }
  final evidence = marker['evidence'];
  if (evidence is! Map) {
    return null;
  }
  final count = evidence['unresolvedErrorCount'];
  return count is num ? count.toInt() : null;
}

bool _hasStrictDecrease(List<int> counts) {
  for (var index = 1; index < counts.length; index += 1) {
    if (counts[index - 1] > counts[index]) {
      return true;
    }
  }
  return false;
}

bool _hasTerminalVerifierSuccess(List<Map<String, dynamic>> entries) {
  return entries.any((entry) => _containsTerminalVerifierSuccess(entry));
}

bool _containsTerminalVerifierSuccess(Object? value) {
  if (value is Map) {
    if (value['canary'] == 'todo_app' &&
        value['command'] == _verifyCommand &&
        value['exit_code'] == 0) {
      return true;
    }
    return value.values.any(_containsTerminalVerifierSuccess);
  }
  if (value is Iterable) {
    return value.any(_containsTerminalVerifierSuccess);
  }
  return false;
}

bool _hasOrderedTriple(
  List<int> turnExitIndices,
  List<int> autoContinueIndices,
  List<int> continuationRequestIndices,
) {
  for (final exitIndex in turnExitIndices) {
    for (final markerIndex in autoContinueIndices) {
      if (markerIndex <= exitIndex) {
        continue;
      }
      for (final requestIndex in continuationRequestIndices) {
        if (requestIndex > markerIndex) {
          return true;
        }
      }
    }
  }
  return false;
}

String _diagnostic(
  ProviderContainer container,
  _TodoAutoContinueDataSource? dataSource,
  _TodoToolService? toolService,
  _TodoFixture? fixture,
) {
  final state = container.read(chatNotifierProvider);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final messages = state.messages
      .map((message) => '${message.role.name}: ${message.content}')
      .join('\n---\n');
  return [
    'isLoading=${state.isLoading}',
    'error=${state.error}',
    'goal=${jsonEncode(conversation?.goal?.toJson())}',
    'forcedStops=${dataSource?.forcedIncompleteTurns}',
    'fixtureRoot=${fixture?.root.path ?? '(none)'}',
    'toolCalls=${toolService?.executedCalls.map((call) => call.toJson()).map(jsonEncode).join(' | ') ?? '(none)'}',
    'messages=$messages',
  ].join('\n');
}

class _TodoFixture {
  _TodoFixture({
    required this.root,
    required this.project,
    required this.deleteOnDispose,
  });

  final Directory root;
  final CodingProject project;
  final bool deleteOnDispose;

  static _TodoFixture create(String? workspaceRoot) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('todo_auto_continue_fixture_')
        : Directory(workspaceRoot);
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
    root.createSync(recursive: true);
    Directory('${root.path}/bin').createSync(recursive: true);
    Directory('${root.path}/tool').createSync(recursive: true);
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: todo_auto_continue_fixture
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
    final fixtureDocument = File('docs/coding_mvp_fixtures/todo_app.md');
    if (!fixtureDocument.existsSync()) {
      throw StateError(
        'docs/coding_mvp_fixtures/todo_app.md is required for the TODO fixture.',
      );
    }
    File(
      '${root.path}/todo_app.md',
    ).writeAsStringSync(fixtureDocument.readAsStringSync());
    File('${root.path}/tool/verify_todo_app.dart').writeAsStringSync('''
// Live canary placeholder.
//
// Do not edit this file. The Caverno test harness intercepts
// `dart run tool/verify_todo_app.dart` and runs the behavioral TODO fixture
// verifier from outside the model-edited project.
void main() {}
''');
    final now = DateTime.now();
    return _TodoFixture(
      root: root,
      project: CodingProject(
        id: 'todo-auto-continue-fixture',
        name: 'todo_auto_continue_fixture',
        rootPath: root.absolute.path,
        createdAt: now,
        updatedAt: now,
      ),
      deleteOnDispose: deleteOnDispose,
    );
  }

  void dispose() {
    if (deleteOnDispose && root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

class _TodoFixtureEnv {
  const _TodoFixtureEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
    required this.workspaceRoot,
    required this.sessionLogRoot,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;
  final String? workspaceRoot;
  final String sessionLogRoot;

  static _TodoFixtureEnv fromEnvironment() {
    return _TodoFixtureEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_TODO_MAX_TOKENS'] ?? '',
          ) ??
          2048,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_TODO_TEMPERATURE'] ?? '',
          ) ??
          0.1,
      workspaceRoot: Platform.environment['CAVERNO_CODING_GOAL_TODO_WORK_ROOT'],
      sessionLogRoot: _requiredEnv('CAVERNO_CODING_GOAL_TODO_SESSION_LOG_ROOT'),
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for TODO auto-continue validation.');
  }
  return value;
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier(this.env);

  final _TodoFixtureEnv env;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.coding,
      baseUrl: env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      temperature: env.temperature,
      maxTokens: env.maxTokens,
      mcpEnabled: true,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      enableLlmSessionLogs: true,
      demoMode: false,
    );
  }
}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());

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
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}

class _LiveCodingProjectsNotifier extends CodingProjectsNotifier {
  _LiveCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() {
    return CodingProjectsState(
      projects: [project],
      selectedProjectId: project.id,
    );
  }

  @override
  Future<bool> ensureProjectAccess(String? projectId) async {
    return projectId == project.id;
  }
}

class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _NoopNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService()
    : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) {
    return null;
  }

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    return const MemoryUpdateResult.none();
  }

  @override
  UserMemoryProfile loadProfile() {
    return UserMemoryProfile.empty();
  }
}

class _TodoAutoContinueDataSource extends ChatRemoteDataSource {
  _TodoAutoContinueDataSource(
    _TodoFixtureEnv env, {
    required this.stagedFailureTurns,
  }) : super(baseUrl: env.baseUrl, apiKey: env.apiKey);

  final int stagedFailureTurns;

  int forcedIncompleteTurns = 0;

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final forced = _forcedIncompleteResult(toolResults);
    if (forced != null) {
      return Future.value(forced);
    }
    return super.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final forced = _forcedIncompleteResult([
      ToolResultInfo(
        id: toolCallId,
        name: toolName,
        arguments: _decodeArguments(toolArguments),
        result: toolResult,
      ),
    ]);
    if (forced != null) {
      return Future.value(forced);
    }
    return super.createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final forced = _forcedIncompleteResult([
      ToolResultInfo(
        id: toolCallId,
        name: toolName,
        arguments: _decodeArguments(toolArguments),
        result: toolResult,
      ),
    ]);
    if (forced != null) {
      lastFinishReason = forced.finishReason;
      yield forced.content;
      return;
    }
    yield* super.streamWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  ChatCompletionResult? _forcedIncompleteResult(
    List<ToolResultInfo> toolResults,
  ) {
    if (forcedIncompleteTurns >= stagedFailureTurns) {
      return null;
    }
    final failedTodoResult = toolResults
        .map((result) => _tryDecodeObject(result.result))
        .where((decoded) => decoded['canary'] == 'todo_app')
        .where((decoded) => decoded['exit_code'] != 0)
        .where((decoded) => decoded['diagnostics'] is List)
        .firstOrNull;
    if (failedTodoResult == null) {
      return null;
    }
    forcedIncompleteTurns += 1;
    final diagnostics = (failedTodoResult['diagnostics'] as List).length;
    lastFinishReason = 'stop';
    return ChatCompletionResult(
      content:
          'TASK NOT COMPLETE: $diagnostics unresolved Error diagnostics remain '
          'for the TODO app fixture. Continue from the concrete verifier '
          'diagnostics in the next turn.',
      finishReason: 'stop',
      usage: TokenUsage.zero,
    );
  }
}

Map<String, dynamic> _decodeArguments(String value) {
  return _tryDecodeObject(value);
}

class _TodoToolCall {
  const _TodoToolCall({
    required this.name,
    required this.arguments,
    required this.result,
    required this.success,
  });

  final String name;
  final Map<String, dynamic> arguments;
  final String result;
  final bool success;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'arguments': arguments,
      'success': success,
      'result': result,
    };
  }
}

class _TodoToolService extends McpToolService {
  _TodoToolService(this.root, {required this.stagedFailureTurns});

  final Directory root;
  final int stagedFailureTurns;
  final List<_TodoToolCall> executedCalls = [];
  int verificationAttempts = 0;

  bool get hasSuccessfulVerifierCall {
    return executedCalls.any((call) {
      if (call.name != 'local_execute_command') {
        return false;
      }
      final decoded = _tryDecodeObject(call.result);
      return decoded['canary'] == 'todo_app' && decoded['exit_code'] == 0;
    });
  }

  List<_TodoToolCall> get postSuccessMutationAttempts {
    return executedCalls
        .where((call) {
          return _tryDecodeObject(call.result)['code'] ==
              _postSuccessMutationCode;
        })
        .toList(growable: false);
  }

  Future<_TodoVerification> verifyTodoApp() => _verifyTodoApp();

  Directory createVerificationRoot() => _createVerificationRoot();

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return [
      _toolDefinition(
        name: 'list_directory',
        description: 'List files in the TODO fixture project.',
        properties: {
          'path': {'type': 'string'},
          'recursive': {'type': 'boolean'},
          'max_entries': {'type': 'integer'},
          'reason': {'type': 'string'},
        },
      ),
      _toolDefinition(
        name: 'read_file',
        description: 'Read a UTF-8 text file in the TODO fixture project.',
        properties: {
          'path': {'type': 'string'},
          'offset': {'type': 'integer'},
          'limit': {'type': 'integer'},
          'reason': {'type': 'string'},
        },
        required: const ['path'],
      ),
      _toolDefinition(
        name: 'write_file',
        description:
            'Write a full UTF-8 text file in the TODO fixture project.',
        properties: {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
          'create_parents': {'type': 'boolean'},
          'reason': {'type': 'string'},
        },
        required: const ['path', 'content'],
      ),
      _toolDefinition(
        name: 'edit_file',
        description:
            'Replace exact text in an existing TODO fixture project file.',
        properties: {
          'path': {'type': 'string'},
          'old_text': {'type': 'string'},
          'new_text': {'type': 'string'},
          'replace_all': {'type': 'boolean'},
          'reason': {'type': 'string'},
        },
        required: const ['path', 'old_text', 'new_text'],
      ),
      _toolDefinition(
        name: 'delete_file',
        description:
            'Delete one unnecessary file inside the TODO fixture project.',
        properties: {
          'path': {'type': 'string'},
          'reason': {'type': 'string'},
        },
        required: const ['path'],
      ),
      _toolDefinition(
        name: 'local_execute_command',
        description:
            'Run the TODO fixture verifier. Accepted command: $_verifyCommand.',
        properties: {
          'command': {'type': 'string'},
          'working_directory': {'type': 'string'},
          'reason': {'type': 'string'},
        },
        required: const ['command'],
      ),
    ];
  }

  Map<String, dynamic> _toolDefinition({
    required String name,
    required String description,
    required Map<String, dynamic> properties,
    List<String> required = const [],
  }) {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          if (required.isNotEmpty) 'required': required,
        },
      },
    };
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final result = _isMutation(name) && hasSuccessfulVerifierCall
        ? _postSuccessMutationError(name, arguments)
        : await _executeTool(name: name, arguments: arguments);
    executedCalls.add(
      _TodoToolCall(
        name: name,
        arguments: Map<String, dynamic>.from(arguments),
        result: result.result,
        success: result.isSuccess,
      ),
    );
    return result;
  }

  bool _isMutation(String name) =>
      name == 'write_file' || name == 'edit_file' || name == 'delete_file';

  McpToolResult _postSuccessMutationError(
    String name,
    Map<String, dynamic> arguments,
  ) {
    final result = jsonEncode({
      'canary': 'todo_app',
      'code': _postSuccessMutationCode,
      'error': 'post_success_mutation',
      'message':
          'The verifier already passed; further file mutations are blocked.',
      if (arguments['path'] is String) 'path': arguments['path'],
    });
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: false,
      errorMessage:
          'The verifier already passed; further file mutations are blocked.',
    );
  }

  Future<McpToolResult> _executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    switch (name) {
      case 'list_directory':
        final path = _resolveInsideRoot(
          arguments['path'] as String?,
          allowEmpty: true,
        );
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.listDirectory(
          path: path.value!,
          recursive: arguments['recursive'] as bool? ?? false,
          maxEntries: ((arguments['max_entries'] as num?)?.toInt() ?? 200)
              .clamp(1, 500),
        );
        return _toolResult(name, result);
      case 'read_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.readFile(
          path: path.value!,
          offset: ((arguments['offset'] as num?)?.toInt() ?? 1).clamp(
            1,
            1000000,
          ),
          limit: (arguments['limit'] as num?)?.toInt(),
        );
        return _toolResult(name, result);
      case 'write_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        if (_isProtectedVerifierPath(path.value!)) {
          return _toolError(
            name,
            'tool/verify_todo_app.dart is provided by the harness; edit bin/todo_cli.dart instead.',
          );
        }
        final result = await FilesystemTools.writeFile(
          path: path.value!,
          content: arguments['content'] as String? ?? '',
          createParents: arguments['create_parents'] as bool? ?? true,
        );
        return _toolResult(name, result);
      case 'edit_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        if (_isProtectedVerifierPath(path.value!)) {
          return _toolError(
            name,
            'tool/verify_todo_app.dart is provided by the harness; edit bin/todo_cli.dart instead.',
          );
        }
        final result = await FilesystemTools.editFile(
          path: path.value!,
          oldText: arguments['old_text'] as String? ?? '',
          newText: arguments['new_text'] as String? ?? '',
          replaceAll: arguments['replace_all'] as bool? ?? false,
        );
        return _toolResult(name, result);
      case 'delete_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        if (_isProtectedVerifierPath(path.value!)) {
          return _toolError(
            name,
            'tool/verify_todo_app.dart is provided by the harness and cannot be deleted.',
          );
        }
        final file = File(path.value!);
        if (!file.existsSync()) {
          return _toolError(
            name,
            'File does not exist: ${_relativePath(path.value!)}',
          );
        }
        file.deleteSync();
        return McpToolResult(
          toolName: name,
          result: jsonEncode({
            'deleted': true,
            'path': _relativePath(path.value!),
          }),
          isSuccess: true,
        );
      case 'local_execute_command':
        return _executeVerifier(name, arguments);
      default:
        return _toolError(name, 'Unsupported TODO fixture tool: $name');
    }
  }

  bool _isProtectedVerifierPath(String path) {
    return _relativePath(path) == 'tool/verify_todo_app.dart';
  }

  Future<McpToolResult> _executeVerifier(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final command = _normalizedCommand(arguments['command'] as String?);
    if (name == 'local_execute_command' && command != _verifyCommand) {
      return _toolError(
        name,
        'Unsupported command for this TODO fixture: $command',
      );
    }
    final workingDirectory = _resolveInsideRoot(
      arguments['working_directory'] as String?,
      allowEmpty: true,
      directory: true,
    );
    if (workingDirectory.error != null) {
      return _toolError(name, workingDirectory.error!);
    }
    if (workingDirectory.value != root.absolute.path) {
      return _toolError(name, 'working_directory must be the fixture root.');
    }

    verificationAttempts += 1;
    if (verificationAttempts <= stagedFailureTurns) {
      return _stagedVerifierFailure(name, verificationAttempts);
    }
    final verification = await _verifyTodoApp();
    return _verifierResult(name, verification);
  }

  String _normalizedCommand(String? command) {
    final normalized = (command ?? _verifyCommand)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized.isEmpty ? _verifyCommand : normalized;
  }

  McpToolResult _stagedVerifierFailure(String name, int attempt) {
    final diagnostics = attempt == 1
        ? [
            _diagnosticJson(
              code: 'todo_cli_persistence_unverified',
              message:
                  'Verifier has not yet observed task persistence across fresh process runs.',
            ),
            _diagnosticJson(
              code: 'todo_cli_unknown_id_unverified',
              message:
                  'Verifier has not yet observed non-zero unknown id handling.',
            ),
          ]
        : [
            _diagnosticJson(
              code: 'todo_cli_unknown_id_unverified',
              message:
                  'Verifier still needs a non-zero unknown id behavior check.',
            ),
          ];
    final payload = jsonEncode({
      'canary': 'todo_app',
      'command': _verifyCommand,
      'working_directory': root.absolute.path,
      'exit_code': 1,
      'stdout': '',
      'stderr':
          'Staged TODO verifier failure $attempt/$stagedFailureTurns for auto-continuation evidence.\n',
      'diagnostics': diagnostics,
    });
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: false,
      errorMessage: 'TODO verifier reported staged diagnostics.',
    );
  }

  Future<_TodoVerification> _verifyTodoApp() async {
    final verificationRoot = _createVerificationRoot();
    try {
      return await _verifyTodoAppIn(verificationRoot);
    } finally {
      if (verificationRoot.existsSync()) {
        verificationRoot.deleteSync(recursive: true);
      }
    }
  }

  Future<_TodoVerification> _verifyTodoAppIn(Directory verificationRoot) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final cli = File('${verificationRoot.path}/bin/todo_cli.dart');
    if (!cli.existsSync()) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_missing',
          message: 'bin/todo_cli.dart does not exist.',
        ),
      );
      return _TodoVerification(diagnostics: diagnostics, transcript: '');
    }
    final unexpectedEntrypoints = Directory('${verificationRoot.path}/bin')
        .listSync()
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              file.absolute.path != cli.absolute.path,
        )
        .toList(growable: false);
    if (unexpectedEntrypoints.isNotEmpty) {
      for (final file in unexpectedEntrypoints) {
        final relativePath = file.absolute.path
            .substring(verificationRoot.absolute.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        diagnostics.add(
          _diagnosticJson(
            code: 'todo_cli_unexpected_entrypoint',
            message:
                'Unexpected Dart entrypoint $relativePath. Keep only bin/todo_cli.dart and remove this file with delete_file.',
            relativePath: relativePath,
          ),
        );
      }
      return _TodoVerification(diagnostics: diagnostics, transcript: '');
    }

    final firstList = await _runTodoCommand(['list'], verificationRoot);
    transcript.writeln(_formatProcess('list', firstList));
    final firstListText = [
      firstList.stdout as String,
      firstList.stderr as String,
    ].join('\n').toLowerCase();
    if (firstList.exitCode != 0 ||
        firstListText.trim().isEmpty ||
        (!_containsAny(firstListText, const [
          'no task',
          'no todo',
          'empty',
          'nothing',
        ]))) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_first_list_failed',
          message:
              'First-ever list must succeed and print a friendly empty-list message.',
        ),
      );
    }

    final noArguments = await _runTodoCommand(const [], verificationRoot);
    transcript.writeln(_formatProcess('no arguments', noArguments));
    final noArgumentsText = [
      noArguments.stdout as String,
      noArguments.stderr as String,
    ].join('\n').toLowerCase();
    if (noArguments.exitCode != 0 || !_looksLikeUsage(noArgumentsText)) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_no_arguments_usage_failed',
          message: 'Running without arguments must succeed and print usage.',
        ),
      );
    }

    final help = await _runTodoCommand(const ['help'], verificationRoot);
    transcript.writeln(_formatProcess('help', help));
    final helpText = [
      help.stdout as String,
      help.stderr as String,
    ].join('\n').toLowerCase();
    if (help.exitCode != 0 || !_looksLikeUsage(helpText)) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_help_failed',
          message: 'The help command must succeed and print usage.',
        ),
      );
    }

    final addMilk = await _runTodoCommand([
      'add',
      'buy milk',
    ], verificationRoot);
    transcript.writeln(_formatProcess('add buy milk', addMilk));
    final addReport = await _runTodoCommand([
      'add',
      'write report',
    ], verificationRoot);
    transcript.writeln(_formatProcess('add write report', addReport));
    final firstId = _extractId(addMilk.stdout as String);
    final secondId = _extractId(addReport.stdout as String);
    if (addMilk.exitCode != 0 || firstId == null) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_add_first_failed',
          message: 'Adding the first task did not print a stable id.',
        ),
      );
    }
    if (addReport.exitCode != 0 || secondId == null || secondId == firstId) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_add_second_failed',
          message: 'Adding the second task did not print a distinct stable id.',
        ),
      );
    }

    final list = await _runTodoCommand(['list'], verificationRoot);
    transcript.writeln(_formatProcess('list after adds', list));
    final listOutput = (list.stdout as String).toLowerCase();
    if (list.exitCode != 0 ||
        !listOutput.contains('buy milk') ||
        !listOutput.contains('write report')) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_list_missing_tasks',
          message: 'Listing after two adds did not show both tasks.',
        ),
      );
    }

    if (firstId != null) {
      final done = await _runTodoCommand(['done', firstId], verificationRoot);
      transcript.writeln(_formatProcess('done $firstId', done));
      final afterDone = await _runTodoCommand(['list'], verificationRoot);
      transcript.writeln(_formatProcess('list after done', afterDone));
      final afterDoneOutput = (afterDone.stdout as String).toLowerCase();
      if (done.exitCode != 0 ||
          !afterDoneOutput.contains('buy milk') ||
          !_looksCompleted(afterDoneOutput, 'buy milk') ||
          !_looksUndone(afterDoneOutput, 'write report')) {
        diagnostics.add(
          _diagnosticJson(
            code: 'todo_cli_done_not_persisted',
            message:
                'Done did not persist task 1 as completed while task 2 stayed undone.',
          ),
        );
      }
    }

    final persistenceList = await _runTodoCommand(['list'], verificationRoot);
    transcript.writeln(_formatProcess('fresh list', persistenceList));
    if (persistenceList.exitCode != 0 ||
        !(persistenceList.stdout as String).toLowerCase().contains(
          'buy milk',
        )) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_persistence_failed',
          message: 'A fresh list run did not reflect prior state.',
        ),
      );
    }

    if (secondId != null) {
      final delete = await _runTodoCommand([
        'delete',
        secondId,
      ], verificationRoot);
      transcript.writeln(_formatProcess('delete $secondId', delete));
      final afterDelete = await _runTodoCommand(['list'], verificationRoot);
      transcript.writeln(_formatProcess('list after delete', afterDelete));
      final afterDeleteOutput = (afterDelete.stdout as String).toLowerCase();
      if (delete.exitCode != 0 ||
          afterDeleteOutput.contains('write report') ||
          !afterDeleteOutput.contains('buy milk')) {
        diagnostics.add(
          _diagnosticJson(
            code: 'todo_cli_delete_failed',
            message: 'Delete did not remove only the requested task.',
          ),
        );
      }
    }

    final unknown = await _runTodoCommand(['done', '999999'], verificationRoot);
    transcript.writeln(_formatProcess('done unknown', unknown));
    final unknownText = [
      unknown.stdout as String,
      unknown.stderr as String,
    ].join('\n').toLowerCase();
    if (unknown.exitCode == 0 ||
        unknownText.trim().isEmpty ||
        _looksLikeStackTrace(unknownText)) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_unknown_id_failed',
          message:
              'Unknown id did not produce a clear message and non-zero exit code.',
        ),
      );
    }

    final unknownDelete = await _runTodoCommand([
      'delete',
      '999999',
    ], verificationRoot);
    transcript.writeln(_formatProcess('delete unknown', unknownDelete));
    final unknownDeleteText = [
      unknownDelete.stdout as String,
      unknownDelete.stderr as String,
    ].join('\n').toLowerCase();
    if (unknownDelete.exitCode == 0 ||
        unknownDeleteText.trim().isEmpty ||
        _looksLikeStackTrace(unknownDeleteText)) {
      diagnostics.add(
        _diagnosticJson(
          code: 'todo_cli_unknown_delete_failed',
          message:
              'Unknown delete id did not produce a clear message and non-zero exit code.',
        ),
      );
    }

    return _TodoVerification(
      diagnostics: diagnostics,
      transcript: transcript.toString(),
    );
  }

  Future<ProcessResult> _runTodoCommand(
    List<String> args,
    Directory verificationRoot,
  ) {
    final usePub = File('${verificationRoot.path}/pubspec.yaml').existsSync();
    final processArgs = usePub
        ? ['run', 'bin/todo_cli.dart', ...args]
        : ['bin/todo_cli.dart', ...args];
    return Process.run(
      'dart',
      processArgs,
      workingDirectory: verificationRoot.path,
    ).timeout(const Duration(seconds: 20));
  }

  Directory _createVerificationRoot() {
    final verificationRoot = Directory.systemTemp.createTempSync(
      'todo_mvp_verification_',
    );
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relativePath = _relativePath(entity.path);
      if (relativePath == null ||
          relativePath == 'tool/verify_todo_app.dart' ||
          (relativePath != 'pubspec.yaml' && !relativePath.endsWith('.dart'))) {
        continue;
      }
      final target = File('${verificationRoot.path}/$relativePath');
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(entity.readAsBytesSync());
    }
    return verificationRoot;
  }

  String? _extractId(String output) {
    final match = RegExp(r'\b([0-9]{1,9})\b').firstMatch(output);
    return match?.group(1);
  }

  bool _looksCompleted(String listOutput, String taskText) {
    final line = _lineContaining(listOutput, taskText);
    if (line == null) {
      return false;
    }
    return line.contains('[x]') ||
        line.contains('done') ||
        line.contains('complete') ||
        line.contains('✓');
  }

  bool _looksUndone(String listOutput, String taskText) {
    final line = _lineContaining(listOutput, taskText);
    if (line == null) {
      return false;
    }
    return line.contains('[ ]') ||
        line.contains('todo') ||
        line.contains('undone') ||
        (!line.contains('[x]') &&
            !line.contains('done') &&
            !line.contains('complete') &&
            !line.contains('✓'));
  }

  bool _looksLikeUsage(String output) {
    return output.contains('usage') ||
        (_containsAny(output, const ['add', 'list']) &&
            _containsAny(output, const ['done', 'delete']));
  }

  bool _looksLikeStackTrace(String output) {
    return output.contains('stack trace') ||
        output.contains('unhandled exception') ||
        output.contains('#0 ');
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  String? _lineContaining(String text, String needle) {
    for (final line in const LineSplitter().convert(text)) {
      if (line.toLowerCase().contains(needle)) {
        return line.toLowerCase();
      }
    }
    return null;
  }

  String _formatProcess(String label, ProcessResult result) {
    return [
      '== $label ==',
      'exit=${result.exitCode}',
      'stdout=${result.stdout}',
      'stderr=${result.stderr}',
    ].join('\n');
  }

  McpToolResult _verifierResult(String name, _TodoVerification verification) {
    final exitCode = verification.diagnostics.isEmpty ? 0 : 1;
    final payload = jsonEncode({
      'canary': 'todo_app',
      'command': _verifyCommand,
      'working_directory': root.absolute.path,
      'exit_code': exitCode,
      'stdout': verification.transcript,
      'stderr': exitCode == 0
          ? ''
          : 'TODO fixture acceptance criteria failed.\n',
      'diagnostics': verification.diagnostics,
      if (exitCode == 0) ...{
        'terminal_success': true,
        'terminal_message':
            'The TODO app verifier passed. The requested work is complete.',
      },
    });
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: exitCode == 0,
      errorMessage: exitCode == 0
          ? null
          : 'TODO verifier found ${verification.diagnostics.length} issue(s).',
    );
  }

  Map<String, dynamic> _diagnosticJson({
    required String code,
    required String message,
    String relativePath = 'bin/todo_cli.dart',
  }) {
    final path = File('${root.path}/$relativePath').absolute.path;
    return {
      'severity': 'Error',
      'path': path,
      'relative_path': relativePath,
      'line': 1,
      'column': 1,
      'code': code,
      'message': message,
    };
  }

  _ResolvedPath _resolveInsideRoot(
    String? rawPath, {
    bool allowEmpty = false,
    bool directory = false,
  }) {
    final trimmed = rawPath?.trim();
    final effectivePath = (trimmed == null || trimmed.isEmpty) && allowEmpty
        ? '.'
        : trimmed;
    final resolved = FilesystemTools.resolvePath(
      effectivePath,
      defaultRoot: root.absolute.path,
    );
    if (resolved == null || resolved.trim().isEmpty) {
      return const _ResolvedPath(error: 'path is required');
    }

    final rootPath = root.absolute.path;
    final targetPath = directory
        ? Directory(resolved).absolute.path
        : File(resolved).absolute.path;
    if (targetPath != rootPath &&
        !targetPath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return const _ResolvedPath(
        error: 'Path must stay inside the TODO fixture root.',
      );
    }
    return _ResolvedPath(value: targetPath);
  }

  String? _relativePath(String absolutePath) {
    final rootPath = root.absolute.path;
    final targetPath = File(absolutePath).absolute.path;
    if (targetPath == rootPath) {
      return '.';
    }
    if (!targetPath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return null;
    }
    return targetPath
        .substring(rootPath.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
  }

  McpToolResult _toolResult(String name, String result) {
    final decoded = _tryDecodeObject(result);
    final error = decoded['error'] as String?;
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: error == null || error.isEmpty,
      errorMessage: error,
    );
  }

  McpToolResult _toolError(String name, String error) {
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': error}),
      isSuccess: false,
      errorMessage: error,
    );
  }
}

class _WordFrequencyToolService extends _TodoToolService {
  _WordFrequencyToolService(super.root) : super(stagedFailureTurns: 0);

  @override
  bool get hasSuccessfulVerifierCall => executedCalls.any((call) {
    final result = _tryDecodeObject(call.result);
    return call.name == 'local_execute_command' &&
        result['canary'] == 'word_frequency_cli' &&
        result['exit_code'] == 0;
  });

  Future<_TodoVerification> verifyWordFrequency() => _verifyTodoApp();

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    final definitions = super.getOpenAiToolDefinitions();
    for (final definition in definitions) {
      final function = definition['function'] as Map<String, dynamic>;
      if (function['name'] == 'local_execute_command') {
        function['description'] =
            'Run the word-frequency fixture verifier. Accepted command: '
            '$_wordFrequencyVerifyCommand.';
      }
    }
    return definitions;
  }

  @override
  bool _isProtectedVerifierPath(String path) {
    return _relativePath(path) == 'tool/verify_word_frequency_cli.dart';
  }

  @override
  Future<McpToolResult> _executeVerifier(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final command = (arguments['command'] as String? ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (command != _wordFrequencyVerifyCommand) {
      return _toolError(
        name,
        'Unsupported command for this word-frequency fixture: $command',
      );
    }
    final workingDirectory = _resolveInsideRoot(
      arguments['working_directory'] as String?,
      allowEmpty: true,
      directory: true,
    );
    if (workingDirectory.error != null) {
      return _toolError(name, workingDirectory.error!);
    }
    if (workingDirectory.value != root.absolute.path) {
      return _toolError(name, 'working_directory must be the fixture root.');
    }
    verificationAttempts += 1;
    return _verifierResult(name, await _verifyTodoApp());
  }

  @override
  Future<_TodoVerification> _verifyTodoApp() async {
    final verificationRoot = _createVerificationRoot();
    try {
      return await _verifyWordFrequencyIn(verificationRoot);
    } finally {
      verificationRoot.deleteSync(recursive: true);
    }
  }

  @override
  Directory _createVerificationRoot() {
    final verificationRoot = Directory.systemTemp.createTempSync(
      'word_frequency_mvp_verification_',
    );
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = _relativePath(entity.path);
      if (relativePath == null ||
          relativePath == 'tool/verify_word_frequency_cli.dart' ||
          (relativePath != 'pubspec.yaml' && !relativePath.endsWith('.dart'))) {
        continue;
      }
      final target = File('${verificationRoot.path}/$relativePath');
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(entity.readAsBytesSync());
    }
    return verificationRoot;
  }

  Future<_TodoVerification> _verifyWordFrequencyIn(Directory work) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final cli = File('${work.path}/bin/word_frequency.dart');
    if (!cli.existsSync()) {
      diagnostics.add(
        _diagnosticJson(
          code: 'word_frequency_cli_missing',
          message: 'bin/word_frequency.dart does not exist.',
        ),
      );
      return _TodoVerification(diagnostics: diagnostics, transcript: '');
    }
    final unexpected = Directory('${work.path}/bin')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart') && file.path != cli.path);
    for (final file in unexpected) {
      diagnostics.add(
        _diagnosticJson(
          code: 'word_frequency_unexpected_entrypoint',
          message: 'Remove unexpected entrypoint ${file.path}.',
        ),
      );
    }

    File(
      '${work.path}/sample.txt',
    ).writeAsStringSync('The cat sat on THE mat. The cat.\n');
    final full = await _runWordCommand(['sample.txt'], work);
    transcript.writeln(_formatProcess('default top 10', full));
    const expected = ['the 3', 'cat 2', 'mat 1', 'on 1', 'sat 1'];
    final rows = const LineSplitter().convert(
      (full.stdout as String).trim().toLowerCase(),
    );
    if (full.exitCode != 0 || !_containsOrderedRows(rows, expected)) {
      diagnostics.add(
        _diagnosticJson(
          code: 'word_frequency_normalization_or_order_failed',
          message:
              'Counts must be case-insensitive, punctuation-stripped, and ties alphabetical.',
        ),
      );
    }

    final topTwo = await _runWordCommandWithTopN(
      'sample.txt',
      2,
      expectedRows: 2,
      work: work,
    );
    transcript.writeln(_formatProcess('top 2', topTwo));
    final topRows = const LineSplitter().convert(
      (topTwo.stdout as String).trim().toLowerCase(),
    );
    if (topTwo.exitCode != 0 ||
        topRows.length != 2 ||
        !_containsOrderedRows(topRows, expected.take(2).toList())) {
      diagnostics.add(
        _diagnosticJson(
          code: 'word_frequency_top_n_failed',
          message: 'Top 2 must return exactly the two most frequent words.',
        ),
      );
    }

    final oversized = await _runWordCommandWithTopN(
      'sample.txt',
      100,
      expectedRows: 5,
      work: work,
    );
    transcript.writeln(_formatProcess('top 100', oversized));
    if (oversized.exitCode != 0 ||
        const LineSplitter()
                .convert((oversized.stdout as String).trim())
                .length !=
            5) {
      diagnostics.add(
        _diagnosticJson(
          code: 'word_frequency_oversized_n_failed',
          message: 'N larger than the vocabulary must print all words.',
        ),
      );
    }

    File('${work.path}/empty.txt').writeAsStringSync('');
    final empty = await _runWordCommand(['empty.txt'], work);
    transcript.writeln(_formatProcess('empty input', empty));
    if (empty.exitCode != 0) {
      diagnostics.add(
        _diagnosticJson(
          code: 'word_frequency_empty_input_failed',
          message: 'Empty input must exit with code 0.',
        ),
      );
    }

    final missingArgument = await _runWordCommand(const [], work);
    transcript.writeln(_formatProcess('missing argument', missingArgument));
    if (missingArgument.exitCode == 0 ||
        '${missingArgument.stdout}${missingArgument.stderr}'.trim().isEmpty) {
      diagnostics.add(
        _diagnosticJson(
          code: 'word_frequency_missing_argument_failed',
          message:
              'Missing file argument must explain usage and exit non-zero.',
        ),
      );
    }

    final unreadable = await _runWordCommand(['missing.txt'], work);
    transcript.writeln(_formatProcess('missing file', unreadable));
    if (unreadable.exitCode == 0 ||
        '${unreadable.stdout}${unreadable.stderr}'.trim().isEmpty) {
      diagnostics.add(
        _diagnosticJson(
          code: 'word_frequency_missing_file_failed',
          message:
              'An unreadable file must explain the error and exit non-zero.',
        ),
      );
    }
    return _TodoVerification(
      diagnostics: diagnostics,
      transcript: transcript.toString(),
    );
  }

  bool _containsOrderedRows(List<String> actual, List<String> expected) {
    if (actual.length < expected.length) return false;
    for (var index = 0; index < expected.length; index += 1) {
      if (actual[index].trim() != expected[index]) return false;
    }
    return true;
  }

  Future<ProcessResult> _runWordCommand(List<String> args, Directory work) {
    return Process.run('dart', [
      'run',
      'bin/word_frequency.dart',
      ...args,
    ], workingDirectory: work.path).timeout(const Duration(seconds: 20));
  }

  Future<ProcessResult> _runWordCommandWithTopN(
    String path,
    int count, {
    required int expectedRows,
    required Directory work,
  }) async {
    final candidates = <List<String>>[
      [path, '$count'],
      [path, '--top', '$count'],
      ['--top', '$count', path],
      [path, '-n', '$count'],
      ['-n', '$count', path],
    ];
    ProcessResult? lastResult;
    for (final args in candidates) {
      final result = await _runWordCommand(args, work);
      lastResult = result;
      final rows = const LineSplitter().convert(
        (result.stdout as String).trim(),
      );
      if (result.exitCode == 0 && rows.length == expectedRows) return result;
    }
    return lastResult!;
  }

  @override
  McpToolResult _verifierResult(String name, _TodoVerification verification) {
    final exitCode = verification.diagnostics.isEmpty ? 0 : 1;
    final payload = jsonEncode({
      'canary': 'word_frequency_cli',
      'command': _wordFrequencyVerifyCommand,
      'working_directory': root.absolute.path,
      'exit_code': exitCode,
      'stdout': verification.transcript,
      'stderr': exitCode == 0
          ? ''
          : 'Word-frequency acceptance criteria failed.\n',
      'diagnostics': verification.diagnostics,
      if (exitCode == 0) ...{
        'terminal_success': true,
        'terminal_message':
            'The word-frequency verifier passed. The requested work is complete.',
      },
    });
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: exitCode == 0,
      errorMessage: exitCode == 0 ? null : 'Word-frequency verifier failed.',
    );
  }

  @override
  Map<String, dynamic> _diagnosticJson({
    required String code,
    required String message,
    String relativePath = 'bin/word_frequency.dart',
  }) {
    return super._diagnosticJson(
      code: code,
      message: message,
      relativePath: relativePath,
    );
  }
}

class _MarkdownTocToolService extends _TodoToolService {
  _MarkdownTocToolService(super.root) : super(stagedFailureTurns: 0);

  @override
  bool get hasSuccessfulVerifierCall => executedCalls.any((call) {
    final result = _tryDecodeObject(call.result);
    return call.name == 'local_execute_command' &&
        result['canary'] == 'markdown_toc' &&
        result['exit_code'] == 0;
  });

  Future<_TodoVerification> verifyMarkdownToc() => _verifyTodoApp();

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    final definitions = super.getOpenAiToolDefinitions();
    for (final definition in definitions) {
      final function = definition['function'] as Map<String, dynamic>;
      if (function['name'] == 'local_execute_command') {
        function['description'] =
            'Run the Markdown TOC fixture verifier. Accepted command: '
            '$_markdownTocVerifyCommand.';
      }
    }
    return definitions;
  }

  @override
  bool _isProtectedVerifierPath(String path) {
    return _relativePath(path) == 'tool/verify_markdown_toc.dart';
  }

  @override
  Future<McpToolResult> _executeVerifier(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final command = (arguments['command'] as String? ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (command != _markdownTocVerifyCommand) {
      return _toolError(
        name,
        'Unsupported command for this Markdown TOC fixture: $command',
      );
    }
    final workingDirectory = _resolveInsideRoot(
      arguments['working_directory'] as String?,
      allowEmpty: true,
      directory: true,
    );
    if (workingDirectory.error != null) {
      return _toolError(name, workingDirectory.error!);
    }
    if (workingDirectory.value != root.absolute.path) {
      return _toolError(name, 'working_directory must be the fixture root.');
    }
    verificationAttempts += 1;
    return _verifierResult(name, await _verifyTodoApp());
  }

  @override
  Future<_TodoVerification> _verifyTodoApp() async {
    final verificationRoot = _createVerificationRoot();
    try {
      return await _verifyMarkdownTocIn(verificationRoot);
    } finally {
      verificationRoot.deleteSync(recursive: true);
    }
  }

  @override
  Directory _createVerificationRoot() {
    final verificationRoot = Directory.systemTemp.createTempSync(
      'markdown_toc_mvp_verification_',
    );
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = _relativePath(entity.path);
      if (relativePath == null ||
          relativePath == 'tool/verify_markdown_toc.dart' ||
          (relativePath != 'pubspec.yaml' && !relativePath.endsWith('.dart'))) {
        continue;
      }
      final target = File('${verificationRoot.path}/$relativePath');
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(entity.readAsBytesSync());
    }
    return verificationRoot;
  }

  Future<_TodoVerification> _verifyMarkdownTocIn(Directory work) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final cli = File('${work.path}/bin/markdown_toc.dart');
    if (!cli.existsSync()) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_cli_missing',
          message: 'bin/markdown_toc.dart does not exist.',
        ),
      );
      return _TodoVerification(diagnostics: diagnostics, transcript: '');
    }
    final unexpected = Directory('${work.path}/bin')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart') && file.path != cli.path);
    for (final file in unexpected) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_unexpected_entrypoint',
          message: 'Remove unexpected entrypoint ${file.path}.',
        ),
      );
    }

    File('${work.path}/sample.md').writeAsStringSync(r'''
## API Reference!
### Setup
```dart
# hidden backtick heading
```
~~~text
## hidden tilde heading
~~~
### Notes
### Notes
#### Detail
####### Seven hashes
''');
    final sample = await _runMarkdownTocCommand(['sample.md'], work);
    transcript.writeln(_formatProcess('combined Markdown traps', sample));
    const expected = <String>[
      '- [API Reference!](#api-reference)',
      '  - [Setup](#setup)',
      '  - [Notes](#notes)',
      '  - [Notes](#notes-1)',
      '    - [Detail](#detail)',
    ];
    final actual = const LineSplitter().convert(
      (sample.stdout as String).trim(),
    );
    if (sample.exitCode != 0) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_execution_failed',
          message:
              'Generating a TOC from a readable Markdown file must exit 0.',
        ),
      );
    }
    if (actual.length < 2 ||
        actual[0] != expected[0] ||
        actual[1] != expected[1]) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_heading_or_slug_failed',
          message:
              'Preserve heading labels, use the shallowest heading as indent 0, '
              'and normalize punctuation only in the slug.',
        ),
      );
    }
    final emittedNotes = actual.any((line) => line.contains('[Notes]'));
    if (!emittedNotes) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_fence_close_failed',
          message:
              'Headings after closed backtick and tilde fences were missing. '
              'Track the opening marker and recognize its matching closing fence.',
        ),
      );
    } else {
      if (!actual.contains('  - [Notes](#notes)') ||
          !actual.contains('  - [Notes](#notes-1)')) {
        diagnostics.add(
          _diagnosticJson(
            code: 'markdown_toc_duplicate_slug_failed',
            message: 'Duplicate heading slugs must use -1, -2 suffixes.',
          ),
        );
      }
      if (!actual.contains('    - [Detail](#detail)')) {
        diagnostics.add(
          _diagnosticJson(
            code: 'markdown_toc_nesting_failed',
            message: 'Each heading level below the shallowest adds two spaces.',
          ),
        );
      }
    }
    if (actual.any((line) => line.contains('hidden'))) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_fenced_heading_leaked',
          message: 'Headings inside backtick or tilde fences must be ignored.',
        ),
      );
    }
    if (actual.any((line) => line.contains('Seven hashes'))) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_seven_hash_heading_failed',
          message:
              'Seven or more leading hash characters are not ATX headings.',
        ),
      );
    }
    if (actual.length != expected.length) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_row_count_failed',
          message:
              'The combined fixture must emit exactly five TOC rows and no extras.',
        ),
      );
    } else if (expected.every(actual.contains) &&
        !_sameRows(actual, expected)) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_sequence_failed',
          message: 'TOC rows must preserve the source heading order.',
        ),
      );
    }

    File(
      '${work.path}/plain.md',
    ).writeAsStringSync('Paragraph only.\n```\n# code only\n```\n');
    final empty = await _runMarkdownTocCommand(['plain.md'], work);
    transcript.writeln(_formatProcess('no headings', empty));
    if (empty.exitCode != 0 || (empty.stdout as String).trim().isNotEmpty) {
      diagnostics.add(
        _diagnosticJson(
          code: 'markdown_toc_empty_document_failed',
          message: 'A document without headings must print nothing and exit 0.',
        ),
      );
    }

    return _TodoVerification(
      diagnostics: diagnostics,
      transcript: transcript.toString(),
    );
  }

  bool _sameRows(List<String> actual, List<String> expected) {
    for (var index = 0; index < expected.length; index += 1) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  Future<ProcessResult> _runMarkdownTocCommand(
    List<String> args,
    Directory work,
  ) {
    return Process.run('dart', [
      'run',
      'bin/markdown_toc.dart',
      ...args,
    ], workingDirectory: work.path).timeout(const Duration(seconds: 20));
  }

  @override
  McpToolResult _verifierResult(String name, _TodoVerification verification) {
    final exitCode = verification.diagnostics.isEmpty ? 0 : 1;
    final payload = jsonEncode({
      'canary': 'markdown_toc',
      'command': _markdownTocVerifyCommand,
      'working_directory': root.absolute.path,
      'exit_code': exitCode,
      'stdout': verification.transcript,
      'stderr': exitCode == 0
          ? ''
          : 'Markdown TOC acceptance criteria failed.\n',
      'diagnostics': verification.diagnostics,
      if (exitCode == 0) ...{
        'terminal_success': true,
        'terminal_message':
            'The Markdown TOC verifier passed. The requested work is complete.',
      },
    });
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: exitCode == 0,
      errorMessage: exitCode == 0 ? null : 'Markdown TOC verifier failed.',
    );
  }

  @override
  Map<String, dynamic> _diagnosticJson({
    required String code,
    required String message,
    String relativePath = 'bin/markdown_toc.dart',
  }) {
    return super._diagnosticJson(
      code: code,
      message: message,
      relativePath: relativePath,
    );
  }
}

class _TodoVerification {
  const _TodoVerification({
    required this.diagnostics,
    required this.transcript,
  });

  final List<Map<String, dynamic>> diagnostics;
  final String transcript;
}

class _ResolvedPath {
  const _ResolvedPath({this.value, this.error});

  final String? value;
  final String? error;
}

Map<String, dynamic> _tryDecodeObject(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

class _MockConversationBox extends Mock implements Box<String> {}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}
