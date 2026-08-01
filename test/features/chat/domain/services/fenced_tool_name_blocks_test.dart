import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/fenced_tool_name_blocks.dart';

void main() {
  group('FencedToolNameBlocks', () {
    test('extracts trimmed non-empty names case-insensitively', () {
      const content = '''
before
```tool_name
 read_file
```
```TOOL_NAME write_file ```
```tool_name   ```
after
''';

      expect(FencedToolNameBlocks.extract(content), [
        'read_file',
        'write_file',
      ]);
    });

    test('strips every complete block and trims the remainder', () {
      const content =
          '  before\n```tool_name\nread_file\n```\n'
          'middle\n```TOOL_NAME write_file```\nafter  ';

      expect(FencedToolNameBlocks.strip(content), 'before\n\nmiddle\n\nafter');
    });

    test('leaves incomplete blocks and finds no complete name', () {
      const content = '  ```tool_name\nread_file  ';

      expect(FencedToolNameBlocks.extract(content), isEmpty);
      expect(FencedToolNameBlocks.strip(content), content.trim());
    });
  });
}
