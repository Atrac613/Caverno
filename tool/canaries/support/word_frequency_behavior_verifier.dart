import 'dart:convert';
import 'dart:io';

import 'dart_cli_entrypoint_resolver.dart';

/// Behavioral acceptance checks for the word_frequency_cli.md MVP fixture.
///
/// Lives outside the live-canary test file so the verifier the model is told to
/// run can forward to it, and so a human can re-check an artifact by hand. It
/// deliberately repeats a few small helpers from
/// `todo_app_behavior_verifier.dart` rather than sharing a base: these
/// verifiers must stay readable and dependency-free, and a shared base would
/// couple every fixture's checks to every other fixture's edits.
class WordFrequencyVerificationResult {
  const WordFrequencyVerificationResult({
    required this.diagnostics,
    required this.transcript,
  });

  final List<Map<String, dynamic>> diagnostics;
  final String transcript;

  bool get passed => diagnostics.isEmpty;
}

class WordFrequencyBehaviorVerifier {
  const WordFrequencyBehaviorVerifier({
    required this.root,
    this.entrypointPolicy = DartCliEntrypointPolicy.fixed,
  });

  static const String canonicalEntrypoint = 'bin/word_frequency.dart';
  static const String verifierPath = 'tool/verify_word_frequency_cli.dart';

  final Directory root;
  final DartCliEntrypointPolicy entrypointPolicy;

  Future<WordFrequencyVerificationResult> verify() async {
    final verificationRoot = createVerificationRoot();
    try {
      return await verifyIn(verificationRoot);
    } finally {
      if (verificationRoot.existsSync()) {
        verificationRoot.deleteSync(recursive: true);
      }
    }
  }

  Future<WordFrequencyVerificationResult> verifyIn(Directory work) async {
    final diagnostics = <Map<String, dynamic>>[];
    final transcript = StringBuffer();
    final resolution = const DartCliEntrypointResolver().resolve(
      root: work,
      canonicalRelativePath: canonicalEntrypoint,
      policy: entrypointPolicy,
    );
    final entrypointDiagnostics = _entrypointDiagnostics(resolution);
    if (entrypointDiagnostics.isNotEmpty) {
      return WordFrequencyVerificationResult(
        diagnostics: entrypointDiagnostics,
        transcript: '',
      );
    }

    File(
      '${work.path}/sample.txt',
    ).writeAsStringSync('The cat sat on THE mat. The cat.\n');
    const expected = ['the 3', 'cat 2', 'mat 1', 'on 1', 'sat 1'];

    final full = await runCommand(['sample.txt'], work);
    transcript.writeln(_formatProcess('default top 10', full));
    final rows = const LineSplitter().convert(
      (full.stdout as String).trim().toLowerCase(),
    );
    if (full.exitCode != 0 || !_containsOrderedRows(rows, expected)) {
      diagnostics.add(
        _diagnostic(
          code: 'word_frequency_normalization_or_order_failed',
          message:
              'Counts must be case-insensitive, punctuation-stripped, and '
              'ties alphabetical.',
        ),
      );
    }

    final topTwo = await _runWithTopN(
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
        _diagnostic(
          code: 'word_frequency_top_n_failed',
          message: 'Top 2 must return exactly the two most frequent words.',
        ),
      );
    }

    final oversized = await _runWithTopN(
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
        _diagnostic(
          code: 'word_frequency_oversized_n_failed',
          message: 'N larger than the vocabulary must print all words.',
        ),
      );
    }

    File('${work.path}/empty.txt').writeAsStringSync('');
    final empty = await runCommand(['empty.txt'], work);
    transcript.writeln(_formatProcess('empty input', empty));
    if (empty.exitCode != 0) {
      diagnostics.add(
        _diagnostic(
          code: 'word_frequency_empty_input_failed',
          message: 'Empty input must exit with code 0.',
        ),
      );
    }

    final missingArgument = await runCommand(const [], work);
    transcript.writeln(_formatProcess('missing argument', missingArgument));
    if (missingArgument.exitCode == 0 ||
        '${missingArgument.stdout}${missingArgument.stderr}'.trim().isEmpty) {
      diagnostics.add(
        _diagnostic(
          code: 'word_frequency_missing_argument_failed',
          message:
              'Missing file argument must explain usage and exit non-zero.',
        ),
      );
    }

    final unreadable = await runCommand(['missing.txt'], work);
    transcript.writeln(_formatProcess('missing file', unreadable));
    if (unreadable.exitCode == 0 ||
        '${unreadable.stdout}${unreadable.stderr}'.trim().isEmpty) {
      diagnostics.add(
        _diagnostic(
          code: 'word_frequency_missing_file_failed',
          message:
              'An unreadable file must explain the error and exit non-zero.',
        ),
      );
    }

    return WordFrequencyVerificationResult(
      diagnostics: diagnostics,
      transcript: transcript.toString(),
    );
  }

  /// Copies the model's sources into a fresh directory, so leftover runtime
  /// state from earlier commands cannot make a broken build look correct.
  Directory createVerificationRoot() {
    final verificationRoot = Directory.systemTemp.createTempSync(
      'word_frequency_verification_',
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

  /// The spec does not pin how "top N" is spelled, so try the shapes a
  /// reasonable CLI might use before calling the behaviour missing.
  Future<ProcessResult> _runWithTopN(
    String path,
    int count, {
    required int expectedRows,
    required Directory work,
  }) async {
    const shapes = [
      ['%p', '%n'],
      ['%p', '--top', '%n'],
      ['--top', '%n', '%p'],
      ['%p', '-n', '%n'],
      ['-n', '%n', '%p'],
    ];
    ProcessResult? lastResult;
    for (final shape in shapes) {
      final args = shape
          .map(
            (token) => token.replaceAll('%p', path).replaceAll('%n', '$count'),
          )
          .toList(growable: false);
      final result = await runCommand(args, work);
      lastResult = result;
      final rows = const LineSplitter().convert(
        (result.stdout as String).trim(),
      );
      if (result.exitCode == 0 && rows.length == expectedRows) {
        return result;
      }
    }
    return lastResult!;
  }

  bool _containsOrderedRows(List<String> actual, List<String> expected) {
    if (actual.length < expected.length) {
      return false;
    }
    for (var index = 0; index < expected.length; index += 1) {
      if (actual[index].trim() != expected[index]) {
        return false;
      }
    }
    return true;
  }

  List<Map<String, dynamic>> _entrypointDiagnostics(
    DartCliEntrypointResolution resolution,
  ) {
    return resolution.issues
        .map(
          (issue) => _diagnostic(
            code: switch (issue.kind) {
              DartCliEntrypointIssueKind.missing =>
                'word_frequency_cli_missing',
              DartCliEntrypointIssueKind.unexpected =>
                'word_frequency_unexpected_entrypoint',
              DartCliEntrypointIssueKind.ambiguous =>
                'word_frequency_ambiguous_entrypoint',
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
