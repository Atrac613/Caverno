import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/file_reference_extractor.dart';

void main() {
  group('FileReferenceExtractor', () {
    test('extracts relative paths, named files, and line numbers', () {
      final references = FileReferenceExtractor.extract(
        'Check lib/features/chat/widgets/message_bubble.dart:42, '
        'pubspec.yaml, and README.md.',
      );

      expect(
        references.map((reference) => reference.label),
        containsAll([
          'lib/features/chat/widgets/message_bubble.dart:42',
          'pubspec.yaml',
          'README.md',
        ]),
      );
    });

    test('ignores URLs and fenced code blocks', () {
      final references = FileReferenceExtractor.extract('''
Visit https://example.com/readme.md.

```diff
--- lib/ignored.dart
+++ lib/ignored.dart
```

Open lib/visible.dart instead.
''');

      expect(references.map((reference) => reference.path), [
        'lib/visible.dart',
      ]);
    });
  });

  group('FileReferenceMarkdownLinkifier', () {
    test('wraps plain paths with internal file links', () {
      final markdown = FileReferenceMarkdownLinkifier.linkify(
        'Open lib/main.dart:12 before editing `lib/inline.dart`.',
      );

      expect(markdown, contains('[lib/main.dart:12](caverno-file:'));
      expect(markdown, contains('`lib/inline.dart`'));
    });

    test('round-trips encoded href payloads', () {
      final href = FileReferenceMarkdownLinkifier.hrefForPath(
        'lib/features/chat/message_bubble.dart',
      );

      expect(
        FileReferenceMarkdownLinkifier.decodeHref(href),
        'lib/features/chat/message_bubble.dart',
      );
    });
  });
}
