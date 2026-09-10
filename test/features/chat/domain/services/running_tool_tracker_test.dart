import 'package:caverno/features/chat/domain/services/running_tool_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RunningToolTracker.next', () {
    test('ignores queued: a queued call may never run', () {
      expect(
        RunningToolTracker.next(
          const [],
          toolName: 'read_file',
          lifecycleState: 'queued',
        ),
        isNull,
      );
    });

    test('adds on started', () {
      expect(
        RunningToolTracker.next(
          const [],
          toolName: 'read_file',
          lifecycleState: 'started',
        ),
        ['read_file'],
      );
    });

    test('keeps both entries for a parallel batch of the same tool', () {
      final first = RunningToolTracker.next(
        const [],
        toolName: 'read_file',
        lifecycleState: 'started',
      )!;
      final second = RunningToolTracker.next(
        first,
        toolName: 'read_file',
        lifecycleState: 'started',
      );

      expect(second, ['read_file', 'read_file']);
    });

    test('removes one entry per terminal event', () {
      expect(
        RunningToolTracker.next(
          const ['read_file', 'read_file'],
          toolName: 'read_file',
          lifecycleState: 'completed',
        ),
        ['read_file'],
      );
    });

    test('every terminal state removes, so a skip cannot strand a name', () {
      for (final terminal in const ['completed', 'skipped', 'failed']) {
        expect(
          RunningToolTracker.next(
            const ['grep'],
            toolName: 'grep',
            lifecycleState: terminal,
          ),
          isEmpty,
          reason: terminal,
        );
      }
    });

    test('reports no change when removing a name that is not running', () {
      expect(
        RunningToolTracker.next(
          const ['grep'],
          toolName: 'read_file',
          lifecycleState: 'completed',
        ),
        isNull,
      );
    });

    test('does not mutate the list it was given', () {
      const current = ['grep'];
      RunningToolTracker.next(
        current,
        toolName: 'grep',
        lifecycleState: 'completed',
      );
      expect(current, ['grep']);
    });
  });
}
