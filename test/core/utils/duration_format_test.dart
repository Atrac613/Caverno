import 'package:caverno/core/utils/duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCompactDuration', () {
    test('renders sub-minute durations in seconds', () {
      expect(formatCompactDuration(Duration.zero), '0s');
      expect(formatCompactDuration(const Duration(seconds: 8)), '8s');
      expect(formatCompactDuration(const Duration(seconds: 59)), '59s');
    });

    test('renders minutes with unpadded seconds', () {
      expect(formatCompactDuration(const Duration(minutes: 1)), '1m 0s');
      expect(
        formatCompactDuration(const Duration(minutes: 14, seconds: 8)),
        '14m 8s',
      );
      expect(
        formatCompactDuration(const Duration(minutes: 59, seconds: 59)),
        '59m 59s',
      );
    });

    test('drops seconds once the turn passes an hour', () {
      expect(formatCompactDuration(const Duration(hours: 1)), '1h 0m');
      expect(
        formatCompactDuration(
          const Duration(hours: 2, minutes: 14, seconds: 8),
        ),
        '2h 14m',
      );
    });

    test('clamps negative durations to zero', () {
      expect(formatCompactDuration(const Duration(seconds: -5)), '0s');
    });
  });
}
