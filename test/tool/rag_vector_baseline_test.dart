import 'package:flutter_test/flutter_test.dart';

import '../../tool/rag_vector_baseline.dart';

void main() {
  test('ranks vectors by cosine similarity with stable ties', () {
    expect(
      rankRagVectors(
        [1, 0],
        [
          [0, 1],
          [1, 0],
          [0.5, 0.5],
        ],
        limit: 3,
      ),
      [1, 2, 0],
    );
  });

  test('fuses lexical and vector ranks deterministically', () {
    expect(fuseRagRanks(['a', 'b'], ['b', 'c'], limit: 3), ['b', 'a', 'c']);
  });
}
