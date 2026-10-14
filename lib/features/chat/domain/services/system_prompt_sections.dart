/// One named part of a rendered system prompt and how many characters it
/// contributed.
///
/// LL46: the coding system prompt is ~23.8k characters at the median, most of
/// it inline guidance that had no name, so neither the session log nor the
/// model-input inventory could say which rule costs what.
final class SystemPromptSection {
  const SystemPromptSection(this.id, this.length);

  final String id;
  final int length;

  Map<String, Object> toJson() => {'id': id, 'chars': length};

  @override
  bool operator ==(Object other) =>
      other is SystemPromptSection && other.id == id && other.length == length;

  @override
  int get hashCode => Object.hash(id, length);

  @override
  String toString() => '$id:$length';
}

/// A [StringBuffer] that remembers where each named section starts.
///
/// Marking a section writes nothing, so a builder can be sectioned without
/// changing a byte of what it renders.
final class SectionedPromptBuffer {
  final _buffer = StringBuffer();
  final _starts = <(String, int)>[];

  /// Starts section [id] at the current end of the text.
  void section(String id) => _starts.add((id, _buffer.length));

  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  String toString() => _buffer.toString();

  /// The sections that wrote something, in order, measured against [text],
  /// which may be a trimmed copy of this buffer's contents.
  List<SystemPromptSection> sectionsFor(String text) {
    final sections = <SystemPromptSection>[];
    for (var i = 0; i < _starts.length; i++) {
      final (id, start) = _starts[i];
      final end = i + 1 < _starts.length ? _starts[i + 1].$2 : _buffer.length;
      final length = (end < text.length ? end : text.length) - start;
      if (length > 0) sections.add(SystemPromptSection(id, length));
    }
    return sections;
  }
}
