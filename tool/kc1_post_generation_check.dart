import 'dart:convert';
import 'dart:io';

import 'kc1_cutoff_oracle.dart';

/// KC1 slice 3 — would a post-generation symbol check have caught these?
///
/// The second census settled what a KC2 prompt block should carry and left one
/// problem behind: **coverage**. A block has to guess which APIs will matter
/// before the model writes anything, and the measurement showed it fixes
/// exactly the cases it guessed and nothing else — three of three covered,
/// zero of one uncovered.
///
/// KC4 (`docs/knowledge_currency_track_design.md`) does not have that problem
/// by construction. It reads the answer, so it knows precisely which symbols
/// were used. Its promotion gate asks for precision and recall against KC1's
/// labeled set, shadow-only, before anything transforms an answer.
///
/// That set exists, and so do the responses. This replays them offline: no
/// model, no endpoint, no new requests. It answers whether the check KC4 would
/// perform actually finds what the census already labeled stale — including the
/// case the digest could not reach.
///
/// Two honest limits on what a symbol check can claim, both reported rather
/// than assumed away:
///
/// - It can only flag what the oracle knows. A stale idiom that is not an
///   annotated deprecation or a `legacy/` symbol — Freezed's missing `abstract`
///   is a codegen contract, not a symbol — is invisible to it, and is counted
///   here as a miss rather than quietly excluded.
/// - Its precision risk offline is firing on a mention rather than a use. That
///   is measured by scoring each response twice, once with comments and once
///   without, and reporting the difference.
///
/// **This index nominates; it must never render a verdict.** Measured
/// 2026-09-03: bare-identifier matching flagged 14 of 30 correct answers, and
/// almost every flag was a collision on a common word — `alpha`, `value`,
/// `builder`, `of`, `blue` — because those are deprecated *field names*
/// somewhere in the SDK and a name has no receiver type. `.withValues(alpha:
/// 0.5)`, the current idiom, trips `alpha`. As a nominator that is acceptable:
/// nineteen nominations over thirty answers is cheap to verify. As a verdict it
/// would fail KC4's own precision gate, which is why the design says the verdict
/// comes only from ground truth — LL11 `deprecated_member_use`, which knows the
/// receiver's type — and never from the pattern that triggered the check.
Future<void> main(List<String> args) async {
  final options = CheckOptions.parse(args);
  if (options == null) {
    stderr.writeln(CheckOptions.usage);
    exitCode = 64;
    return;
  }

  final oracle = CutoffOracle.resolve(projectRoot: options.projectRoot);
  final flags = StaleSymbolIndex.fromOracle(oracle, packages: options.packages);
  if (flags.isEmpty) {
    stderr.writeln('The oracle produced no stale symbols; check the SDK path.');
    exitCode = 65;
    return;
  }

  final verdicts = _loadVerdicts(options.censusPaths);
  final responses = _loadResponses(options.rawDirectories);
  if (responses.isEmpty) {
    stderr.writeln('No raw responses found under ${options.rawDirectories}.');
    exitCode = 65;
    return;
  }

  final report = replayPostGenerationCheck(
    responses: responses,
    verdicts: verdicts,
    index: flags,
  );
  final encoded = const JsonEncoder.withIndent('  ').convert(report.toJson());
  if (options.outputPath != null) {
    final file = File(options.outputPath!);
    await file.parent.create(recursive: true);
    await file.writeAsString('$encoded\n');
  }
  stdout.writeln(options.json ? encoded : report.render());
}

/// Every symbol the installed toolchain considers expired.
///
/// Built once. Unlike the KC2 digest this is deliberately **uncapped**: a
/// prompt block has a token budget and has to choose, and a post-generation
/// check has neither constraint. That asymmetry is the thing being measured.
class StaleSymbolIndex {
  const StaleSymbolIndex({required this.deprecations, required this.legacy});

  factory StaleSymbolIndex.fromOracle(
    CutoffOracle oracle, {
    required List<String> packages,
  }) {
    final deprecations = <String, String>{};
    for (final entry in oracle.recentFlutterDeprecations(limit: 100000)) {
      deprecations.putIfAbsent(entry.symbol, () => entry.advice);
    }
    final legacy = <String, String>{};
    for (final package in packages) {
      for (final symbol in oracle.packageLegacySymbols(package)) {
        legacy.putIfAbsent(symbol, () => package);
      }
    }
    return StaleSymbolIndex(deprecations: deprecations, legacy: legacy);
  }

  /// Symbol to the advice its annotation gives.
  final Map<String, String> deprecations;

  /// Symbol to the package that keeps it under `legacy/`.
  final Map<String, String> legacy;

  bool get isEmpty => deprecations.isEmpty && legacy.isEmpty;

  int get length => deprecations.length + legacy.length;

  /// Why [symbol] is expired, or null when the toolchain does not say it is.
  String? reasonFor(String symbol) {
    if (deprecations[symbol] case final advice?) {
      return 'deprecated: $advice';
    }
    if (legacy[symbol] case final package?) {
      return 'moved to $package legacy';
    }
    return null;
  }
}

/// One dumped response, identified the way the census named the file.
class ReplayedResponse {
  const ReplayedResponse({
    required this.caseId,
    required this.arm,
    required this.repeat,
    required this.content,
  });

  final String caseId;
  final String arm;
  final int repeat;
  final String content;

  String get key => '$caseId|$arm|$repeat';
}

class SymbolFlag {
  const SymbolFlag({
    required this.symbol,
    required this.reason,
    required this.inCode,
  });

  final String symbol;
  final String reason;

  /// False when the symbol appears only in a comment.
  final bool inCode;

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'reason': reason,
    'in_code': inCode,
  };
}

class ReplayReport {
  const ReplayReport({
    required this.indexSize,
    required this.rows,
  });

  final int indexSize;
  final List<ReplayRow> rows;

  Iterable<ReplayRow> get labelledStale =>
      rows.where((row) => row.verdict == 'stale');

  Iterable<ReplayRow> get labelledCorrect =>
      rows.where((row) => row.verdict == 'correct');

  int get caught =>
      labelledStale.where((row) => row.codeFlags.isNotEmpty).length;

  int get missed =>
      labelledStale.where((row) => row.codeFlags.isEmpty).length;

  /// Correct answers the check would still have flagged.
  ///
  /// Not automatically a false positive: a response can use the current idiom
  /// for the fixture and an unrelated expired API elsewhere, which is a real
  /// finding rather than noise. Listed so the distinction stays visible.
  int get flaggedCorrect =>
      labelledCorrect.where((row) => row.codeFlags.isNotEmpty).length;

  /// Flags that would only have come from a comment.
  int get commentOnlyFlags => rows.fold<int>(
    0,
    (sum, row) => sum + row.commentOnlyFlags.length,
  );

  Map<String, dynamic> toJson() => {
    'schema': 'caverno_kc1_post_generation_check',
    'schemaVersion': 1,
    'indexSize': indexSize,
    'responses': rows.length,
    'labelledStale': labelledStale.length,
    'caught': caught,
    'missed': missed,
    'flaggedCorrect': flaggedCorrect,
    'labelledCorrect': labelledCorrect.length,
    'commentOnlyFlags': commentOnlyFlags,
    'rows': rows.map((row) => row.toJson()).toList(growable: false),
  };

  String render() {
    final stale = labelledStale.length;
    final buffer = StringBuffer()
      ..writeln('KC1 — post-generation symbol check, replayed offline')
      ..writeln('stale symbols known to the oracle: $indexSize')
      ..writeln('responses replayed: ${rows.length}')
      ..writeln()
      ..writeln('against the claims the census labelled stale ($stale)')
      ..writeln('  caught: $caught')
      ..writeln('  missed: $missed');
    if (stale > 0) {
      buffer.writeln(
        '  recall: ${(caught / stale * 100).toStringAsFixed(0)}%',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        'also flagged in ${labelledCorrect.length} responses labelled correct: '
        '$flaggedCorrect',
      )
      ..writeln(
        'flags that came only from a comment: $commentOnlyFlags',
      )
      ..writeln()
      ..writeln('missed, by case');
    final missedByCase = <String, int>{};
    for (final row in labelledStale.where((row) => row.codeFlags.isEmpty)) {
      missedByCase[row.caseId] = (missedByCase[row.caseId] ?? 0) + 1;
    }
    if (missedByCase.isEmpty) {
      buffer.writeln('  none');
    } else {
      for (final entry in missedByCase.entries) {
        buffer.writeln('  ${entry.key.padRight(24)} ${entry.value}');
      }
    }
    return buffer.toString();
  }
}

class ReplayRow {
  const ReplayRow({
    required this.caseId,
    required this.arm,
    required this.repeat,
    required this.verdict,
    required this.flags,
  });

  final String caseId;
  final String arm;
  final int repeat;

  /// The census truth verdict, or `unlabelled` when the run predates the dump.
  final String verdict;
  final List<SymbolFlag> flags;

  List<SymbolFlag> get codeFlags =>
      flags.where((flag) => flag.inCode).toList(growable: false);

  List<SymbolFlag> get commentOnlyFlags =>
      flags.where((flag) => !flag.inCode).toList(growable: false);

  Map<String, dynamic> toJson() => {
    'case': caseId,
    'arm': arm,
    'repeat': repeat,
    'verdict': verdict,
    'flags': flags.map((flag) => flag.toJson()).toList(growable: false),
  };
}

ReplayReport replayPostGenerationCheck({
  required List<ReplayedResponse> responses,
  required Map<String, String> verdicts,
  required StaleSymbolIndex index,
}) {
  final rows = <ReplayRow>[];
  for (final response in responses) {
    // Both sets once per response, not once per symbol: the identifier scan is
    // a regex over the whole text and there are a few hundred symbols to test.
    final mentioned = extractIdentifiers(response.content);
    final inCode = extractIdentifiers(stripComments(response.content));
    final flags = <SymbolFlag>[];
    for (final symbol in mentioned) {
      final reason = index.reasonFor(symbol);
      if (reason == null) continue;
      flags.add(
        SymbolFlag(
          symbol: symbol,
          reason: reason,
          inCode: inCode.contains(symbol),
        ),
      );
    }
    rows.add(
      ReplayRow(
        caseId: response.caseId,
        arm: response.arm,
        repeat: response.repeat,
        verdict: verdicts[response.key] ?? 'unlabelled',
        flags: flags,
      ),
    );
  }
  return ReplayReport(indexSize: index.length, rows: rows);
}

/// Identifiers a response mentions, including `.method` call targets.
Set<String> extractIdentifiers(String content) => RegExp(r'\b[A-Za-z_]\w*\b')
    .allMatches(content)
    .map((match) => match.group(0)!)
    .toSet();

/// [content] with comment lines, trailing comments and fence markers removed.
///
/// A symbol named only in a comment is a mention, not a use, and the difference
/// is the only precision signal available without running the code.
String stripComments(String content) {
  final kept = <String>[];
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('```')) continue;
    if (trimmed.startsWith('//')) continue;
    final marker = line.indexOf('//');
    kept.add(marker < 0 ? line : line.substring(0, marker));
  }
  return kept.join('\n');
}

Map<String, String> _loadVerdicts(List<String> censusPaths) {
  final verdicts = <String, String>{};
  for (final path in censusPaths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    for (final record in (decoded['records'] as List<dynamic>? ?? const [])) {
      final row = record as Map<String, dynamic>;
      final key = '${row['case']}|${row['arm']}|${row['repeat']}';
      verdicts[key] = row['truth_verdict'] as String? ?? 'unlabelled';
    }
  }
  return verdicts;
}

List<ReplayedResponse> _loadResponses(List<String> directories) {
  final responses = <ReplayedResponse>[];
  for (final path in directories) {
    final directory = Directory(path);
    if (!directory.existsSync()) continue;
    for (final file in directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.txt'))) {
      final name = file.uri.pathSegments.last.replaceAll('.txt', '');
      final parts = name.split('.');
      if (parts.length < 3) continue;
      responses.add(
        ReplayedResponse(
          caseId: parts[0],
          arm: parts[1],
          repeat: int.tryParse(parts[2]) ?? 0,
          content: file.readAsStringSync(),
        ),
      );
    }
  }
  return responses;
}

class CheckOptions {
  const CheckOptions({
    required this.censusPaths,
    required this.rawDirectories,
    required this.packages,
    required this.projectRoot,
    required this.json,
    required this.outputPath,
  });

  static const usage =
      'Usage: dart run tool/kc1_post_generation_check.dart \\\n'
      '  --raw build/kc1/raw_delta [--raw <dir>]... \\\n'
      '  --census build/kc1/census_delta.json [--census <file>]... \\\n'
      '  [--package riverpod]... [--json] [--out build/kc1/postgen.json]\n'
      'Replays dumped responses against the on-disk oracle. Sends nothing.';

  final List<String> censusPaths;
  final List<String> rawDirectories;
  final List<String> packages;
  final String projectRoot;
  final bool json;
  final String? outputPath;

  static CheckOptions? parse(List<String> args) {
    final censusPaths = <String>[];
    final rawDirectories = <String>[];
    final packages = <String>[];
    var projectRoot = Directory.current.path;
    var json = false;
    String? outputPath;

    String? value(int index) => index + 1 < args.length ? args[index + 1] : null;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--census':
          if (value(i) case final path?) censusPaths.add(path);
          i++;
        case '--raw':
          if (value(i) case final path?) rawDirectories.add(path);
          i++;
        case '--package':
          if (value(i) case final name?) packages.add(name);
          i++;
        case '--project-root':
          projectRoot = value(i) ?? projectRoot;
          i++;
        case '--out':
          outputPath = value(i);
          i++;
        case '--json':
          json = true;
        case '--help':
          return null;
      }
    }
    if (rawDirectories.isEmpty) return null;
    return CheckOptions(
      censusPaths: censusPaths,
      rawDirectories: rawDirectories,
      packages: packages.isEmpty ? const ['riverpod'] : packages,
      projectRoot: projectRoot,
      json: json,
      outputPath: outputPath,
    );
  }
}
