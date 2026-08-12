import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_authored_corpus.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_authored_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end shape of an authored replay, minus the model: load the committed
/// corpus, materialize an isolated workspace, confirm the seeded defect is
/// really there, then confirm a correct edit turns the verifier green.
///
/// That is the whole measurement loop. Plugging a candidate model in replaces
/// the "write the known-good source" step and nothing else.
void main() {
  final repositoryRoot = Directory.current.path;
  final corpus = PersonalEvalAuthoredCorpus.parse(
    File('tool/personal_eval_corpus/corpus.json').readAsStringSync(),
  );
  final dart = _resolveDart();

  test('loads every task as an authored, runnable case', () {
    expect(corpus.cases, isNotEmpty);
    for (final evalCase in corpus.cases) {
      expect(evalCase.origin, PersonalEvalCaseOrigin.authored);
      expect(evalCase.readiness, PersonalEvalCaseReadiness.ready);
      expect(evalCase.excludedFromExport, isFalse);
      expect(evalCase.normalizedRepoStateRef, isEmpty);
      expect(evalCase.classifiedTier, isNotNull);
      expect(evalCase.hasClassifiedPromptStyle, isTrue);
    }
    expect(corpus.heldIn, isNotEmpty);
    expect(corpus.heldOut, isNotEmpty);
    expect(
      corpus.heldIn.length + corpus.heldOut.length,
      corpus.cases.length,
      reason: 'every case belongs to exactly one split',
    );
  });

  test('refuses a recorded case', () {
    const recorded = PersonalEvalCase(
      caseId: 'recorded-1',
      prompt: 'p',
      repoStateRef: 'abc',
    );
    expect(
      () => PersonalEvalAuthoredWorkspace.prepare(
        evalCase: recorded,
        repositoryRoot: repositoryRoot,
      ),
      throwsArgumentError,
    );
  });

  test('refuses a case whose seed is missing', () {
    final unseeded = corpus.cases.first.copyWith(caseId: 'no_such_seed');
    expect(
      () => PersonalEvalAuthoredWorkspace.prepare(
        evalCase: unseeded,
        repositoryRoot: repositoryRoot,
        seedRoot: corpus.seedRoot,
      ),
      throwsStateError,
      reason: 'an unseeded workspace would score a task that was never broken',
    );
  });

  test('rejects an unknown corpus split instead of exposing it as held-in', () {
    final source = File(
      'tool/personal_eval_corpus/corpus.json',
    ).readAsStringSync().replaceFirst('"heldOut"', '"held_out"');

    expect(
      () => PersonalEvalAuthoredCorpus.parse(source),
      throwsFormatException,
    );
  });

  test('rejects invalid difficulty metadata', () {
    final source = File(
      'tool/personal_eval_corpus/corpus.json',
    ).readAsStringSync();

    expect(
      () => PersonalEvalAuthoredCorpus.parse(
        source.replaceFirst('"tier": 1', '"tier": 4'),
      ),
      throwsFormatException,
    );
    expect(
      () => PersonalEvalAuthoredCorpus.parse(
        source.replaceFirst(
          '"promptStyle": "guided"',
          '"promptStyle": "brief"',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => PersonalEvalAuthoredCorpus.parse(
        source.replaceFirst(
          '"objectiveFingerprint": "money.split.remainder_distribution",',
          '"objectiveFingerprint": "",',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => PersonalEvalAuthoredCorpus.parse(
        source.replaceFirst(
          '"objectiveFingerprint": "stats.rank.score_and_label_order",',
          '"objectiveFingerprint": "money.split.remainder_distribution",',
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects a corpus task without a verification command', () {
    final source = File('tool/personal_eval_corpus/corpus.json')
        .readAsStringSync()
        .replaceFirst(
          '"verificationCommand": "dart run bin/verify.dart",',
          '"verificationCommand": "",',
        );

    expect(
      () => PersonalEvalAuthoredCorpus.parse(source),
      throwsFormatException,
    );
  });

  test(
    'materializes outside the repository and withholds other answer keys',
    () {
      final evalCase = corpus.cases.first;
      final workspace = PersonalEvalAuthoredWorkspace.prepare(
        evalCase: evalCase,
        repositoryRoot: repositoryRoot,
        seedRoot: corpus.seedRoot,
      );
      addTearDown(workspace.dispose);

      expect(
        workspace.path.startsWith(repositoryRoot),
        isFalse,
        reason: 'a replay must never be handed the repository tree',
      );
      expect(File('${workspace.path}/bin/verify.dart').existsSync(), isTrue);
      expect(
        Directory('${workspace.path}/${corpus.seedRoot}').existsSync(),
        isFalse,
        reason: 'copying the seed tree would hand the model every answer key',
      );

      workspace.dispose();
      expect(Directory(workspace.path).existsSync(), isFalse);
    },
  );

  group('tier 3 is genuinely multi-site', () {
    final tierThree = corpus.cases
        .where((evalCase) {
          final raw = File(
            'tool/personal_eval_corpus/corpus.json',
          ).readAsStringSync();
          final tasks =
              (jsonDecode(raw) as Map<String, dynamic>)['tasks'] as List;
          final task = tasks.cast<Map<String, dynamic>>().firstWhere(
            (item) => item['caseId'] == evalCase.caseId,
          );
          return task['tier'] == 3;
        })
        .toList(growable: false);

    test('the corpus declares some', () {
      expect(tierThree, isNotEmpty);
    });

    for (final evalCase in tierThree) {
      test(
        '${evalCase.caseId}: repairing one file leaves it red',
        () {
          final fixture =
              '$repositoryRoot/${evalCase.normalizedFixtureDirectory}';
          final seedDir = Directory(
            '$fixture/${corpus.seedRoot}/${evalCase.caseId}',
          );
          final seeded = seedDir
              .listSync(recursive: true)
              .whereType<File>()
              .toList(growable: false);
          expect(
            seeded.length,
            greaterThan(1),
            reason: 'tier 3 must span more than one file to be checkable',
          );

          // The defining property: fixing the first symptom is not enough. A
          // "tier 3" whose partial repair already passes is a tier 1 task
          // wearing the wrong label, and would quietly stop discriminating.
          for (final restore in seeded) {
            final workspace = PersonalEvalAuthoredWorkspace.prepare(
              evalCase: evalCase,
              repositoryRoot: repositoryRoot,
              seedRoot: corpus.seedRoot,
            );
            addTearDown(workspace.dispose);
            final relative = restore.path.substring(seedDir.path.length + 1);
            File('$fixture/$relative').copySync('${workspace.path}/$relative');

            final partial = Process.runSync(dart!, [
              'run',
              'bin/verify.dart',
            ], workingDirectory: workspace.path);
            expect(
              partial.exitCode,
              isNot(0),
              reason:
                  'restoring only $relative made ${evalCase.caseId} pass, so it '
                  'is not multi-site',
            );
            workspace.dispose();
          }
        },
        skip: dart == null ? 'No Dart SDK on PATH' : false,
      );
    }
  });

  group('measurement loop', () {
    for (final evalCase in corpus.cases) {
      test(
        '${evalCase.caseId}: fails seeded, passes once fixed',
        () {
          final workspace = PersonalEvalAuthoredWorkspace.prepare(
            evalCase: evalCase,
            repositoryRoot: repositoryRoot,
            seedRoot: corpus.seedRoot,
          );
          addTearDown(workspace.dispose);

          final seeded = Process.runSync(dart!, [
            'run',
            'bin/verify.dart',
          ], workingDirectory: workspace.path);
          expect(
            seeded.exitCode,
            isNot(0),
            reason: 'the seeded workspace must start red',
          );

          // Stand in for a model that solves the task: restore the committed
          // sources. The verifier has to be able to say "green" too, or a run
          // could never score a success.
          _copyCommittedSources(
            fixture: '$repositoryRoot/${evalCase.normalizedFixtureDirectory}',
            into: workspace.path,
          );
          final fixed = Process.runSync(dart, [
            'run',
            'bin/verify.dart',
          ], workingDirectory: workspace.path);
          expect(
            fixed.exitCode,
            0,
            reason: 'a correct fix must be observable\n${fixed.stderr}',
          );
        },
        skip: dart == null ? 'No Dart SDK on PATH' : false,
      );

      test(
        '${evalCase.caseId}: the seeded workspace still analyzes clean',
        () {
          final workspace = PersonalEvalAuthoredWorkspace.prepare(
            evalCase: evalCase,
            repositoryRoot: repositoryRoot,
            seedRoot: corpus.seedRoot,
          );
          addTearDown(workspace.dispose);

          final analyzed = Process.runSync(dart!, [
            'analyze',
          ], workingDirectory: workspace.path);

          // Two failures hide here, and the red/green check cannot see either.
          // A seed that leaves dead code tells an analyzing model exactly what
          // went missing. A seed that has gone stale against a grown fixture
          // deletes unrelated code, so the workspace fails to compile -- which
          // still reads as "red, then green" while measuring the wrong defect.
          expect(
            analyzed.exitCode,
            0,
            reason:
                'Seeded workspace for ${evalCase.caseId} does not analyze '
                'clean:\n${analyzed.stdout}',
          );
        },
        skip: dart == null ? 'No Dart SDK on PATH' : false,
      );
    }
  });
}

void _copyCommittedSources({required String fixture, required String into}) {
  for (final file in Directory('$fixture/src').listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    file.copySync('$into/src/$name');
  }
}

String? _resolveDart() {
  final which = Process.runSync('which', ['dart']);
  if (which.exitCode != 0) {
    return null;
  }
  final path = (which.stdout as String).trim();
  return path.isEmpty ? null : path;
}
