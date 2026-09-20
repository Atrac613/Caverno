import '../entities/skill.dart';

/// The skill index the system prompt carries, plus the one skill a turn is
/// working from.
///
/// **A loaded skill's content does not survive the turn that loaded it.**
/// Measured 2026-09-20 in session fd153d88: `load_skill` fired in turn 2 and
/// the request there carried the whole skill — the path it names for release
/// notes and the template to write them in. From turn 3 only the skill's *name*
/// appears, because the name is this index and the content was a tool result.
/// The write ran in turn 4, so the model could see that a skill called "Caverno
/// Version Bump" had been read and not what it said; it put the notes at the
/// repository root in its own layout, against a convention that was written
/// down and had been handed over two turns earlier.
///
/// [StickyToolResultPolicy] already lists `load_skill`, and
/// [RecentReadResultCarry] carries recent reads, but both resolve over the
/// current turn's `executedToolResults`: they are intra-turn, and across a turn
/// boundary that list starts empty.
///
/// A skill is a standing instruction rather than something that happened, so it
/// belongs in the prompt rather than in a tool result replayed into a turn that
/// did not produce it. **Exactly one** skill is carried in full, the one most
/// recently loaded, because the index is rebuilt every turn: a rule that keeps
/// every loaded skill would put a document into every later turn of the thread,
/// including the ones that have moved on, and several loaded skills would
/// exhaust [defaultMaxPromptChars] outright. Carrying the last one bounds the
/// cost and answers the eviction question by construction.
///
/// Every other skill loaded earlier keeps its clipped entry and gains a marker
/// saying its instructions are gone. That marker is deliberately not the whole
/// mechanism: prose can prompt a reload but cannot guarantee one, which is why
/// the skill actually in use is carried structurally instead.
class SkillPromptIndexBuilder {
  SkillPromptIndexBuilder._();

  static const int defaultMaxPromptChars = 2400;
  static const int defaultMaxSkillChars = 250;

  /// Budget for the single carried skill, held apart from the index list so a
  /// long skill cannot evict the index and a long index cannot evict it.
  static const int defaultMaxCarriedSkillChars = 4000;

  static String? build(
    Iterable<Skill> skills, {
    int maxPromptChars = defaultMaxPromptChars,
    int maxSkillChars = defaultMaxSkillChars,
    int maxCarriedSkillChars = defaultMaxCarriedSkillChars,

    /// The most recently loaded skill, carried with its instructions.
    String? carriedSkillId,

    /// Every skill loaded earlier in this thread, including [carriedSkillId].
    Set<String> loadedSkillIds = const <String>{},
  }) {
    final enabledSkills =
        skills.where((skill) => skill.isUsable).toList(growable: false)..sort(
          (a, b) => a.normalizedName.toLowerCase().compareTo(
            b.normalizedName.toLowerCase(),
          ),
        );
    if (enabledSkills.isEmpty) {
      return null;
    }

    final carried = _carriedSkill(enabledSkills, carriedSkillId);
    final buffer = StringBuffer();

    if (carried != null) {
      buffer
        ..writeln(
          'Skill in use, loaded earlier in this thread and repeated here '
          'because a tool result does not survive its turn. Follow it:',
        )
        ..writeln('# ${carried.normalizedName} (id=${carried.id})')
        ..writeln(_clipBlock(carried.normalizedContent, maxCarriedSkillChars))
        ..writeln();
    }

    buffer
      ..writeln('Available user skills (lightweight index):')
      ..writeln(
        'Call load_skill with the id or name before relying on a skill. '
        'The index is clipped and does not contain full instructions.',
      );

    final indexStart = buffer.length;
    for (final skill in enabledSkills) {
      if (skill.id == carried?.id) continue;
      final entry = _buildEntry(
        skill,
        maxSkillChars: maxSkillChars,
        wasLoaded: loadedSkillIds.contains(skill.id),
      );
      if (buffer.length - indexStart + entry.length > maxPromptChars) {
        buffer.writeln(
          '- More skills are saved but omitted from this clipped index.',
        );
        break;
      }
      buffer.write(entry);
    }

    return buffer.toString().trimRight();
  }

  static Skill? _carriedSkill(List<Skill> skills, String? carriedSkillId) {
    final id = carriedSkillId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final skill in skills) {
      if (skill.id == id && skill.normalizedContent.isNotEmpty) return skill;
    }
    // A skill that was disabled or deleted since it was loaded carries
    // nothing; the marker path below still tells the model it is gone.
    return null;
  }

  static String _buildEntry(
    Skill skill, {
    required int maxSkillChars,
    required bool wasLoaded,
  }) {
    final parts = <String>[
      'id=${skill.id}',
      'name=${skill.normalizedName}',
      if (skill.normalizedDescription.isNotEmpty)
        'description=${skill.normalizedDescription}',
      if (skill.normalizedWhenToUse.isNotEmpty)
        'whenToUse=${skill.normalizedWhenToUse}',
    ];
    final clipped = _clip(parts.join(' | '), maxSkillChars);
    if (!wasLoaded) {
      return '- $clipped\n';
    }
    // Appended after the clip so the warning cannot be the part that is cut.
    return '- $clipped\n'
        '  (loaded earlier in this thread; its instructions are NOT in this '
        'turn — call load_skill again before relying on them)\n';
  }

  static String _clip(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }

  /// Clips without collapsing newlines: a skill's instructions are a document,
  /// and flattening them would destroy the very formatting they specify.
  static String _clipBlock(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }
}
