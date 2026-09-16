import 'package:caverno/features/chat/application/runtime/turn_prompt_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurnPromptClock', () {
    test('every request in a turn reads the clock the turn opened with', () {
      final clock = TurnPromptClock();
      final opened = DateTime(2026, 9, 15, 21, 48);

      final first = clock.pin(
        conversationId: 'c1',
        interactionGeneration: 15,
        now: opened,
      );
      // Session c138c465's tool loop ran for 31 minutes; the later requests used
      // to carry a fresh minute each, which reprefilled the whole prompt.
      final later = clock.pin(
        conversationId: 'c1',
        interactionGeneration: 15,
        now: opened.add(const Duration(minutes: 31)),
      );

      expect(first, opened);
      expect(later, opened);
    });

    test('a new generation repins to the clock that generation opened with', () {
      final clock = TurnPromptClock();
      final firstTurn = DateTime(2026, 9, 15, 21, 48);
      final secondTurn = DateTime(2026, 9, 15, 22, 19);

      clock.pin(
        conversationId: 'c1',
        interactionGeneration: 15,
        now: firstTurn,
      );
      final next = clock.pin(
        conversationId: 'c1',
        interactionGeneration: 16,
        now: secondTurn,
      );

      expect(next, secondTurn);
      expect(clock.pinnedCount, 1, reason: 'one pin per thread, not per turn');
    });

    test('concurrent threads keep their own pins', () {
      final clock = TurnPromptClock();
      final a = DateTime(2026, 9, 15, 21, 48);
      final b = DateTime(2026, 9, 15, 21, 52);

      clock.pin(conversationId: 'a', interactionGeneration: 3, now: a);
      clock.pin(conversationId: 'b', interactionGeneration: 1, now: b);

      expect(
        clock.pin(
          conversationId: 'a',
          interactionGeneration: 3,
          now: DateTime(2026, 9, 15, 22, 30),
        ),
        a,
        reason: "thread b's turn must not steal thread a's pin",
      );
      expect(
        clock.pin(
          conversationId: 'b',
          interactionGeneration: 1,
          now: DateTime(2026, 9, 15, 22, 30),
        ),
        b,
      );
      expect(clock.pinnedCount, 2);
    });
  });
}
