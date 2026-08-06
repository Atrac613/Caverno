import 'package:caverno/core/utils/bounded_process.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('runProcessBounded', () {
    test('returns the command output when it finishes in time', () async {
      final result = await runProcessBounded('echo', const ['caverno']);

      expect(result.exitCode, 0);
      expect(result.stdout, 'caverno\n');
    });

    test('kills a command that outlives its budget', () async {
      final stopwatch = Stopwatch()..start();
      final result = await runProcessBounded(
        'sleep',
        const ['30'],
        timeout: const Duration(milliseconds: 200),
      );
      stopwatch.stop();

      // `Process.run` has no timeout, so a command blocked on an unreachable
      // resolver would otherwise hold the tool call open indefinitely.
      expect(result.exitCode, boundedProcessTimeoutExitCode);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(result.stderr, contains('timed out'));
    });
  });
}
