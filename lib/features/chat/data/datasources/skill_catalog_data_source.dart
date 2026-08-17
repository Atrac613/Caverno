import 'package:flutter/services.dart';

import '../../domain/entities/skill_catalog_entry.dart';
import '../../domain/services/skill_markdown_parser.dart';

/// Loads the prebuilt skills bundled under `assets/skills/`.
///
/// Entries are plain skill markdown parsed by [SkillMarkdownParser], the same
/// parser the editor uses, so a catalog file and a hand-written skill cannot
/// drift into two formats.
class SkillCatalogDataSource {
  const SkillCatalogDataSource({AssetBundle? bundle}) : _bundle = bundle;

  static const String assetDirectory = 'assets/skills/';

  final AssetBundle? _bundle;

  AssetBundle get _assets => _bundle ?? rootBundle;

  /// Returns the catalog sorted by name.
  ///
  /// A malformed or unreadable file is skipped rather than failing the whole
  /// catalog: one bad asset must not remove the user's ability to browse the
  /// rest.
  Future<List<SkillCatalogEntry>> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_assets);
    final paths =
        manifest
            .listAssets()
            .where(
              (path) => path.startsWith(assetDirectory) && path.endsWith('.md'),
            )
            .toList()
          ..sort();

    final entries = <SkillCatalogEntry>[];
    for (final path in paths) {
      final entry = await _loadEntry(path);
      if (entry != null) {
        entries.add(entry);
      }
    }
    entries.sort(
      (a, b) => a.normalizedName.toLowerCase().compareTo(
        b.normalizedName.toLowerCase(),
      ),
    );
    return List<SkillCatalogEntry>.unmodifiable(entries);
  }

  Future<SkillCatalogEntry?> _loadEntry(String path) async {
    final String markdown;
    try {
      markdown = await _assets.loadString(path);
    } catch (_) {
      return null;
    }
    final trimmed = markdown.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = SkillMarkdownParser.parse(trimmed);
    if (parsed.name.trim().isEmpty) {
      return null;
    }
    return SkillCatalogEntry(
      assetPath: path,
      name: parsed.name,
      description: parsed.description,
      whenToUse: parsed.whenToUse,
      markdown: trimmed,
    );
  }
}
