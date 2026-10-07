import 'dart:io';

import 'dependency_inventory.dart';

/// One deprecation an installed SDK ships.
class SdkDeprecation {
  const SdkDeprecation({
    required this.symbol,
    required this.advice,
    required this.since,
  });

  final String symbol;

  /// What the annotation says to use instead, when it says.
  final String advice;

  /// The release the annotation names, such as `v3.33.0-1.0.pre`.
  final String since;

  @override
  String toString() => '$symbol: $advice (since $since)';
}

/// What an installed package's own sources say changed in its release line.
class PackageChange {
  const PackageChange({
    required this.record,
    required this.legacySymbols,
    required this.breakingEntries,
  });

  final DependencyRecord record;

  /// Symbols the package keeps in a legacy library: still working, but moved
  /// aside by the package itself.
  final List<String> legacySymbols;

  /// Changelog entries marked breaking within the installed release line.
  final List<String> breakingEntries;

  bool get isEmpty => legacySymbols.isEmpty && breakingEntries.isEmpty;
}

/// KC2 slice 4: the "what changed" evidence, read from installed sources.
///
/// KC1's second and sixth measurements found that naming a version does not
/// move API-drift claims, while a digest of what the installed versions
/// changed halves them on the APIs it covers. Nothing here is written by hand:
/// a hand-written list of what expired is a belief with an expiry date, which
/// is the problem this track exists for.
///
/// The SDK scanner moved here from the KC1 oracle (`tool/kc1_cutoff_oracle.dart`)
/// unchanged, and the oracle now delegates to it, so the measured instrument
/// and the production block read deprecations the same way.
abstract final class InstalledChangeDigest {
  /// The framework and the engine's `dart:ui`, relative to an SDK root:
  /// the two halves of "the SDK" live in different trees.
  static List<String> flutterSourceRoots(String flutterSdkRoot) => [
    '$flutterSdkRoot/packages/flutter/lib/src',
    '$flutterSdkRoot/bin/cache/pkg/sky_engine/lib/ui',
  ];

  /// Deprecations under [sourceRoots], newest first.
  ///
  /// Ordered by the release named in the annotation, so a caller can take the
  /// most recent [limit] without deciding which APIs matter — that decision is
  /// exactly the one a digest must not smuggle in.
  static List<SdkDeprecation> recentSdkDeprecations(
    Iterable<String> sourceRoots, {
    int limit = 40,
  }) {
    final found = <SdkDeprecation>[];
    for (final root in sourceRoots) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final file
          in directory
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        found.addAll(_deprecationsIn(file.readAsLinesSync()));
      }
    }
    found.sort(
      (a, b) => _compareRelease(_releaseKey(b.since), _releaseKey(a.since)),
    );
    // One deprecated parameter reappears on every widget that takes it, so the
    // raw scan repeats `cacheExtent` eight times before reaching a second API.
    // Deduplicated on the advice a reader would act on, which is the symbol and
    // its replacement, not the declaration site.
    final seen = <String>{};
    return found
        .where((entry) => seen.add('${entry.symbol}|${entry.advice}'))
        .take(limit)
        .toList(growable: false);
  }

  /// Legacy symbols and breaking entries for an attested package, or null
  /// when the package root is unknown.
  static PackageChange? packageChange(
    DependencyRecord record, {
    int breakingLimit = 6,
  }) {
    final root = record.resolvedRoot;
    final version = record.lockedVersion;
    if (root == null || version == null) return null;
    return PackageChange(
      record: record,
      legacySymbols: legacySymbols(root),
      breakingEntries: breakingEntries(
        File('$root/CHANGELOG.md'),
        installedVersion: version,
        limit: breakingLimit,
      ),
    );
  }

  /// Symbols a package keeps in a legacy library: the names a public
  /// `lib/legacy.dart` shows, and the classes declared under a `legacy/`
  /// directory. flutter_riverpod uses the first, riverpod the second.
  static List<String> legacySymbols(String packageRoot) {
    final symbols = <String>{};
    final library = File('$packageRoot/lib/legacy.dart');
    if (library.existsSync()) {
      for (final match in RegExp(
        r'\bshow\s+([\w\s,]+);',
      ).allMatches(library.readAsStringSync())) {
        symbols.addAll(
          match
              .group(1)!
              .split(',')
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty && !name.startsWith('_')),
        );
      }
    }
    final lib = Directory('$packageRoot/lib');
    if (lib.existsSync()) {
      for (final file
          in lib
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .where((file) => file.path.contains('/legacy/'))) {
        for (final match in RegExp(
          r'^(?:abstract\s+|final\s+|base\s+|sealed\s+|interface\s+)*class\s+(\w+)',
          multiLine: true,
        ).allMatches(file.readAsStringSync())) {
          final name = match.group(1)!;
          if (!name.startsWith('_')) symbols.add(name);
        }
      }
    }
    return symbols.toList(growable: false)..sort();
  }

  static final _versionHeading = RegExp(r'^#{1,3}\s+\[?v?(\d+)\.(\d+)\.(\d+)');
  static final _bullet = RegExp(r'^(\s*)[-*]\s+');

  /// Changelog entries marked breaking in the installed release line — the
  /// same major, or the same minor below 1.0 — at or below [installedVersion].
  ///
  /// Markers vary by package (`**Breaking**`, `**BREAKING CHANGE**`,
  /// `__Potentially breaking change__`), so the entry is matched on the word,
  /// and its wrapped or nested continuation lines are joined to it: go_router
  /// puts the substance of a breaking change in the bullets beneath the
  /// marker, and a "Breaking changes" subheading marks every bullet under
  /// it. Entries from older release lines are excluded; they describe a
  /// migration this installed version is already past.
  static List<String> breakingEntries(
    File changelog, {
    required String installedVersion,
    int limit = 6,
    int maxEntryChars = 240,
  }) {
    if (!changelog.existsSync()) return const [];
    final installed = _versionTriple(installedVersion);
    if (installed == null) return const [];
    final entries = <String>[];
    var inLine = false;
    // A "### Breaking changes" subheading marks every bullet under it.
    var inBreakingSection = false;
    String? current;
    var currentIndent = 0;

    void flush() {
      final entry = current;
      current = null;
      if (entry == null || entries.length >= limit) return;
      final text = cleanEntry(entry);
      entries.add(
        text.length <= maxEntryChars
            ? text
            : '${text.substring(0, maxEntryChars - 3).trimRight()}...',
      );
    }

    for (final line in changelog.readAsLinesSync()) {
      final heading = _versionHeading.firstMatch(line);
      if (heading != null) {
        flush();
        final version = [
          for (var group = 1; group <= 3; group++)
            int.parse(heading.group(group)!),
        ];
        inLine =
            _sameReleaseLine(version, installed) &&
            _compareRelease(version, installed) <= 0;
        inBreakingSection = false;
        continue;
      }
      if (line.startsWith('#')) {
        flush();
        inBreakingSection = line.toLowerCase().contains('breaking');
        continue;
      }
      if (!inLine) continue;
      final bullet = _bullet.firstMatch(line);
      if (current != null &&
          line.trim().isNotEmpty &&
          (bullet == null || bullet.group(1)!.length > currentIndent)) {
        current = '$current ${line.trim().replaceFirst(_bullet, '')}';
        continue;
      }
      flush();
      if (bullet != null &&
          (inBreakingSection || _marksBreaking(line.substring(bullet.end)))) {
        current = line.substring(bullet.end);
        currentIndent = bullet.group(1)!.length;
      }
    }
    flush();
    return entries;
  }

  /// Whether a bullet opens with a breaking marker, after an optional
  /// `scope:` prefix: `**Breaking**`, `BREAKING CHANGE:`, `chore: **Breaking
  /// change**`, `__Potentially breaking change__`. Prose that merely mentions
  /// the word ("Non-breaking updates", "Revert the breaking change") is not an
  /// entry.
  static bool _marksBreaking(String text) => RegExp(
    r'^(?:[\w-]+(?:\([^)]*\))?:\s*)?(?:potentially\s+)?breaking\b',
    caseSensitive: false,
  ).hasMatch(text.replaceAll(RegExp(r'[*_]'), '').trimLeft());

  /// Collapses an entry to its text: link targets, issue numbers, and commit
  /// hashes cost prompt space and say nothing about the API.
  static String cleanEntry(String entry) => entry
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (match) => match.group(1)!,
      )
      .replaceAll(RegExp(r'\s*\((?:#\d+|[0-9a-f]{7,40})\)\.?'), '')
      .replaceAll(RegExp(r'[*_]{2}'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<int>? _versionTriple(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
    if (match == null) return null;
    return [
      for (var group = 1; group <= 3; group++) int.parse(match.group(group)!),
    ];
  }

  static bool _sameReleaseLine(List<int> a, List<int> b) =>
      a[0] == b[0] && (a[0] > 0 || a[1] == b[1]);

  static int _compareRelease(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      final difference = a[i].compareTo(b[i]);
      if (difference != 0) return difference;
    }
    return 0;
  }

  /// Sortable key for a release string such as `v3.33.0-1.0.pre`.
  static List<int> _releaseKey(String since) {
    final numbers = RegExp(
      r'\d+',
    ).allMatches(since).map((m) => int.parse(m.group(0)!));
    return [...numbers, 0, 0, 0].take(3).toList(growable: false);
  }

  static Iterable<SdkDeprecation> _deprecationsIn(List<String> lines) sync* {
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('@Deprecated(')) continue;
      final annotation = StringBuffer();
      var j = i;
      while (j < lines.length && !lines[j].trimRight().endsWith(')')) {
        annotation.write('${lines[j].trim()} ');
        j++;
      }
      if (j >= lines.length) continue;
      annotation.write(lines[j].trim());
      var k = j + 1;
      while (k < lines.length &&
          (lines[k].trim().isEmpty ||
              lines[k].trim().startsWith('//') ||
              lines[k].trim().startsWith('@'))) {
        k++;
      }
      if (k >= lines.length) continue;
      final symbol = _declaredName(lines[k]);
      if (symbol == null) continue;
      final text = annotation.toString();
      final since = RegExp(r'after (v[\d.a-z-]+)').firstMatch(text)?.group(1);
      if (since == null) continue;
      final quoted = RegExp(r"'([^']*)'")
          .allMatches(text)
          .map((m) => m.group(1)!.trim())
          .where((part) => part.isNotEmpty && !part.startsWith('This feature'));
      yield SdkDeprecation(
        symbol: symbol,
        advice: quoted.join(' '),
        since: since,
      );
    }
  }

  /// The name a declaration line declares, or null when it declares nothing.
  static String? _declaredName(String line) {
    final trimmed = line.trim();
    for (final pattern in [
      RegExp(r'^(?:abstract\s+|sealed\s+|final\s+)*class\s+(\w+)'),
      RegExp(r'^(?:static\s+)?(?:final|const)\s+[\w<>?, ]+\s+(\w+)\s*[;=]'),
      RegExp(r'^[\w<>?, ]+\s+get\s+(\w+)'),
      RegExp(r'^(?:static\s+)?[\w<>?, ]+\s+(\w+)\s*\('),
    ]) {
      final match = pattern.firstMatch(trimmed);
      if (match != null) return match.group(1);
    }
    return null;
  }
}

/// Renders the digest for a prompt within a character budget.
///
/// Deterministic, so the bytes stay stable while the files do. The budget is
/// spent in a fixed order: legacy libraries first (compact, and each names an
/// idiom a package itself moved aside), then the newest SDK deprecations up to
/// [sdkAllowance], then one breaking entry per package in name order, then a
/// second, and so on. Round-robin rather than package by package, so a long
/// changelog early in the alphabet cannot crowd out every package after it.
abstract final class ChangeDigestRenderer {
  static const heading =
      'What the installed versions changed, from their own changelogs, '
      'legacy libraries, and deprecation annotations:';

  static String? render({
    required List<PackageChange> packages,
    required List<SdkDeprecation> sdkDeprecations,
    required String? flutterVersion,
    required int maxChars,
    int sdkAllowance = 1600,
    int maxEntryChars = 160,
  }) {
    if (maxChars <= heading.length) return null;
    final lines = <String>[];
    var used = heading.length;
    bool add(String line, {bool clip = true}) {
      final clipped = !clip || line.length <= maxEntryChars + 40
          ? line
          : '${line.substring(0, maxEntryChars + 37).trimRight()}...';
      if (used + 1 + clipped.length > maxChars) return false;
      lines.add(clipped);
      used += 1 + clipped.length;
      return true;
    }

    for (final change in packages) {
      if (change.legacySymbols.isEmpty) continue;
      add(
        '- ${change.record.name} ${change.record.lockedVersion} keeps these '
        'only in its legacy library: ${change.legacySymbols.join(', ')}',
        // A clipped symbol list drops exactly the names it exists to carry.
        clip: false,
      );
    }

    if (flutterVersion != null) {
      var sdkUsed = 0;
      for (final deprecation in sdkDeprecations) {
        final line =
            '- Flutter $flutterVersion deprecates ${deprecation.symbol}: '
            '${deprecation.advice}';
        if (sdkUsed + line.length + 1 > sdkAllowance) break;
        if (!add(line)) break;
        sdkUsed += line.length + 1;
      }
    }

    final seen = <String>{};
    final queues = [
      for (final change in packages)
        (
          change,
          [
            for (final entry in change.breakingEntries)
              if (seen.add(entry)) entry,
          ],
        ),
    ];
    var round = 0;
    var full = false;
    while (!full) {
      var any = false;
      for (final (change, entries) in queues) {
        if (round >= entries.length) continue;
        any = true;
        final line =
            '- ${change.record.name} ${change.record.lockedVersion}: '
            '${entries[round]}';
        if (!add(line)) {
          full = true;
          break;
        }
      }
      if (!any) break;
      round++;
    }
    if (lines.isEmpty) return null;
    return '$heading\n${lines.join('\n')}';
  }
}
