/// Parses assistant-authored fenced `tool_name` blocks.
abstract final class FencedToolNameBlocks {
  static final RegExp _pattern = RegExp(
    r'```tool_name\s*([\s\S]*?)```',
    caseSensitive: false,
  );

  static List<String> extract(String content) {
    final names = <String>[];
    for (final match in _pattern.allMatches(content)) {
      final name = (match.group(1) ?? '').trim();
      if (name.isNotEmpty) names.add(name);
    }
    return names;
  }

  static String strip(String content) =>
      content.replaceAll(_pattern, '').trim();
}
