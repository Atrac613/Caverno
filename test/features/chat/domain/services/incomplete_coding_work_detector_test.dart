import 'package:caverno/features/chat/domain/services/incomplete_coding_work_detector.dart';
import 'package:test/test.dart';

void main() {
  const detector = IncompleteCodingWorkDetector();
  test('reports unfinished prose only as a diagnostic', () {
    expect(detector.hasIncompleteTask('The task remains incomplete.'), isTrue);
    expect(
      detector.hasIncompleteTask('Unexecuted verification command:'),
      isTrue,
    );
    expect(detector.hasIncompleteTask('The task is not incomplete.'), isFalse);
    expect(
      detector.hasIncompleteTask(
        'The task is complete; live testing is unverified.',
      ),
      isFalse,
    );
  });
  test('ignores status statements confined to thinking', () {
    expect(
      detector.hasIncompleteTask(
        '<think>The task remains incomplete.</think>The task is complete.',
      ),
      isFalse,
    );
  });
}
