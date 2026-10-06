import 'package:caverno/features/project_farm/domain/roadmap_next_task_contract.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/farm0_next_task_extraction_spike.dart';

void main() {
  group('recommendationCorrect', () {
    ExtractedItem recommended(String id) =>
        ExtractedItem(id: id, title: '', quote: '', line: 0);

    test('scores the leading id token', () {
      expect(
        recommendationCorrect(
          expectedId: 'ANA3',
          modelRecommended: recommended('ANA3 PR 2b'),
          recommendedVerified: true,
        ),
        isTrue,
      );
      expect(
        recommendationCorrect(
          expectedId: 'PT-12',
          modelRecommended: recommended('PT-12'),
          recommendedVerified: true,
        ),
        isTrue,
      );
      expect(
        recommendationCorrect(
          expectedId: 'ANA3',
          modelRecommended: recommended('ANA4'),
          recommendedVerified: true,
        ),
        isFalse,
      );
    });

    test('requires the recommendation to be verified', () {
      expect(
        recommendationCorrect(
          expectedId: 'RC1',
          modelRecommended: recommended('RC1'),
          recommendedVerified: false,
        ),
        isFalse,
      );
    });

    test('requires abstention when the document recommends nothing', () {
      expect(
        recommendationCorrect(
          expectedId: null,
          modelRecommended: null,
          recommendedVerified: false,
        ),
        isTrue,
      );
      expect(
        recommendationCorrect(
          expectedId: null,
          modelRecommended: recommended('W3'),
          recommendedVerified: false,
        ),
        isFalse,
      );
    });
  });
}
