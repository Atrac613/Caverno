import '../entities/skill.dart';

class SkillPromptIndexBuilder {
  SkillPromptIndexBuilder._();

  static const int defaultMaxPromptChars = 2400;
  static const int defaultMaxSkillChars = 250;

  static String? build(
    Iterable<Skill> skills, {
    int maxPromptChars = defaultMaxPromptChars,
    int maxSkillChars = defaultMaxSkillChars,
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

    final buffer = StringBuffer()
      ..writeln('Available user skills (lightweight index):')
      ..writeln(
        'Call load_skill with the id or name before relying on a skill. '
        'The index is clipped and does not contain full instructions.',
      );

    for (final skill in enabledSkills) {
      final entry = _buildEntry(skill, maxSkillChars: maxSkillChars);
      if (buffer.length + entry.length > maxPromptChars) {
        buffer.writeln(
          '- More skills are saved but omitted from this clipped index.',
        );
        break;
      }
      buffer.write(entry);
    }

    return buffer.toString().trimRight();
  }

  static String _buildEntry(Skill skill, {required int maxSkillChars}) {
    final parts = <String>[
      'id=${skill.id}',
      'name=${skill.normalizedName}',
      if (skill.normalizedDescription.isNotEmpty)
        'description=${skill.normalizedDescription}',
      if (skill.normalizedWhenToUse.isNotEmpty)
        'whenToUse=${skill.normalizedWhenToUse}',
    ];
    return '- ${_clip(parts.join(' | '), maxSkillChars)}\n';
  }

  static String _clip(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }
}
