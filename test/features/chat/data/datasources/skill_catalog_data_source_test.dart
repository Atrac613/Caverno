import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/skill_catalog_data_source.dart';
import 'package:caverno/features/chat/domain/services/skill_markdown_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the bundled catalog from the asset bundle', () async {
    final entries = await const SkillCatalogDataSource().load();

    expect(entries, isNotEmpty);
    for (final entry in entries) {
      expect(
        entry.assetPath,
        startsWith(SkillCatalogDataSource.assetDirectory),
      );
      expect(entry.normalizedName, isNotEmpty);
      expect(entry.markdown, isNotEmpty);
    }
    final names = entries.map((entry) => entry.normalizedName).toList();
    expect(
      names,
      equals(List<String>.from(names)..sort()),
      reason: 'entries are sorted by name',
    );
    expect(
      names.toSet().length,
      names.length,
      reason: 'a duplicate name would make the added-state check ambiguous',
    );
  });

  test('every shipped skill round-trips through the editor parser', () async {
    final directory = Directory(SkillCatalogDataSource.assetDirectory);
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.md'))
        .toList();

    expect(files, isNotEmpty);
    for (final file in files) {
      final parsed = SkillMarkdownParser.parse(file.readAsStringSync());
      expect(parsed.name.trim(), isNotEmpty, reason: file.path);
      // Both are surfaced before the body is ever loaded, so an entry without
      // them cannot be chosen on purpose.
      expect(parsed.description.trim(), isNotEmpty, reason: file.path);
      expect(parsed.whenToUse.trim(), isNotEmpty, reason: file.path);
      expect(parsed.content.trim(), isNotEmpty, reason: file.path);
    }
  });

  test('the commit-split skill names the summary-diff trap up front', () {
    // Two sessions planned commit work from `--stat` alone, which reports file
    // names while hiding the change. The rule has to sit in the front matter:
    // the model reads the listing before it ever loads the body.
    final file = File(
      '${SkillCatalogDataSource.assetDirectory}git_commit_split.md',
    );
    expect(file.existsSync(), isTrue);

    final parsed = SkillMarkdownParser.parse(file.readAsStringSync());
    final frontMatter = '${parsed.description} ${parsed.whenToUse}';
    expect(frontMatter, contains('--stat'));
    expect(frontMatter, contains('git show'));
    // The body must not quietly accept a summary form as the first read.
    expect(parsed.content, contains('--name-only'));
    expect(parsed.content, contains('git diff <sha> HEAD'));
  });

  test('shipped GitHub skills steer away from fetching the PR URL', () {
    // The turn is contaminated by an http_get 404 login page before the body
    // is ever read, so this rule has to live in the front matter the model
    // sees in the skill listing — not only in the instructions.
    final files = Directory(SkillCatalogDataSource.assetDirectory)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('github'))
        .toList();

    expect(files, isNotEmpty);
    for (final file in files) {
      final parsed = SkillMarkdownParser.parse(file.readAsStringSync());
      final frontMatter = '${parsed.description} ${parsed.whenToUse}';
      expect(frontMatter, contains('gh'), reason: file.path);
      expect(frontMatter, contains('http_get'), reason: file.path);
    }
  });
}
