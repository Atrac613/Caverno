import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = FlutterTestFailureSetOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/flutter_test_failure_set.dart '
      '--base PATH --candidate PATH',
    );
    exitCode = 64;
    return;
  }
  final baseFile = File(options.basePath);
  final candidateFile = File(options.candidatePath);
  if (!baseFile.existsSync() || !candidateFile.existsSync()) {
    stderr.writeln('Both Flutter JSON logs must exist.');
    exitCode = 66;
    return;
  }
  final comparison = compareFlutterTestFailureSets(
    parseFlutterTestFailureSet(await baseFile.readAsString()),
    parseFlutterTestFailureSet(await candidateFile.readAsString()),
  );
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(comparison.toJson()),
  );
  if (!comparison.isComplete) {
    exitCode = 2;
  } else if (comparison.candidateOnly.isNotEmpty) {
    exitCode = 1;
  }
}

final class FlutterTestFailureSetOptions {
  const FlutterTestFailureSetOptions({
    required this.basePath,
    required this.candidatePath,
  });

  final String basePath;
  final String candidatePath;

  static FlutterTestFailureSetOptions? parse(List<String> args) {
    String? basePath;
    String? candidatePath;
    for (var index = 0; index < args.length; index += 1) {
      switch (args[index]) {
        case '--base':
          if (++index >= args.length) return null;
          basePath = args[index];
          break;
        case '--candidate':
          if (++index >= args.length) return null;
          candidatePath = args[index];
          break;
        default:
          return null;
      }
    }
    if (basePath == null || candidatePath == null) return null;
    return FlutterTestFailureSetOptions(
      basePath: basePath,
      candidatePath: candidatePath,
    );
  }
}

final class FlutterTestFailureSet {
  const FlutterTestFailureSet({
    required this.failures,
    required this.doneSeen,
    required this.runnerSuccess,
    required this.malformedLineCount,
  });

  final Set<String> failures;
  final bool doneSeen;
  final bool? runnerSuccess;
  final int malformedLineCount;

  bool get isComplete => doneSeen && runnerSuccess != null;
}

final class FlutterTestFailureSetComparison {
  const FlutterTestFailureSetComparison({
    required this.base,
    required this.candidate,
    required this.shared,
    required this.baseOnly,
    required this.candidateOnly,
  });

  final FlutterTestFailureSet base;
  final FlutterTestFailureSet candidate;
  final List<String> shared;
  final List<String> baseOnly;
  final List<String> candidateOnly;

  bool get isComplete => base.isComplete && candidate.isComplete;

  Map<String, Object?> toJson() => {
    'schemaName': 'caverno_flutter_test_failure_set_comparison',
    'schemaVersion': 1,
    'complete': isComplete,
    'base': _runJson(base),
    'candidate': _runJson(candidate),
    'sharedFailures': shared,
    'baseOnlyFailures': baseOnly,
    'candidateOnlyFailures': candidateOnly,
  };

  Map<String, Object?> _runJson(FlutterTestFailureSet run) => {
    'doneSeen': run.doneSeen,
    'runnerSuccess': run.runnerSuccess,
    'failureCount': run.failures.length,
    'malformedLineCount': run.malformedLineCount,
  };
}

FlutterTestFailureSet parseFlutterTestFailureSet(String rawLog) {
  final suites = <int, String>{};
  final tests = <int, ({String name, int? suiteId, String? url})>{};
  final failures = <String>{};
  var doneSeen = false;
  bool? runnerSuccess;
  var malformedLineCount = 0;
  for (final line in const LineSplitter().convert(rawLog)) {
    if (line.trim().isEmpty) continue;
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      malformedLineCount += 1;
      continue;
    }
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>?;
        final id = (suite?['id'] as num?)?.toInt();
        final path = suite?['path'] as String?;
        if (id != null && path != null) suites[id] = _normalizeTestPath(path);
        break;
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>?;
        final id = (test?['id'] as num?)?.toInt();
        final name = test?['name'] as String?;
        if (id != null && name != null) {
          tests[id] = (
            name: _normalizeLoadingName(name),
            suiteId: (test?['suiteID'] as num?)?.toInt(),
            url: test?['url'] as String?,
          );
        }
        break;
      case 'testDone':
        if (event['result'] != 'failure') break;
        final id = (event['testID'] as num?)?.toInt();
        final test = id == null ? null : tests[id];
        if (test == null) break;
        final path = test.url == null
            ? suites[test.suiteId]
            : _normalizeTestPath(Uri.parse(test.url!).toFilePath());
        failures.add('${path ?? 'unknown'}::${test.name}');
        break;
      case 'done':
        doneSeen = true;
        runnerSuccess = event['success'] as bool?;
        break;
    }
  }
  return FlutterTestFailureSet(
    failures: Set<String>.unmodifiable(failures),
    doneSeen: doneSeen,
    runnerSuccess: runnerSuccess,
    malformedLineCount: malformedLineCount,
  );
}

FlutterTestFailureSetComparison compareFlutterTestFailureSets(
  FlutterTestFailureSet base,
  FlutterTestFailureSet candidate,
) {
  List<String> sorted(Iterable<String> values) => values.toList()..sort();
  return FlutterTestFailureSetComparison(
    base: base,
    candidate: candidate,
    shared: sorted(base.failures.intersection(candidate.failures)),
    baseOnly: sorted(base.failures.difference(candidate.failures)),
    candidateOnly: sorted(candidate.failures.difference(base.failures)),
  );
}

String _normalizeTestPath(String rawPath) {
  final normalized = rawPath.replaceAll('\\', '/');
  final marker = normalized.lastIndexOf('/test/');
  return marker < 0 ? normalized : normalized.substring(marker + 1);
}

String _normalizeLoadingName(String name) {
  if (!name.startsWith('loading ')) return name;
  return 'loading ${_normalizeTestPath(name.substring('loading '.length))}';
}
