import 'package:flutter_test/flutter_test.dart';

import '../../tool/canaries/support/pro_reasoning_grounded_claims_verifier.dart';

void main() {
  const verifier = ProReasoningGroundedClaimsVerifier();

  test('accepts quantities directly supported by the evidence', () {
    final unsupported = verifier.unsupportedMemoryClaims(
      evidence: 'Verified artifact size: 397 GB.',
      answer: 'The artifact is 397 GB. The runtime minimum is not specified.',
    );

    expect(unsupported, isEmpty);
  });

  test('accepts an equivalent decimal unit conversion', () {
    final unsupported = verifier.unsupportedMemoryClaims(
      evidence: 'Verified artifact size: 397 GB.',
      answer: 'The artifact is 0.397 TB.',
    );

    expect(unsupported, isEmpty);
  });

  test('reports every unsupported memory quantity regardless of value', () {
    final unsupported = verifier.unsupportedMemoryClaims(
      evidence: 'Verified artifact size: 397 GB.',
      answer: 'Plan for 420 GB, 512 GiB, or 1 TB of runtime RAM.',
    );

    expect(unsupported, ['420 GB', '512 GiB', '1 TB']);
  });

  test('normalizes separators and preserves distinct binary units', () {
    expect(
      verifier.unsupportedMemoryClaims(
        evidence: 'Capacity: 1,024 GiB.',
        answer: 'Capacity: 1 TiB.',
      ),
      isEmpty,
    );
    expect(
      verifier.unsupportedMemoryClaims(
        evidence: 'Capacity: 1 TB.',
        answer: 'Capacity: 1 TiB.',
      ),
      ['1 TiB'],
    );
  });

  test('ignores bare numbers without memory units', () {
    expect(
      verifier.memoryClaims('The model has 397 files and two variants.'),
      isEmpty,
    );
  });
}
