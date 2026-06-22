import '../entities/skill.dart';

class ParsedSkillMarkdown {
  const ParsedSkillMarkdown({
    required this.name,
    required this.description,
    required this.whenToUse,
    required this.content,
  });

  final String name;
  final String description;
  final String whenToUse;
  final String content;
}

class SkillMarkdownParser {
  SkillMarkdownParser._();

  static final RegExp _frontMatterPattern = RegExp(
    r'^\s*---\s*\r?\n([\s\S]*?)\r?\n---\s*(?:\r?\n|$)',
  );

  static ParsedSkillMarkdown parse(String markdown) {
    final normalized = markdown.replaceAll('\r\n', '\n').trim();
    final match = _frontMatterPattern.firstMatch(normalized);
    final frontMatter = <String, String>{};
    var content = normalized;

    if (match != null) {
      frontMatter.addAll(_parseFrontMatter(match.group(1) ?? ''));
      content = normalized.substring(match.end).trim();
    }

    final headingName = _firstMarkdownHeading(content);
    final name = _firstNonEmpty([
      frontMatter['name'],
      headingName,
      'Untitled Skill',
    ]);
    final description = _firstNonEmpty([
      frontMatter['description'],
      frontMatter['summary'],
      '',
    ]);
    final whenToUse = _firstNonEmpty([
      frontMatter['whenToUse'],
      frontMatter['when_to_use'],
      frontMatter['when'],
      '',
    ]);

    return ParsedSkillMarkdown(
      name: name,
      description: description,
      whenToUse: whenToUse,
      content: content,
    );
  }

  static String toMarkdown(Skill skill) {
    return composeMarkdown(
      name: skill.normalizedName,
      description: skill.normalizedDescription,
      whenToUse: skill.normalizedWhenToUse,
      body: skill.content,
    );
  }

  /// Builds skill markdown (front matter + body) from raw fields.
  ///
  /// The emitted front matter mirrors [parse], so a composed skill round-trips
  /// back to the same name/description/whenToUse. This lets callers assemble a
  /// skill from structured input (e.g. the `save_skill` tool) and persist it
  /// through the same markdown path as the settings UI.
  static String composeMarkdown({
    required String name,
    String description = '',
    String whenToUse = '',
    String body = '',
  }) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('name: ${_escapeFrontMatterValue(name.trim())}');
    if (description.trim().isNotEmpty) {
      buffer.writeln(
        'description: ${_escapeFrontMatterValue(description.trim())}',
      );
    }
    if (whenToUse.trim().isNotEmpty) {
      buffer.writeln(
        'whenToUse: ${_escapeFrontMatterValue(whenToUse.trim())}',
      );
    }
    buffer
      ..writeln('---')
      ..writeln()
      ..write(body.trim());
    return buffer.toString().trimRight();
  }

  static Map<String, String> _parseFrontMatter(String frontMatter) {
    final values = <String, String>{};
    for (final line in frontMatter.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final separatorIndex = trimmed.indexOf(':');
      if (separatorIndex <= 0) {
        continue;
      }
      final key = trimmed.substring(0, separatorIndex).trim();
      final value = trimmed.substring(separatorIndex + 1).trim();
      if (key.isEmpty) {
        continue;
      }
      values[key] = _unquoteFrontMatterValue(value);
    }
    return values;
  }

  static String _firstMarkdownHeading(String content) {
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('#')) {
        continue;
      }
      final heading = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      if (heading.isNotEmpty) {
        return heading;
      }
    }
    return '';
  }

  static String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  static String _unquoteFrontMatterValue(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1).trim();
    }
    return value.trim();
  }

  static String _escapeFrontMatterValue(String value) {
    final trimmed = value.trim();
    if (trimmed.contains(':') || trimmed.contains('#')) {
      return '"${trimmed.replaceAll('"', r'\"')}"';
    }
    return trimmed;
  }
}
