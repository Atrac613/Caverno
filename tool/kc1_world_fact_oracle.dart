import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// KC1 class 1 oracle: world facts, read from the registry that publishes them.
///
/// Classes 2-4 are answerable from the user's disk; class 1 is not, by
/// definition (`docs/knowledge_currency_track_design.md` §2). What *is* on disk
/// is the installed version, and that is a different fact: this repository
/// locks freezed 3.2.5 while pub.dev's latest stable is 4.x. A new-project
/// answer that copies the lockfile is stale about the world while being
/// correct about this project, so the two oracles must never be merged.
///
/// The ground here is the registry's machine-readable API rather than a web
/// search, which keeps the verdict deterministic: the claim scored is the
/// version a pubspec constraint names, and the expected value is what pub.dev
/// reports as the latest stable release at fetch time.
///
/// **A world fact expires.** The snapshot therefore carries its source URL and
/// fetch time, and a run records the snapshot it was scored against. Two runs
/// against different snapshots are not a paired comparison; replay a frozen
/// snapshot (`--world-facts`) when they must be.
class WorldFact {
  const WorldFact({
    required this.package,
    required this.latestVersion,
    required this.publishedAt,
    required this.source,
    required this.fetchedAt,
  });

  factory WorldFact.fromJson(Map<String, dynamic> json) => WorldFact(
    package: json['package'] as String,
    latestVersion: json['latestVersion'] as String,
    publishedAt: json['publishedAt'] as String?,
    source: json['source'] as String,
    fetchedAt: json['fetchedAt'] as String,
  );

  final String package;
  final String latestVersion;
  final String? publishedAt;
  final String source;
  final String fetchedAt;

  Map<String, dynamic> toJson() => {
    'package': package,
    'latestVersion': latestVersion,
    'publishedAt': publishedAt,
    'source': source,
    'fetchedAt': fetchedAt,
  };
}

class WorldFactSnapshot {
  const WorldFactSnapshot(this.facts);

  factory WorldFactSnapshot.fromJson(Map<String, dynamic> json) =>
      WorldFactSnapshot({
        for (final entry in (json['facts'] as Map<String, dynamic>).entries)
          entry.key: WorldFact.fromJson(entry.value as Map<String, dynamic>),
      });

  static WorldFactSnapshot load(String path) => WorldFactSnapshot.fromJson(
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
  );

  final Map<String, WorldFact> facts;

  WorldFact? operator [](String package) => facts[package];

  Map<String, dynamic> toJson() => {
    'schema': 'caverno_kc1_world_fact_snapshot',
    'schemaVersion': 1,
    'facts': {
      for (final entry in facts.entries) entry.key: entry.value.toJson(),
    },
  };

  /// Reads each package's latest stable release from pub.dev.
  ///
  /// A package that cannot be read is an error, not an omission: a fixture
  /// scored without its expected value would be silently dropped from the
  /// class 1 rate, which is the rate this oracle exists to produce.
  static Future<WorldFactSnapshot> fetch({
    required HttpClient client,
    required Iterable<String> packages,
    String registry = 'https://pub.dev',
    Duration timeout = const Duration(seconds: 20),
    DateTime Function() now = DateTime.now,
  }) async {
    final facts = <String, WorldFact>{};
    for (final package in packages) {
      final source = '$registry/api/packages/$package';
      final request = await client.getUrl(Uri.parse(source));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.pub.v2+json',
      );
      final response = await request.close().timeout(timeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('$source: HTTP ${response.statusCode}');
      }
      final latest =
          (jsonDecode(body) as Map<String, dynamic>)['latest']
              as Map<String, dynamic>?;
      final version = latest?['version'] as String?;
      if (version == null) {
        throw HttpException('$source: response carried no latest version');
      }
      facts[package] = WorldFact(
        package: package,
        latestVersion: version,
        publishedAt: latest?['published'] as String?,
        source: source,
        fetchedAt: now().toUtc().toIso8601String(),
      );
    }
    return WorldFactSnapshot(facts);
  }
}

/// A pub version reduced to what a release-line comparison needs. Pre-release
/// and build suffixes are ignored: the registry's `latest` is always stable.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(this.major, this.minor, this.patch);

  static final _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$');

  static ReleaseVersion? tryParse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) return null;
    return ReleaseVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  /// The caret-compatible line: the major for 1.0.0 and later, the minor
  /// below it, matching what `^` admits in pub.
  (int, int) get line => major > 0 ? (major, 0) : (0, minor);

  @override
  int compareTo(ReleaseVersion other) => major != other.major
      ? major.compareTo(other.major)
      : minor != other.minor
      ? minor.compareTo(other.minor)
      : patch.compareTo(other.patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// How a pubspec version constraint relates to the latest published release.
enum WorldFactVerdict {
  /// Names the latest release line: the constraint admits the latest release.
  current,

  /// Names an older release line: the expired belief KC1 measures.
  behind,

  /// Names a version newer than anything published: a fabrication, not
  /// staleness, kept separate so it is not read as a cutoff effect.
  ahead,

  /// No version claim: missing, `any`, a path or git source, a conflicting
  /// pair of lines, or a form this scorer does not parse.
  unscorable,
}

/// Every constraint [response] gives [package] in a pubspec, in order.
///
/// Anchored to the start of a line so `riverpod:` does not match inside
/// `flutter_riverpod:`, and read from `dependencies` and `dev_dependencies`
/// alike: freezed belongs in the latter, and the model is right to put it
/// there.
List<String> pubspecConstraintsFor(String response, String package) => [
  for (final match in RegExp(
    '^[ \\t]*${RegExp.escape(package)}[ \\t]*:[ \\t]*(.*)\$',
    multiLine: true,
  ).allMatches(response))
    match.group(1)!.trim(),
];

/// Scores one constraint against [latest]. Reads only the constraint, never
/// prose, in the same spirit as the idiom scorer.
WorldFactVerdict scoreVersionConstraint({
  required String constraint,
  required ReleaseVersion latest,
}) {
  final text = constraint
      .replaceAll(RegExp(r'\s+#.*$'), '')
      .replaceAll(RegExp('''^["']|["']\$'''), '')
      .trim();
  if (text.isEmpty || text == 'any') return WorldFactVerdict.unscorable;

  ReleaseVersion? lower;
  ReleaseVersion? upper;
  var upperInclusive = false;
  if (text.startsWith('^')) {
    lower = ReleaseVersion.tryParse(text.substring(1));
  } else if (text.startsWith('>=') || text.startsWith('>')) {
    final bounds = RegExp(
      r'^>=?\s*(\S+)(?:\s+<(=?)\s*(\S+))?$',
    ).firstMatch(text);
    if (bounds == null) return WorldFactVerdict.unscorable;
    lower = ReleaseVersion.tryParse(bounds.group(1)!);
    if (bounds.group(3) case final upperText?) {
      upper = ReleaseVersion.tryParse(upperText);
      if (upper == null) return WorldFactVerdict.unscorable;
      upperInclusive = bounds.group(2) == '=';
    }
  } else {
    lower = ReleaseVersion.tryParse(text);
  }
  if (lower == null) return WorldFactVerdict.unscorable;

  if (lower.compareTo(latest) > 0) return WorldFactVerdict.ahead;
  // An explicit range that admits the latest release names it, whatever its
  // lower bound: `>=3.0.0 <5.0.0` is current when 4.x is latest.
  if (upper != null) {
    final belowUpper = upperInclusive
        ? latest.compareTo(upper) <= 0
        : latest.compareTo(upper) < 0;
    return belowUpper ? WorldFactVerdict.current : WorldFactVerdict.behind;
  }
  return lower.line == latest.line
      ? WorldFactVerdict.current
      : WorldFactVerdict.behind;
}

/// Scores every constraint [response] gives [package]. Constraints that
/// disagree are unscorable rather than either side, like an idiom response
/// that uses both idioms.
({WorldFactVerdict verdict, String asserted}) scoreWorldFactResponse({
  required String response,
  required String package,
  required ReleaseVersion latest,
}) {
  final constraints = pubspecConstraintsFor(response, package);
  if (constraints.isEmpty) {
    return (verdict: WorldFactVerdict.unscorable, asserted: 'none');
  }
  final verdicts = {
    for (final constraint in constraints)
      scoreVersionConstraint(constraint: constraint, latest: latest),
  };
  return (
    verdict: verdicts.length == 1
        ? verdicts.single
        : WorldFactVerdict.unscorable,
    asserted: constraints.join(' | '),
  );
}
