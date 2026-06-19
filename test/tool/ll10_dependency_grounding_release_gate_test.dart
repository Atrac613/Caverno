import 'package:flutter_test/flutter_test.dart';

import '../../tool/ll10_dependency_grounding_release_gate.dart';

void main() {
  test('passes deterministic LL10 dependency grounding evidence', () async {
    final result = await buildLl10DependencyGroundingReleaseGate(
      generatedAt: DateTime.utc(2026, 6, 19),
    );

    expect(result.status, 'ready_for_ll10_release');
    expect(result.isReady, isTrue);
    expect(result.blockedGateIds, isEmpty);
    expect(
      result.toJson()['schemaName'],
      'll10_dependency_grounding_release_gate',
    );
    expect(
      result.gates.map((gate) => gate.id),
      containsAll([
        'dart_lockfile_exact_source',
        'dart_symbol_only_resolution',
        'newer_upstream_symbol_not_claimed',
        'node_lockfile_exact_source',
        'python_lockfile_exact_source',
        'vendored_source_resolution',
        'offline_missing_package_blocks',
        'coding_prompt_guidance',
      ]),
    );
    expect(
      result.toMarkdown(),
      contains('LL10 Dependency Grounding Release Gate'),
    );
    expect(result.toMarkdown(), contains('ready_for_ll10_release'));
  });

  test('parses report output options', () {
    final options = Ll10DependencyGroundingGateOptions.parse(const [
      '--out-json',
      'gate.json',
      '--out-md',
      'gate.md',
    ]);

    expect(options.showHelp, isFalse);
    expect(options.outJsonPath, 'gate.json');
    expect(options.outMarkdownPath, 'gate.md');
  });

  test('rejects unknown options', () {
    expect(
      () => Ll10DependencyGroundingGateOptions.parse(const ['--unknown']),
      throwsFormatException,
    );
  });
}
