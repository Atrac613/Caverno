import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag2_explicit_source_roots_replay.dart';

const _fixturePath =
    'tool/fixtures/rag2_explicit_source_roots_development_v1/declaration.json';

void main() {
  test('freezes the development declaration before evaluation questions', () {
    final fixture = jsonDecode(File(_fixturePath).readAsStringSync())
        as Map<String, dynamic>;
    final roots = (fixture['sourceRoots'] as List<dynamic>).cast<String>();
    final policy = fixture['policy'] as Map<String, dynamic>;

    expect(
      fixture['declarationId'],
      'caverno-chat-memory-persistence-development-v1',
    );
    expect(fixture['contract'], rag2ExplicitSourceRootsContract);
    expect(fixture['evaluationState'], 'questions_not_created');
    expect(fixture['priorFixtureUse'], 'forbidden');
    expect(fixture.containsKey('questions'), isFalse);
    expect(fixture.containsKey('evidencePaths'), isFalse);
    expect(
      roots,
      const [
        'lib/features/chat/application/persistence',
        'lib/features/chat/data/repositories',
        'lib/features/chat/domain/entities',
        'lib/features/chat/domain/services',
        'lib/features/chat/presentation/providers',
      ],
    );
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

  test('keeps the declaration normalized, unique, and non-overlapping', () {
    final fixture = jsonDecode(File(_fixturePath).readAsStringSync())
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
