import 'dart:convert';
import 'dart:io';

import 'dart_cli_entrypoint_resolver.dart';

class TodoAppVerificationResult {
  const TodoAppVerificationResult({
    required this.diagnostics,
    required this.transcript,
  });

  final List<Map<String, dynamic>> diagnostics;
  final String transcript;

  bool get passed => diagnostics.isEmpty;
}

class TodoAppBehaviorVerifier {
  const TodoAppBehaviorVerifier({
    required this.root,
    this.entrypointPolicy = DartCliEntrypointPolicy.fixed,
  });

  final Directory root;
  final DartCliEntrypointPolicy entrypointPolicy;

  Future<TodoAppVerificationResult> verify() async {
    final verificationRoot = createVerificationRoot();
    try {
      return await verifyIn(verificationRoot);
    } finally {
      if (verificationRoot.existsSync()) {
        verificationRoot.deleteSync(recursive: true);
      }
    }
  }

  Future<TodoAppVerificationResult> verifyIn(Directory verificationRoot) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final resolution = const DartCliEntrypointResolver().resolve(
      root: verificationRoot,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: entrypointPolicy,
    );
    diagnostics.addAll(_entrypointDiagnostics(resolution));
    if (diagnostics.isNotEmpty) {
      return TodoAppVerificationResult(
        diagnostics: diagnostics,
        transcript: '',
      );
    }
    final entrypoint = resolution.selectedRelativePath!;

    final firstList = await runCommand(
      const ['list'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('list', firstList));
    final firstListText = _processText(firstList);
    if (firstList.exitCode != 0 ||
        firstListText.trim().isEmpty ||
        !_containsAny(firstListText, const [
          'no task',
          'no todo',
          'empty',
          'nothing',
        ])) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_first_list_failed',
          message:
              'First-ever list must succeed and print a friendly empty-list message.',
          entrypoint: entrypoint,
        ),
      );
    }

    final noArguments = await runCommand(
      const [],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('no arguments', noArguments));
    if (!_looksLikeUsage(_processText(noArguments))) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_no_arguments_usage_failed',
          message: 'Running without arguments must print usage.',
          entrypoint: entrypoint,
        ),
      );
    }

    final help = await runCommand(
      const ['help'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('help', help));
    if (help.exitCode != 0 || !_looksLikeUsage(_processText(help))) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_help_failed',
          message: 'The help command must succeed and print usage.',
          entrypoint: entrypoint,
        ),
      );
    }

    final addMilk = await runCommand(
      const ['add', 'buy milk'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('add buy milk', addMilk));
    final addReport = await runCommand(
      const ['add', 'write report'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('add write report', addReport));
    final firstId = _extractId(addMilk.stdout as String);
    final secondId = _extractId(addReport.stdout as String);
    if (addMilk.exitCode != 0 || firstId == null) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_add_first_failed',
          message: 'Adding the first task did not print a stable id.',
          entrypoint: entrypoint,
        ),
      );
    }
    if (addReport.exitCode != 0 || secondId == null || secondId == firstId) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_add_second_failed',
          message: 'Adding the second task did not print a distinct stable id.',
          entrypoint: entrypoint,
        ),
      );
    }

    final list = await runCommand(
      const ['list'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('list after adds', list));
    final listOutput = (list.stdout as String).toLowerCase();
    if (list.exitCode != 0 ||
        !listOutput.contains('buy milk') ||
        !listOutput.contains('write report')) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_list_missing_tasks',
          message: 'Listing after two adds did not show both tasks.',
          entrypoint: entrypoint,
        ),
      );
    }

    if (firstId != null) {
      final done = await runCommand(
        ['done', firstId],
        verificationRoot,
        entrypoint: entrypoint,
      );
      transcript.writeln(_formatProcess('done $firstId', done));
      final afterDone = await runCommand(
        const ['list'],
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
          _diagnostic(
            code: 'todo_cli_done_not_persisted',
            message:
                'Done did not persist task 1 as completed while task 2 stayed undone.',
            entrypoint: entrypoint,
          ),
        );
      }
    }

    final persistenceList = await runCommand(
      const ['list'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('fresh list', persistenceList));
    if (persistenceList.exitCode != 0 ||
        !(persistenceList.stdout as String).toLowerCase().contains(
          'buy milk',
        )) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_persistence_failed',
          message: 'A fresh list run did not reflect prior state.',
          entrypoint: entrypoint,
        ),
      );
    }

    if (secondId != null) {
      final delete = await runCommand(
        ['delete', secondId],
        verificationRoot,
        entrypoint: entrypoint,
      );
      transcript.writeln(_formatProcess('delete $secondId', delete));
      final afterDelete = await runCommand(
        const ['list'],
        verificationRoot,
        entrypoint: entrypoint,
      );
      transcript.writeln(_formatProcess('list after delete', afterDelete));
      final afterDeleteOutput = (afterDelete.stdout as String).toLowerCase();
      if (delete.exitCode != 0 ||
          afterDeleteOutput.contains('write report') ||
          !afterDeleteOutput.contains('buy milk')) {
        diagnostics.add(
          _diagnostic(
            code: 'todo_cli_delete_failed',
            message: 'Delete did not remove only the requested task.',
            entrypoint: entrypoint,
          ),
        );
      }
    }

    final unknownDone = await runCommand(
      const ['done', '999999'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('done unknown', unknownDone));
    final unknownDoneText = _processText(unknownDone);
    if (unknownDone.exitCode == 0 ||
        unknownDoneText.trim().isEmpty ||
        _looksLikeStackTrace(unknownDoneText)) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_unknown_id_failed',
          message:
              'Unknown id did not produce a clear message and non-zero exit code.',
          entrypoint: entrypoint,
        ),
      );
    }

    final unknownDelete = await runCommand(
      const ['delete', '999999'],
      verificationRoot,
      entrypoint: entrypoint,
    );
    transcript.writeln(_formatProcess('delete unknown', unknownDelete));
    final unknownDeleteText = _processText(unknownDelete);
    if (unknownDelete.exitCode == 0 ||
        unknownDeleteText.trim().isEmpty ||
        _looksLikeStackTrace(unknownDeleteText)) {
      diagnostics.add(
        _diagnostic(
          code: 'todo_cli_unknown_delete_failed',
          message:
              'Unknown delete id did not produce a clear message and non-zero exit code.',
          entrypoint: entrypoint,
        ),
      );
    }

    return TodoAppVerificationResult(
      diagnostics: diagnostics,
      transcript: transcript.toString(),
    );
  }

  Directory createVerificationRoot() {
    final verificationRoot = Directory.systemTemp.createTempSync(
      'todo_mvp_verification_',
    );
    final rootPath = root.absolute.path;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final absolutePath = entity.absolute.path;
      if (!absolutePath.startsWith('$rootPath${Platform.pathSeparator}')) {
        continue;
      }
      final relativePath = absolutePath
          .substring(rootPath.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      if (relativePath == 'tool/verify_todo_app.dart' ||
          (relativePath != 'pubspec.yaml' && !relativePath.endsWith('.dart'))) {
        continue;
      }
      final target = File('${verificationRoot.path}/$relativePath');
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(entity.readAsBytesSync());
    }
    return verificationRoot;
  }

  Future<ProcessResult> runCommand(
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

  List<Map<String, dynamic>> _entrypointDiagnostics(
    DartCliEntrypointResolution resolution,
  ) {
    return resolution.issues
        .map(
          (issue) => _diagnostic(
            code: switch (issue.kind) {
              DartCliEntrypointIssueKind.missing => 'todo_cli_missing',
              DartCliEntrypointIssueKind.unexpected =>
                'todo_cli_unexpected_entrypoint',
              DartCliEntrypointIssueKind.ambiguous =>
                'todo_cli_ambiguous_entrypoint',
            },
            message: issue.message,
            entrypoint: issue.relativePath,
          ),
        )
        .toList(growable: false);
  }

  Map<String, dynamic> _diagnostic({
    required String code,
    required String message,
    required String entrypoint,
  }) {
    final relativePath = entrypoint.trim().isEmpty
        ? 'bin/todo_cli.dart'
        : entrypoint;
    return <String, dynamic>{
      'severity': 'Error',
      'path': File('${root.path}/$relativePath').absolute.path,
      'relative_path': relativePath,
      'line': 1,
      'column': 1,
      'code': code,
      'message': message,
    };
  }

  String? _extractId(String output) {
    return RegExp(r'\b([0-9]{1,9})\b').firstMatch(output)?.group(1);
  }

  bool _looksCompleted(String listOutput, String taskText) {
    return todoListEntryLooksCompleted(listOutput, taskText);
  }

  bool _looksUndone(String listOutput, String taskText) {
    final line = _lineContaining(listOutput, taskText);
    if (line == null) {
      return false;
    }
    return line.contains('[ ]') ||
        line.contains('todo') ||
        line.contains('undone') ||
        !todoListEntryLooksCompleted(line, taskText);
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

  String _processText(ProcessResult result) {
    return [
      result.stdout as String,
      result.stderr as String,
    ].join('\n').toLowerCase();
  }

  String _formatProcess(String label, ProcessResult result) {
    return <String>[
      '== $label ==',
      'exit=${result.exitCode}',
      'stdout=${result.stdout}',
      'stderr=${result.stderr}',
    ].join('\n');
  }
}

bool todoListEntryLooksCompleted(String listOutput, String taskText) {
  final normalizedTaskText = taskText.toLowerCase();
  for (final rawLine in const LineSplitter().convert(listOutput)) {
    final line = rawLine.toLowerCase();
    if (!line.contains(normalizedTaskText)) {
      continue;
    }
    final statusText = line.replaceFirst(normalizedTaskText, '');
    return statusText.contains('[x]') ||
        statusText.contains('done') ||
        statusText.contains('complete') ||
        statusText.contains('✓') ||
        RegExp(r'(^|[\s\[\]():|])x(?=$|[\s\[\]():|])').hasMatch(statusText);
  }
  return false;
}
