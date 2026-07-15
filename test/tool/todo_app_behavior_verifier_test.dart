import 'package:flutter_test/flutter_test.dart';

import '../../tool/canaries/support/todo_app_behavior_verifier.dart';

void main() {
  group('todoListEntryLooksCompleted', () {
    test('accepts a standalone x status marker after the task id', () {
      expect(
        todoListEntryLooksCompleted(
          '[1] x buy milk\n[2]   write report\n',
          'buy milk',
        ),
        isTrue,
      );
    });

    test('keeps a task without a status marker unfinished', () {
      expect(
        todoListEntryLooksCompleted(
          '[1]   buy milk\n[2]   write report\n',
          'buy milk',
        ),
        isFalse,
      );
    });

    test('does not treat an x inside task text as a status marker', () {
      expect(
        todoListEntryLooksCompleted(
          '[1]   fix x coordinate\n',
          'fix x coordinate',
        ),
        isFalse,
      );
    });

    test('retains checkbox completion marker support', () {
      expect(
        todoListEntryLooksCompleted('[x] [1] buy milk\n', 'buy milk'),
        isTrue,
      );
    });

    test('accepts a Japanese completion marker', () {
      expect(
        todoListEntryLooksCompleted(
          '[id: 1] [完了] buy milk\n[id: 2] [未完了] write report\n',
          'buy milk',
        ),
        isTrue,
      );
    });

    test('does not treat Japanese undone as completed', () {
      expect(
        todoListEntryLooksCompleted('[id: 1] [未完了] buy milk\n', 'buy milk'),
        isFalse,
      );
    });
  });

  group('todoEmptyListMessageLooksFriendly', () {
    test('accepts the Japanese empty-list message from the live artifact', () {
      expect(todoEmptyListMessageLooksFriendly('タスクはありません。'), isTrue);
    });

    test('rejects a blank or unrelated message', () {
      expect(todoEmptyListMessageLooksFriendly(''), isFalse);
      expect(todoEmptyListMessageLooksFriendly('Unknown command.'), isFalse);
    });
  });
}
