import 'package:caverno/features/chat/domain/services/coding/coding_future_action_detector.dart';
import 'package:test/test.dart';

void main() {
  const detector = CodingFutureActionDetector();

  test('fix promises include coding filenames and completed substeps', () {
    for (final text in [
      'watcher.py still needs retry. Let me make the fixes:',
      'The Dart source was updated. Let me apply these edits.',
      '`test_watcher.py` \u306e `fake_fetch` \u306b\u30d1\u30e9\u30e1\u30fc\u30bf\u3092\u8ffd\u52a0\u3057\u307e\u3059\u3002',
    ]) {
      expect(detector.matchesFixPromise(text), isTrue);
      expect(detector.matches(text), isFalse);
    }
  });

  test('ignores thinking-only promises and noncoding plans', () {
    for (final text in [
      '<think>watcher.py needs work. Let me make the fixes.</think>'
          'The Python code was fixed.',
      'Let me make the fixes to the dinner plan.',
      'I made the fixes in watcher.py.',
      '`test_watcher.py` \u306b\u30d1\u30e9\u30e1\u30fc\u30bf\u3092\u8ffd\u52a0\u3057\u307e\u3057\u305f\u3002',
      '`test_watcher.py` \u306b\u30d1\u30e9\u30e1\u30fc\u30bf\u3092\u8ffd\u52a0\u6e08\u307f\u3067\u3059\u3002',
    ]) {
      expect(detector.matchesFixPromise(text), isFalse);
      expect(detector.matches(text), isFalse);
    }
  });
}
