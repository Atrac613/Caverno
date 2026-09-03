import 'dart:convert';
import 'dart:io';

/// KC1 — the on-disk oracle for version-sensitive claims.
///
/// The Knowledge Currency track's premise is that the damaging case is not
/// missing knowledge but a model that cannot tell which of its beliefs expired.
/// Classes 2 and 3 of `docs/knowledge_currency_track_design.md` §2 — API drift
/// and environment facts — are answerable from the user's own disk with no
/// network, and KC1 exists to measure whether they dominate before anything is
/// built to fix them.
///
/// **The instrument must not encode the same expiry it is measuring.** A
/// fixture here does not get to declare which idiom is stale; it names a pair
/// of symbols and the oracle confirms from the installed SDK and pub cache
/// which one this project actually has. If a symbol is un-deprecated, or a
/// package moves an API back, the fixture fails loudly instead of quietly
/// measuring the author's own 2026 beliefs against a model's.
/// One deprecation the installed toolchain ships.
class ToolchainDeprecation {
  const ToolchainDeprecation({
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

class CutoffOracle {
  CutoffOracle({
    required this.flutterSdkRoot,
    required this.pubCacheRoot,
    required this.projectRoot,
  });

  /// Resolves the SDK from `.fvmrc` and the pub cache from the usual location.
  ///
  /// Both are overridable so a run can be pinned, which the KC1 acceptance
  /// criteria require: the oracle is part of the run's identity.
  factory CutoffOracle.resolve({
    String? projectRoot,
    String? flutterSdkRoot,
    String? pubCacheRoot,
    Map<String, String> environment = const {},
  }) {
    final root = projectRoot ?? Directory.current.path;
    final home = environment['HOME'] ?? Platform.environment['HOME'] ?? '';
    var sdk = flutterSdkRoot;
    if (sdk == null) {
      final fvmrc = File('$root/.fvmrc');
      if (fvmrc.existsSync()) {
        final decoded = jsonDecode(fvmrc.readAsStringSync());
        final version = (decoded as Map<String, dynamic>)['flutter'] as String?;
        if (version != null) sdk = '$home/fvm/versions/$version';
      }
    }
    return CutoffOracle(
      flutterSdkRoot: sdk ?? '',
      pubCacheRoot: pubCacheRoot ?? '$home/.pub-cache/hosted/pub.dev',
      projectRoot: root,
    );
  }

  final String flutterSdkRoot;
  final String pubCacheRoot;
  final String projectRoot;

  /// The Flutter version this project is pinned to, from `.fvmrc`.
  String? get flutterVersion {
    final fvmrc = File('$projectRoot/.fvmrc');
    if (!fvmrc.existsSync()) return null;
    final decoded = jsonDecode(fvmrc.readAsStringSync());
    return (decoded as Map<String, dynamic>)['flutter'] as String?;
  }

  /// Locked version of [package], from `pubspec.lock`.
  ///
  /// The lockfile rather than `pubspec.yaml`, because a caret constraint is not
  /// a fact about what is installed.
  String? packageVersion(String package) {
    final lock = File('$projectRoot/pubspec.lock');
    if (!lock.existsSync()) return null;
    String? current;
    for (final line in lock.readAsLinesSync()) {
      final name = RegExp(r'^  (\S+):').firstMatch(line);
      if (name != null) current = name.group(1);
      final version = RegExp(r'^    version: "(.+)"').firstMatch(line);
      if (version != null && current == package) return version.group(1);
    }
    return null;
  }

  int? packageMajor(String package) {
    final version = packageVersion(package);
    if (version == null) return null;
    return int.tryParse(version.split('.').first);
  }

  /// The `@Deprecated(...)` message attached to [symbol] in the installed
  /// Flutter SDK, or null when the SDK does not deprecate it.
  ///
  /// Searches the framework and the engine's `dart:ui`, because the two halves
  /// of "the SDK" live in different trees and a caller should not have to know
  /// which one owns a symbol.
  String? flutterDeprecation(String symbol) {
    for (final root in _flutterSourceRoots()) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final file in directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        final message = _deprecationBefore(file.readAsLinesSync(), symbol);
        if (message != null) return message;
      }
    }
    return null;
  }

  /// Whether the SDK still defines [symbol] at all.
  bool flutterDefines(String symbol) {
    for (final root in _flutterSourceRoots()) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      final found = directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .any(
            (file) => file
                .readAsStringSync()
                .contains(RegExp('(class|Color) $symbol\\b')),
          );
      if (found) return true;
    }
    return false;
  }

  /// Whether [package] defines [symbol] under a path segment named `legacy`.
  ///
  /// A package that keeps an old API working but moves it into `legacy/` has
  /// said what it thinks of the idiom without deprecating it, and that is the
  /// case Riverpod 3 presents.
  ///
  /// Matched on word boundaries. A substring match reports `NotifierProvider`
  /// as legacy because `StateNotifierProvider` contains it, which inverts the
  /// fixture it is supposed to validate — found by probing the oracle against
  /// real disk state before trusting it.
  bool packageSymbolIsLegacy(String package, String symbol) {
    final lib = Directory(_packageLib(package));
    if (!lib.existsSync()) return false;
    return lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .any(
          (file) =>
              file.path.contains('/legacy/') &&
              file.readAsStringSync().contains(RegExp('\\b$symbol\\b')),
        );
  }

  /// Whether [package]'s changelog records [needle] on a line marked breaking.
  ///
  /// Weaker evidence than a deprecation annotation and used only where the
  /// change is a codegen contract rather than a symbol — Freezed 3 requiring
  /// `abstract` cannot be found by looking for a deprecated class.
  String? packageBreakingChange(String package, String needle) {
    final version = packageVersion(package);
    if (version == null) return null;
    final changelog = File('$pubCacheRoot/$package-$version/CHANGELOG.md');
    if (!changelog.existsSync()) return null;
    for (final line in changelog.readAsLinesSync()) {
      final lowered = line.toLowerCase();
      if (lowered.contains('breaking') &&
          lowered.contains(needle.toLowerCase())) {
        return line.trim();
      }
    }
    return null;
  }

  /// Deprecations the installed SDK ships, newest first.
  ///
  /// The raw material for a KC2 "what changed" block. Read from the SDK rather
  /// than written down, for the same reason the fixtures are: a hand-written
  /// list of what expired is itself a belief with an expiry date.
  ///
  /// Ordered by the release named in the annotation, so a caller can take the
  /// most recent [limit] without deciding which APIs matter — that decision is
  /// exactly the one a digest must not smuggle in.
  List<ToolchainDeprecation> recentFlutterDeprecations({int limit = 40}) {
    final found = <ToolchainDeprecation>[];
    for (final root in _flutterSourceRoots()) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final file in directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        found.addAll(_deprecationsIn(file.readAsLinesSync()));
      }
    }
    found.sort((a, b) => _compareRelease(_releaseKey(b.since), _releaseKey(a.since)));
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

  /// Symbols [package] keeps under a `legacy/` path.
  ///
  /// Accepts every class modifier, not just `abstract`. Riverpod declares
  /// `final class StateNotifierProvider<...>`, and a regex that only knew
  /// `abstract` returned one symbol out of the set — a digest missing the very
  /// idiom the fixture is about.
  List<String> packageLegacySymbols(String package) {
    final lib = Directory(_packageLib(package));
    if (!lib.existsSync()) return const [];
    final symbols = <String>{};
    for (final file in lib
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
    return symbols.toList(growable: false)..sort();
  }

  /// Breaking-change lines from [package]'s changelog, newest first.
  List<String> packageBreakingChanges(String package, {int limit = 6}) {
    final version = packageVersion(package);
    if (version == null) return const [];
    final changelog = File('$pubCacheRoot/$package-$version/CHANGELOG.md');
    if (!changelog.existsSync()) return const [];
    return changelog
        .readAsLinesSync()
        .where((line) => line.toLowerCase().contains('breaking'))
        .map((line) => line.trim())
        .take(limit)
        .toList(growable: false);
  }

  static int _compareRelease(List<int> a, List<int> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      final difference = a[i].compareTo(b[i]);
      if (difference != 0) return difference;
    }
    return 0;
  }

  /// Sortable key for a release string such as `v3.33.0-1.0.pre`.
  static List<int> _releaseKey(String since) {
    final numbers = RegExp(r'\d+').allMatches(since).map((m) => int.parse(m.group(0)!));
    return [...numbers, 0, 0, 0].take(3).toList(growable: false);
  }

  static Iterable<ToolchainDeprecation> _deprecationsIn(List<String> lines) sync* {
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
      yield ToolchainDeprecation(
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

  /// How often each of [symbols] appears in the project's own `lib/`.
  ///
  /// The class 4 oracle. "What does this repository do" is not a fact about a
  /// package version and cannot be read from a lockfile — it is read from the
  /// code, and it is the one class where a model can be current about the
  /// ecosystem and still wrong here. Generated files are excluded: what
  /// `build_runner` emitted is not a convention anyone chose.
  Map<String, int> repoUsage(Iterable<String> symbols) {
    final counts = {for (final symbol in symbols) symbol: 0};
    final lib = Directory('$projectRoot/lib');
    if (!lib.existsSync()) return counts;
    for (final file in lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              !file.path.endsWith('.g.dart') &&
              !file.path.endsWith('.freezed.dart'),
        )) {
      final contents = file.readAsStringSync();
      for (final symbol in counts.keys) {
        counts[symbol] = counts[symbol]! +
            RegExp('\\b$symbol\\b').allMatches(contents).length;
      }
    }
    return counts;
  }

  String _packageLib(String package) {
    final version = packageVersion(package);
    return '$pubCacheRoot/$package-$version/lib';
  }

  List<String> _flutterSourceRoots() => [
    '$flutterSdkRoot/packages/flutter/lib/src',
    '$flutterSdkRoot/bin/cache/pkg/sky_engine/lib/ui',
  ];

  /// The `@Deprecated('...')` message on the declaration of [symbol], if the
  /// annotation sits within a few lines above it.
  static String? _deprecationBefore(List<String> lines, String symbol) {
    final declaration = RegExp('(class|Color) $symbol\\b');
    for (var i = 0; i < lines.length; i++) {
      if (!declaration.hasMatch(lines[i])) continue;
      final from = i - 8 < 0 ? 0 : i - 8;
      final window = lines.sublist(from, i).join(' ');
      final marker = window.lastIndexOf('@Deprecated(');
      if (marker < 0) continue;
      // Only the annotation's own text: prose above it carries apostrophes,
      // and a quote-run scan over the whole window returns that instead.
      final annotation = window.substring(marker);
      final quoted = RegExp(r"'([^']*)'").allMatches(annotation);
      if (quoted.isEmpty) return '@Deprecated';
      return quoted
          .map((match) => match.group(1)!.trim())
          .where((part) => part.isNotEmpty)
          .join(' ');
    }
    return null;
  }
}
