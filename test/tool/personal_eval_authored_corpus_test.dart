import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the authored fixture corpus (Task 3, hybrid corpus strategy).
///
/// The structural checks always run. The seeded-defect checks need a Dart SDK
/// to spawn, so they skip rather than fail when one is not resolvable — but
/// they are the important ones: a "task" whose seed does not actually break the
/// verifier is already solved, and would silently inflate a model's score.
void main() {
  // Parsed at registration time, not in setUpAll: the per-seed tests are
  // generated from the real task count, so a corpus of three tasks registers
  // three seed tests. Padding to a fixed count would register tests that pass
  // without checking anything.
  final corpus =
      jsonDecode(
            File('tool/personal_eval_corpus/corpus.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final tasks = (corpus['tasks'] as List).cast<Map<String, dynamic>>().toList(
    growable: false,
  );

  test('declares its schema and its authored provenance', () {
    expect(corpus['schemaName'], 'caverno_personal_eval_authored_corpus');
    expect(corpus['schemaVersion'], 1);
    // The corpus must say what it is not: general coding capability, not this
    // user's own work.
    expect(corpus['note'], contains('origin=authored'));
    expect(
      (corpus['replay'] as Map<String, dynamic>)['isolation'],
      contains('temporary working directory'),
    );
  });

  test('every task is complete and uniquely identified', () {
    expect(tasks, isNotEmpty);
    final ids = <String>{};
    for (final task in tasks) {
      final id = task['caseId'] as String;
      expect(ids.add(id), isTrue, reason: 'duplicate caseId $id');
      expect((task['prompt'] as String).trim(), isNotEmpty, reason: id);
      expect((task['title'] as String).trim(), isNotEmpty, reason: id);
      expect(
        (task['verificationCommand'] as String).trim(),
        isNotEmpty,
        reason: id,
      );
      expect(['heldIn', 'heldOut'], contains(task['split']), reason: id);
      expect(
        Directory(task['fixtureDirectory'] as String).existsSync(),
        isTrue,
        reason: 'missing fixture for $id',
      );
    }
  });

  test('every task ships a seed that changes the fixture', () {
    for (final task in tasks) {
      final id = task['caseId'] as String;
      final seedDir = Directory(
        '${task['fixtureDirectory']}/${(corpus['replay'] as Map)['seedRoot']}/$id',
      );
      expect(seedDir.existsSync(), isTrue, reason: 'missing seed for $id');

      final seededFiles = seedDir
          .listSync(recursive: true)
          .whereType<File>()
          .toList(growable: false);
      expect(seededFiles, isNotEmpty, reason: 'empty seed for $id');

      for (final seeded in seededFiles) {
        final relative = seeded.path.substring(seedDir.path.length + 1);
        final original = File('${task['fixtureDirectory']}/$relative');
        expect(
          original.existsSync(),
          isTrue,
          reason: '$id seeds $relative, which does not exist in the fixture',
        );
        expect(
          seeded.readAsStringSync(),
          isNot(original.readAsStringSync()),
          reason: '$id seeds $relative with identical content',
        );
      }
    }
  });

  test('both splits are represented', () {
    final splits = tasks.map((task) => task['split']).toSet();
    expect(splits, containsAll(<String>['heldIn', 'heldOut']));
  });

  test('new reconstruction tasks are held-out and objective-distinct', () {
    const expected = {
      'authored_datekit_rebuild_parse': (
        tier: 2,
        objective: 'duration.parse.tokenized_units',
      ),
      'authored_textkit_rebuild_slug': (
        tier: 2,
        objective: 'text.slug.normalization_pipeline',
      ),
      'authored_taskflow_rebuild_state_and_budget': (
        tier: 3,
        objective: 'taskflow.state_graph_and_retry_budget',
      ),
    };
    final objectives = <String>{};
    for (final entry in expected.entries) {
      final task = tasks.singleWhere(
        (candidate) => candidate['caseId'] == entry.key,
      );
      expect(task['split'], 'heldOut', reason: entry.key);
      expect(task['tier'], entry.value.tier, reason: entry.key);
      expect(task['promptStyle'], 'unguided', reason: entry.key);
      expect(
        task['objectiveFingerprint'],
        entry.value.objective,
        reason: entry.key,
      );
      expect(
        objectives.add(task['objectiveFingerprint'] as String),
        isTrue,
        reason: '${entry.key} duplicates an objective',
      );
    }
  });

  test('every reconstruction objective is declared and unique', () {
    final objectives = <String>{};
    for (final task in tasks.where((task) => (task['tier'] as int) >= 2)) {
      final objective = task['objectiveFingerprint'];
      expect(objective, isA<String>(), reason: task['caseId'] as String);
      expect((objective as String).trim(), isNotEmpty);
      expect(
        objectives.add(objective),
        isTrue,
        reason: '${task['caseId']} duplicates $objective',
      );
    }
  });

  group('seeded defects', () {
    final dart = _resolveDart();

    test(
      'the committed fixture passes its own verifier',
      () {
        final fixture = tasks.first['fixtureDirectory'] as String;
        final result = _runVerifier(dart!, fixture, seedDirectory: null);
        expect(
          result.exitCode,
          0,
          reason:
              'The corpus must be committed green so a seed is the only defect.\n'
              '${result.stdout}\n${result.stderr}',
        );
      },
      skip: dart == null ? 'No Dart SDK on PATH' : false,
    );

    for (final task in tasks) {
      final id = task['caseId'] as String;
      test(
        'seed $id breaks the verifier',
        () {
          final fixture = task['fixtureDirectory'] as String;
          final seedRoot = (corpus['replay'] as Map)['seedRoot'];
          final result = _runVerifier(
            dart!,
            fixture,
            seedDirectory: '$fixture/$seedRoot/$id',
          );
          expect(
            result.exitCode,
            isNot(0),
            reason:
                'Seed $id left the verifier passing, so the task is already '
                'solved and would inflate any score built on it.',
          );
        },
        skip: dart == null ? 'No Dart SDK on PATH' : false,
      );
    }
  });
}

String? _resolveDart() {
  final which = Process.runSync('which', ['dart']);
  if (which.exitCode != 0) {
    return null;
  }
  final path = (which.stdout as String).trim();
  return path.isEmpty ? null : path;
}

/// Copies [fixture] into a temp directory, optionally overlays [seedDirectory],
/// and runs the fixture verifier there. Never runs in the repository tree.
ProcessResult _runVerifier(
  String dart,
  String fixture, {
  required String? seedDirectory,
}) {
  final work = Directory.systemTemp.createTempSync('caverno_authored_corpus_');
  addTearDown(() => work.deleteSync(recursive: true));
  _copyTree(Directory(fixture), work, skipDirectoryNames: const {'seeds'});
  if (seedDirectory != null) {
    _copyTree(Directory(seedDirectory), work);
  }
  return Process.runSync(dart, [
    'run',
    'bin/verify.dart',
  ], workingDirectory: work.path);
}

void _copyTree(
  Directory from,
  Directory to, {
  Set<String> skipDirectoryNames = const {},
}) {
  for (final entity in from.listSync()) {
    final name = entity.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (entity is Directory) {
      if (skipDirectoryNames.contains(name)) {
        continue;
      }
      final target = Directory('${to.path}/$name')..createSync();
      _copyTree(entity, target, skipDirectoryNames: skipDirectoryNames);
    } else if (entity is File) {
      entity.copySync('${to.path}/$name');
    }
  }
}
