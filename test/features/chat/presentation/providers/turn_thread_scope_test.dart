import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/turn_thread_scope.dart';

void main() {
  test('TurnThread preserves and restores exact nested owners', () async {
    expect(TurnThread.currentId, isNull);

    await TurnThread.runScoped('thread-a', () async {
      expect(TurnThread.currentId, 'thread-a');
      await Future<void>.delayed(Duration.zero);
      expect(TurnThread.currentId, 'thread-a');

      await TurnThread.runScoped('thread-b', () async {
        expect(TurnThread.currentId, 'thread-b');
        await Future<void>.delayed(Duration.zero);
        expect(TurnThread.currentId, 'thread-b');
      });

      expect(TurnThread.currentId, 'thread-a');
    });

    expect(TurnThread.currentId, isNull);
  });

  test('TurnThread leaves missing owners unscoped', () {
    expect(TurnThread.runScoped(null, () => TurnThread.currentId), isNull);
    expect(TurnThread.runScoped('', () => TurnThread.currentId), isNull);
  });

  test('TurnGeneration preserves and restores exact nested owners', () async {
    expect(TurnGeneration.current, isNull);

    await TurnGeneration.runScoped(7, () async {
      expect(TurnGeneration.current, 7);
      await Future<void>.delayed(Duration.zero);
      expect(TurnGeneration.current, 7);

      await TurnGeneration.runScoped(11, () async {
        expect(TurnGeneration.current, 11);
        await Future<void>.delayed(Duration.zero);
        expect(TurnGeneration.current, 11);
      });

      expect(TurnGeneration.current, 7);
    });

    expect(TurnGeneration.current, isNull);
  });

  test('TurnGeneration leaves unowned callbacks unscoped', () {
    final result = TurnGeneration.runScoped(null, () {
      expect(TurnGeneration.current, isNull);
      return 'unscoped';
    });

    expect(result, 'unscoped');
  });
}
