import 'dart:convert';
import 'dart:io';

import 'dart_cli_entrypoint_resolver.dart';

/// Behavioral acceptance checks for the expense_tracker.md MVP fixture.
///
/// Lives outside the live-canary test file so the verifier the model is told to
/// run can forward to it, and so a human can re-check an artifact by hand. Like
/// the sibling verifiers it repeats a few small helpers rather than sharing a
/// base: these must stay readable and dependency-free, and a shared base would
/// couple every fixture's checks to every other fixture's edits.
class ExpenseTrackerVerificationResult {
  const ExpenseTrackerVerificationResult({
    required this.diagnostics,
    required this.transcript,
  });

  final List<Map<String, dynamic>> diagnostics;
  final String transcript;

  bool get passed => diagnostics.isEmpty;
}

class ExpenseTrackerBehaviorVerifier {
  const ExpenseTrackerBehaviorVerifier({
    required this.root,
    this.entrypointPolicy = DartCliEntrypointPolicy.fixed,
  });

  static const String canonicalEntrypoint = 'bin/expense_tracker.dart';
  static const String verifierPath = 'tool/verify_expense_tracker.dart';

  final Directory root;
  final DartCliEntrypointPolicy entrypointPolicy;

  Future<ExpenseTrackerVerificationResult> verify() async {
    final verificationRoot = createVerificationRoot();
    try {
      return await verifyIn(verificationRoot);
    } finally {
      if (verificationRoot.existsSync()) {
        verificationRoot.deleteSync(recursive: true);
      }
    }
  }

  Future<ExpenseTrackerVerificationResult> verifyIn(Directory work) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final entrypointDiagnostics = _entrypointDiagnostics(
      const DartCliEntrypointResolver().resolve(
        root: work,
        canonicalRelativePath: canonicalEntrypoint,
        policy: entrypointPolicy,
      ),
    );
    if (entrypointDiagnostics.isNotEmpty) {
      return ExpenseTrackerVerificationResult(
        diagnostics: entrypointDiagnostics,
        transcript: '',
      );
    }

    final emptyList = await runCommand(['list'], work);
    transcript.writeln(_formatProcess('empty list', emptyList));
    if (emptyList.exitCode != 0 || _looksLikeStackTrace(_text(emptyList))) {
      diagnostics.add(
        _diagnostic(
          code: 'expense_tracker_empty_list_failed',
          message: 'Listing with no state file must succeed without crashing.',
        ),
      );
    }

    final emptySummary = await runCommand(['summary'], work);
    transcript.writeln(_formatProcess('empty summary', emptySummary));
    final emptySummaryOutput = _text(emptySummary);
    if (emptySummary.exitCode != 0 ||
        _looksLikeStackTrace(emptySummaryOutput) ||
        !_hasAmount(emptySummaryOutput, 'total', '0.00')) {
      diagnostics.add(
        _diagnostic(
          code: 'expense_tracker_empty_summary_failed',
          message:
              'Summary with no state file must succeed and report total 0.00.',
        ),
      );
    }

    for (final args in const <List<String>>[
      ['add', '10.00', 'food', 'lunch'],
      ['add', '5.50', 'food', 'coffee'],
      ['add', '20.00', 'transport', 'taxi'],
    ]) {
      final result = await runCommand(args, work);
      transcript.writeln(_formatProcess(args.join(' '), result));
      if (result.exitCode != 0) {
        diagnostics.add(
          _diagnostic(
            code: 'expense_tracker_add_failed',
            message: 'A valid expense was rejected: ${args.join(' ')}.',
          ),
        );
      }
    }

    final baselineSummary = await runCommand(['summary'], work);
    transcript.writeln(_formatProcess('baseline summary', baselineSummary));
    final baselineOutput = _text(baselineSummary);
    if (baselineSummary.exitCode != 0 ||
        !_hasAmount(baselineOutput, 'food', '15.50') ||
        !_hasAmount(baselineOutput, 'transport', '20.00') ||
        !_hasAmount(baselineOutput, 'total', '35.50')) {
      diagnostics.add(
        _diagnostic(
          code: 'expense_tracker_baseline_summary_failed',
          message:
              'Summary must report food 15.50, transport 20.00, and total '
              '35.50.',
        ),
      );
    }

    // A rejected amount must not only fail: it must leave the ledger alone.
    final beforeInvalid = await runCommand(['list'], work);
    transcript.writeln(
      _formatProcess('list before invalid input', beforeInvalid),
    );
    for (final args in const <List<String>>[
      ['add', '-5', 'food', 'invalid negative'],
      ['add', 'abc', 'food', 'invalid text'],
      ['add', '0', 'food', 'invalid zero'],
      ['add', '0.00', 'food', 'invalid zero decimal'],
    ]) {
      final result = await runCommand(args, work);
      transcript.writeln(_formatProcess(args.join(' '), result));
      if (result.exitCode == 0 || _text(result).trim().isEmpty) {
        diagnostics.add(
          _diagnostic(
            code: 'expense_tracker_invalid_amount_accepted',
            message:
                'Zero, negative, and non-numeric amounts must fail with a '
                'clear message.',
          ),
        );
      }
    }
    final afterInvalid = await runCommand(['list'], work);
    transcript.writeln(
      _formatProcess('list after invalid input', afterInvalid),
    );
    if (beforeInvalid.exitCode != 0 ||
        afterInvalid.exitCode != 0 ||
        beforeInvalid.stdout.toString().trim() !=
            afterInvalid.stdout.toString().trim()) {
      diagnostics.add(
        _diagnostic(
          code: 'expense_tracker_invalid_amount_mutated_state',
          message: 'Rejected amounts must not add or change any expense.',
        ),
      );
    }

    for (final args in const <List<String>>[
      ['add', '0.1', 'food', 'decimal a'],
      ['add', '0.2', 'food', 'decimal b'],
    ]) {
      final result = await runCommand(args, work);
      transcript.writeln(_formatProcess(args.join(' '), result));
      if (result.exitCode != 0) {
        diagnostics.add(
          _diagnostic(
            code: 'expense_tracker_decimal_add_failed',
            message: 'Valid one- and two-decimal amounts must be accepted.',
          ),
        );
      }
    }
    final decimalSummary = await runCommand(['summary'], work);
    transcript.writeln(_formatProcess('decimal summary', decimalSummary));
    final decimalOutput = _text(decimalSummary);
    if (decimalSummary.exitCode != 0 ||
        !_hasAmount(decimalOutput, 'food', '15.80') ||
        !_hasAmount(decimalOutput, 'transport', '20.00') ||
        !_hasAmount(decimalOutput, 'total', '35.80')) {
      diagnostics.add(
        _diagnostic(
          code: 'expense_tracker_decimal_or_total_failed',
          message:
              'Exact decimal aggregation must report food 15.80 and total '
              '35.80.',
        ),
      );
    }

    const quotedNote = 'dinner, "with" team';
    final quotedAdd = await runCommand([
      'add',
      '3.00',
      'misc',
      quotedNote,
    ], work);
    transcript.writeln(_formatProcess('add quoted CSV note', quotedAdd));
    final export = await runCommand(['export', 'out.csv'], work);
    transcript.writeln(_formatProcess('export out.csv', export));
    final csvFile = File('${work.path}/out.csv');
    if (quotedAdd.exitCode != 0 ||
        export.exitCode != 0 ||
        !csvFile.existsSync() ||
        !_csvContainsExpense(csvFile, '3.00', 'misc', quotedNote)) {
      diagnostics.add(
        _diagnostic(
          code: 'expense_tracker_csv_quoting_failed',
          message:
              'CSV export must preserve comma and quote characters in one '
              'note field.',
        ),
      );
    }

    final freshList = await runCommand(['list'], work);
    transcript.writeln(_formatProcess('fresh-process list', freshList));
    final freshOutput = _text(freshList);
    if (freshList.exitCode != 0 ||
        !freshOutput.contains('lunch') ||
        !freshOutput.contains('coffee') ||
        !freshOutput.contains('taxi') ||
        !freshOutput.contains('dinner')) {
      diagnostics.add(
        _diagnostic(
          code: 'expense_tracker_persistence_failed',
          message:
              'A fresh process must list expenses recorded by earlier '
              'processes.',
        ),
      );
    }

    return ExpenseTrackerVerificationResult(
      diagnostics: diagnostics,
      transcript: transcript.toString(),
    );
  }

  /// Copies the model's sources into a fresh directory, so leftover runtime
  /// state from earlier commands cannot make a broken build look correct.
  Directory createVerificationRoot() {
    final verificationRoot = Directory.systemTemp.createTempSync(
      'expense_tracker_verification_',
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
      if (relativePath == verifierPath ||
          (relativePath != 'pubspec.yaml' && !relativePath.endsWith('.dart'))) {
        continue;
      }
      final target = File('${verificationRoot.path}/$relativePath');
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(entity.readAsBytesSync());
    }
    return verificationRoot;
  }

  Future<ProcessResult> runCommand(List<String> args, Directory work) {
    final entrypoint =
        const DartCliEntrypointResolver()
            .resolve(
              root: work,
              canonicalRelativePath: canonicalEntrypoint,
              policy: entrypointPolicy,
            )
            .selectedRelativePath ??
        canonicalEntrypoint;
    final usePub = File('${work.path}/pubspec.yaml').existsSync();
    return _runIsolatedDartCommand(
      usePub ? ['run', entrypoint, ...args] : [entrypoint, ...args],
      work,
    );
  }

  /// Runs `dart` with every home and temp directory pointed inside [work], so
  /// a program that persists to `$HOME` cannot leave state behind — or read
  /// state a previous run left in the real one.
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

  String _text(ProcessResult result) =>
      '${result.stdout}\n${result.stderr}'.toLowerCase();

  bool _looksLikeStackTrace(String output) {
    return output.contains('stack trace') ||
        output.contains('unhandled exception') ||
        output.contains('#0 ');
  }

  bool _hasAmount(String output, String label, String amount) {
    return const LineSplitter().convert(output).any((line) {
      return RegExp(
        '\\b${RegExp.escape(label)}\\b.*(?:^|[^0-9])'
        '${RegExp.escape(amount)}(?![0-9])',
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
    if (rows.length < 2) {
      return false;
    }
    final header = rows.first
        .map((value) => value.trim().toLowerCase())
        .toList();
    final amountIndex = header.indexOf('amount');
    final categoryIndex = header.indexOf('category');
    final noteIndex = header.indexOf('note');
    if (amountIndex < 0 || categoryIndex < 0 || noteIndex < 0) {
      return false;
    }
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
        if (row.any((value) => value.isNotEmpty)) {
          rows.add(row);
        }
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

  List<Map<String, dynamic>> _entrypointDiagnostics(
    DartCliEntrypointResolution resolution,
  ) {
    return resolution.issues
        .map(
          (issue) => _diagnostic(
            code: switch (issue.kind) {
              DartCliEntrypointIssueKind.missing =>
                'expense_tracker_cli_missing',
              DartCliEntrypointIssueKind.unexpected =>
                'expense_tracker_unexpected_entrypoint',
              DartCliEntrypointIssueKind.ambiguous =>
                'expense_tracker_ambiguous_entrypoint',
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
    String entrypoint = '',
  }) {
    final relativePath = entrypoint.trim().isEmpty
        ? canonicalEntrypoint
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

  String _formatProcess(String label, ProcessResult result) {
    return <String>[
      '== $label ==',
      'exit=${result.exitCode}',
      'stdout=${result.stdout}',
      'stderr=${result.stderr}',
    ].join('\n');
  }
}
