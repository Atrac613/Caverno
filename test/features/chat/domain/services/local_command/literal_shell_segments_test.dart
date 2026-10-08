import 'package:caverno/features/chat/domain/services/local_command/literal_shell_segments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps Python code and quoted paths inside their shell arguments', () {
    const probe = 'python3 -c "import pytest; print(pytest.__file__)" 2>&1';
    expect(LiteralShellSegments.parse("cd '/project; space' && ls; $probe"), [
      "cd '/project; space'",
      'ls',
      probe,
    ]);
    expect(LiteralShellSegments.parse('python3 -c "print(\'a && b; c\')"'), [
      'python3 -c "print(\'a && b; c\')"',
    ]);
  });
  test('fallback splitting is opt-in and keeps quoted operators intact', () {
    const source = 'ls .venv || ls venv && python3 -c "print(\'a || b\')"';
    expect(LiteralShellSegments.parse(source), [
      'ls .venv || ls venv',
      'python3 -c "print(\'a || b\')"',
    ]);
    expect(LiteralShellSegments.parse(source, allowFallbacks: true), [
      'ls .venv',
      'ls venv',
      'python3 -c "print(\'a || b\')"',
    ]);
    for (final source in ['|| ls', 'ls ||', 'ls || || pwd', 'ls ||| pwd']) {
      final segments = LiteralShellSegments.parse(source, allowFallbacks: true);
      if (source == 'ls ||| pwd') {
        expect(segments, ['ls', '| pwd']);
      } else {
        expect(segments, isNull);
      }
    }
  });
  for (final source in ['', '; ls', 'ls;', 'ls &&', 'ls;;pwd', 'ls "open']) {
    test('rejects empty segments and unmatched quotes: $source', () {
      expect(LiteralShellSegments.parse(source), isNull);
    });
  }
}
