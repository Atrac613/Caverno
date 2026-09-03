import 'dart:convert';
import 'dart:io';

import 'kc1_cutoff_oracle.dart';

/// KC1 — cutoff exposure census, first slice: the paired replay.
///
/// Design: `docs/knowledge_currency_track_design.md` §2 and §4. The premise is
/// that "knowledge cutoff" is four problems, not one, and that two of them —
/// API drift and environment facts — are answerable from the user's own disk
/// with no network at all. KC1 measures whether they are actually the frequent
/// ones before any milestone is built to fix them.
///
/// This slice ships the instrument the acceptance criteria are written around:
/// a labeled fixture set with authoritative expected values, replayed under a
/// fixed model, endpoint, sampler and build, with a negative control.
///
/// Three properties it holds deliberately.
///
/// **The instrument does not encode the expiry it measures.** A fixture names a
/// pair of idioms; it does not get to declare which is stale. `CutoffOracle`
/// confirms that from the installed SDK and pub cache, and `verifyFixtures`
/// fails the run when it cannot. Otherwise this measures the author's beliefs
/// from one date against a model's from another, and calls the difference a
/// finding.
///
/// **Truth and grounding are separate axes.** A correct claim made with nothing
/// to ground it and a stale claim made with nothing to ground it get different
/// truth verdicts and the same grounding verdict, which is what the criteria
/// require and what a single "did it get it right" number destroys.
///
/// **Scoring never reads prose.** Each fixture carries two patterns and the
/// verdict is which of them the response matched. A response matching both or
/// neither is `unscorable`, reported as itself rather than folded into either
/// side.
///
/// Scope limit, stated rather than implied. Classes 2 (API drift) and 4 (this
/// repository) are covered; classes 1 and 3 are not, and neither is an
/// oversight:
///
/// - **Class 1, world facts**, has no offline oracle by definition — its
///   correct ground is web search, per §2. Sizing it needs a networked run, not
///   a fixture here.
/// - **Class 3, environment facts**, does not decompose into a two-idiom pair.
///   Its failure is usually an *unnecessary* line rather than a wrong one — a
///   model setting `useMaterial3: true` on an SDK where it is both the default
///   and deprecated. Scoring "wrote something superfluous" needs a different
///   verdict shape than "used the expired idiom of two", and forcing it into
///   this one would make most responses unscorable.
///
/// So the §4 promotion gate, which asks whether class 2 *dominates*, is not yet
/// answered. What this measures is class 2's rate against class 4's.
Future<void> main(List<String> args) async {
  final options = CensusOptions.parse(args, Platform.environment);
  if (options == null) {
    stderr.writeln(CensusOptions.usage);
    exitCode = 64;
    return;
  }

  final oracle = CutoffOracle.resolve(projectRoot: options.projectRoot);
  final fixtureProblems = verifyFixtures(cutoffCases, oracle);
  if (fixtureProblems.isNotEmpty) {
    stderr.writeln('Fixture verification failed against the installed toolchain:');
    for (final problem in fixtureProblems) {
      stderr.writeln('  - $problem');
    }
    exitCode = 65;
    return;
  }
  if (options.verifyOnly) {
    stdout.writeln('All ${cutoffCases.length} fixtures confirmed by the oracle.');
    stdout.writeln(groundTruthBlock(oracle));
    return;
  }

  final client = HttpClient();
  try {
    final summary = await runCutoffCensus(
      options: options,
      oracle: oracle,
      send: (system, user) => postChatCompletion(
        client: client,
        endpoint: options.endpoint,
        model: options.model,
        apiKey: options.apiKey,
        temperature: options.temperature,
        timeout: options.timeout,
        systemPrompt: system,
        userPrompt: user,
      ),
      onProgress: (line) => stderr.writeln(line),
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(summary.toJson());
    if (options.outputPath != null) {
      final file = File(options.outputPath!);
      await file.parent.create(recursive: true);
      await file.writeAsString('$encoded\n');
    }
    stdout.writeln(options.json ? encoded : summary.report());
  } finally {
    client.close(force: true);
  }
}

typedef ChatCompletionSender =
    Future<String> Function(String systemPrompt, String userPrompt);

/// The four failure classes of `docs/knowledge_currency_track_design.md` §2.
enum CutoffClass { worldFact, apiDrift, environment, thisRepository }

/// Where a claim's grounding came from, per the KC1 claim record.
enum GroundingProvenance { promptContext, toolResult, none }

enum TruthVerdict { correct, stale, unscorable }

enum GroundingVerdict { supported, contradicted, absent }

/// One replayable case.
///
/// [task] is phrased as the work, not as a quiz about versions. Asking "which
/// version of X is installed" measures whether the model will look something
/// up; the damaging case is the model writing the expired idiom while doing
/// ordinary work, which is what this asks for.
class CutoffCase {
  const CutoffCase({
    required this.id,
    required this.cutoffClass,
    required this.task,
    required this.stale,
    required this.current,
    required this.confirmStale,
    required this.description,
    this.coverageSymbols = const [],
  });

  final String id;
  final CutoffClass cutoffClass;
  final String task;

  /// Matches the expired idiom.
  final RegExp stale;

  /// Matches the idiom this project's installed toolchain actually uses.
  final RegExp current;

  /// Reads the installed toolchain and returns why [stale] is expired, or null
  /// when the toolchain does not agree — which fails the run.
  final String? Function(CutoffOracle oracle) confirmStale;

  final String description;

  /// Plain names whose presence in the delta block counts as coverage.
  ///
  /// Separate from [stale], which is a pattern for *code* — `\.withOpacity\(`
  /// never appears in a prose digest that renders the symbol as `withOpacity`.
  /// Matching the code pattern against the digest reported every case as
  /// uncovered, which would have read as a digest that reaches nothing.
  final List<String> coverageSymbols;
}

final cutoffCases = <CutoffCase>[
  CutoffCase(
    id: 'flutter-pop-scope',
    coverageSymbols: const ['WillPopScope'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'WillPopScope superseded by PopScope',
    task:
        'In Flutter, write a widget that asks the user to confirm before '
        'leaving a screen that has unsaved changes. Return only Dart code.',
    stale: RegExp(r'\bWillPopScope\b'),
    current: RegExp(r'\bPopScope\b'),
    confirmStale: (oracle) => oracle.flutterDeprecation('WillPopScope') == null
        ? 'the installed SDK does not deprecate WillPopScope'
        : oracle.flutterDeprecation('PopScope') != null
        ? 'the installed SDK deprecates PopScope too'
        : null,
  ),
  CutoffCase(
    id: 'color-with-values',
    coverageSymbols: const ['withOpacity'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'Color.withOpacity superseded by Color.withValues',
    // Names an existing colour and asks for it transformed. The first wording
    // -- "give the expression for a Color at 50% opacity" -- invited
    // constructing one instead, and the model answered `const
    // Color(0x80FF0000)` in eight of ten runs: neither idiom, so the fixture
    // measured its own phrasing rather than the model.
    task:
        'In Flutter, given `final base = Colors.blue;`, give the expression '
        'for that same colour at 50% opacity. Return only the Dart expression.',
    stale: RegExp(r'\.withOpacity\('),
    current: RegExp(r'\.withValues\('),
    confirmStale: (oracle) => oracle.flutterDeprecation('withOpacity') == null
        ? 'the installed SDK does not deprecate Color.withOpacity'
        : null,
  ),
  CutoffCase(
    id: 'riverpod-notifier',
    coverageSymbols: const ['StateNotifierProvider', 'StateProvider'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'StateNotifierProvider moved to riverpod legacy',
    task:
        'Using Riverpod, write a provider holding an int counter with an '
        'increment method. Return only Dart code.',
    stale: RegExp(r'\bStateNotifierProvider\b|\bStateProvider\b'),
    current: RegExp(r'\bNotifierProvider\b|\bAsyncNotifierProvider\b'),
    confirmStale: (oracle) =>
        !oracle.packageSymbolIsLegacy('riverpod', 'StateNotifierProvider')
        ? 'the installed riverpod does not keep StateNotifierProvider under legacy/'
        : oracle.packageSymbolIsLegacy('riverpod', 'NotifierProvider')
        ? 'the installed riverpod treats NotifierProvider as legacy too'
        : null,
  ),
  CutoffCase(
    id: 'freezed-abstract',
    coverageSymbols: const ['Freezed classes'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'Freezed 3 requires abstract or sealed on the class',
    task:
        'Using the freezed package, write a data class named Point with int x '
        'and int y. Return only Dart code.',
    stale: RegExp(r'^\s*(?:@\w+\s+)?class\s+\w+\s+with\s+_\$', multiLine: true),
    current: RegExp(
      r'^\s*(?:abstract|sealed)\s+class\s+\w+\s+with\s+_\$',
      multiLine: true,
    ),
    confirmStale: (oracle) =>
        oracle.packageBreakingChange('freezed', 'abstract') == null
        ? 'the installed freezed changelog records no breaking abstract requirement'
        : null,
  ),
  CutoffCase(
    id: 'repo-state-management',
    cutoffClass: CutoffClass.thisRepository,
    description: 'this project holds state in Riverpod Notifier providers',
    task:
        'In this Flutter project, add a state holder for a counter with an '
        'increment method, following the project\'s existing conventions. '
        'Return only Dart code.',
    // Bare `ChangeNotifier` as well as `ChangeNotifierProvider`: `\b` does not
    // match inside the longer name, and the first live run returned
    // `class CounterStateHolder extends ChangeNotifier` three times out of
    // three. Without this the whole arm scored unscorable and read as the model
    // having asserted nothing, when it had asserted the wrong thing every time.
    stale: RegExp(
      r'\bChangeNotifier\b|\bChangeNotifierProvider\b|\bBlocProvider\b'
      r'|\bStateNotifierProvider\b|\bBlocBuilder\b|\bCubit\b|setState\(',
    ),
    current: RegExp(r'\bNotifierProvider\b|\bAsyncNotifierProvider\b'),
    confirmStale: (oracle) {
      final usage = oracle.repoUsage(const [
        'NotifierProvider',
        'ChangeNotifierProvider',
        'BlocProvider',
        'StateNotifierProvider',
      ]);
      if ((usage['NotifierProvider'] ?? 0) < 5) {
        return 'lib/ does not establish NotifierProvider as the convention';
      }
      final alternatives = usage.entries
          .where((entry) => entry.key != 'NotifierProvider' && entry.value > 0)
          .map((entry) => '${entry.key}=${entry.value}');
      return alternatives.isEmpty
          ? null
          : 'lib/ also uses ${alternatives.join(', ')}';
    },
  ),
];

/// Fixture problems, empty when the installed toolchain confirms every case.
///
/// Runs before any request. A fixture the toolchain does not back is not a
/// measurement of the model, and the run must not proceed as though it were.
List<String> verifyFixtures(List<CutoffCase> cases, CutoffOracle oracle) => [
  for (final testCase in cases)
    if (testCase.confirmStale(oracle) case final problem?)
      '${testCase.id}: $problem',
];

/// The ground-truth block the `grounded` arm carries.
///
/// A preview of KC2, and the reason the grounded arm's provenance is
/// `promptContext`: the evidence is in the prompt, not in a tool result.
String groundTruthBlock(CutoffOracle oracle) {
  final buffer = StringBuffer('Installed toolchain for this project:');
  final flutter = oracle.flutterVersion;
  if (flutter != null) buffer.write('\n- Flutter SDK: $flutter');
  for (final package in const ['flutter_riverpod', 'riverpod', 'freezed']) {
    final version = oracle.packageVersion(package);
    if (version != null) buffer.write('\n- $package: $version');
  }
  return buffer.toString();
}

enum CensusArm {
  /// The task alone: nothing in the prompt says what is installed.
  bare,

  /// The task plus the measured version block — KC2 as designed.
  grounded,

  /// The version block plus a measured record of what those versions changed.
  ///
  /// The first run said a version number only helps where the model already
  /// knows what that version changed, which is the belief the block was meant
  /// to correct. This arm tests the obvious next move before KC2 is built
  /// around it, and it is an increment over [grounded] so the delta's own
  /// contribution is what is measured.
  deltaGrounded,
}

/// What the installed toolchain changed, as a prompt block.
///
/// Assembled from the oracle, never written down here. A hand-written list of
/// what expired is a belief with an expiry date, and this instrument exists
/// because those are the problem.
///
/// Deliberately general rather than per-question. A block naming the exact
/// replacement for each fixture's symbol would measure instruction-following:
/// the model would be reading back an answer it was handed. So it is the
/// toolchain's own recent deprecations, capped by recency, which leaves
/// `WillPopScope` (deprecated at v3.12, far outside the window) uncovered — and
/// that case becomes the control for what the digest does *not* reach.
String deltaBlock(CutoffOracle oracle) {
  final buffer = StringBuffer('Recent changes in this project\'s toolchain:');
  for (final entry in oracle.recentFlutterDeprecations()) {
    buffer.write('\n- Flutter ${entry.symbol}: ${entry.advice}');
  }
  final legacy = oracle.packageLegacySymbols('riverpod');
  if (legacy.isNotEmpty) {
    buffer.write(
      '\n- riverpod moved these to legacy: ${legacy.join(', ')}',
    );
  }
  for (final line in oracle.packageBreakingChanges('freezed')) {
    buffer.write('\n- freezed: ${line.replaceFirst(RegExp(r'^-\s*'), '')}');
  }
  return buffer.toString();
}

/// Whether the digest names the idiom [testCase] is about.
///
/// Reported per case, because "the digest helped" and "the digest covered it"
/// are different claims and the second one bounds the first.
bool digestCovers(CutoffCase testCase, CutoffOracle oracle) {
  if (testCase.coverageSymbols.isEmpty) return false;
  final digest = deltaBlock(oracle);
  return testCase.coverageSymbols.any(digest.contains);
}

class ClaimRecord {
  const ClaimRecord({
    required this.claimId,
    required this.caseId,
    required this.cutoffClass,
    required this.arm,
    required this.repeat,
    required this.truth,
    required this.grounding,
    required this.provenance,
    required this.assertedValue,
    required this.expectedValue,
    required this.truthSource,
    this.failure,
  });

  final String claimId;
  final String caseId;
  final CutoffClass cutoffClass;
  final CensusArm arm;
  final int repeat;
  final TruthVerdict truth;
  final GroundingVerdict grounding;
  final GroundingProvenance provenance;

  /// The idiom the response actually used, as matched.
  final String assertedValue;

  /// The idiom the installed toolchain uses.
  final String expectedValue;

  /// What on disk said so.
  final String truthSource;
  final String? failure;

  Map<String, dynamic> toJson() => {
    'claim_id': claimId,
    'case': caseId,
    'class': cutoffClass.name,
    'arm': arm.name,
    'repeat': repeat,
    'truth_verdict': truth.name,
    'grounding_verdict': grounding.name,
    'grounding_provenance': provenance.name,
    'asserted_value': assertedValue,
    'expected_value': expectedValue,
    'truth_source': truthSource,
    if (failure != null) 'failure': failure,
  };
}

class CensusSummary {
  const CensusSummary({
    required this.claims,
    required this.runIdentity,
    this.digestCoverage = const {},
  });

  final List<ClaimRecord> claims;
  final Map<String, dynamic> runIdentity;

  /// Per case, whether the delta block names the idiom it is about.
  ///
  /// "The digest helped" and "the digest covered it" are different claims, and
  /// the second bounds the first. A case the digest never mentioned is a
  /// control, not a failure of the idea.
  final Map<String, bool> digestCoverage;

  Iterable<ClaimRecord> _scored(CensusArm arm) =>
      claims.where((c) => c.arm == arm && c.failure == null);

  double staleRate(CensusArm arm) {
    final scored = _scored(
      arm,
    ).where((c) => c.truth != TruthVerdict.unscorable).toList(growable: false);
    if (scored.isEmpty) return 0;
    return scored.where((c) => c.truth == TruthVerdict.stale).length /
        scored.length;
  }

  int unscorable(CensusArm arm) =>
      _scored(arm).where((c) => c.truth == TruthVerdict.unscorable).length;

  int failures() => claims.where((c) => c.failure != null).length;

  /// Stale-claim rate for one class in one arm, or null when nothing scorable.
  ///
  /// Reported per class rather than as one aggregate, because the whole
  /// premise of the track is that these are four different problems with four
  /// different grounds. An aggregate hides the network/offline boundary, which
  /// §4 says not to do.
  double? staleRateFor(CutoffClass cutoffClass, CensusArm arm) {
    final scored = claims
        .where(
          (c) =>
              c.cutoffClass == cutoffClass &&
              c.arm == arm &&
              c.failure == null &&
              c.truth != TruthVerdict.unscorable,
        )
        .toList(growable: false);
    if (scored.isEmpty) return null;
    return scored.where((c) => c.truth == TruthVerdict.stale).length /
        scored.length;
  }

  Set<CutoffClass> get classes =>
      claims.map((c) => c.cutoffClass).toSet();

  Map<String, dynamic> toJson() => {
    'schema': 'caverno_kc1_cutoff_exposure_census',
    'schemaVersion': 1,
    'run': runIdentity,
    'claims': claims.length,
    'failures': failures(),
    'byClass': {
      for (final cutoffClass in classes)
        cutoffClass.name: {
          'bare': staleRateFor(cutoffClass, CensusArm.bare),
          'grounded': staleRateFor(cutoffClass, CensusArm.grounded),
        },
    },
    'arms': {
      for (final arm in CensusArm.values)
        arm.name: {
          'staleRate': staleRate(arm),
          'unscorable': unscorable(arm),
        },
    },
    'digestCoverage': digestCoverage,
    'records': claims.map((c) => c.toJson()).toList(growable: false),
  };

  String report() {
    final buffer = StringBuffer()
      ..writeln('KC1 — cutoff exposure census')
      ..writeln('model: ${runIdentity['model']}  flutter: ${runIdentity['flutter']}')
      ..writeln('build: ${runIdentity['buildCommit']}${runIdentity['buildDirty'] == true ? ' (dirty)' : ''}')
      ..writeln('claims: ${claims.length}  failures: ${failures()}')
      ..writeln()
      ..writeln('stale-claim rate');
    for (final arm in CensusArm.values) {
      buffer.writeln(
        '  ${arm.name.padRight(16)} '
        '${(staleRate(arm) * 100).toStringAsFixed(0).padLeft(3)}%  '
        '(${unscorable(arm)} unscorable)',
      );
    }
    buffer
      ..writeln()
      ..writeln('per class (bare / grounded / delta stale rate)');
    for (final cutoffClass in classes) {
      String rate(CensusArm arm) {
        final value = staleRateFor(cutoffClass, arm);
        return value == null ? '-' : '${(value * 100).toStringAsFixed(0)}%';
      }

      buffer.writeln(
        '  ${cutoffClass.name.padRight(22)} '
        '${rate(CensusArm.bare).padLeft(5)} / '
        '${rate(CensusArm.grounded).padLeft(5)} / '
        '${rate(CensusArm.deltaGrounded).padLeft(5)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('per case (bare / grounded / delta stale, digest coverage)');
    for (final caseId in claims.map((c) => c.caseId).toSet()) {
      String rate(CensusArm arm) {
        final scored = claims
            .where(
              (c) =>
                  c.caseId == caseId &&
                  c.arm == arm &&
                  c.failure == null &&
                  c.truth != TruthVerdict.unscorable,
            )
            .toList(growable: false);
        if (scored.isEmpty) return '-';
        final stale = scored.where((c) => c.truth == TruthVerdict.stale).length;
        return '$stale/${scored.length}';
      }

      buffer.writeln(
        '  ${caseId.padRight(22)} ${rate(CensusArm.bare).padLeft(5)} / '
        '${rate(CensusArm.grounded).padLeft(5)} / '
        '${rate(CensusArm.deltaGrounded).padLeft(5)}   '
        '${digestCoverage[caseId] == true ? 'in digest' : 'not in digest'}',
      );
    }
    return buffer.toString();
  }
}

/// Scores one response for one case, by which idiom it used.
ClaimRecord scoreCutoffResponse({
  required CutoffCase testCase,
  required CensusArm arm,
  required int repeat,
  required String response,
  required String truthSource,
}) {
  final usedStale = testCase.stale.hasMatch(response);
  final usedCurrent = testCase.current.hasMatch(response);
  final truth = usedStale && !usedCurrent
      ? TruthVerdict.stale
      : usedCurrent && !usedStale
      ? TruthVerdict.correct
      : TruthVerdict.unscorable;
  return ClaimRecord(
    claimId: '${testCase.id}:${arm.name}:$repeat',
    caseId: testCase.id,
    cutoffClass: testCase.cutoffClass,
    arm: arm,
    repeat: repeat,
    truth: truth,
    // No tools are attached, so the only grounding a claim can have is what the
    // prompt carried. Recorded rather than inferred: the criteria ask that KC2
    // evidence not be reported as an absent same-turn tool result.
    grounding: arm == CensusArm.bare
        ? GroundingVerdict.absent
        : GroundingVerdict.supported,
    provenance: arm == CensusArm.bare
        ? GroundingProvenance.none
        : GroundingProvenance.promptContext,
    assertedValue: usedStale && usedCurrent
        ? 'both'
        : usedStale
        ? testCase.stale.pattern
        : usedCurrent
        ? testCase.current.pattern
        : 'neither',
    expectedValue: testCase.current.pattern,
    truthSource: truthSource,
  );
}

Future<CensusSummary> runCutoffCensus({
  required CensusOptions options,
  required CutoffOracle oracle,
  required ChatCompletionSender send,
  void Function(String line)? onProgress,
  List<CutoffCase> cases = const [],
}) async {
  final all = cases.isEmpty ? cutoffCases : cases;
  final selected = options.caseFilter.isEmpty
      ? all
      : all
            .where((testCase) => options.caseFilter.contains(testCase.id))
            .toList(growable: false);
  final ground = groundTruthBlock(oracle);
  final delta = deltaBlock(oracle);
  final claims = <ClaimRecord>[];
  for (final testCase in selected) {
    final truthSource =
        testCase.confirmStale(oracle) ?? _truthSourceFor(testCase, oracle);
    for (var repeat = 1; repeat <= options.repeats; repeat++) {
      for (final arm in CensusArm.values) {
        onProgress?.call('${testCase.id} ${arm.name} #$repeat');
        final prompt = switch (arm) {
          CensusArm.bare => testCase.task,
          CensusArm.grounded => '$ground\n\n${testCase.task}',
          CensusArm.deltaGrounded => '$ground\n\n$delta\n\n${testCase.task}',
        };
        try {
          final response = await send(_systemPrompt, prompt);
          if (options.dumpDir case final dumpDir?) {
            final file = File(
              '$dumpDir/${testCase.id}.${arm.name}.$repeat.txt',
            );
            await file.parent.create(recursive: true);
            await file.writeAsString(response);
          }
          claims.add(
            scoreCutoffResponse(
              testCase: testCase,
              arm: arm,
              repeat: repeat,
              response: response,
              truthSource: truthSource,
            ),
          );
        } on Object catch (error) {
          claims.add(
            ClaimRecord(
              claimId: '${testCase.id}:${arm.name}:$repeat',
              caseId: testCase.id,
              cutoffClass: testCase.cutoffClass,
              arm: arm,
              repeat: repeat,
              truth: TruthVerdict.unscorable,
              grounding: GroundingVerdict.absent,
              provenance: GroundingProvenance.none,
              assertedValue: 'none',
              expectedValue: testCase.current.pattern,
              truthSource: truthSource,
              failure: 'request failed: $error',
            ),
          );
        }
      }
    }
  }
  return CensusSummary(
    claims: claims,
    runIdentity: _runIdentity(options: options, oracle: oracle),
    digestCoverage: {
      for (final testCase in selected)
        testCase.id: digestCovers(testCase, oracle),
    },
  );
}

const _systemPrompt =
    'You are a coding assistant. Answer with code only, no explanation.';

String _truthSourceFor(CutoffCase testCase, CutoffOracle oracle) =>
    switch (testCase.id) {
      'flutter-pop-scope' =>
        'flutter ${oracle.flutterVersion}: ${oracle.flutterDeprecation('WillPopScope')}',
      'color-with-values' =>
        'flutter ${oracle.flutterVersion}: ${oracle.flutterDeprecation('withOpacity')}',
      'riverpod-notifier' =>
        'riverpod ${oracle.packageVersion('riverpod')}: StateNotifierProvider under lib/src/providers/legacy/',
      'freezed-abstract' =>
        'freezed ${oracle.packageVersion('freezed')}: ${oracle.packageBreakingChange('freezed', 'abstract')}',
      'repo-state-management' =>
        'lib/ uses NotifierProvider ${oracle.repoUsage(const ['NotifierProvider'])['NotifierProvider']} times and no alternative',
      _ => 'installed toolchain',
    };

Map<String, dynamic> _runIdentity({
  required CensusOptions options,
  required CutoffOracle oracle,
}) {
  final head = Process.runSync('git', [
    'rev-parse',
    '--short',
    'HEAD',
  ], workingDirectory: options.projectRoot);
  final status = Process.runSync('git', [
    'status',
    '--porcelain',
  ], workingDirectory: options.projectRoot);
  return {
    'model': options.model,
    'endpoint': options.endpoint,
    'temperature': options.temperature,
    'toolCatalog': 'none',
    'flutter': oracle.flutterVersion,
    'riverpod': oracle.packageVersion('riverpod'),
    'freezed': oracle.packageVersion('freezed'),
    'buildCommit': (head.stdout as String).trim(),
    'buildDirty': (status.stdout as String).trim().isNotEmpty,
  };
}

Future<String> postChatCompletion({
  required HttpClient client,
  required String endpoint,
  required String model,
  required String apiKey,
  required double temperature,
  required Duration timeout,
  required String systemPrompt,
  required String userPrompt,
}) async {
  final request = await client.postUrl(Uri.parse(endpoint));
  request.headers.contentType = ContentType.json;
  if (apiKey.isNotEmpty) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
  }
  // Content-Length, not chunked: llama.cpp answers a chunked request body with
  // HTTP 500 "attempting to parse an empty input", and Dart chunks any body
  // written without an explicit length.
  final payload = utf8.encode(
    jsonEncode({
      'model': model,
      'temperature': temperature,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    }),
  );
  request.contentLength = payload.length;
  request.add(payload);
  final response = await request.close().timeout(timeout);
  final body = await response.transform(utf8.decoder).join();
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}: ${body.trim()}');
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final choices = decoded['choices'] as List<dynamic>?;
  if (choices == null || choices.isEmpty) {
    throw const HttpException('response carried no choices');
  }
  final message = (choices.first as Map<String, dynamic>)['message'];
  return ((message as Map<String, dynamic>)['content'] as String?) ?? '';
}

class CensusOptions {
  const CensusOptions({
    required this.endpoint,
    required this.model,
    required this.apiKey,
    required this.repeats,
    required this.temperature,
    required this.timeout,
    required this.json,
    required this.outputPath,
    required this.projectRoot,
    required this.verifyOnly,
    required this.dumpDir,
    required this.caseFilter,
  });

  static const usage =
      'Usage: dart run tool/kc1_cutoff_exposure_census.dart \\\n'
      '  --endpoint http://host:1234/v1/chat/completions --model <id> \\\n'
      '  [--repeats 3] [--temperature 0.7] [--timeout 180] [--json] \\\n'
      '  [--out build/kc1/census.json] [--dump-dir build/kc1/raw] \\\n'
      '  [--case <id>]... [--verify-only]\n'
      '--verify-only checks every fixture against the installed toolchain and '
      'sends nothing.';

  final String endpoint;
  final String model;
  final String apiKey;
  final int repeats;
  final double temperature;
  final Duration timeout;
  final bool json;
  final String? outputPath;
  final String projectRoot;
  final bool verifyOnly;

  /// Where to write each raw response.
  ///
  /// A stale rate is a claim about a model, and the only way to tell it from a
  /// claim about a regex is to read what the model wrote. Every measurement
  /// defect this repository has found in an instrument was found this way.
  final String? dumpDir;

  /// Run only these case ids, for spot-checking one fixture's wording.
  final Set<String> caseFilter;

  static CensusOptions? parse(
    List<String> args,
    Map<String, String> environment,
  ) {
    var endpoint = environment['CAVERNO_LLM_ENDPOINT'] ?? '';
    var model = environment['CAVERNO_LLM_MODEL'] ?? '';
    var apiKey = environment['CAVERNO_LLM_API_KEY'] ?? '';
    var repeats = 3;
    var temperature = 0.7;
    var timeoutSeconds = 180;
    var json = false;
    var verifyOnly = false;
    String? outputPath;
    String? dumpDir;
    final caseFilter = <String>{};
    var projectRoot = Directory.current.path;

    String? value(int index) => index + 1 < args.length ? args[index + 1] : null;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--endpoint':
          endpoint = value(i) ?? endpoint;
          i++;
        case '--model':
          model = value(i) ?? model;
          i++;
        case '--api-key':
          apiKey = value(i) ?? apiKey;
          i++;
        case '--repeats':
          repeats = int.tryParse(value(i) ?? '') ?? repeats;
          i++;
        case '--temperature':
          temperature = double.tryParse(value(i) ?? '') ?? temperature;
          i++;
        case '--timeout':
          timeoutSeconds = int.tryParse(value(i) ?? '') ?? timeoutSeconds;
          i++;
        case '--out':
          outputPath = value(i);
          i++;
        case '--project-root':
          projectRoot = value(i) ?? projectRoot;
          i++;
        case '--dump-dir':
          dumpDir = value(i);
          i++;
        case '--case':
          final id = value(i);
          if (id != null) caseFilter.add(id);
          i++;
        case '--json':
          json = true;
        case '--verify-only':
          verifyOnly = true;
        case '--help':
          return null;
      }
    }
    if (repeats < 1) return null;
    if (!verifyOnly && (endpoint.isEmpty || model.isEmpty)) return null;
    return CensusOptions(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      repeats: repeats,
      temperature: temperature,
      timeout: Duration(seconds: timeoutSeconds),
      json: json,
      outputPath: outputPath,
      projectRoot: projectRoot,
      verifyOnly: verifyOnly,
      dumpDir: dumpDir,
      caseFilter: caseFilter,
    );
  }
}
