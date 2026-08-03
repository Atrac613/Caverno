// Shared entrypoint body for the generated MVP fixture verifiers.
//
// This lives outside the project the model edits, and the generated in-project
// script forwards to it. That placement is the point: a model that reads its
// own verifier — a reasonable thing to do — must not learn that early outcomes
// can be staged, or where the staging and the run log are kept. A live run on
// 2026-08-03 (`f0b830ce`) showed the cost of the previous arrangement: the
// model read the in-project verifier, then spent its remaining tool budget
// hunting for the support library named in its imports instead of re-running
// verification, and the turn ended on an exhausted loop.
//
// Only `dart:` libraries may be used here, because the generated script imports
// this file by absolute URI and has no package resolution of its own.
import 'dart:convert';
import 'dart:io';

/// Diagnostics plus the human-readable transcript of one verification run.
typedef FixtureVerificationOutcome = (List<Map<String, dynamic>>, String);

String _stateKey(Directory root) =>
    root.absolute.path.hashCode.toUnsigned(32).toRadixString(16);

/// Where a scenario stages the first verifier outcomes it needs.
///
/// Deliberately outside the project. An earlier version put this in the project
/// root and explained the mechanism in the generated verifier's own doc comment,
/// which the model read.
String fixtureStagedOutcomesPath(Directory root) =>
    '${Directory.systemTemp.path}/caverno_verifier_script_${_stateKey(root)}'
    '.jsonl';

/// Where each verifier run is recorded, oldest first.
///
/// Also outside the project. This is the canary's ground truth — what a run
/// reported, written where no tool-routing decision can hide it — so the model
/// must not be able to read or edit it, and it must not appear in a directory
/// listing of the workspace.
String fixtureVerificationLogPath(Directory root) =>
    '${Directory.systemTemp.path}/caverno_verifier_runs_${_stateKey(root)}'
    '.jsonl';

List<Map<String, dynamic>> _stagedOutcomes(Directory root) {
  final script = File(fixtureStagedOutcomesPath(root));
  if (!script.existsSync()) {
    return const [];
  }
  return script
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .map((line) => jsonDecode(line) as Map<String, dynamic>)
      .toList(growable: false);
}

int _priorRunCount(Directory root) {
  final log = File(fixtureVerificationLogPath(root));
  if (!log.existsSync()) {
    return 0;
  }
  return log.readAsLinesSync().where((line) => line.trim().isNotEmpty).length;
}

/// Runs [verify] unless this run is still covered by a staged outcome, records
/// the result, and reports it the way Caverno can read.
Future<void> runFixtureVerification({
  required Directory root,
  required Future<FixtureVerificationOutcome> Function() verify,
}) async {
  final staged = _stagedOutcomes(root);
  final runIndex = _priorRunCount(root);

  List<Map<String, dynamic>> diagnostics;
  String transcript;
  String failureStderr;
  if (runIndex < staged.length) {
    final outcome = staged[runIndex];
    diagnostics = (outcome['diagnostics'] as List).cast<Map<String, dynamic>>();
    transcript = (outcome['stdout'] as String?) ?? '';
    failureStderr =
        (outcome['stderr'] as String?) ?? 'Verifier reported a problem.';
  } else {
    final result = await verify();
    diagnostics = result.$1;
    transcript = result.$2;
    failureStderr = 'Fixture acceptance criteria failed.';
  }

  File(fixtureVerificationLogPath(root)).writeAsStringSync(
    '${jsonEncode({'at': DateTime.now().toIso8601String(), 'exit_code': diagnostics.isEmpty ? 0 : 1, 'diagnostic_count': diagnostics.length, 'scripted': runIndex < staged.length, 'diagnostics': diagnostics})}\n',
    mode: FileMode.append,
  );

  stdout.write(transcript);
  if (diagnostics.isEmpty) {
    stdout.writeln('All acceptance criteria passed.');
    return;
  }
  // Also emit each diagnostic in `dart analyze --format=machine` syntax.
  // Caverno reads diagnostics off a failing command by parsing that syntax out
  // of its output, and a JSON array parses to nothing -- a verifier that only
  // pretty-prints is legible to a human and invisible to the harness.
  for (final diagnostic in diagnostics) {
    stdout.writeln(
      [
        (diagnostic['severity'] ?? 'Error').toString().toUpperCase(),
        'COMPILE_TIME_ERROR',
        diagnostic['code'] ?? 'verifier_failure',
        diagnostic['path'] ?? diagnostic['relative_path'] ?? '',
        diagnostic['line'] ?? 1,
        diagnostic['column'] ?? 1,
        1,
        (diagnostic['message'] ?? '').toString().replaceAll('|', '/'),
      ].join('|'),
    );
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(diagnostics));
  stderr.writeln(failureStderr);
  exitCode = 1;
}
