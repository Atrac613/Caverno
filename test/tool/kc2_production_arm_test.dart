import 'package:flutter_test/flutter_test.dart';

import '../../tool/kc1_cutoff_exposure_census.dart';
import '../../tool/kc1_cutoff_oracle.dart';

/// KC2 slice 5: the paired re-run must measure the block production carries,
/// not the census's prototype. Defended here: production arms replace the
/// prototype arms, each carries its own block verbatim, grounding follows what
/// that block actually names, and the run records the bytes it measured.
void main() {
  CensusOptions options(List<String> extra) => CensusOptions.parse([
    '--endpoint',
    'http://scripted/v1/chat/completions',
    '--model',
    'scripted',
    '--repeats',
    '1',
    ...extra,
  ], const {})!;

  CutoffCase caseNamed(String id) =>
      cutoffCases.firstWhere((testCase) => testCase.id == id);

  test(
    'production arms replace the prototype arms and carry their block',
    () async {
      final seen = <String, String>{};
      final summary = await runCutoffCensus(
        options: options(const []),
        oracle: CutoffOracle.resolve(),
        cases: [caseNamed('color-with-values')],
        production: const {
          CensusArm.productionDefault: 'BLOCK-DEFAULT without the idiom',
          CensusArm.production64k: 'BLOCK-64K deprecates withOpacity',
        },
        send: (system, user) async {
          seen[user.split('\n').first] = user;
          return 'base.withValues(alpha: 0.5)';
        },
      );

      expect(seen.keys, [
        'BLOCK-DEFAULT without the idiom',
        'BLOCK-64K deprecates withOpacity',
      ]);
      expect(summary.claims.map((c) => c.arm), [
        CensusArm.productionDefault,
        CensusArm.production64k,
      ]);
      final byArm = {for (final c in summary.claims) c.arm: c};
      expect(
        byArm[CensusArm.productionDefault]!.grounding,
        GroundingVerdict.absent,
      );
      expect(
        byArm[CensusArm.production64k]!.grounding,
        GroundingVerdict.supported,
      );
      expect(
        (summary.runIdentity['productionBlocks'] as Map)['production64k'],
        'BLOCK-64K deprecates withOpacity',
      );
      expect(summary.productionCoverage['color-with-values'], {
        'productionDefault': false,
        'production64k': true,
      });
      final report = summary.report();
      expect(report, contains('(productionDefault / production64k)'));
      expect(report, contains('production64k:covered'));
      expect(report, isNot(contains('deltaGrounded')));
    },
  );

  test('without production blocks the prototype arms run unchanged', () async {
    final summary = await runCutoffCensus(
      options: options(const []),
      oracle: CutoffOracle.resolve(),
      cases: [caseNamed('color-with-values')],
      send: (system, user) async => 'base.withValues(alpha: 0.5)',
    );
    expect(summary.claims.map((c) => c.arm).toSet(), idiomArms.toSet());
    expect(summary.runIdentity.containsKey('productionBlocks'), isFalse);
  });

  test('--production is parsed', () {
    expect(options(const ['--production']).production, isTrue);
    expect(options(const []).production, isFalse);
    expect(
      options(const [
        '--production',
        '--arm',
        'productionVersionsOnly',
        '--arm',
        'productionDefault',
      ]).armFilter,
      {'productionVersionsOnly', 'productionDefault'},
    );
  });

  test('this repository yields a block per budget, growing with context', () {
    final blocks = productionBlocks('.');
    expect(blocks.keys, productionArmContext.keys);
    final defaultBlock = blocks[CensusArm.productionDefault]!;
    final largeBlock = blocks[CensusArm.production64k]!;
    expect(largeBlock.length, greaterThan(defaultBlock.length));
    // A named SDK deprecation is not a stable sentinel: the digest keeps the
    // newest entries, and a longer Flutter deprecation list drops older
    // symbols such as withOpacity even from the 64k arm.
    const digestHeader = 'What the installed versions changed';
    final defaultDigestAt = defaultBlock.indexOf(digestHeader);
    final largeDigestAt = largeBlock.indexOf(digestHeader);
    expect(defaultDigestAt, greaterThanOrEqualTo(0));
    expect(largeDigestAt, greaterThanOrEqualTo(0));
    expect(
      largeBlock.length - largeDigestAt,
      greaterThan(defaultBlock.length - defaultDigestAt),
      reason:
          'the 64k arm keeps a longer change digest than the default budget',
    );
    expect(
      blocks[CensusArm.productionVersionsOnly],
      isNot(contains('What the installed versions changed')),
      reason: 'the versions-only arm carries no change digest',
    );
    final imported = blocks[CensusArm.productionImported]!;
    expect(imported, contains('flutter_riverpod'));
    expect(
      RegExp(
        r'^- Dependencies: (.*)$',
        multiLine: true,
      ).firstMatch(imported)!.group(1)!.split(', ').length,
      lessThanOrEqualTo(productionImportedCount),
    );
    expect(imported, isNot(contains('What the installed versions changed')));
    expect(
      blocks[CensusArm.productionImportedDigest],
      startsWith(imported),
      reason: 'the digest arm is the same selection with the digest added',
    );
    expect(
      blocks[CensusArm.productionDefault],
      startsWith(blocks[CensusArm.productionVersionsOnly]!),
      reason: 'it is the same version list the default arm opens with',
    );
  });
}
