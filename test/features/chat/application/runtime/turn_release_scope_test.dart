import 'dart:io';

import 'package:caverno/features/chat/application/runtime/turn_release_scope.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurnReleaseScope', () {
    test('discharges every release once, in registration order', () {
      final scope = TurnReleaseScope(owner: _owner());
      final order = <String>[];
      scope.register('first', () => order.add('first'));
      scope.register('second', () => order.add('second'));
      scope.register('third', () => order.add('third'));

      scope.dispose();

      expect(order, ['first', 'second', 'third']);
      expect(scope.dischargedNames, ['first', 'second', 'third']);
      expect(scope.isDisposed, isTrue);
    });

    test('is idempotent, so a doubled teardown path cannot double-release', () {
      final scope = TurnReleaseScope(owner: _owner());
      var runs = 0;
      scope.register('once', () => runs += 1);

      scope.dispose();
      scope.dispose();

      expect(runs, 1);
    });

    // Teardown is what runs when something already went wrong, so one failing
    // release must not strand the ones after it.
    test('runs the remaining releases when one throws, then reports', () {
      final scope = TurnReleaseScope(owner: _owner());
      final order = <String>[];
      scope.register('before', () => order.add('before'));
      scope.register('boom', () => throw StateError('release failed'));
      scope.register('after', () => order.add('after'));

      expect(scope.dispose, throwsA(isA<TurnReleaseFailure>()));

      expect(order, ['before', 'after']);
      expect(scope.dischargedNames, ['before', 'after']);
    });

    test('rejects a release registered after disposal', () {
      final scope = TurnReleaseScope(owner: _owner());
      scope.dispose();

      expect(() => scope.register('late', () {}), throwsA(isA<StateError>()));
    });

    test('reports what it was asked to release', () {
      final scope = TurnReleaseScope(owner: _owner())
        ..register('alpha', () {})
        ..register('beta', () {});

      expect(scope.registeredNames, ['alpha', 'beta']);
      expect(scope.dischargedNames, isEmpty);
    });

    test('scope has no presentation or notifier dependency', () {
      final source = File(
        'lib/features/chat/application/runtime/turn_release_scope.dart',
      ).readAsStringSync();
      final code = source
          .split('\n')
          .map((line) {
            final index = line.indexOf('//');
            return index == -1 ? line : line.substring(0, index);
          })
          .join('\n');

      expect(code, isNot(contains('ChatNotifier')));
      expect(code, isNot(contains('ChatState')));
      expect(code, isNot(contains('flutter_riverpod')));
      expect(code, isNot(matches(RegExp(r'\bRef\b'))));
    });
  });
}

ChatTurnOwner _owner() =>
    ChatTurnOwner(conversationId: 'conversation-a', interactionGeneration: 7);
