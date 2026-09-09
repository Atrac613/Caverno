import '../entities/skill.dart';

/// Picks an enabled skill whose name appears in [text].
abstract final class EnabledSkillNamedInText {
  static Skill? find(String text, Iterable<Skill> skills) {
    final normalizedText = text.toLowerCase();
    if (normalizedText.isEmpty) {
      return null;
    }
    for (final skill in skills) {
      final name = skill.normalizedName;
      if (name.isEmpty) {
        continue;
      }
      if (normalizedText.contains(name.toLowerCase())) {
        return skill;
      }
    }
    return null;
  }
}
