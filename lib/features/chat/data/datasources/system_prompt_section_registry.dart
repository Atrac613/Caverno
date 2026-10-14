import '../../domain/services/system_prompt_sections.dart';

/// The named sections of recently built system prompts, keyed by the prompt
/// text, so the session log can record which sections a request carried
/// without threading them through every request path.
///
/// LL46: a builder registers each prompt it renders; the log store looks the
/// request's system message up when it writes the entry. Bounded, because a
/// prompt is only looked up by the requests of the turn that built it.
final class SystemPromptSectionRegistry {
  SystemPromptSectionRegistry({this.capacity = 16});

  static final instance = SystemPromptSectionRegistry();

  final int capacity;
  // Insertion-ordered, so the first key is the least recently recorded.
  final _entries = <String, List<SystemPromptSection>>{};

  void record(String prompt, List<SystemPromptSection> sections) {
    _entries
      ..remove(prompt)
      ..[prompt] = List.unmodifiable(sections);
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  List<SystemPromptSection>? sectionsFor(String prompt) => _entries[prompt];
}
