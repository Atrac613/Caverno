import 'dart:convert';
import 'dart:io';

import 'dart_cli_entrypoint_resolver.dart';

/// Behavioral acceptance checks for the markdown_toc_generator.md MVP fixture.
///
/// Lives outside the live-canary test file so the verifier the model is told to
/// run can forward to it, and so a human can re-check an artifact by hand. Like
/// the sibling verifiers it repeats a few small helpers rather than sharing a
/// base: these must stay readable and dependency-free, and a shared base would
/// couple every fixture's checks to every other fixture's edits.
class MarkdownTocVerificationResult {
  const MarkdownTocVerificationResult({
    required this.diagnostics,
    required this.transcript,
  });

  final List<Map<String, dynamic>> diagnostics;
  final String transcript;

  bool get passed => diagnostics.isEmpty;
}

class MarkdownTocBehaviorVerifier {
  const MarkdownTocBehaviorVerifier({
    required this.root,
    this.entrypointPolicy = DartCliEntrypointPolicy.fixed,
  });

  static const String canonicalEntrypoint = 'bin/markdown_toc.dart';
  static const String verifierPath = 'tool/verify_markdown_toc.dart';

  /// One document carrying every trap at once: punctuation in a label, fenced
  /// headings behind both fence styles, a repeated heading, a deeper level, and
  /// a seven-hash line that is not a heading at all.
  static const String _sampleDocument = r'''
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
''';

  static const List<String> _expectedRows = <String>[
    '- [API Reference!](#api-reference)',
    '  - [Setup](#setup)',
    '  - [Notes](#notes)',
    '  - [Notes](#notes-1)',
    '    - [Detail](#detail)',
  ];

  final Directory root;
  final DartCliEntrypointPolicy entrypointPolicy;

  Future<MarkdownTocVerificationResult> verify() async {
    final verificationRoot = createVerificationRoot();
    try {
      return await verifyIn(verificationRoot);
    } finally {
      if (verificationRoot.existsSync()) {
        verificationRoot.deleteSync(recursive: true);
      }
    }
  }

  Future<MarkdownTocVerificationResult> verifyIn(Directory work) async {
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
      return MarkdownTocVerificationResult(
        diagnostics: entrypointDiagnostics,
        transcript: '',
      );
    }

    File('${work.path}/sample.md').writeAsStringSync(_sampleDocument);
    final sample = await runCommand(['sample.md'], work);
    transcript.writeln(_formatProcess('combined Markdown traps', sample));
    final actual = const LineSplitter().convert(
      (sample.stdout as String).trim(),
    );

    if (sample.exitCode != 0) {
      diagnostics.add(
        _diagnostic(
          code: 'markdown_toc_execution_failed',
          message: 'Generating a TOC from a readable Markdown file must exit 0.',
        ),
      );
    }
    if (actual.length < 2 ||
        actual[0] != _expectedRows[0] ||
        actual[1] != _expectedRows[1]) {
      diagnostics.add(
        _diagnostic(
          code: 'markdown_toc_heading_or_slug_failed',
          message:
              'Preserve heading labels, use the shallowest heading as indent '
              '0, and normalize punctuation only in the slug.',
        ),
      );
    }

    final emittedNotes = actual.any((line) => line.contains('[Notes]'));
    if (!emittedNotes) {
      diagnostics.add(
        _diagnostic(
          code: 'markdown_toc_fence_close_failed',
          message:
              'Headings after closed backtick and tilde fences were missing. '
              'Track the opening marker and recognize its matching closing '
              'fence.',
        ),
      );
    } else {
      if (!actual.contains('  - [Notes](#notes)') ||
          !actual.contains('  - [Notes](#notes-1)')) {
        diagnostics.add(
          _diagnostic(
            code: 'markdown_toc_duplicate_slug_failed',
            message: 'Duplicate heading slugs must use -1, -2 suffixes.',
          ),
        );
      }
      if (!actual.contains('    - [Detail](#detail)')) {
        diagnostics.add(
          _diagnostic(
            code: 'markdown_toc_nesting_failed',
            message: 'Each heading level below the shallowest adds two spaces.',
          ),
        );
      }
    }
    if (actual.any((line) => line.contains('hidden'))) {
      diagnostics.add(
        _diagnostic(
          code: 'markdown_toc_fenced_heading_leaked',
          message: 'Headings inside backtick or tilde fences must be ignored.',
        ),
      );
    }
    if (actual.any((line) => line.contains('Seven hashes'))) {
      diagnostics.add(
        _diagnostic(
          code: 'markdown_toc_seven_hash_heading_failed',
          message: 'Seven or more leading hash characters are not ATX headings.',
        ),
      );
    }
    if (actual.length != _expectedRows.length) {
      diagnostics.add(
        _diagnostic(
          code: 'markdown_toc_row_count_failed',
          message:
              'The combined fixture must emit exactly five TOC rows and no '
              'extras.',
        ),
      );
    } else if (_expectedRows.every(actual.contains) &&
        !_sameRows(actual, _expectedRows)) {
      diagnostics.add(
        _diagnostic(
          code: 'markdown_toc_sequence_failed',
          message: 'TOC rows must preserve the source heading order.',
        ),
      );
    }

    File(
      '${work.path}/plain.md',
    ).writeAsStringSync('Paragraph only.\n```\n# code only\n```\n');
    final empty = await runCommand(['plain.md'], work);
    transcript.writeln(_formatProcess('no headings', empty));
    if (empty.exitCode != 0 || (empty.stdout as String).trim().isNotEmpty) {
      diagnostics.add(
        _diagnostic(
          code: 'markdown_toc_empty_document_failed',
          message: 'A document without headings must print nothing and exit 0.',
        ),
      );
    }

    return MarkdownTocVerificationResult(
      diagnostics: diagnostics,
      transcript: transcript.toString(),
    );
  }

  /// Copies the model's sources into a fresh directory, so leftover runtime
  /// state from earlier commands cannot make a broken build look correct.
  Directory createVerificationRoot() {
    final verificationRoot = Directory.systemTemp.createTempSync(
      'markdown_toc_verification_',
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

  bool _sameRows(List<String> actual, List<String> expected) {
    for (var index = 0; index < expected.length; index += 1) {
      if (actual[index] != expected[index]) {
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
              DartCliEntrypointIssueKind.missing => 'markdown_toc_cli_missing',
              DartCliEntrypointIssueKind.unexpected =>
                'markdown_toc_unexpected_entrypoint',
              DartCliEntrypointIssueKind.ambiguous =>
                'markdown_toc_ambiguous_entrypoint',
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
