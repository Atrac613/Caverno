import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/research_followup_detector.dart';

void main() {
  const detector = ResearchFollowupDetector();

  // Japanese fixtures built from code units to keep the test source ASCII.
  String jp(List<int> units) => String.fromCharCodes(units);
  // "RTX 3090の中古価格を調べます" (I'll look up the used RTX 3090 price)
  final jaLookup =
      'RTX 3090'
      '${jp(const [0x306e, 0x4e2d, 0x53e4, 0x4fa1, 0x683c, 0x3092, 0x8abf, 0x3079, 0x307e, 0x3059])}';
  // "実行しますか" (shall I run it?)
  final jaConfirm = jp(const [0x5b9f, 0x884c, 0x3057, 0x307e, 0x3059, 0x304b]);

  group('ResearchFollowupDetector', () {
    test('fires on an English lookup announcement', () {
      expect(
        detector.looksLikeUnactionedResearch(
          "I'll look up the current used RTX 3090 prices for you.",
        ),
        isTrue,
      );
    });

    test('fires on a Japanese lookup announcement', () {
      expect(detector.looksLikeUnactionedResearch(jaLookup), isTrue);
    });

    test('does not fire when the response asks for confirmation (JA)', () {
      // Announces a lookup but also asks "shall I?" — a deliberate pause.
      expect(
        detector.looksLikeUnactionedResearch('$jaLookup $jaConfirm'),
        isFalse,
      );
    });

    test('does not fire when the response asks for confirmation (EN)', () {
      expect(
        detector.looksLikeUnactionedResearch(
          "I'll look up the price. Shall I proceed?",
        ),
        isFalse,
      );
    });

    test('does not fire on plain prose without lookup intent', () {
      expect(
        detector.looksLikeUnactionedResearch(
          'The RTX 4060 Ti 16GB is generally the most affordable option.',
        ),
        isFalse,
      );
    });

    test('does not fire on empty or very long text', () {
      expect(detector.looksLikeUnactionedResearch(''), isFalse);
      expect(
        detector.looksLikeUnactionedResearch("I'll search. ${'x' * 1700}"),
        isFalse,
      );
    });
  });
}
