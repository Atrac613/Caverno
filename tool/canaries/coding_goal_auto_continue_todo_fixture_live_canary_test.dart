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
import 'package:caverno/features/chat/domain/services/coding_diagnostic_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

import 'support/dart_cli_entrypoint_resolver.dart';

const _verifyCommand = 'dart run tool/verify_todo_app.dart';
const _wordFrequencyVerifyCommand =
    'dart run tool/verify_word_frequency_cli.dart';
const _markdownTocVerifyCommand = 'dart run tool/verify_markdown_toc.dart';
const _expenseTrackerVerifyCommand =
    'dart run tool/verify_expense_tracker.dart';
const _wordFrequencyFixtureSpec = _MvpFixtureSpec(
  canaryId: 'word_frequency_cli',
  documentName: 'word_frequency_cli.md',
  entrypoint: 'bin/word_frequency.dart',
  verifierCommand: _wordFrequencyVerifyCommand,
  verifierPath: 'tool/verify_word_frequency_cli.dart',
  verificationRootPrefix: 'word_frequency_mvp_verification_',
  displayName: 'word-frequency',
  failureStderr: 'Word-frequency acceptance criteria failed.\n',
  terminalMessage:
      'The word-frequency verifier passed. The requested work is complete.',
  toolFailureMessage: 'Word-frequency verifier failed.',
);
const _expenseTrackerFixtureSpec = _MvpFixtureSpec(
  canaryId: 'expense_tracker',
  documentName: 'expense_tracker.md',
  entrypoint: 'bin/expense_tracker.dart',
  verifierCommand: _expenseTrackerVerifyCommand,
  verifierPath: 'tool/verify_expense_tracker.dart',
  verificationRootPrefix: 'expense_tracker_mvp_verification_',
  displayName: 'Expense tracker',
  failureStderr: 'Expense tracker acceptance criteria failed.\n',
  terminalMessage:
      'The Expense tracker verifier passed. The requested work is complete.',
  toolFailureMessage: 'Expense tracker verifier failed.',
);
const _markdownTocFixtureSpec = _MvpFixtureSpec(
  canaryId: 'markdown_toc',
  documentName: 'markdown_toc_generator.md',
  entrypoint: 'bin/markdown_toc.dart',
  verifierCommand: _markdownTocVerifyCommand,
  verifierPath: 'tool/verify_markdown_toc.dart',
  verificationRootPrefix: 'markdown_toc_mvp_verification_',
  displayName: 'Markdown TOC',
  failureStderr: 'Markdown TOC acceptance criteria failed.\n',
  terminalMessage:
      'The Markdown TOC verifier passed. The requested work is complete.',
  toolFailureMessage: 'Markdown TOC verifier failed.',
);
const _stagedFailureTurns = 2;
const _stableDiagnosticFailureTurns = 2;
const _postSuccessMutationCode = 'todo_post_success_mutation';
const _todoTerminalMessage =
    'The TODO app verifier passed. The requested work is complete.';

String _exactShortMvpPrompt(String documentName) =>
    '$documentName を参考にしてMVPを実装。言語はdartとする。';

void main() {
  final originalHttpOverrides = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = originalHttpOverrides;
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
  final markdownTocExactShortEnabled =
      Platform
          .environment['CAVERNO_CODING_MARKDOWN_TOC_EXACT_SHORT_LIVE_CANARY'] ==
      '1';
  final expenseTrackerEnabled =
      Platform.environment['CAVERNO_CODING_EXPENSE_TRACKER_LIVE_CANARY'] == '1';
  final stalledDiagnosticRepairEnabled =
      Platform
          .environment['CAVERNO_CODING_STALLED_DIAGNOSTIC_REPAIR_LIVE_CANARY'] ==
      '1';
  final pendingActionLengthRecoveryEnabled =
      Platform
          .environment['CAVERNO_CODING_PENDING_ACTION_LENGTH_RECOVERY_LIVE_CANARY'] ==
      '1';

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

  test('MVP trace detects an unchanged path-backed verifier replay', () {
    final verifierFailure = _fixtureVerifierCall(
      command: _verifyCommand,
      diagnostics: const [
        {
          'relative_path': 'bin/todo_cli.dart',
          'code': 'todo_cli_missing',
          'message': 'The entrypoint is missing.',
        },
      ],
    );

    final replays = _unchangedPathBackedVerifierReplays([
      verifierFailure,
      const _TodoToolCall(
        name: 'read_file',
        arguments: {'path': 'bin/todo_cli.dart'},
        result: '{"content":""}',
        success: true,
      ),
      verifierFailure,
    ]);

    expect(replays, hasLength(1));
  });

  test('MVP trace allows the verifier after a mutation attempt', () {
    final verifierFailure = _fixtureVerifierCall(
      command: _verifyCommand,
      diagnostics: const [
        {
          'relative_path': 'bin/todo_cli.dart',
          'code': 'todo_cli_missing',
          'message': 'The entrypoint is missing.',
        },
      ],
    );

    final replays = _unchangedPathBackedVerifierReplays([
      verifierFailure,
      const _TodoToolCall(
        name: 'edit_file',
        arguments: {'path': 'bin/todo_cli.dart'},
        result: '{"error":"old_text was not found"}',
        success: false,
      ),
      verifierFailure,
    ]);

    expect(replays, isEmpty);
  });

  test('MVP trace ignores repeated pathless verifier diagnostics', () {
    final verifierFailure = _fixtureVerifierCall(
      command: _verifyCommand,
      diagnostics: const [
        {
          'code': 'dependency_error',
          'message': 'Resolve the missing dependency.',
        },
      ],
    );

    expect(
      _unchangedPathBackedVerifierReplays([verifierFailure, verifierFailure]),
      isEmpty,
    );
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

  test('TODO commands isolate runtime state from the host profile', () async {
    final root = Directory.systemTemp.createTempSync('todo_runtime_isolation_');
    final hostHome =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    expect(hostHome, isNotNull);
    final probeName =
        '.caverno_fixture_home_probe_${DateTime.now().microsecondsSinceEpoch}_$pid';
    final hostProbe = File('$hostHome/$probeName');
    try {
      Directory('${root.path}/bin').createSync(recursive: true);
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
      File('${root.path}/bin/todo_cli.dart').writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  const keys = [
    'HOME',
    'USERPROFILE',
    'XDG_DATA_HOME',
    'XDG_STATE_HOME',
    'XDG_CONFIG_HOME',
    'APPDATA',
    'LOCALAPPDATA',
    'TMPDIR',
    'TMP',
    'TEMP',
  ];
  final home = Platform.environment['HOME'];
  if (home == null || args.length != 1) {
    exitCode = 64;
    return;
  }
  File('$home/${args.single}').writeAsStringSync('isolated');
  stdout.write(jsonEncode({
    for (final key in keys) key: Platform.environment[key],
  }));
}
''');
      final service = _TodoToolService(root, stagedFailureTurns: 0);

      final result = await service._runTodoCommand([probeName], root);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final isolatedHome = Directory('${root.path}/.runtime_home');
      final environment = Map<String, dynamic>.from(
        jsonDecode(result.stdout as String) as Map,
      );
      expect(environment['HOME'], isolatedHome.path);
      expect(environment['USERPROFILE'], isolatedHome.path);
      expect(environment['XDG_DATA_HOME'], '${isolatedHome.path}/.local/share');
      expect(
        environment['XDG_STATE_HOME'],
        '${isolatedHome.path}/.local/state',
      );
      expect(environment['XDG_CONFIG_HOME'], '${isolatedHome.path}/.config');
      expect(environment['APPDATA'], '${isolatedHome.path}/AppData/Roaming');
      expect(environment['LOCALAPPDATA'], '${isolatedHome.path}/AppData/Local');
      expect(environment['TMPDIR'], '${isolatedHome.path}/.tmp');
      expect(environment['TMP'], '${isolatedHome.path}/.tmp');
      expect(environment['TEMP'], '${isolatedHome.path}/.tmp');
      expect(File('${isolatedHome.path}/$probeName').existsSync(), isTrue);
      expect(hostProbe.existsSync(), isFalse);
    } finally {
      if (hostProbe.existsSync()) hostProbe.deleteSync();
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
        final diagnostic = verification.diagnostics.singleWhere(
          (item) => item['code'] == 'todo_cli_unexpected_entrypoint',
        );
        expect(diagnostic['relative_path'], 'bin/todo.dart');
        expect(diagnostic['path'], unexpected.absolute.path);
        expect(diagnostic['message'], contains('bin/todo.dart'));
        expect(diagnostic['message'], isNot(contains('_mvp_verification_')));
        final deletion = await service.executeTool(
          name: 'delete_file',
          arguments: {'path': diagnostic['relative_path']},
        );
        expect(deletion.isSuccess, isTrue);
        expect(unexpected.existsSync(), isFalse);
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test('TODO adaptive verifier executes one alternate entrypoint', () async {
    final root = Directory.systemTemp.createTempSync(
      'todo_adaptive_entrypoint_',
    );
    try {
      Directory('${root.path}/bin').createSync(recursive: true);
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
      File('${root.path}/bin/todo.dart').writeAsStringSync(r'''
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty || args.first == 'help') {
    stdout.writeln('Usage: add list done delete');
    return;
  }
  if (args.first == 'list') {
    stdout.writeln('No tasks.');
    return;
  }
  stderr.writeln('Not implemented.');
  exitCode = 1;
}
''');
      final service = _TodoToolService(
        root,
        stagedFailureTurns: 0,
        entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
      );

      final verification = await service.verifyTodoApp();
      final codes = verification.diagnostics
          .map((diagnostic) => diagnostic['code'])
          .toSet();

      expect(codes, isNot(contains('todo_cli_missing')));
      expect(codes, isNot(contains('todo_cli_unexpected_entrypoint')));
      expect(codes, isNot(contains('todo_cli_ambiguous_entrypoint')));
      expect(codes, contains('todo_cli_add_first_failed'));
      expect(
        verification.diagnostics
            .where(
              (diagnostic) => diagnostic['code'] == 'todo_cli_add_first_failed',
            )
            .single['relative_path'],
        'bin/todo.dart',
      );
      expect(verification.transcript, contains('== list =='));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('TODO adaptive verifier reports repairable ambiguity', () async {
    final root = Directory.systemTemp.createTempSync(
      'todo_ambiguous_entrypoint_',
    );
    try {
      Directory('${root.path}/bin').createSync(recursive: true);
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');
      File('${root.path}/bin/a.dart').writeAsStringSync('void main() {}\n');
      File('${root.path}/bin/b.dart').writeAsStringSync('void main() {}\n');
      final service = _TodoToolService(
        root,
        stagedFailureTurns: 0,
        entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
      );

      final verification = await service.verifyTodoApp();
      final diagnostic = verification.diagnostics.single;

      expect(diagnostic['code'], 'todo_cli_ambiguous_entrypoint');
      expect(diagnostic['relative_path'], 'bin/a.dart');
      expect(diagnostic['path'], File('${root.path}/bin/a.dart').absolute.path);
      expect(diagnostic['message'], contains('bin/a.dart, bin/b.dart'));
      expect(diagnostic['message'], isNot(contains('_mvp_verification_')));
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'Markdown adaptive diagnostics target the selected alternate entrypoint',
    () async {
      final fixture = _TodoFixture.create(null);
      try {
        _configureMarkdownTocFixture(fixture.root);
        File(
          '${fixture.root.path}/bin/generate_toc.dart',
        ).writeAsStringSync('void main() {}\n');
        final service = _MarkdownTocToolService(
          fixture.root,
          entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
        );

        final verification = await service.verifyMarkdownToc();

        expect(verification.diagnostics, isNotEmpty);
        expect(
          verification.diagnostics.map(
            (diagnostic) => diagnostic['relative_path'],
          ),
          everyElement('bin/generate_toc.dart'),
        );
        expect(
          verification.diagnostics.map((diagnostic) => diagnostic['code']),
          isNot(contains('markdown_toc_ambiguous_entrypoint')),
        );
      } finally {
        fixture.dispose();
      }
    },
  );

  test(
    'derived verifiers return repairable unexpected entrypoint paths',
    () async {
      await _expectRepairableUnexpectedEntrypoint<_WordFrequencyToolService>(
        configure: _configureWordFrequencyFixture,
        entrypoint: 'bin/word_frequency.dart',
        code: 'word_frequency_unexpected_entrypoint',
        createService: _WordFrequencyToolService.new,
        verify: (service) => service.verifyWordFrequency(),
      );
      await _expectRepairableUnexpectedEntrypoint<_ExpenseTrackerToolService>(
        configure: _configureExpenseTrackerFixture,
        entrypoint: 'bin/expense_tracker.dart',
        code: 'expense_tracker_unexpected_entrypoint',
        createService: _ExpenseTrackerToolService.new,
        verify: (service) => service.verifyExpenseTracker(),
      );
      await _expectRepairableUnexpectedEntrypoint<_MarkdownTocToolService>(
        configure: _configureMarkdownTocFixture,
        entrypoint: 'bin/markdown_toc.dart',
        code: 'markdown_toc_unexpected_entrypoint',
        createService: _MarkdownTocToolService.new,
        verify: (service) => service.verifyMarkdownToc(),
      );
    },
  );

  test(
    'word-frequency verifier accepts fixed and adaptive entrypoints',
    () async {
      final fixture = _TodoFixture.create(null);
      try {
        _configureWordFrequencyFixture(fixture.root);
        final cli = File('${fixture.root.path}/bin/word_frequency.dart')
          ..writeAsStringSync(r'''
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
''');
        final service = _WordFrequencyToolService(fixture.root);

        final verification = await service.verifyWordFrequency();

        expect(
          verification.diagnostics,
          isEmpty,
          reason: verification.transcript,
        );

        cli.renameSync('${fixture.root.path}/bin/count.dart');
        final adaptiveService = _WordFrequencyToolService(
          fixture.root,
          entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
        );
        final adaptiveVerification = await adaptiveService
            .verifyWordFrequency();

        expect(
          adaptiveVerification.diagnostics,
          isEmpty,
          reason: adaptiveVerification.transcript,
        );
      } finally {
        fixture.dispose();
      }
    },
  );

  test('Expense tracker verifier enforces canonical Dart behavior', () async {
    final fixture = _TodoFixture.create(null);
    try {
      _configureExpenseTrackerFixture(fixture.root);
      final cli = File('${fixture.root.path}/bin/expense_tracker.dart')
        ..writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

File get stateFile {
  final home = Platform.environment['HOME'] ?? '.';
  return File('$home/.expenses.json');
}

List<Map<String, dynamic>> loadExpenses() {
  if (!stateFile.existsSync()) return [];
  final decoded = jsonDecode(stateFile.readAsStringSync()) as List;
  return decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList();
}

void saveExpenses(List<Map<String, dynamic>> expenses) {
  stateFile.writeAsStringSync(jsonEncode(expenses));
}

int? parseCents(String value) {
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.parse(parts[0]);
  final fraction = parts.length == 1 ? '' : parts[1];
  final cents = whole * 100 + int.parse((fraction + '00').substring(0, 2));
  return cents > 0 ? cents : null;
}

String money(int cents) =>
    '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

String csv(String value) =>
    value.contains(RegExp(r'[,"\r\n]')) ? '"${value.replaceAll('"', '""')}"' : value;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: expense_tracker add|list|summary|export');
    exitCode = 64;
    return;
  }
  final expenses = loadExpenses();
  switch (args[0]) {
    case 'add':
      if (args.length < 4) {
        stderr.writeln('Usage: add <amount> <category> <note>');
        exitCode = 64;
        return;
      }
      final cents = parseCents(args[1]);
      if (cents == null) {
        stderr.writeln('Amount must be a positive number with up to 2 decimals.');
        exitCode = 65;
        return;
      }
      expenses.add({
        'amount_cents': cents,
        'category': args[2],
        'note': args.sublist(3).join(' '),
      });
      saveExpenses(expenses);
      stdout.writeln('Added ${money(cents)} ${args[2]}');
      break;
    case 'list':
      for (var index = 0; index < expenses.length; index++) {
        final item = expenses[index];
        stdout.writeln(
          '${index + 1} ${money(item['amount_cents'] as int)} '
          '${item['category']} ${item['note']}',
        );
      }
      break;
    case 'summary':
      final totals = <String, int>{};
      for (final item in expenses) {
        final category = item['category'] as String;
        totals[category] =
            (totals[category] ?? 0) + (item['amount_cents'] as int);
      }
      for (final category in totals.keys.toList()..sort()) {
        stdout.writeln('$category ${money(totals[category]!)}');
      }
      stdout.writeln('total ${money(totals.values.fold(0, (a, b) => a + b))}');
      break;
    case 'export':
      if (args.length != 2) {
        stderr.writeln('Usage: export <path>');
        exitCode = 64;
        return;
      }
      final output = StringBuffer('amount,category,note\n');
      for (final item in expenses) {
        output.writeln(
          '${money(item['amount_cents'] as int)},'
          '${csv(item['category'] as String)},${csv(item['note'] as String)}',
        );
      }
      File(args[1]).writeAsStringSync(output.toString());
      break;
    default:
      stderr.writeln('Unknown command: ${args[0]}');
      exitCode = 64;
  }
}
''');
      final service = _ExpenseTrackerToolService(fixture.root);

      final verification = await service.verifyExpenseTracker();

      expect(
        verification.diagnostics,
        isEmpty,
        reason: verification.transcript,
      );

      final repeatedVerification = await service.verifyExpenseTracker();

      expect(
        repeatedVerification.diagnostics,
        isEmpty,
        reason: repeatedVerification.transcript,
      );

      final canonicalSource = cli.readAsStringSync();
      cli.writeAsStringSync(
        canonicalSource
            .replaceFirst(r'\d{1,2}', r'\d{2}')
            .replaceFirst(
              'return cents > 0 ? cents : null;',
              'return cents >= 0 ? cents : null;',
            ),
      );
      final invalidAmountVerification = await service.verifyExpenseTracker();
      expect(
        invalidAmountVerification.diagnostics.map((item) => item['code']),
        containsAll(const [
          'expense_tracker_invalid_amount_accepted',
          'expense_tracker_decimal_add_failed',
        ]),
        reason: invalidAmountVerification.transcript,
      );

      cli.writeAsStringSync(
        canonicalSource.replaceFirst(
          'if (!stateFile.existsSync()) return [];',
          "if (!stateFile.existsSync()) throw StateError('missing state');",
        ),
      );
      final missingStateVerification = await service.verifyExpenseTracker();
      expect(
        missingStateVerification.diagnostics.map((item) => item['code']),
        containsAll(const [
          'expense_tracker_empty_list_failed',
          'expense_tracker_empty_summary_failed',
        ]),
        reason: missingStateVerification.transcript,
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
    () => _runTodoMvpLiveScenario(
      _exactShortMvpPrompt('todo_app.md'),
      entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
    ),
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

  test(
    'live LLM assembles the markdown_toc_generator.md MVP from the exact short prompt',
    _runMarkdownTocExactShortLiveScenario,
    skip: markdownTocExactShortEnabled
        ? false
        : 'Set CAVERNO_CODING_MARKDOWN_TOC_EXACT_SHORT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    'live LLM assembles the expense_tracker.md MVP from a short prompt',
    _runExpenseTrackerLiveScenario,
    skip: expenseTrackerEnabled
        ? false
        : 'Set CAVERNO_CODING_EXPENSE_TRACKER_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    'live LLM repairs a stable diagnostic plateau with constrained tools',
    _runStalledDiagnosticRepairLiveScenario,
    skip: stalledDiagnosticRepairEnabled
        ? false
        : 'Set CAVERNO_CODING_STALLED_DIAGNOSTIC_REPAIR_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test(
    'live LLM recovers one length-truncated pending coding action',
    _runPendingActionLengthRecoveryLiveScenario,
    skip: pendingActionLengthRecoveryEnabled
        ? false
        : 'Set CAVERNO_CODING_PENDING_ACTION_LENGTH_RECOVERY_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<void> _expectRepairableUnexpectedEntrypoint<T extends _TodoToolService>({
  required void Function(Directory root) configure,
  required String entrypoint,
  required String code,
  required T Function(Directory root) createService,
  required Future<_TodoVerification> Function(T service) verify,
}) async {
  final fixture = _TodoFixture.create(null);
  try {
    configure(fixture.root);
    File(
      '${fixture.root.path}/$entrypoint',
    ).writeAsStringSync('void main() {}');
    final unexpected = File('${fixture.root.path}/bin/unexpected.dart')
      ..writeAsStringSync('void main() {}');
    final service = createService(fixture.root);

    final verification = await verify(service);

    final diagnostic = verification.diagnostics.singleWhere(
      (item) => item['code'] == code,
    );
    expect(diagnostic['relative_path'], 'bin/unexpected.dart');
    expect(diagnostic['path'], unexpected.absolute.path);
    expect(diagnostic['message'], contains('bin/unexpected.dart'));
    expect(diagnostic['message'], isNot(contains('_mvp_verification_')));

    final deletion = await service.executeTool(
      name: 'delete_file',
      arguments: {'path': diagnostic['relative_path']},
    );
    expect(deletion.isSuccess, isTrue);
    expect(unexpected.existsSync(), isFalse);
  } finally {
    fixture.dispose();
  }
}

void _expectVerifiedGoalNotBlocked(
  ProviderContainer container,
  String diagnostic,
) {
  final goal = container
      .read(conversationsNotifierProvider)
      .currentConversation
      ?.goal;
  expect(goal, isNotNull, reason: diagnostic);
  expect(
    goal?.status,
    isNot(ConversationGoalStatus.blocked),
    reason: '$diagnostic\nA verified goal must not be marked blocked.',
  );
}

Future<void> _runExpenseTrackerLiveScenario() =>
    _runShortPromptMvpLiveScenario<_ExpenseTrackerToolService>(
      spec: _expenseTrackerFixtureSpec,
      createService: (root) => _ExpenseTrackerToolService(
        root,
        entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
      ),
      verify: (service) => service.verifyExpenseTracker(),
    );

Future<void> _runMarkdownTocLiveScenario() =>
    _runShortPromptMvpLiveScenario<_MarkdownTocToolService>(
      spec: _markdownTocFixtureSpec,
      createService: (root) => _MarkdownTocToolService(
        root,
        entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
      ),
      verify: (service) => service.verifyMarkdownToc(),
    );

Future<void> _runMarkdownTocExactShortLiveScenario() =>
    _runShortPromptMvpLiveScenario<_MarkdownTocToolService>(
      spec: _markdownTocFixtureSpec,
      createService: (root) => _MarkdownTocToolService(
        root,
        entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
      ),
      verify: (service) => service.verifyMarkdownToc(),
      prompt: _exactShortMvpPrompt(_markdownTocFixtureSpec.documentName),
    );

Future<void> _runWordFrequencyLiveScenario() =>
    _runShortPromptMvpLiveScenario<_WordFrequencyToolService>(
      spec: _wordFrequencyFixtureSpec,
      createService: (root) => _WordFrequencyToolService(
        root,
        entrypointPolicy: DartCliEntrypointPolicy.singleUnderBin,
      ),
      verify: (service) => service.verifyWordFrequency(),
    );

Future<void> _runStalledDiagnosticRepairLiveScenario() async {
  final env = _TodoFixtureEnv.fromEnvironment();
  final fixture = _TodoFixture.create(env.workspaceRoot);
  final sessionLogRoot = Directory(env.sessionLogRoot)
    ..createSync(recursive: true);
  final logStore = LlmSessionLogStore(
    rootDirectoryProvider: () async => sessionLogRoot,
  );
  final dataSource = _TodoAutoContinueDataSource(
    env,
    stagedFailureTurns: _stableDiagnosticFailureTurns,
  );
  final toolService = _TodoToolService(
    fixture.root,
    stagedFailureTurns: 0,
    stableDiagnosticFailureTurns: _stableDiagnosticFailureTurns,
  );
  final container = _buildContainer(
    env: env,
    fixture: fixture,
    dataSource: dataSource,
    toolService: toolService,
    logStore: logStore,
    disableCodingDiagnosticFeedback: true,
  );
  final prompt = _exactShortMvpPrompt('todo_app.md');

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
      turnBudget: 6,
    );

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage(prompt, bypassPlanMode: true);
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
    final diagnostic = _diagnostic(container, dataSource, toolService, fixture);
    final verifierCalls = toolService.executedCalls
        .where(_isTodoVerifierCall)
        .toList(growable: false);
    final mutations = toolService.executedCalls
        .asMap()
        .entries
        .where((entry) => toolService._isMutation(entry.value.name))
        .where((entry) => entry.value.success)
        .map((entry) => entry.key)
        .toList(growable: false);
    final repairToolRequests = entries
        .where(_containsRepairContractRequest)
        .where(_advertisesTools)
        .toList(growable: false);
    final unresolvedErrorCounts = entries
        .map(_unresolvedErrorCount)
        .whereType<int>()
        .toList(growable: false);

    expect(verifierCalls.length, greaterThanOrEqualTo(3), reason: diagnostic);
    expect(
      _diagnosticsFromCall(verifierCalls[0]),
      _diagnosticsFromCall(verifierCalls[1]),
      reason: diagnostic,
    );
    expect(
      unresolvedErrorCounts.take(2),
      orderedEquals(const [1, 1]),
      reason: diagnostic,
    );
    expect(
      entries.any(
        (entry) => _requestContainsToolResult(
          entry,
          CodingDiagnosticFeedbackService.toolName,
        ),
      ),
      isFalse,
      reason: diagnostic,
    );
    final secondFailureIndex = toolService.executedCalls.indexOf(
      verifierCalls[1],
    );
    final successIndex = toolService.executedCalls.lastIndexWhere((call) {
      return _isTodoVerifierCall(call) &&
          _tryDecodeObject(call.result)['exit_code'] == 0;
    });
    expect(
      mutations.any(
        (index) => index > secondFailureIndex && index < successIndex,
      ),
      isTrue,
      reason: diagnostic,
    );
    expect(repairToolRequests, isNotEmpty, reason: diagnostic);
    expect(
      repairToolRequests.every(_usesOnlyRepairTools),
      isTrue,
      reason: diagnostic,
    );
    expect(toolService.hasSuccessfulVerifierCall, isTrue, reason: diagnostic);
    _expectVerifiedGoalNotBlocked(container, diagnostic);
    final completedGoal = container
        .read(conversationsNotifierProvider)
        .currentConversation
        ?.goal;
    expect(
      completedGoal?.status,
      ConversationGoalStatus.completed,
      reason: '$diagnostic\nTerminal verifier success must complete the goal.',
    );
    expect(
      completedGoal?.completionSummary,
      _todoTerminalMessage,
      reason:
          '$diagnostic\nThe goal summary must use terminal evidence instead '
          'of earlier assistant narration.',
    );
    expect(
      toolService.postSuccessMutationAttempts,
      isEmpty,
      reason: diagnostic,
    );
    final independentVerification = await toolService.verifyTodoApp();
    expect(
      independentVerification.diagnostics,
      isEmpty,
      reason: '$diagnostic\n${independentVerification.transcript}',
    );
  } finally {
    container.dispose();
    fixture.dispose();
  }
}

List<dynamic> _diagnosticsFromCall(_TodoToolCall call) {
  return _tryDecodeObject(call.result)['diagnostics'] as List<dynamic>? ??
      const <dynamic>[];
}

_TodoToolCall _fixtureVerifierCall({
  required String command,
  required List<Map<String, dynamic>> diagnostics,
}) {
  return _TodoToolCall(
    name: 'local_execute_command',
    arguments: {'command': command},
    result: jsonEncode({
      'command': command,
      'exit_code': diagnostics.isEmpty ? 0 : 1,
      'diagnostics': diagnostics,
    }),
    success: diagnostics.isEmpty,
  );
}

List<_TodoToolCall> _unchangedPathBackedVerifierReplays(
  List<_TodoToolCall> calls,
) {
  final replays = <_TodoToolCall>[];
  String? activeVerifierCommand;
  var mutationAttempted = false;

  for (final call in calls) {
    if (_isFixtureMutationCall(call)) {
      mutationAttempted = true;
      continue;
    }
    final command = _fixtureVerifierCommand(call);
    if (command == null) continue;

    if (activeVerifierCommand == command && !mutationAttempted) {
      replays.add(call);
    }
    final result = _tryDecodeObject(call.result);
    if (_hasPathBackedDiagnostics(result['diagnostics']) &&
        result['exit_code'] != 0) {
      activeVerifierCommand = command;
      mutationAttempted = false;
    } else {
      activeVerifierCommand = null;
      mutationAttempted = false;
    }
  }

  return replays;
}

bool _isFixtureMutationCall(_TodoToolCall call) =>
    call.name == 'write_file' ||
    call.name == 'edit_file' ||
    call.name == 'delete_file';

String? _fixtureVerifierCommand(_TodoToolCall call) {
  if (call.name != 'local_execute_command') return null;
  final result = _tryDecodeObject(call.result);
  if (!result.containsKey('exit_code')) return null;
  final rawCommand = call.arguments['command'] ?? result['command'];
  if (rawCommand is! String || rawCommand.trim().isEmpty) return null;
  return rawCommand.replaceAll(RegExp(r'\s+'), ' ').trim();
}

bool _hasPathBackedDiagnostics(Object? rawDiagnostics) {
  if (rawDiagnostics is! List) return false;
  return rawDiagnostics.whereType<Map>().any((diagnostic) {
    final relativePath = diagnostic['relative_path'];
    final path = diagnostic['path'];
    return (relativePath is String && relativePath.trim().isNotEmpty) ||
        (path is String && path.trim().isNotEmpty);
  });
}

bool _isTodoVerifierCall(_TodoToolCall call) {
  if (call.name != 'local_execute_command') return false;
  final command = (call.arguments['command'] as String? ?? _verifyCommand)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return command == _verifyCommand;
}

bool _containsRepairContractRequest(Map<String, dynamic> entry) {
  final request = entry['request'];
  if (request is! Map) return false;
  final messages = request['messages'];
  if (messages is! List) return false;
  for (final message in messages.reversed) {
    if (message is! Map || message['role'] != 'user') continue;
    return (message['content'] as String? ?? '').contains('<repair_contract>');
  }
  return false;
}

bool _advertisesTools(Map<String, dynamic> entry) {
  final request = entry['request'];
  if (request is! Map) return false;
  final tools = request['tools'];
  return tools is List && tools.isNotEmpty;
}

bool _requestContainsToolResult(Map<String, dynamic> entry, String toolName) {
  final request = entry['request'];
  if (request is! Map) return false;
  final toolResults = request['toolResults'];
  if (toolResults is! List) return false;
  return toolResults.whereType<Map>().any(
    (result) => result['name'] == toolName,
  );
}

bool _usesOnlyRepairTools(Map<String, dynamic> entry) {
  final request = entry['request'];
  if (request is! Map) return false;
  final tools = request['tools'];
  if (tools is! List) return false;
  final names = tools
      .whereType<Map>()
      .map((tool) => tool['function'])
      .whereType<Map>()
      .map((function) => function['name'])
      .whereType<String>()
      .toSet();
  return names.isNotEmpty &&
      names.difference(const {
        'list_directory',
        'read_file',
        'write_file',
        'edit_file',
        'delete_file',
      }).isEmpty &&
      !names.contains('local_execute_command');
}

Future<void> _runShortPromptMvpLiveScenario<T extends _TodoToolService>({
  required _MvpFixtureSpec spec,
  required T Function(Directory root) createService,
  required Future<_TodoVerification> Function(T service) verify,
  String? prompt,
}) async {
  final env = _TodoFixtureEnv.fromEnvironment();
  final fixture = _TodoFixture.create(env.workspaceRoot);
  _configureMvpFixture(fixture.root, spec);
  final sessionLogRoot = Directory(env.sessionLogRoot)
    ..createSync(recursive: true);
  final dataSource = _TodoAutoContinueDataSource(env, stagedFailureTurns: 0);
  final toolService = createService(fixture.root);
  final container = _buildContainer(
    env: env,
    fixture: fixture,
    dataSource: dataSource,
    toolService: toolService,
    logStore: LlmSessionLogStore(
      rootDirectoryProvider: () async => sessionLogRoot,
    ),
  );
  final effectivePrompt =
      prompt ??
      '${spec.documentName} の要件に従って、DartでMVPを実装してください。'
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
      objective: effectivePrompt,
      enabled: true,
      autoContinue: true,
      status: ConversationGoalStatus.active,
      tokenBudget: 60000,
      turnBudget: 5,
    );

    await container
        .read(chatNotifierProvider.notifier)
        .sendMessage(effectivePrompt, bypassPlanMode: true);
    await _waitForGoalTerminalOrIdle(container);

    final verification = await verify(toolService);
    final diagnostic = _diagnostic(container, dataSource, toolService, fixture);
    final entrypointResolution = toolService._resolveDartCliEntrypoint(
      work: fixture.root,
      canonicalRelativePath: spec.entrypoint,
    );
    expect(entrypointResolution.isResolved, isTrue, reason: diagnostic);
    expect(
      File(
        '${fixture.root.path}/${entrypointResolution.selectedRelativePath}',
      ).existsSync(),
      isTrue,
      reason: diagnostic,
    );
    expect(entrypointResolution.candidates, hasLength(1), reason: diagnostic);
    expect(toolService.hasSuccessfulVerifierCall, isTrue, reason: diagnostic);
    expect(
      _unchangedPathBackedVerifierReplays(toolService.executedCalls),
      isEmpty,
      reason:
          '$diagnostic\nThe same path-backed verifier must not be dispatched '
          'again before a mutation attempt.',
    );
    _expectVerifiedGoalNotBlocked(container, diagnostic);
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

void _configureWordFrequencyFixture(Directory root) =>
    _configureMvpFixture(root, _wordFrequencyFixtureSpec);

void _configureExpenseTrackerFixture(Directory root) =>
    _configureMvpFixture(root, _expenseTrackerFixtureSpec);

void _configureMarkdownTocFixture(Directory root) =>
    _configureMvpFixture(root, _markdownTocFixtureSpec);

void _configureMvpFixture(Directory root, _MvpFixtureSpec spec) {
  File('${root.path}/todo_app.md').deleteSync();
  File('${root.path}/tool/verify_todo_app.dart').deleteSync();
  final source = File('docs/coding_mvp_fixtures/${spec.documentName}');
  if (!source.existsSync()) {
    throw StateError('${spec.documentName} fixture is required.');
  }
  File(
    '${root.path}/${spec.documentName}',
  ).writeAsStringSync(source.readAsStringSync());
  File('${root.path}/${spec.verifierPath}').writeAsStringSync('''
// Live canary placeholder. The harness intercepts this verifier command.
void main() {}
''');
}

Future<void> _runTodoMvpLiveScenario(
  String prompt, {
  DartCliEntrypointPolicy entrypointPolicy = DartCliEntrypointPolicy.fixed,
}) async {
  final env = _TodoFixtureEnv.fromEnvironment();
  final fixture = _TodoFixture.create(env.workspaceRoot);
  final sessionLogRoot = Directory(env.sessionLogRoot)
    ..createSync(recursive: true);
  final logStore = LlmSessionLogStore(
    rootDirectoryProvider: () async => sessionLogRoot,
  );
  final dataSource = _TodoAutoContinueDataSource(env, stagedFailureTurns: 0);
  final toolService = _TodoToolService(
    fixture.root,
    stagedFailureTurns: 0,
    entrypointPolicy: entrypointPolicy,
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
    final entrypointResolution = toolService._resolveDartCliEntrypoint(
      work: fixture.root,
      canonicalRelativePath: 'bin/todo_cli.dart',
    );

    expect(entrypointResolution.isResolved, isTrue, reason: diagnostic);
    expect(
      File(
        '${fixture.root.path}/${entrypointResolution.selectedRelativePath}',
      ).existsSync(),
      isTrue,
      reason: diagnostic,
    );
    expect(entrypointResolution.candidates, hasLength(1), reason: diagnostic);
    _expectVerifiedGoalNotBlocked(container, diagnostic);
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
      _unchangedPathBackedVerifierReplays(toolService.executedCalls),
      isEmpty,
      reason:
          '$diagnostic\nThe same path-backed verifier must not be dispatched '
          'again before a mutation attempt.',
    );
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

Future<void> _runPendingActionLengthRecoveryLiveScenario() async {
  final env = _TodoFixtureEnv.fromEnvironment();
  final fixture = _TodoFixture.create(env.workspaceRoot);
  final sessionLogRoot = Directory(env.sessionLogRoot)
    ..createSync(recursive: true);
  final dataSource = _TodoAutoContinueDataSource(
    env,
    stagedFailureTurns: 0,
    forcePendingActionLengthRecovery: true,
  );
  final toolService = _TodoToolService(fixture.root, stagedFailureTurns: 1);
  final container = _buildContainer(
    env: env,
    fixture: fixture,
    dataSource: dataSource,
    toolService: toolService,
    logStore: LlmSessionLogStore(
      rootDirectoryProvider: () async => sessionLogRoot,
    ),
  );
  final prompt = _exactShortMvpPrompt('todo_app.md');

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

    final verification = await toolService.verifyTodoApp();
    final diagnostic = _diagnostic(container, dataSource, toolService, fixture);
    expect(dataSource.forcedPendingActionLengthCount, 1, reason: diagnostic);
    expect(dataSource.pendingActionRecoveryRequestCount, 1, reason: diagnostic);
    expect(
      dataSource.pendingActionRecoveryToolCallCount,
      greaterThan(0),
      reason: diagnostic,
    );
    expect(
      dataSource.pendingActionRecoveryToolNames,
      dataSource.preTruncationToolNames,
      reason: diagnostic,
    );
    expect(
      toolService.verificationAttempts,
      greaterThanOrEqualTo(2),
      reason: diagnostic,
    );
    expect(toolService.hasSuccessfulVerifierCall, isTrue, reason: diagnostic);
    _expectVerifiedGoalNotBlocked(container, diagnostic);
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
  bool disableCodingDiagnosticFeedback = false,
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
      if (disableCodingDiagnosticFeedback)
        codingDiagnosticFeedbackServiceProvider.overrideWithValue(
          CodingDiagnosticFeedbackService(
            provider: const _NoopCodingDiagnosticFeedbackProvider(),
          ),
        ),
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

class _NoopCodingDiagnosticFeedbackProvider
    implements CodingDiagnosticFeedbackProvider {
  const _NoopCodingDiagnosticFeedbackProvider();

  @override
  String get providerName => 'noop';

  @override
  Future<CodingDiagnosticSnapshot?> collectSnapshot({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    return null;
  }
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
    this.forcePendingActionLengthRecovery = false,
  }) : super(baseUrl: env.baseUrl, apiKey: env.apiKey);

  final int stagedFailureTurns;
  final bool forcePendingActionLengthRecovery;

  int forcedIncompleteTurns = 0;
  int forcedPendingActionLengthCount = 0;
  int pendingActionRecoveryRequestCount = 0;
  int pendingActionRecoveryToolCallCount = 0;
  Set<String> preTruncationToolNames = const {};
  Set<String> pendingActionRecoveryToolNames = const {};
  bool _awaitingForcedFinalStream = false;

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (_isPendingActionRecoveryRequest(messages)) {
      pendingActionRecoveryRequestCount += 1;
      pendingActionRecoveryToolNames = _toolNames(tools);
      final result = await super.createChatCompletionWithToolResults(
        messages: messages,
        toolResults: toolResults,
        assistantContent: assistantContent,
        tools: tools,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      if (result.hasToolCalls) {
        pendingActionRecoveryToolCallCount += result.toolCalls!.length;
      }
      return result;
    }
    if (_shouldForcePendingActionLength(toolResults)) {
      preTruncationToolNames = _toolNames(tools);
      _awaitingForcedFinalStream = true;
      lastFinishReason = 'stop';
      return ChatCompletionResult(
        content: '',
        finishReason: 'stop',
        usage: TokenUsage.zero,
      );
    }
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
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    if (_awaitingForcedFinalStream) {
      _awaitingForcedFinalStream = false;
      forcedPendingActionLengthCount += 1;
      lastFinishReason = 'length';
      yield 'The verifier still reports unresolved diagnostics. I will';
      return;
    }
    yield* super.streamChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  bool _shouldForcePendingActionLength(List<ToolResultInfo> toolResults) {
    if (!forcePendingActionLengthRecovery ||
        forcedPendingActionLengthCount > 0 ||
        _awaitingForcedFinalStream) {
      return false;
    }
    return toolResults.any((result) {
      final decoded = _tryDecodeObject(result.result);
      return decoded['canary'] == 'todo_app' &&
          decoded['exit_code'] != 0 &&
          _hasPathBackedDiagnostics(decoded['diagnostics']);
    });
  }

  bool _isPendingActionRecoveryRequest(List<Message> messages) => messages.any(
    (message) =>
        message.id.startsWith('length_truncated_pending_action_recovery_'),
  );

  Set<String> _toolNames(List<Map<String, dynamic>>? tools) =>
      tools
          ?.map((tool) => tool['function'])
          .whereType<Map<String, dynamic>>()
          .map((function) => function['name'])
          .whereType<String>()
          .toSet() ??
      const {};

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
  _TodoToolService(
    this.root, {
    required this.stagedFailureTurns,
    this.stableDiagnosticFailureTurns = 0,
    this.entrypointPolicy = DartCliEntrypointPolicy.fixed,
  });

  final Directory root;
  final int stagedFailureTurns;
  final int stableDiagnosticFailureTurns;
  final DartCliEntrypointPolicy entrypointPolicy;
  final List<_TodoToolCall> executedCalls = [];
  String? _resolvedDiagnosticEntrypoint;
  int verificationAttempts = 0;

  String get _canonicalDiagnosticEntrypoint => 'bin/todo_cli.dart';

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
    if (verificationAttempts <= stableDiagnosticFailureTurns) {
      return _stableDiagnosticVerifierFailure(name);
    }
    if (verificationAttempts <= stagedFailureTurns) {
      return _stagedVerifierFailure(name, verificationAttempts);
    }
    final verification = await _verifyTodoApp();
    return _verifierResult(name, verification);
  }

  McpToolResult _stableDiagnosticVerifierFailure(String name) {
    final payload = jsonEncode({
      'canary': 'todo_app',
      'command': _verifyCommand,
      'working_directory': root.absolute.path,
      'exit_code': 1,
      'stdout': '',
      'stderr': 'Stable TODO verifier diagnostic plateau.\n',
      'diagnostics': [
        _diagnosticJson(
          code: 'todo_cli_stable_repair_probe',
          message:
              'The TODO implementation still requires one concrete repair before final verification.',
        ),
      ],
    });
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: false,
      errorMessage: 'TODO verifier reported a stable repair diagnostic.',
    );
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
    final entrypointResolution = _resolveDartCliEntrypoint(
      work: verificationRoot,
      canonicalRelativePath: 'bin/todo_cli.dart',
    );
    final entrypointDiagnostics = _entrypointDiagnostics(
      entrypointResolution,
      missingCode: 'todo_cli_missing',
      unexpectedCode: 'todo_cli_unexpected_entrypoint',
      ambiguousCode: 'todo_cli_ambiguous_entrypoint',
    );
    if (entrypointDiagnostics.isNotEmpty) {
      diagnostics.addAll(entrypointDiagnostics);
      return _TodoVerification(diagnostics: diagnostics, transcript: '');
    }
    final entrypoint = entrypointResolution.selectedRelativePath!;

    final firstList = await _runTodoCommand(
      ['list'],
      verificationRoot,
      entrypoint: entrypoint,
    );
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

    final noArguments = await _runTodoCommand(
      const [],
      verificationRoot,
      entrypoint: entrypoint,
    );
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

    final help = await _runTodoCommand(
      const ['help'],
      verificationRoot,
      entrypoint: entrypoint,
    );
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

    final addMilk = await _runTodoCommand(
      ['add', 'buy milk'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('add buy milk', addMilk));
    final addReport = await _runTodoCommand(
      ['add', 'write report'],
      verificationRoot,
      entrypoint: entrypoint,
    );
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

    final list = await _runTodoCommand(
      ['list'],
      verificationRoot,
      entrypoint: entrypoint,
    );
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
      final done = await _runTodoCommand(
        ['done', firstId],
        verificationRoot,
        entrypoint: entrypoint,
      );
      transcript.writeln(_formatProcess('done $firstId', done));
      final afterDone = await _runTodoCommand(
        ['list'],
        verificationRoot,
        entrypoint: entrypoint,
      );
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

    final persistenceList = await _runTodoCommand(
      ['list'],
      verificationRoot,
      entrypoint: entrypoint,
    );
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
      final delete = await _runTodoCommand(
        ['delete', secondId],
        verificationRoot,
        entrypoint: entrypoint,
      );
      transcript.writeln(_formatProcess('delete $secondId', delete));
      final afterDelete = await _runTodoCommand(
        ['list'],
        verificationRoot,
        entrypoint: entrypoint,
      );
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

    final unknown = await _runTodoCommand(
      ['done', '999999'],
      verificationRoot,
      entrypoint: entrypoint,
    );
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

    final unknownDelete = await _runTodoCommand(
      ['delete', '999999'],
      verificationRoot,
      entrypoint: entrypoint,
    );
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
    Directory verificationRoot, {
    String entrypoint = 'bin/todo_cli.dart',
  }) {
    final usePub = File('${verificationRoot.path}/pubspec.yaml').existsSync();
    final processArgs = usePub
        ? ['run', entrypoint, ...args]
        : [entrypoint, ...args];
    return _runIsolatedDartCommand(processArgs, verificationRoot);
  }

  Future<ProcessResult> _runIsolatedDartCommand(
    List<String> processArgs,
    Directory work,
  ) {
    final runtimeHome = Directory('${work.path}/.runtime_home')
      ..createSync(recursive: true);
    final dataHome = Directory('${runtimeHome.path}/.local/share')
      ..createSync(recursive: true);
    final stateHome = Directory('${runtimeHome.path}/.local/state')
      ..createSync(recursive: true);
    final configHome = Directory('${runtimeHome.path}/.config')
      ..createSync(recursive: true);
    final appData = Directory('${runtimeHome.path}/AppData/Roaming')
      ..createSync(recursive: true);
    final localAppData = Directory('${runtimeHome.path}/AppData/Local')
      ..createSync(recursive: true);
    final tempDirectory = Directory('${runtimeHome.path}/.tmp')
      ..createSync(recursive: true);
    return Process.run(
      'dart',
      processArgs,
      workingDirectory: work.path,
      environment: {
        ...Platform.environment,
        'HOME': runtimeHome.path,
        'USERPROFILE': runtimeHome.path,
        'XDG_DATA_HOME': dataHome.path,
        'XDG_STATE_HOME': stateHome.path,
        'XDG_CONFIG_HOME': configHome.path,
        'APPDATA': appData.path,
        'LOCALAPPDATA': localAppData.path,
        'TMPDIR': tempDirectory.path,
        'TMP': tempDirectory.path,
        'TEMP': tempDirectory.path,
      },
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
        'terminal_message': _todoTerminalMessage,
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
    String relativePath = '',
  }) {
    final effectiveRelativePath = relativePath.isEmpty
        ? (_resolvedDiagnosticEntrypoint ?? _canonicalDiagnosticEntrypoint)
        : relativePath;
    final path = File('${root.path}/$effectiveRelativePath').absolute.path;
    return {
      'severity': 'Error',
      'path': path,
      'relative_path': effectiveRelativePath,
      'line': 1,
      'column': 1,
      'code': code,
      'message': message,
    };
  }

  DartCliEntrypointResolution _resolveDartCliEntrypoint({
    required Directory work,
    required String canonicalRelativePath,
  }) {
    final resolution = const DartCliEntrypointResolver().resolve(
      root: work,
      canonicalRelativePath: canonicalRelativePath,
      policy: entrypointPolicy,
    );
    _resolvedDiagnosticEntrypoint = resolution.selectedRelativePath;
    return resolution;
  }

  List<Map<String, dynamic>> _entrypointDiagnostics(
    DartCliEntrypointResolution resolution, {
    required String missingCode,
    required String unexpectedCode,
    required String ambiguousCode,
  }) {
    return resolution.issues
        .map(
          (issue) => _diagnosticJson(
            code: switch (issue.kind) {
              DartCliEntrypointIssueKind.missing => missingCode,
              DartCliEntrypointIssueKind.unexpected => unexpectedCode,
              DartCliEntrypointIssueKind.ambiguous => ambiguousCode,
            },
            message: issue.message,
            relativePath: issue.relativePath,
          ),
        )
        .toList(growable: false);
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

abstract class _DerivedMvpToolService extends _TodoToolService {
  _DerivedMvpToolService(
    super.root,
    this.fixtureSpec, {
    super.entrypointPolicy = DartCliEntrypointPolicy.fixed,
  }) : super(stagedFailureTurns: 0);

  final _MvpFixtureSpec fixtureSpec;

  @override
  bool get hasSuccessfulVerifierCall => executedCalls.any((call) {
    final result = _tryDecodeObject(call.result);
    return call.name == 'local_execute_command' &&
        result['canary'] == fixtureSpec.canaryId &&
        result['exit_code'] == 0;
  });

  Future<_TodoVerification> verifyFixture() => _verifyTodoApp();

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    final definitions = super.getOpenAiToolDefinitions();
    for (final definition in definitions) {
      final function = definition['function'] as Map<String, dynamic>;
      if (function['name'] == 'local_execute_command') {
        function['description'] =
            'Run the ${fixtureSpec.displayName} fixture verifier. '
            'Accepted command: ${fixtureSpec.verifierCommand}.';
      }
    }
    return definitions;
  }

  @override
  bool _isProtectedVerifierPath(String path) {
    return _relativePath(path) == fixtureSpec.verifierPath;
  }

  @override
  Future<McpToolResult> _executeVerifier(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final command = (arguments['command'] as String? ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (command != fixtureSpec.verifierCommand) {
      return _toolError(
        name,
        'Unsupported command for this ${fixtureSpec.displayName} fixture: '
        '$command',
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
      return await verifyFixtureIn(verificationRoot);
    } finally {
      if (verificationRoot.existsSync()) {
        verificationRoot.deleteSync(recursive: true);
      }
    }
  }

  @override
  Directory _createVerificationRoot() {
    final verificationRoot = Directory.systemTemp.createTempSync(
      fixtureSpec.verificationRootPrefix,
    );
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = _relativePath(entity.path);
      if (relativePath == null ||
          relativePath == fixtureSpec.verifierPath ||
          (relativePath != 'pubspec.yaml' && !relativePath.endsWith('.dart'))) {
        continue;
      }
      final target = File('${verificationRoot.path}/$relativePath');
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(entity.readAsBytesSync());
    }
    return verificationRoot;
  }

  Future<_TodoVerification> verifyFixtureIn(Directory work);

  @override
  McpToolResult _verifierResult(String name, _TodoVerification verification) {
    final exitCode = verification.diagnostics.isEmpty ? 0 : 1;
    final payload = jsonEncode({
      'canary': fixtureSpec.canaryId,
      'command': fixtureSpec.verifierCommand,
      'working_directory': root.absolute.path,
      'exit_code': exitCode,
      'stdout': verification.transcript,
      'stderr': exitCode == 0 ? '' : fixtureSpec.failureStderr,
      'diagnostics': verification.diagnostics,
      if (exitCode == 0) ...{
        'terminal_success': true,
        'terminal_message': fixtureSpec.terminalMessage,
      },
    });
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: exitCode == 0,
      errorMessage: exitCode == 0 ? null : fixtureSpec.toolFailureMessage,
    );
  }

  @override
  String get _canonicalDiagnosticEntrypoint => fixtureSpec.entrypoint;
}

class _WordFrequencyToolService extends _DerivedMvpToolService {
  _WordFrequencyToolService(
    Directory root, {
    DartCliEntrypointPolicy entrypointPolicy = DartCliEntrypointPolicy.fixed,
  }) : super(
         root,
         _wordFrequencyFixtureSpec,
         entrypointPolicy: entrypointPolicy,
       );

  Future<_TodoVerification> verifyWordFrequency() => verifyFixture();

  @override
  Future<_TodoVerification> verifyFixtureIn(Directory work) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final entrypointResolution = _resolveDartCliEntrypoint(
      work: work,
      canonicalRelativePath: fixtureSpec.entrypoint,
    );
    final entrypointDiagnostics = _entrypointDiagnostics(
      entrypointResolution,
      missingCode: 'word_frequency_cli_missing',
      unexpectedCode: 'word_frequency_unexpected_entrypoint',
      ambiguousCode: 'word_frequency_ambiguous_entrypoint',
    );
    if (entrypointDiagnostics.isNotEmpty) {
      diagnostics.addAll(entrypointDiagnostics);
      return _TodoVerification(diagnostics: diagnostics, transcript: '');
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
    final entrypoint = _resolveDartCliEntrypoint(
      work: work,
      canonicalRelativePath: fixtureSpec.entrypoint,
    ).selectedRelativePath!;
    return _runIsolatedDartCommand(['run', entrypoint, ...args], work);
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
}

class _ExpenseTrackerToolService extends _DerivedMvpToolService {
  _ExpenseTrackerToolService(
    Directory root, {
    DartCliEntrypointPolicy entrypointPolicy = DartCliEntrypointPolicy.fixed,
  }) : super(
         root,
         _expenseTrackerFixtureSpec,
         entrypointPolicy: entrypointPolicy,
       );

  Future<_TodoVerification> verifyExpenseTracker() => verifyFixture();

  @override
  Future<_TodoVerification> verifyFixtureIn(Directory work) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final entrypointResolution = _resolveDartCliEntrypoint(
      work: work,
      canonicalRelativePath: fixtureSpec.entrypoint,
    );
    final entrypointDiagnostics = _entrypointDiagnostics(
      entrypointResolution,
      missingCode: 'expense_tracker_cli_missing',
      unexpectedCode: 'expense_tracker_unexpected_entrypoint',
      ambiguousCode: 'expense_tracker_ambiguous_entrypoint',
    );
    if (entrypointDiagnostics.isNotEmpty) {
      diagnostics.addAll(entrypointDiagnostics);
      return _TodoVerification(diagnostics: diagnostics, transcript: '');
    }

    final emptyList = await _runExpenseCommand(['list'], work);
    transcript.writeln(_formatProcess('empty list', emptyList));
    if (emptyList.exitCode != 0 ||
        _looksLikeStackTrace(_processText(emptyList))) {
      diagnostics.add(
        _diagnosticJson(
          code: 'expense_tracker_empty_list_failed',
          message: 'Listing with no state file must succeed without crashing.',
        ),
      );
    }
    final emptySummary = await _runExpenseCommand(['summary'], work);
    transcript.writeln(_formatProcess('empty summary', emptySummary));
    final emptySummaryOutput = _processText(emptySummary);
    if (emptySummary.exitCode != 0 ||
        _looksLikeStackTrace(emptySummaryOutput) ||
        !_hasAmount(emptySummaryOutput, 'total', '0.00')) {
      diagnostics.add(
        _diagnosticJson(
          code: 'expense_tracker_empty_summary_failed',
          message:
              'Summary with no state file must succeed and report total 0.00.',
        ),
      );
    }

    final baselineAdds = <List<String>>[
      ['add', '10.00', 'food', 'lunch'],
      ['add', '5.50', 'food', 'coffee'],
      ['add', '20.00', 'transport', 'taxi'],
    ];
    for (final args in baselineAdds) {
      final result = await _runExpenseCommand(args, work);
      transcript.writeln(_formatProcess(args.join(' '), result));
      if (result.exitCode != 0) {
        diagnostics.add(
          _diagnosticJson(
            code: 'expense_tracker_add_failed',
            message: 'A valid expense was rejected: ${args.join(' ')}.',
          ),
        );
      }
    }

    final baselineSummary = await _runExpenseCommand(['summary'], work);
    transcript.writeln(_formatProcess('baseline summary', baselineSummary));
    final baselineOutput = _processText(baselineSummary);
    if (baselineSummary.exitCode != 0 ||
        !_hasAmount(baselineOutput, 'food', '15.50') ||
        !_hasAmount(baselineOutput, 'transport', '20.00') ||
        !_hasAmount(baselineOutput, 'total', '35.50')) {
      diagnostics.add(
        _diagnosticJson(
          code: 'expense_tracker_baseline_summary_failed',
          message:
              'Summary must report food 15.50, transport 20.00, and total 35.50.',
        ),
      );
    }

    final beforeInvalid = await _runExpenseCommand(['list'], work);
    transcript.writeln(
      _formatProcess('list before invalid input', beforeInvalid),
    );
    for (final args in const <List<String>>[
      ['add', '-5', 'food', 'invalid negative'],
      ['add', 'abc', 'food', 'invalid text'],
      ['add', '0', 'food', 'invalid zero'],
      ['add', '0.00', 'food', 'invalid zero decimal'],
    ]) {
      final result = await _runExpenseCommand(args, work);
      transcript.writeln(_formatProcess(args.join(' '), result));
      if (result.exitCode == 0 || _processText(result).trim().isEmpty) {
        diagnostics.add(
          _diagnosticJson(
            code: 'expense_tracker_invalid_amount_accepted',
            message:
                'Zero, negative, and non-numeric amounts must fail with a clear message.',
          ),
        );
      }
    }
    final afterInvalid = await _runExpenseCommand(['list'], work);
    transcript.writeln(
      _formatProcess('list after invalid input', afterInvalid),
    );
    if (beforeInvalid.exitCode != 0 ||
        afterInvalid.exitCode != 0 ||
        beforeInvalid.stdout.toString().trim() !=
            afterInvalid.stdout.toString().trim()) {
      diagnostics.add(
        _diagnosticJson(
          code: 'expense_tracker_invalid_amount_mutated_state',
          message: 'Rejected amounts must not add or change any expense.',
        ),
      );
    }

    for (final args in const <List<String>>[
      ['add', '0.1', 'food', 'decimal a'],
      ['add', '0.2', 'food', 'decimal b'],
    ]) {
      final result = await _runExpenseCommand(args, work);
      transcript.writeln(_formatProcess(args.join(' '), result));
      if (result.exitCode != 0) {
        diagnostics.add(
          _diagnosticJson(
            code: 'expense_tracker_decimal_add_failed',
            message: 'Valid one- and two-decimal amounts must be accepted.',
          ),
        );
      }
    }
    final decimalSummary = await _runExpenseCommand(['summary'], work);
    transcript.writeln(_formatProcess('decimal summary', decimalSummary));
    final decimalOutput = _processText(decimalSummary);
    if (decimalSummary.exitCode != 0 ||
        !_hasAmount(decimalOutput, 'food', '15.80') ||
        !_hasAmount(decimalOutput, 'transport', '20.00') ||
        !_hasAmount(decimalOutput, 'total', '35.80')) {
      diagnostics.add(
        _diagnosticJson(
          code: 'expense_tracker_decimal_or_total_failed',
          message:
              'Exact decimal aggregation must report food 15.80 and total 35.80.',
        ),
      );
    }

    const quotedNote = 'dinner, "with" team';
    final quotedAdd = await _runExpenseCommand([
      'add',
      '3.00',
      'misc',
      quotedNote,
    ], work);
    transcript.writeln(_formatProcess('add quoted CSV note', quotedAdd));
    final export = await _runExpenseCommand(['export', 'out.csv'], work);
    transcript.writeln(_formatProcess('export out.csv', export));
    final csvFile = File('${work.path}/out.csv');
    if (quotedAdd.exitCode != 0 ||
        export.exitCode != 0 ||
        !csvFile.existsSync() ||
        !_csvContainsExpense(csvFile, '3.00', 'misc', quotedNote)) {
      diagnostics.add(
        _diagnosticJson(
          code: 'expense_tracker_csv_quoting_failed',
          message:
              'CSV export must preserve comma and quote characters in one note field.',
        ),
      );
    }

    final freshList = await _runExpenseCommand(['list'], work);
    transcript.writeln(_formatProcess('fresh-process list', freshList));
    final freshOutput = _processText(freshList);
    if (freshList.exitCode != 0 ||
        !freshOutput.contains('lunch') ||
        !freshOutput.contains('coffee') ||
        !freshOutput.contains('taxi') ||
        !freshOutput.contains('dinner')) {
      diagnostics.add(
        _diagnosticJson(
          code: 'expense_tracker_persistence_failed',
          message:
              'A fresh process must list expenses recorded by earlier processes.',
        ),
      );
    }

    return _TodoVerification(
      diagnostics: diagnostics,
      transcript: transcript.toString(),
    );
  }

  Future<ProcessResult> _runExpenseCommand(List<String> args, Directory work) {
    final entrypoint = _resolveDartCliEntrypoint(
      work: work,
      canonicalRelativePath: fixtureSpec.entrypoint,
    ).selectedRelativePath!;
    return _runIsolatedDartCommand(['run', entrypoint, ...args], work);
  }

  String _processText(ProcessResult result) {
    return '${result.stdout}\n${result.stderr}'.toLowerCase();
  }

  bool _hasAmount(String output, String label, String amount) {
    return const LineSplitter().convert(output).any((line) {
      return RegExp(
        '\\b${RegExp.escape(label)}\\b.*(?:^|[^0-9])${RegExp.escape(amount)}(?![0-9])',
      ).hasMatch(line);
    });
  }

  bool _csvContainsExpense(
    File file,
    String amount,
    String category,
    String note,
  ) {
    final rows = _parseCsv(file.readAsStringSync());
    if (rows.length < 2) return false;
    final header = rows.first
        .map((value) => value.trim().toLowerCase())
        .toList();
    final amountIndex = header.indexOf('amount');
    final categoryIndex = header.indexOf('category');
    final noteIndex = header.indexOf('note');
    if (amountIndex < 0 || categoryIndex < 0 || noteIndex < 0) return false;
    return rows.skip(1).any((row) {
      final maxIndex = [
        amountIndex,
        categoryIndex,
        noteIndex,
      ].reduce((left, right) => left > right ? left : right);
      return row.length > maxIndex &&
          row[amountIndex].replaceAll(RegExp(r'[^0-9.]'), '') == amount &&
          row[categoryIndex] == category &&
          row[noteIndex] == note;
    });
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var index = 0; index < input.length; index++) {
      final character = input[index];
      if (character == '"') {
        if (quoted && index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index += 1;
        } else {
          quoted = !quoted;
        }
      } else if (character == ',' && !quoted) {
        row.add(field.toString());
        field.clear();
      } else if ((character == '\n' || character == '\r') && !quoted) {
        if (character == '\r' &&
            index + 1 < input.length &&
            input[index + 1] == '\n') {
          index += 1;
        }
        row.add(field.toString());
        field.clear();
        if (row.any((value) => value.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(character);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}

class _MarkdownTocToolService extends _DerivedMvpToolService {
  _MarkdownTocToolService(
    Directory root, {
    DartCliEntrypointPolicy entrypointPolicy = DartCliEntrypointPolicy.fixed,
  }) : super(root, _markdownTocFixtureSpec, entrypointPolicy: entrypointPolicy);

  Future<_TodoVerification> verifyMarkdownToc() => verifyFixture();

  @override
  Future<_TodoVerification> verifyFixtureIn(Directory work) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final entrypointResolution = _resolveDartCliEntrypoint(
      work: work,
      canonicalRelativePath: fixtureSpec.entrypoint,
    );
    final entrypointDiagnostics = _entrypointDiagnostics(
      entrypointResolution,
      missingCode: 'markdown_toc_cli_missing',
      unexpectedCode: 'markdown_toc_unexpected_entrypoint',
      ambiguousCode: 'markdown_toc_ambiguous_entrypoint',
    );
    if (entrypointDiagnostics.isNotEmpty) {
      diagnostics.addAll(entrypointDiagnostics);
      return _TodoVerification(diagnostics: diagnostics, transcript: '');
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
    final entrypoint = _resolveDartCliEntrypoint(
      work: work,
      canonicalRelativePath: fixtureSpec.entrypoint,
    ).selectedRelativePath!;
    return _runIsolatedDartCommand(['run', entrypoint, ...args], work);
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

class _MvpFixtureSpec {
  const _MvpFixtureSpec({
    required this.canaryId,
    required this.documentName,
    required this.entrypoint,
    required this.verifierCommand,
    required this.verifierPath,
    required this.verificationRootPrefix,
    required this.displayName,
    required this.failureStderr,
    required this.terminalMessage,
    required this.toolFailureMessage,
  });

  final String canaryId;
  final String documentName;
  final String entrypoint;
  final String verifierCommand;
  final String verifierPath;
  final String verificationRootPrefix;
  final String displayName;
  final String failureStderr;
  final String terminalMessage;
  final String toolFailureMessage;
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
