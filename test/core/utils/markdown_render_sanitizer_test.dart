import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/utils/markdown_render_sanitizer.dart';

void main() {
  test('escapes malformed leading reference labels', () {
    expect(MarkdownRenderSanitizer.sanitize('[broken\\'), '\\[broken\\');
  });

  test('preserves valid inline links at the start of a line', () {
    const markdown = '[OpenAI](https://openai.com)';
    expect(MarkdownRenderSanitizer.sanitize(markdown), markdown);
  });

  test('escapes malformed leading reference labels inside block quotes', () {
    expect(MarkdownRenderSanitizer.sanitize('> [broken\\'), '> \\[broken\\');
  });

  test('escapes html-like tags outside inline code', () {
    expect(
      MarkdownRenderSanitizer.sanitize('Status: <user@host> and `<raw>`'),
      'Status: &lt;user@host&gt; and `<raw>`',
    );
  });
}
