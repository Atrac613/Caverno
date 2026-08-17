/// One prebuilt skill offered in Settings > Skills.
///
/// A catalog entry is not a [Skill]: nothing is persisted until the user saves
/// it. The entry carries the skill markdown verbatim so the editor opens on the
/// exact text the asset holds, and the save path stays the single existing one
/// (parse markdown, then upsert).
final class SkillCatalogEntry {
  const SkillCatalogEntry({
    required this.assetPath,
    required this.name,
    required this.description,
    required this.whenToUse,
    required this.markdown,
  });

  /// Bundle path this entry was loaded from, used as its stable identity.
  final String assetPath;

  final String name;
  final String description;
  final String whenToUse;

  /// Full skill markdown (front matter + body) handed to the editor.
  final String markdown;

  String get normalizedName => name.trim();

  /// Identity used to detect that a saved skill came from this entry.
  ///
  /// Matching on the name keeps the [Skill] entity unchanged. It is
  /// deliberately imperfect: renaming a saved skill makes the entry look
  /// unadded again. Tracking a catalog id on the skill is the way to fix that,
  /// and is only worth it once the catalog needs to offer updates.
  String get matchKey => normalizedName.toLowerCase();
}
