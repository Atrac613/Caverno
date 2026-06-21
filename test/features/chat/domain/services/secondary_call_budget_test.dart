import 'package:caverno/features/chat/domain/services/secondary_call_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecondaryCallBudget.resolve', () {
    test('caps a high user maxTokens at the ceiling', () {
      expect(SecondaryCallBudget.resolve(8192, 1200), 1200);
    });

    test('passes through a value between floor and ceiling', () {
      expect(SecondaryCallBudget.resolve(900, 1200), 900);
    });

    test('floors a low user maxTokens so the call is not starved', () {
      // Regression: a real session set chat maxTokens=64, which truncated the
      // memory-extraction JSON into invalid output. The floor prevents that.
      expect(SecondaryCallBudget.resolve(64, 1200), 512);
    });

    test('uses the default floor of 512', () {
      expect(SecondaryCallBudget.resolve(0, 1200), 512);
      expect(SecondaryCallBudget.resolve(511, 1200), 512);
      expect(SecondaryCallBudget.resolve(512, 1200), 512);
      expect(SecondaryCallBudget.resolve(513, 1200), 513);
    });

    test('never returns more than the ceiling even when the floor exceeds it',
        () {
      // A small ceiling must win over the default floor.
      expect(SecondaryCallBudget.resolve(64, 200), 200);
      expect(SecondaryCallBudget.resolve(8192, 200), 200);
    });

    test('honors an explicit floor', () {
      expect(SecondaryCallBudget.resolve(64, 1200, floor: 256), 256);
      expect(SecondaryCallBudget.resolve(64, 1200, floor: 800), 800);
    });
  });
}
