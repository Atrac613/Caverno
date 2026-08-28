import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_explicit_source_roots_replay.dart';

const _fixturePath =
    'tool/fixtures/rag2_explicit_source_roots_holdout_v1/declaration.json';

void main() {
  test('freezes the promotion holdout declaration before questions', () {
    final fixture =
        jsonDecode(File(_fixturePath).readAsStringSync())
            as Map<String, dynamic>;
    final roots = (fixture['sourceRoots'] as List<dynamic>).cast<String>();
    final policy = fixture['policy'] as Map<String, dynamic>;

    expect(
      fixture['declarationId'],
      'caverno-routines-lifecycle-promotion-holdout-v1',
    );
    expect(fixture['contract'], rag2ExplicitSourceRootsContract);
    expect(fixture['evaluationState'], 'questions_not_created');
    expect(fixture['priorFixtureUse'], 'forbidden');
    expect(fixture['scopeDecision'], 'promotion_holdout_declaration_only');
    expect(fixture['productionDecision'], 'no_go');
    expect(fixture.containsKey('questions'), isFalse);
    expect(fixture.containsKey('evidencePaths'), isFalse);
    expect(roots, const [
      'lib/features/routines/data',
      'lib/features/routines/domain',
      'lib/features/routines/presentation/providers',
    ]);
    expect(policy['maxSourceRoots'], rag2ExplicitSourceRootsMaxRoots);
    expect(policy['maxFiles'], rag2ExplicitSourceRootsPolicy.maxFiles);
    expect(policy['maxFileBytes'], rag2ExplicitSourceRootsPolicy.maxFileBytes);
    expect(
      policy['maxCorpusBytes'],
      rag2ExplicitSourceRootsPolicy.maxCorpusBytes,
    );

    final sortedRoots = List<String>.from(roots)..sort();
    final identityInput =
        '$rag2ExplicitSourceRootsContract\u0000${sortedRoots.join('\u0000')}';
    expect(
      fixture['declarationIdentity'],
      'declaration_${sha256.convert(utf8.encode(identityInput))}',
    );
  });

  test('keeps holdout roots normalized, unique, and non-overlapping', () {
    final fixture =
        jsonDecode(File(_fixturePath).readAsStringSync())
            as Map<String, dynamic>;
    final roots = (fixture['sourceRoots'] as List<dynamic>).cast<String>();

    expect(roots, hasLength(roots.toSet().length));
    expect(roots.length, lessThanOrEqualTo(rag2ExplicitSourceRootsMaxRoots));
    for (final root in roots) {
      expect(root, isNot(startsWith('/')));
      expect(root.split('/'), isNot(contains(anyOf('', '.', '..'))));
      for (final other in roots) {
        if (root == other) continue;
        expect(other.startsWith('$root/'), isFalse);
      }
    }
  });
}
