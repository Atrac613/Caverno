import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/environment_grounding_context_builder.dart';

import 'kc1_cutoff_oracle.dart';
import 'kc1_world_fact_oracle.dart';

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
/// Scope, stated rather than implied. The paired idiom arms cover classes 2
/// (API drift) and 4 (this repository); classes 1 and 3 need verdict shapes of
/// their own:
///
/// - **Class 1, world facts**, has no offline oracle by definition. Its oracle
///   is the registry's API (`kc1_world_fact_oracle.dart`), fetched once per
///   run and recorded with the run, and its verdict is the release line a
///   pubspec constraint names. It is the only part of this instrument that
///   touches the network; `--offline` leaves it out and `--world-facts`
///   replays a frozen snapshot.
/// - **Class 3, environment facts**, does not decompose into a two-idiom pair.
///   Its failure is usually an *unnecessary* line rather than a wrong one — a
///   model setting `useMaterial3: true` on an SDK where it is already the
///   default. Scoring "wrote something superfluous" needs a different verdict
///   shape than "used the expired idiom of two".
///
/// One fixture per class does not size a class, so the §4 promotion gate,
/// which asks whether class 2 *dominates*, is answered only as far as the
/// fixture set reaches. See `docs/knowledge_currency_track_design.md`.
Future<void> main(List<String> args) async {
  final options = CensusOptions.parse(args, Platform.environment);
  if (options == null) {
    stderr.writeln(CensusOptions.usage);
    exitCode = 64;
    return;
  }

  final oracle = CutoffOracle.resolve(projectRoot: options.projectRoot);
  final client = HttpClient();
  try {
    await _runMain(options, oracle, client);
  } finally {
    client.close(force: true);
  }
}

Future<void> _runMain(
  CensusOptions options,
  CutoffOracle oracle,
  HttpClient client,
) async {
  final WorldFactSnapshot? worldFacts;
  if (options.offline) {
    worldFacts = null;
  } else if (options.worldFactsPath case final path?) {
    worldFacts = WorldFactSnapshot.load(path);
  } else {
    try {
      worldFacts = await WorldFactSnapshot.fetch(
        client: client,
        packages: worldFactCases.map((testCase) => testCase.package).toSet(),
      );
    } on Object catch (error) {
      stderr.writeln(
        'Could not read class 1 world facts ($error). '
        'Pass --offline to measure without class 1, or --world-facts to '
        'replay a frozen snapshot.',
      );
      exitCode = 69;
      return;
    }
  }
  if (worldFacts != null && options.saveWorldFactsPath != null) {
    final file = File(options.saveWorldFactsPath!);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(worldFacts.toJson())}\n',
    );
  }

  final fixtureProblems = verifyFixtures(cutoffCases, oracle);
  final environmentProblems = verifyEnvironmentFixtures(
    environmentCases,
    oracle,
  );
  final worldFactProblems = worldFacts == null
      ? const <String>[]
      : verifyWorldFactFixtures(worldFactCases, worldFacts);
  if (fixtureProblems.isNotEmpty ||
      environmentProblems.isNotEmpty ||
      worldFactProblems.isNotEmpty) {
    stderr.writeln(
      'Fixture verification failed against the installed toolchain or the '
      'world-fact snapshot:',
    );
    for (final problem in [
      ...fixtureProblems,
      ...environmentProblems,
      ...worldFactProblems,
    ]) {
      stderr.writeln('  - $problem');
    }
    exitCode = 65;
    return;
  }
  if (options.verifyOnly) {
    final worldFactCount = worldFacts == null ? 0 : worldFactCases.length;
    stdout.writeln(
      'All ${cutoffCases.length + environmentCases.length + worldFactCount} '
      'fixtures confirmed by the oracle.',
    );
    stdout.writeln(groundTruthBlock(oracle));
    final material3Default = oracle.flutterThemeDataUseMaterial3Default();
    if (material3Default != null) {
      stdout.writeln(
        'Environment fixture: Flutter ThemeData.useMaterial3 default: '
        '$material3Default',
      );
    }
    if (worldFacts != null) stdout.writeln(worldFactBlock(worldFacts));
    return;
  }

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
    environmentCases: environmentCases,
    worldFactCases: worldFacts == null ? const [] : worldFactCases,
    worldFacts: worldFacts,
    production: options.production
        ? {
            for (final entry in productionBlocks(options.projectRoot).entries)
              if (options.armFilter.isEmpty ||
                  options.armFilter.contains(entry.key.name))
                entry.key: entry.value,
          }
        : const {},
  );
  final encoded = const JsonEncoder.withIndent('  ').convert(summary.toJson());
  if (options.outputPath != null) {
    final file = File(options.outputPath!);
    await file.parent.create(recursive: true);
    await file.writeAsString('$encoded\n');
  }
  stdout.writeln(options.json ? encoded : summary.report());
}

typedef ChatCompletionSender =
    Future<String> Function(String systemPrompt, String userPrompt);

/// The four failure classes of `docs/knowledge_currency_track_design.md` §2.
enum CutoffClass { worldFact, apiDrift, environment, thisRepository }

/// Where a claim's grounding came from, per the KC1 claim record.
enum GroundingProvenance { promptContext, toolResult, none }

enum TruthVerdict { correct, stale, unscorable }

enum GroundingVerdict { supported, contradicted, absent }

/// The environment-specific shape needed for claims such as an explicit
/// setting that is already the installed SDK default.
enum EnvironmentVerdict {
  /// The setting is required because the installed default is false.
  required,

  /// The response inherits the installed true default by omitting the setting.
  inherited,

  /// The setting repeats the installed true default and exposes stale config
  /// knowledge even though the resulting behavior is still correct.
  unnecessary,

  /// The response disables Material 3 or omits the required enablement.
  wrong,

  /// The response contains conflicting explicit values.
  unscorable,
}

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
  // Broadened 2026-09-24: five fixtures made each arm's result one prompt's
  // flip (the ninth measurement), so classes 2 and 4 gained cases. Each is
  // confirmed from the installed SDK, pub cache, or lib/ like the originals,
  // and each task names the work, never the idiom. A one-repeat calibration
  // pass read every raw answer before any measurement: a ButtonBar fixture
  // was dropped because the model answered with Wrap, which is current and
  // neither idiom, and three patterns were widened as noted on each case.
  CutoffCase(
    id: 'flutter-dialog-background',
    coverageSymbols: const ['dialogBackgroundColor'],
    cutoffClass: CutoffClass.apiDrift,
    description:
        'ThemeData.dialogBackgroundColor superseded by DialogThemeData',
    task:
        'In Flutter, make every dialog in the app use Colors.grey.shade100 as '
        'its background, configured once in the app theme. Return only Dart '
        'code.',
    stale: RegExp(r'\bdialogBackgroundColor\s*:'),
    current: RegExp(r'\bDialogThemeData\s*\('),
    confirmStale: (oracle) => _deprecatedIn(oracle, 'dialogBackgroundColor'),
  ),
  CutoffCase(
    id: 'flutter-raw-keyboard',
    coverageSymbols: const ['RawKeyboardListener'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'RawKeyboardListener superseded by KeyboardListener',
    task:
        'In Flutter, write a widget that listens for hardware key presses and '
        'prints the logical key of every key-down event. Return only Dart code.',
    stale: RegExp(
      r'\bRawKeyboardListener\b|\bRawKeyDownEvent\b|\bRawKeyEvent\b',
    ),
    // Calibration: HardwareKeyboard.instance.addHandler with KeyEvent is the
    // current API too, and the model answered with it.
    current: RegExp(
      r'(?<!Raw)\bKeyboardListener\b|\bKeyDownEvent\b|\bonKeyEvent\b'
      r'|\bHardwareKeyboard\b|(?<!Raw)\bKeyEvent\b',
    ),
    confirmStale: (oracle) => _deprecatedIn(oracle, 'RawKeyboardListener'),
  ),
  CutoffCase(
    id: 'flutter-material-state',
    coverageSymbols: const ['MaterialState', 'MaterialStateProperty'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'MaterialState(Property) superseded by WidgetState(Property)',
    task:
        'In Flutter, give an ElevatedButton a background colour that is red '
        'while it is pressed and blue otherwise, resolved from the button\'s '
        'interaction state. Return only Dart code.',
    stale: RegExp(r'\bMaterialState(?:Property)?\b'),
    current: RegExp(r'\bWidgetState(?:Property)?\b'),
    confirmStale: (oracle) => _deprecatedIn(oracle, 'MaterialStateProperty'),
  ),
  CutoffCase(
    id: 'flutter-text-scale',
    coverageSymbols: const ['textScaleFactor'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'textScaleFactor superseded by textScaler',
    task:
        'In Flutter, read the user\'s text size setting from the build context '
        'and compute the scaled size of a 14-point label with it. Return only '
        'Dart code.',
    stale: RegExp(r'\btextScaleFactor\b'),
    current: RegExp(r'\btextScaler(?:Of)?\b'),
    confirmStale: (oracle) => _deprecatedIn(oracle, 'textScaleFactor'),
  ),
  CutoffCase(
    id: 'file-picker-static',
    coverageSymbols: const ['FilePicker'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'file_picker 11 made FilePicker methods static',
    task:
        'Using the file_picker package, let the user choose one PDF file and '
        'return its path. Return only Dart code.',
    stale: RegExp(r'FilePicker\.platform\b'),
    current: RegExp(r'FilePicker\.pickFiles\('),
    confirmStale: (oracle) =>
        oracle.packageBreakingChange('file_picker', 'static') == null
        ? 'the installed file_picker changelog records no static refactor'
        : oracle.packageSourceMatches(
            'file_picker',
            RegExp(r'\bget\s+platform\b'),
          )
        ? 'the installed file_picker still exposes FilePicker.platform'
        : null,
  ),
  CutoffCase(
    id: 'share-plus-instance',
    coverageSymbols: const ['SharePlus'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'share_plus deprecated Share in favour of SharePlus.instance',
    task:
        'Using the share_plus package, share the text "Hello" through the '
        'platform share sheet. Return only Dart code.',
    stale: RegExp(r'\bShare\.share(?:Uri|XFiles)?\('),
    current: RegExp(r'\bSharePlus\.instance\.share\('),
    confirmStale: (oracle) =>
        oracle.packageDeprecatedDeclaration('share_plus', 'Share') == null
        ? 'the installed share_plus does not deprecate Share'
        : null,
  ),
  CutoffCase(
    id: 'qr-image-view',
    coverageSymbols: const ['QrImageView'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'qr_flutter 4 renamed QrImage to QrImageView',
    task:
        'Using the qr_flutter package, render the string '
        '"https://example.com" as a 200-pixel QR code widget. Return only Dart '
        'code.',
    stale: RegExp(r'\bQrImage\('),
    current: RegExp(r'\bQrImageView\('),
    confirmStale: (oracle) =>
        oracle.packageBreakingChange('qr_flutter', 'QrImageView') == null
        ? 'the installed qr_flutter changelog records no QrImage rename'
        : oracle.packageSourceMatches(
            'qr_flutter',
            RegExp(r'class\s+QrImage\b'),
          )
        ? 'the installed qr_flutter still declares QrImage'
        : null,
  ),
  CutoffCase(
    id: 'freezed-pattern-matching',
    coverageSymbols: const ['map/when', 'when'],
    cutoffClass: CutoffClass.apiDrift,
    description: 'Freezed 3 removed when/map in favour of pattern matching',
    task:
        'Given this freezed union: `@freezed sealed class Result with _\$Result '
        '{ const factory Result.ok(int value) = Ok; const factory '
        'Result.error(String message) = Err; }`, write a function that returns '
        'a display string for a Result. Return only Dart code.',
    stale: RegExp(r'\.(?:maybe)?(?:when|map)\s*\('),
    current: RegExp(r'\bswitch\s*\('),
    confirmStale: (oracle) =>
        oracle.packageBreakingChange('freezed', 'map/when') == null
        ? 'the installed freezed changelog does not record removing map/when'
        : null,
  ),
  CutoffCase(
    id: 'repo-localization',
    cutoffClass: CutoffClass.thisRepository,
    description: 'this project localizes strings with easy_localization .tr()',
    task:
        'In this Flutter project, add a button labelled Save whose label is '
        'localized, following the project\'s existing conventions. Return only '
        'Dart code.',
    // Calibration: the model also invented `'save'.intl(context)`, which is
    // off-convention and matched neither pattern.
    stale: RegExp(r'AppLocalizations\.of|\bIntl\.|\bS\.of\(|\bl10n\b|\.intl\('),
    current: RegExp(r'\.tr\('),
    confirmStale: (oracle) => _conventionOnly(
      oracle,
      convention: RegExp(r'\.tr\('),
      alternatives: RegExp(r'AppLocalizations\.of|Intl\.message|\bS\.of\('),
      name: '.tr()',
    ),
  ),
  CutoffCase(
    id: 'repo-unique-id',
    cutoffClass: CutoffClass.thisRepository,
    description: 'this project creates record ids with the uuid package',
    task:
        'In this Flutter project, add a function that creates a new note '
        'record with a unique id, following the project\'s existing '
        'conventions. Return only Dart code.',
    // Calibration: the model generated ids with Random.secure() and with a
    // timestamp on its own line. An answer using Uuid and a createdAt
    // timestamp therefore scores unscorable (both), a cost accepted so that a
    // hand-rolled id is not read as having asserted nothing.
    stale: RegExp(
      r'millisecondsSinceEpoch|microsecondsSinceEpoch'
      r'|\bRandom(?:\.secure)?\(\)|UniqueKey\(\)',
    ),
    current: RegExp(r'\bUuid\(\)'),
    confirmStale: (oracle) => _conventionOnly(
      oracle,
      convention: RegExp(r'\bUuid\(\)'),
      alternatives: RegExp(r'UniqueKey\(\)\.toString|\bnanoid\b'),
      name: 'Uuid()',
    ),
  ),
  CutoffCase(
    id: 'repo-data-class',
    cutoffClass: CutoffClass.thisRepository,
    description: 'this project declares immutable data classes with freezed',
    task:
        'In this Flutter project, add an immutable data class for a Bookmark '
        'with a title and a url, supporting copyWith and value equality, '
        'following the project\'s existing conventions. Return only Dart code.',
    stale: RegExp(r'\boperator\s*==|\bextends\s+Equatable\b'),
    current: RegExp(r'@freezed\b'),
    confirmStale: (oracle) => _conventionOnly(
      oracle,
      convention: RegExp(r'@freezed\b'),
      alternatives: RegExp(r'\bEquatable\b|\bbuilt_value\b'),
      name: '@freezed',
    ),
  ),
];

String? _deprecatedIn(CutoffOracle oracle, String symbol) =>
    oracle.flutterDeprecatedDeclaration(symbol) == null
    ? 'the installed SDK does not deprecate $symbol'
    : null;

/// Confirms a class 4 convention: established in at least five files under
/// lib/, with no alternative in use.
String? _conventionOnly(
  CutoffOracle oracle, {
  required RegExp convention,
  required RegExp alternatives,
  required String name,
}) {
  final uses = oracle.repoFilesMatching(convention);
  if (uses < 5) return 'lib/ does not establish $name ($uses files)';
  final others = oracle.repoFilesMatching(alternatives);
  return others == 0 ? null : 'lib/ also uses an alternative in $others files';
}

class EnvironmentCase {
  const EnvironmentCase({
    required this.id,
    required this.task,
    required this.description,
    required this.readDefault,
    required this.confirmEnvironment,
  });

  final String id;
  final String task;
  final String description;
  final bool? Function(CutoffOracle oracle) readDefault;
  final String? Function(CutoffOracle oracle) confirmEnvironment;
}

final environmentCases = <EnvironmentCase>[
  EnvironmentCase(
    id: 'flutter-material3-default',
    description: 'ThemeData.useMaterial3 default is read from the SDK source',
    task:
        'In Flutter, write a minimal ThemeData configuration that enables '
        'Material 3 while preserving the installed SDK default when it '
        'already enables Material 3. Do not add redundant overrides. '
        'Return only Dart code.',
    readDefault: (oracle) => oracle.flutterThemeDataUseMaterial3Default(),
    confirmEnvironment: (oracle) =>
        oracle.flutterThemeDataUseMaterial3Default() == null
        ? 'the installed Flutter SDK does not expose ThemeData.useMaterial3'
        : null,
  ),
];

/// A class 1 fixture: start a new app on a package's current release.
///
/// The task asks for the current release explicitly, because without that
/// there is no world-fact claim to score -- any published line is a valid
/// constraint for *some* project. It asks for a new app so the lockfile of
/// this repository is not the right answer, and a caret constraint so the
/// claim lands in a form the scorer parses.
class WorldFactCase {
  const WorldFactCase({
    required this.id,
    required this.package,
    required this.description,
  });

  final String id;
  final String package;
  final String description;

  String get task =>
      'Write the pubspec.yaml dependency entries for a new Flutter app, '
      'created today, that uses the $package package. Depend on the current '
      'stable release of $package with a caret constraint. Return only YAML.';
}

/// Packages chosen for where their current release line sits relative to a
/// model trained some months ago, not for which answer the author expects:
/// the snapshot decides that. dio has stayed on one major for years and is the
/// control; the others moved a major within the last year, and freezed is
/// also locked below its latest here.
const worldFactCases = <WorldFactCase>[
  WorldFactCase(
    id: 'pub-latest-freezed',
    package: 'freezed',
    description: 'freezed latest release line on pub.dev',
  ),
  WorldFactCase(
    id: 'pub-latest-go-router',
    package: 'go_router',
    description: 'go_router latest release line on pub.dev',
  ),
  WorldFactCase(
    id: 'pub-latest-flutter-riverpod',
    package: 'flutter_riverpod',
    description: 'flutter_riverpod latest release line on pub.dev',
  ),
  WorldFactCase(
    id: 'pub-latest-dio',
    package: 'dio',
    description: 'dio latest release line on pub.dev (control)',
  ),
];

/// Fixture problems for class 1, empty when the snapshot holds a parseable
/// latest release for every case's package.
List<String> verifyWorldFactFixtures(
  List<WorldFactCase> cases,
  WorldFactSnapshot snapshot,
) => [
  for (final testCase in cases)
    if (_worldFactProblem(testCase, snapshot) case final problem?)
      '${testCase.id}: $problem',
];

String? _worldFactProblem(WorldFactCase testCase, WorldFactSnapshot snapshot) {
  final fact = snapshot[testCase.package];
  if (fact == null) return 'the snapshot has no fact for ${testCase.package}';
  if (ReleaseVersion.tryParse(fact.latestVersion) == null) {
    return 'latest ${fact.latestVersion} is not a release version';
  }
  return null;
}

/// The world-fact block the `worldFactGrounded` arm carries: what the registry
/// reported, with when, and nothing about which answer is expected.
String worldFactBlock(WorldFactSnapshot snapshot) {
  final buffer = StringBuffer('Latest stable releases on pub.dev:');
  for (final fact in snapshot.facts.values) {
    buffer.write('\n- ${fact.package}: ${fact.latestVersion}');
    if (fact.publishedAt case final published?) {
      buffer.write(' (published ${published.split('T').first})');
    }
  }
  return buffer.toString();
}

/// Fixture problems, empty when the installed toolchain confirms every case.
///
/// Runs before any request. A fixture the toolchain does not back is not a
/// measurement of the model, and the run must not proceed as though it were.
List<String> verifyFixtures(List<CutoffCase> cases, CutoffOracle oracle) => [
  for (final testCase in cases)
    if (testCase.confirmStale(oracle) case final problem?)
      '${testCase.id}: $problem',
];

/// Fixture problems for environment claims, empty when the installed SDK
/// exposes the fact the fixture measures.
List<String> verifyEnvironmentFixtures(
  List<EnvironmentCase> cases,
  CutoffOracle oracle,
) => [
  for (final testCase in cases)
    if (testCase.confirmEnvironment(oracle) case final problem?)
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

/// The environment fixture's measured context. Kept separate from
/// [groundTruthBlock] so adding class 3 does not change the class 2/4 replay
/// baseline.
String environmentGroundTruthBlock(CutoffOracle oracle) {
  final material3Default = oracle.flutterThemeDataUseMaterial3Default();
  if (material3Default == null) return groundTruthBlock(oracle);
  return '${groundTruthBlock(oracle)}\n- Flutter ThemeData.useMaterial3 default: $material3Default';
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

  /// Class 1 only: the task plus the registry's latest release for the
  /// package it names, as a fetched web result would carry it.
  ///
  /// Carried in the prompt so the replay stays fixed; its provenance is
  /// therefore `promptContext`, the same honest label the grounded arm uses
  /// for its KC2 preview. In production this ground would be a tool result.
  worldFactGrounded,

  /// KC2 slice 5: the task plus the block the production prompt carries, from
  /// `EnvironmentGroundingContextBuilder` rather than this file's prototype,
  /// at the budget a model with unknown usable context gets.
  productionDefault,

  /// The production block at the 32k-token budget.
  production32k,

  /// The production block at the 64k-token budget, the only one whose digest
  /// covers every measured idiom on this repository.
  production64k,

  /// The production version list alone, with no change digest: the
  /// configuration a window under 16k tokens gets, measured after the full
  /// block regressed class 4 by listing legacy names.
  productionVersionsOnly,

  /// The eight direct dependencies most imported under `lib/`, versions
  /// only: the selection the eighth measurement pointed at, after the full
  /// 59-entry list diluted the one library class 4 is about.
  productionImported,

  /// The same eight, with the change digest restricted to them.
  productionImportedDigest,
}

/// How many most-imported dependencies the import-selected arms list. Fixed
/// before measuring, so the count is not fitted to the result.
const productionImportedCount = 8;

/// The production arms and the usable context each one stands for. Reported
/// per budget, because the largest budget was chosen with a fixture in view.
const productionArmContext = <CensusArm, int?>{
  CensusArm.productionDefault: null,
  CensusArm.production32k: 32768,
  CensusArm.production64k: 65536,
  CensusArm.productionVersionsOnly: null,
  CensusArm.productionImported: null,
  CensusArm.productionImportedDigest: null,
};

/// Builds each production arm's block from the production builder.
Map<CensusArm, String> productionBlocks(String projectRoot) {
  final builder = EnvironmentGroundingContextBuilder();
  return {
    for (final entry in productionArmContext.entries)
      entry.key: ?builder.build(
        projectRoot,
        maxChars: EnvironmentGroundingContextBuilder.maxCharsForUsableContext(
          entry.value,
        ),
        digestMaxChars:
            entry.key == CensusArm.productionVersionsOnly ||
                entry.key == CensusArm.productionImported
            ? 0
            : EnvironmentGroundingContextBuilder.digestMaxCharsForUsableContext(
                entry.value,
              ),
        mostImported:
            entry.key == CensusArm.productionImported ||
                entry.key == CensusArm.productionImportedDigest
            ? productionImportedCount
            : null,
      ),
  };
}

/// The arms the idiom and environment fixtures run. Their replay baseline
/// predates class 1 and must not change when it is added.
const idiomArms = [CensusArm.bare, CensusArm.grounded, CensusArm.deltaGrounded];

/// The arms the class 1 fixtures run.
///
/// The grounded arm is kept even though the installed-toolchain block says
/// nothing about the world: it is the one place the two oracles disagree.
/// This repository locks freezed below pub.dev's latest, so a new-project
/// answer that copies the lockfile is measured here as what it is.
const worldFactArms = [
  CensusArm.bare,
  CensusArm.grounded,
  CensusArm.worldFactGrounded,
];

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
    buffer.write('\n- riverpod moved these to legacy: ${legacy.join(', ')}');
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

/// Whether the complete prompt context supports [testCase] for [arm].
///
/// The installed-toolchain block contains versions only; it does not state an
/// API migration or repository convention. Only the delta block has explicit
/// case coverage in this fixture set.
bool promptSupportsClaimFor({
  required CutoffCase testCase,
  required CensusArm arm,
  required CutoffOracle oracle,
}) {
  return switch (arm) {
    CensusArm.bare => false,
    CensusArm.grounded => false,
    CensusArm.deltaGrounded => digestCovers(testCase, oracle),
    // Carries registry versions only, and idiom fixtures never run it.
    CensusArm.worldFactGrounded => false,
    // Production arms are scored in [runCutoffCensus] against their block.
    CensusArm.productionDefault ||
    CensusArm.production32k ||
    CensusArm.production64k ||
    CensusArm.productionVersionsOnly ||
    CensusArm.productionImported ||
    CensusArm.productionImportedDigest => false,
  };
}

/// Whether the complete prompt context carries the environment fact for
/// [testCase]. The grounded and delta arms both carry the measured default.
bool promptSupportsEnvironmentClaimFor({
  required EnvironmentCase testCase,
  required CensusArm arm,
  required CutoffOracle oracle,
}) =>
    !productionArmContext.containsKey(arm) &&
    arm != CensusArm.bare &&
    testCase.readDefault(oracle) != null;

class _EnvironmentAssertion {
  const _EnvironmentAssertion({
    required this.hasThemeData,
    required this.explicitTrue,
    required this.explicitFalse,
    required this.unknownValue,
  });

  final bool hasThemeData;
  final bool explicitTrue;
  final bool explicitFalse;
  final bool unknownValue;

  String get value => !hasThemeData
      ? 'none'
      : unknownValue
      ? 'unknown'
      : explicitTrue && explicitFalse
      ? 'both'
      : explicitTrue
      ? 'true'
      : explicitFalse
      ? 'false'
      : 'omitted';
}

/// Replaces comments and string literals with spaces while preserving code
/// characters and newlines. Environment scoring must inspect the constructor,
/// not examples or explanations embedded in an otherwise valid code response.
String _sanitizeDartForEnvironment(String source) {
  final output = StringBuffer();
  var index = 0;
  var lineComment = false;
  var blockComment = false;
  String? quote;
  var tripleQuote = false;
  while (index < source.length) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : null;
    final nextNext = index + 2 < source.length ? source[index + 2] : null;
    if (lineComment) {
      if (char == '\n') {
        lineComment = false;
        output.write('\n');
      } else {
        output.write(' ');
      }
      index++;
      continue;
    }
    if (blockComment) {
      if (char == '*' && next == '/') {
        output.write('  ');
        index += 2;
      } else {
        output.write(char == '\n' ? '\n' : ' ');
        index++;
      }
      if (index >= 2 && source[index - 2] == '*' && source[index - 1] == '/') {
        blockComment = false;
      }
      continue;
    }
    if (quote != null) {
      if (tripleQuote && char == quote && next == quote && nextNext == quote) {
        output.write('   ');
        index += 3;
        quote = null;
        tripleQuote = false;
      } else if (!tripleQuote && char == '\\') {
        output.write('  ');
        index += next == null ? 1 : 2;
      } else if (!tripleQuote && char == quote) {
        output.write(' ');
        index++;
        quote = null;
      } else {
        output.write(char == '\n' ? '\n' : ' ');
        index++;
      }
      continue;
    }
    if (char == '/' && next == '/') {
      output.write('  ');
      index += 2;
      lineComment = true;
      continue;
    }
    if (char == '/' && next == '*') {
      output.write('  ');
      index += 2;
      blockComment = true;
      continue;
    }
    if (char == "'" || char == '"') {
      final isTriple = char == next && char == nextNext;
      output.write(isTriple ? '   ' : ' ');
      index += isTriple ? 3 : 1;
      quote = char;
      tripleQuote = isTriple;
      continue;
    }
    output.write(char);
    index++;
  }
  return output.toString();
}

String? _parenthesizedBody(String source, int openingIndex) {
  var depth = 0;
  for (var index = openingIndex + 1; index < source.length; index++) {
    switch (source[index]) {
      case '(':
        depth++;
      case ')':
        if (depth == 0) return source.substring(openingIndex + 1, index);
        depth--;
    }
  }
  return null;
}

_EnvironmentAssertion _readEnvironmentAssertion(String response) {
  final sanitized = _sanitizeDartForEnvironment(response);
  var hasThemeData = false;
  var malformedThemeData = false;
  var explicitTrue = false;
  var explicitFalse = false;
  var unknownValue = false;
  final constructorPattern = RegExp(
    r'\bThemeData(?:\.(?:from|light|dark|fallback|raw))?\s*\(',
  );
  final settingPattern = RegExp(r'\buseMaterial3\s*:');
  final truePattern = RegExp(r'\buseMaterial3\s*:\s*true\s*(?=,|$)');
  final falsePattern = RegExp(r'\buseMaterial3\s*:\s*false\s*(?=,|$)');
  for (final match in constructorPattern.allMatches(sanitized)) {
    final body = _parenthesizedBody(sanitized, match.end - 1);
    if (body == null) {
      malformedThemeData = true;
      continue;
    }
    hasThemeData = true;
    final hasSetting = settingPattern.hasMatch(body);
    final hasTrue = truePattern.hasMatch(body);
    final hasFalse = falsePattern.hasMatch(body);
    explicitTrue = explicitTrue || hasTrue;
    explicitFalse = explicitFalse || hasFalse;
    unknownValue = unknownValue || (hasSetting && !hasTrue && !hasFalse);
  }
  return _EnvironmentAssertion(
    hasThemeData: hasThemeData && !malformedThemeData,
    explicitTrue: explicitTrue,
    explicitFalse: explicitFalse,
    unknownValue: unknownValue,
  );
}

/// Classifies an environment setting against the installed default. Omitting
/// the setting is a valid, correct inheritance claim when the default already
/// enables Material 3; omitting it on a false-default SDK fails enablement.
/// This is intentionally separate from the stale/current idiom scorer used by
/// API drift fixtures.
EnvironmentVerdict scoreEnvironmentSetting({
  required String response,
  required bool defaultValue,
}) {
  final assertion = _readEnvironmentAssertion(response);
  if (!assertion.hasThemeData ||
      assertion.unknownValue ||
      (assertion.explicitTrue && assertion.explicitFalse)) {
    return EnvironmentVerdict.unscorable;
  }
  if (!assertion.explicitTrue && !assertion.explicitFalse) {
    return defaultValue
        ? EnvironmentVerdict.inherited
        : EnvironmentVerdict.wrong;
  }
  if (assertion.explicitTrue) {
    return defaultValue
        ? EnvironmentVerdict.unnecessary
        : EnvironmentVerdict.required;
  }
  return EnvironmentVerdict.wrong;
}

TruthVerdict truthForEnvironment(EnvironmentVerdict verdict) =>
    switch (verdict) {
      EnvironmentVerdict.required ||
      EnvironmentVerdict.inherited ||
      EnvironmentVerdict.unnecessary => TruthVerdict.correct,
      EnvironmentVerdict.wrong => TruthVerdict.stale,
      EnvironmentVerdict.unscorable => TruthVerdict.unscorable,
    };

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
    this.environmentVerdict,
    this.worldFactVerdict,
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

  /// The value or idiom the response actually asserted, as matched.
  final String assertedValue;

  /// The value or idiom the installed toolchain expects.
  final String expectedValue;

  /// What on disk said so.
  final String truthSource;
  final EnvironmentVerdict? environmentVerdict;
  final WorldFactVerdict? worldFactVerdict;
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
    if (environmentVerdict case final verdict?)
      'environment_verdict': verdict.name,
    if (worldFactVerdict case final verdict?)
      'world_fact_verdict': verdict.name,
    if (failure != null) 'failure': failure,
  };
}

class CensusSummary {
  const CensusSummary({
    required this.claims,
    required this.runIdentity,
    this.digestCoverage = const {},
    this.productionCoverage = const {},
  });

  final List<ClaimRecord> claims;
  final Map<String, dynamic> runIdentity;

  /// Per case, whether the delta block names the idiom it is about.
  ///
  /// "The digest helped" and "the digest covered it" are different claims, and
  /// the second bounds the first. A case the digest never mentioned is a
  /// control, not a failure of the idea.
  final Map<String, bool> digestCoverage;

  /// Per case and production arm, whether that arm's block names the idiom.
  final Map<String, Map<String, bool>> productionCoverage;

  List<CensusArm> get _presentArms {
    final present = claims.map((c) => c.arm).toSet();
    return [
      for (final arm in CensusArm.values)
        if (present.contains(arm)) arm,
    ];
  }

  Iterable<ClaimRecord> _scored(CensusArm arm) =>
      claims.where((c) => c.arm == arm && c.failure == null);

  double? staleRate(CensusArm arm) {
    final scored = _scored(
      arm,
    ).where((c) => c.truth != TruthVerdict.unscorable).toList(growable: false);
    if (scored.isEmpty) return null;
    return scored.where((c) => c.truth == TruthVerdict.stale).length /
        scored.length;
  }

  int unscorable(CensusArm arm) =>
      _scored(arm).where((c) => c.truth == TruthVerdict.unscorable).length;

  int failures() => claims.where((c) => c.failure != null).length;

  /// Claims without supporting grounding, including claims that contradict the
  /// prompt context, as a fraction of scorable claims in [arm], or null when
  /// nothing is scorable.
  double? unsupportedRate(CensusArm arm) {
    final scored = _scored(
      arm,
    ).where((c) => c.truth != TruthVerdict.unscorable).toList(growable: false);
    if (scored.isEmpty) return null;
    return scored
            .where((c) => c.grounding != GroundingVerdict.supported)
            .length /
        scored.length;
  }

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

  /// Rate of environment claims that redundantly restate the installed true
  /// default. This is separate from truth/staleness: the resulting behavior is
  /// correct, but the explicit override is the class-3 exposure being measured.
  double? environmentExposureRateFor(CensusArm arm) {
    final scored = claims
        .where(
          (c) =>
              c.cutoffClass == CutoffClass.environment &&
              c.arm == arm &&
              c.failure == null &&
              c.truth != TruthVerdict.unscorable,
        )
        .toList(growable: false);
    if (scored.isEmpty) return null;
    return scored
            .where(
              (c) => c.environmentVerdict == EnvironmentVerdict.unnecessary,
            )
            .length /
        scored.length;
  }

  /// Unsupported-claim rate for one class in one arm, or null when nothing is
  /// scorable.
  double? unsupportedRateFor(CutoffClass cutoffClass, CensusArm arm) {
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
    return scored
            .where((c) => c.grounding != GroundingVerdict.supported)
            .length /
        scored.length;
  }

  Map<EnvironmentVerdict, int> environmentVerdicts(CensusArm arm) {
    final counts = {
      for (final verdict in EnvironmentVerdict.values) verdict: 0,
    };
    for (final claim in claims) {
      if (claim.arm == arm && claim.failure == null) {
        final verdict = claim.environmentVerdict;
        if (verdict != null) counts[verdict] = counts[verdict]! + 1;
      }
    }
    return counts;
  }

  Map<WorldFactVerdict, int> worldFactVerdicts(CensusArm arm) {
    final counts = {for (final verdict in WorldFactVerdict.values) verdict: 0};
    for (final claim in claims) {
      if (claim.arm == arm && claim.failure == null) {
        final verdict = claim.worldFactVerdict;
        if (verdict != null) counts[verdict] = counts[verdict]! + 1;
      }
    }
    return counts;
  }

  Set<CutoffClass> get classes => claims.map((c) => c.cutoffClass).toSet();

  Map<String, dynamic> toJson() => {
    'schema': 'caverno_kc1_cutoff_exposure_census',
    'schemaVersion': 4,
    'run': runIdentity,
    'claims': claims.length,
    'failures': failures(),
    'byClass': {
      for (final cutoffClass in classes)
        cutoffClass.name: {
          for (final arm in CensusArm.values)
            arm.name: {
              'staleRate': staleRateFor(cutoffClass, arm),
              'unsupportedRate': unsupportedRateFor(cutoffClass, arm),
              if (cutoffClass == CutoffClass.environment)
                'environmentExposureRate': environmentExposureRateFor(arm),
            },
        },
    },
    'arms': {
      for (final arm in CensusArm.values)
        arm.name: {
          'staleRate': staleRate(arm),
          'unsupportedRate': unsupportedRate(arm),
          'unscorable': unscorable(arm),
          'environmentExposureRate': environmentExposureRateFor(arm),
          'environmentVerdicts': {
            for (final entry in environmentVerdicts(arm).entries)
              entry.key.name: entry.value,
          },
          'worldFactVerdicts': {
            for (final entry in worldFactVerdicts(arm).entries)
              entry.key.name: entry.value,
          },
        },
    },
    'digestCoverage': digestCoverage,
    if (productionCoverage.values.any((arms) => arms.isNotEmpty))
      'productionCoverage': productionCoverage,
    'records': claims.map((c) => c.toJson()).toList(growable: false),
  };

  String report() {
    final buffer = StringBuffer()
      ..writeln('KC1 — cutoff exposure census')
      ..writeln(
        'model: ${runIdentity['model']}  flutter: ${runIdentity['flutter']}',
      )
      ..writeln(
        'build: ${runIdentity['buildCommit']}${runIdentity['buildDirty'] == true ? ' (dirty)' : ''}',
      )
      ..writeln('claims: ${claims.length}  failures: ${failures()}')
      ..writeln()
      ..writeln('stale-claim and unsupported-claim rate');
    for (final arm in _presentArms) {
      final stale = staleRate(arm);
      final staleText = stale == null
          ? '-'
          : '${(stale * 100).toStringAsFixed(0).padLeft(3)}%';
      final unsupported = unsupportedRate(arm);
      final unsupportedText = unsupported == null
          ? '-'
          : '${(unsupported * 100).toStringAsFixed(0).padLeft(3)}%';
      buffer.writeln(
        '  ${arm.name.padRight(18)} '
        '$staleText  '
        'stale  $unsupportedText '
        'unsupported  (${unscorable(arm)} unscorable)',
      );
      final environment = environmentVerdicts(arm).entries
          .where((entry) => entry.value > 0)
          .map((entry) => '${entry.key.name}=${entry.value}')
          .join(', ');
      if (environment.isNotEmpty) {
        buffer.writeln('  ${arm.name.padRight(18)} environment $environment');
      }
      final worldFact = worldFactVerdicts(arm).entries
          .where((entry) => entry.value > 0)
          .map((entry) => '${entry.key.name}=${entry.value}')
          .join(', ');
      if (worldFact.isNotEmpty) {
        buffer.writeln('  ${arm.name.padRight(18)} world fact $worldFact');
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'per class stale-claim rate '
        '(${_presentArms.map((a) => a.name).join(' / ')})',
      );
    for (final cutoffClass in classes) {
      String rate(CensusArm arm) {
        final value = staleRateFor(cutoffClass, arm);
        return value == null ? '-' : '${(value * 100).toStringAsFixed(0)}%';
      }

      buffer.writeln(
        '  ${cutoffClass.name.padRight(22)} '
        '${_presentArms.map((arm) => rate(arm).padLeft(5)).join(' / ')}',
      );
      if (cutoffClass == CutoffClass.environment) {
        String exposure(CensusArm arm) {
          final value = environmentExposureRateFor(arm);
          return value == null ? '-' : '${(value * 100).toStringAsFixed(0)}%';
        }

        buffer.writeln(
          '  ${cutoffClass.name.padRight(22)} '
          'environment exposure '
          '${_presentArms.map((arm) => exposure(arm).padLeft(5)).join(' / ')}',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'per class unsupported-claim rate '
        '(${_presentArms.map((a) => a.name).join(' / ')})',
      );
    for (final cutoffClass in classes) {
      String rate(CensusArm arm) {
        final value = unsupportedRateFor(cutoffClass, arm);
        return value == null ? '-' : '${(value * 100).toStringAsFixed(0)}%';
      }

      buffer.writeln(
        '  ${cutoffClass.name.padRight(22)} '
        '${_presentArms.map((arm) => rate(arm).padLeft(5)).join(' / ')}',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        'per case (${_presentArms.map((a) => a.name).join(' / ')} stale, '
        'coverage)',
      );
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
        '  ${caseId.padRight(22)} '
        '${_presentArms.map((arm) => rate(arm).padLeft(5)).join(' / ')}   '
        '${_coverageLabel(caseId)}',
      );
    }
    return buffer.toString();
  }

  String _coverageLabel(String caseId) {
    final production = productionCoverage[caseId];
    if (production != null && production.isNotEmpty) {
      return production.entries
          .map((e) => '${e.key}:${e.value ? 'covered' : 'not covered'}')
          .join(' ');
    }
    return digestCoverage[caseId] == true ? 'in digest' : 'not in digest';
  }
}

/// Scores one response for one case, by which idiom it used.
ClaimRecord scoreCutoffResponse({
  required CutoffCase testCase,
  required CensusArm arm,
  required int repeat,
  required String response,
  required String truthSource,
  required bool promptSupportsClaim,
}) {
  final usedStale = testCase.stale.hasMatch(response);
  final usedCurrent = testCase.current.hasMatch(response);
  final truth = usedStale && !usedCurrent
      ? TruthVerdict.stale
      : usedCurrent && !usedStale
      ? TruthVerdict.correct
      : TruthVerdict.unscorable;
  final grounding = switch ((promptSupportsClaim, truth)) {
    (false, _) => GroundingVerdict.absent,
    (_, TruthVerdict.correct) => GroundingVerdict.supported,
    (_, TruthVerdict.stale) => GroundingVerdict.contradicted,
    (_, TruthVerdict.unscorable) => GroundingVerdict.absent,
  };
  return ClaimRecord(
    claimId: '${testCase.id}:${arm.name}:$repeat',
    caseId: testCase.id,
    cutoffClass: testCase.cutoffClass,
    arm: arm,
    repeat: repeat,
    truth: truth,
    // No tools are attached, so the only grounding a claim can have is what the
    // prompt carried. A stale claim contradicts that context; an unscorable
    // response does not assert a claim that can be grounded.
    grounding: grounding,
    provenance: promptSupportsClaim && truth != TruthVerdict.unscorable
        ? GroundingProvenance.promptContext
        : GroundingProvenance.none,
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

/// Scores one response for an environment fixture while retaining the common
/// truth/grounding axes in the claim record.
ClaimRecord scoreEnvironmentResponse({
  required EnvironmentCase testCase,
  required CensusArm arm,
  required int repeat,
  required String response,
  required String truthSource,
  required bool promptSupportsClaim,
  required bool defaultValue,
}) {
  final assertion = _readEnvironmentAssertion(response);
  final environmentVerdict = scoreEnvironmentSetting(
    response: response,
    defaultValue: defaultValue,
  );
  final truth = truthForEnvironment(environmentVerdict);
  final grounding = switch ((promptSupportsClaim, truth)) {
    (false, _) => GroundingVerdict.absent,
    (_, TruthVerdict.correct) => GroundingVerdict.supported,
    (_, TruthVerdict.stale) => GroundingVerdict.contradicted,
    (_, TruthVerdict.unscorable) => GroundingVerdict.absent,
  };
  return ClaimRecord(
    claimId: '${testCase.id}:${arm.name}:$repeat',
    caseId: testCase.id,
    cutoffClass: CutoffClass.environment,
    arm: arm,
    repeat: repeat,
    truth: truth,
    grounding: grounding,
    provenance: promptSupportsClaim && truth != TruthVerdict.unscorable
        ? GroundingProvenance.promptContext
        : GroundingProvenance.none,
    assertedValue: assertion.value,
    expectedValue: defaultValue ? 'omitted' : 'true',
    truthSource: truthSource,
    environmentVerdict: environmentVerdict,
  );
}

/// Scores one class 1 response against the snapshot's latest release.
///
/// Truth collapses the four-way verdict onto the shared axis: a constraint on
/// the latest line is correct, and one on an older line is stale. A version
/// newer than anything published is also counted as not correct, but it keeps
/// its own `ahead` verdict so a fabrication is never read as a cutoff effect.
ClaimRecord scoreWorldFactClaim({
  required WorldFactCase testCase,
  required CensusArm arm,
  required int repeat,
  required String response,
  required WorldFact fact,
  required String truthSource,
}) {
  final latest = ReleaseVersion.tryParse(fact.latestVersion)!;
  final scored = scoreWorldFactResponse(
    response: response,
    package: testCase.package,
    latest: latest,
  );
  final truth = switch (scored.verdict) {
    WorldFactVerdict.current => TruthVerdict.correct,
    WorldFactVerdict.behind || WorldFactVerdict.ahead => TruthVerdict.stale,
    WorldFactVerdict.unscorable => TruthVerdict.unscorable,
  };
  final promptSupportsClaim = arm == CensusArm.worldFactGrounded;
  final grounding = switch ((promptSupportsClaim, truth)) {
    (false, _) => GroundingVerdict.absent,
    (_, TruthVerdict.correct) => GroundingVerdict.supported,
    (_, TruthVerdict.stale) => GroundingVerdict.contradicted,
    (_, TruthVerdict.unscorable) => GroundingVerdict.absent,
  };
  return ClaimRecord(
    claimId: '${testCase.id}:${arm.name}:$repeat',
    caseId: testCase.id,
    cutoffClass: CutoffClass.worldFact,
    arm: arm,
    repeat: repeat,
    truth: truth,
    grounding: grounding,
    provenance: promptSupportsClaim && truth != TruthVerdict.unscorable
        ? GroundingProvenance.promptContext
        : GroundingProvenance.none,
    assertedValue: scored.asserted,
    expectedValue: '^${fact.latestVersion}',
    truthSource: truthSource,
    worldFactVerdict: scored.verdict,
  );
}

Future<CensusSummary> runCutoffCensus({
  required CensusOptions options,
  required CutoffOracle oracle,
  required ChatCompletionSender send,
  void Function(String line)? onProgress,
  List<CutoffCase> cases = const [],
  List<EnvironmentCase> environmentCases = const [],
  List<WorldFactCase> worldFactCases = const [],
  WorldFactSnapshot? worldFacts,
  Map<CensusArm, String> production = const {},
}) async {
  // A production run replaces the prototype arms in every class; the frozen
  // baseline in docs/evidence is what it is compared against.
  final idiomRunArms = production.isEmpty
      ? idiomArms
      : production.keys.toList();
  final worldRunArms = production.isEmpty
      ? worldFactArms
      : production.keys.toList();
  if (worldFactCases.isNotEmpty && worldFacts == null) {
    throw ArgumentError('class 1 fixtures need a world-fact snapshot');
  }
  final all = cases.isEmpty ? cutoffCases : cases;
  final selected = options.caseFilter.isEmpty
      ? all
      : all
            .where((testCase) => options.caseFilter.contains(testCase.id))
            .toList(growable: false);
  final selectedEnvironment = options.caseFilter.isEmpty
      ? environmentCases
      : environmentCases
            .where((testCase) => options.caseFilter.contains(testCase.id))
            .toList(growable: false);
  final selectedWorldFacts = options.caseFilter.isEmpty
      ? worldFactCases
      : worldFactCases
            .where((testCase) => options.caseFilter.contains(testCase.id))
            .toList(growable: false);
  final ground = groundTruthBlock(oracle);
  final delta = deltaBlock(oracle);
  final environmentGround = environmentGroundTruthBlock(oracle);
  final claims = <ClaimRecord>[];
  for (final testCase in selected) {
    final truthSource =
        testCase.confirmStale(oracle) ?? _truthSourceFor(testCase, oracle);
    for (var repeat = 1; repeat <= options.repeats; repeat++) {
      for (final arm in idiomRunArms) {
        onProgress?.call('${testCase.id} ${arm.name} #$repeat');
        final prompt = switch (arm) {
          CensusArm.bare => testCase.task,
          CensusArm.grounded => '$ground\n\n${testCase.task}',
          CensusArm.deltaGrounded => '$ground\n\n$delta\n\n${testCase.task}',
          CensusArm.worldFactGrounded => throw StateError('not an idiom arm'),
          CensusArm.productionDefault ||
          CensusArm.production32k ||
          CensusArm.production64k ||
          CensusArm.productionVersionsOnly ||
          CensusArm.productionImported ||
          CensusArm.productionImportedDigest =>
            '${production[arm]}\n\n${testCase.task}',
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
              promptSupportsClaim: production.containsKey(arm)
                  ? testCase.coverageSymbols.any(production[arm]!.contains)
                  : promptSupportsClaimFor(
                      testCase: testCase,
                      arm: arm,
                      oracle: oracle,
                    ),
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
  for (final testCase in selectedEnvironment) {
    final defaultValue = testCase.readDefault(oracle);
    if (defaultValue == null) {
      throw StateError(
        '${testCase.id}: the environment oracle returned no default value',
      );
    }
    final truthSource =
        'Flutter ${oracle.flutterVersion}: '
        'ThemeData.useMaterial3 default: $defaultValue';
    for (var repeat = 1; repeat <= options.repeats; repeat++) {
      for (final arm in idiomRunArms) {
        onProgress?.call('${testCase.id} ${arm.name} #$repeat');
        final prompt = switch (arm) {
          CensusArm.bare => testCase.task,
          CensusArm.grounded => '$environmentGround\n\n${testCase.task}',
          CensusArm.deltaGrounded =>
            '$environmentGround\n\n$delta\n\n${testCase.task}',
          CensusArm.worldFactGrounded => throw StateError('not an idiom arm'),
          CensusArm.productionDefault ||
          CensusArm.production32k ||
          CensusArm.production64k ||
          CensusArm.productionVersionsOnly ||
          CensusArm.productionImported ||
          CensusArm.productionImportedDigest =>
            '${production[arm]}\n\n${testCase.task}',
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
            scoreEnvironmentResponse(
              testCase: testCase,
              arm: arm,
              repeat: repeat,
              response: response,
              truthSource: truthSource,
              promptSupportsClaim: promptSupportsEnvironmentClaimFor(
                testCase: testCase,
                arm: arm,
                oracle: oracle,
              ),
              defaultValue: defaultValue,
            ),
          );
        } on Object catch (error) {
          claims.add(
            ClaimRecord(
              claimId: '${testCase.id}:${arm.name}:$repeat',
              caseId: testCase.id,
              cutoffClass: CutoffClass.environment,
              arm: arm,
              repeat: repeat,
              truth: TruthVerdict.unscorable,
              grounding: GroundingVerdict.absent,
              provenance: GroundingProvenance.none,
              assertedValue: 'none',
              expectedValue: defaultValue ? 'omitted' : 'true',
              truthSource: truthSource,
              failure: 'request failed: $error',
            ),
          );
        }
      }
    }
  }
  for (final testCase in selectedWorldFacts) {
    final fact = worldFacts![testCase.package];
    if (fact == null) {
      throw StateError('${testCase.id}: the snapshot has no fact');
    }
    final installed = oracle.packageVersion(testCase.package);
    final truthSource =
        '${fact.source}: latest ${fact.latestVersion}'
        '${fact.publishedAt == null ? '' : ', published ${fact.publishedAt}'}'
        ', fetched ${fact.fetchedAt}; installed here: ${installed ?? 'none'}';
    final worldGround = worldFactBlock(worldFacts);
    for (var repeat = 1; repeat <= options.repeats; repeat++) {
      for (final arm in worldRunArms) {
        onProgress?.call('${testCase.id} ${arm.name} #$repeat');
        final prompt = switch (arm) {
          CensusArm.bare => testCase.task,
          CensusArm.grounded => '$ground\n\n${testCase.task}',
          CensusArm.worldFactGrounded => '$worldGround\n\n${testCase.task}',
          CensusArm.deltaGrounded => throw StateError('not a class 1 arm'),
          CensusArm.productionDefault ||
          CensusArm.production32k ||
          CensusArm.production64k ||
          CensusArm.productionVersionsOnly ||
          CensusArm.productionImported ||
          CensusArm.productionImportedDigest =>
            '${production[arm]}\n\n${testCase.task}',
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
            scoreWorldFactClaim(
              testCase: testCase,
              arm: arm,
              repeat: repeat,
              response: response,
              fact: fact,
              truthSource: truthSource,
            ),
          );
        } on Object catch (error) {
          claims.add(
            ClaimRecord(
              claimId: '${testCase.id}:${arm.name}:$repeat',
              caseId: testCase.id,
              cutoffClass: CutoffClass.worldFact,
              arm: arm,
              repeat: repeat,
              truth: TruthVerdict.unscorable,
              grounding: GroundingVerdict.absent,
              provenance: GroundingProvenance.none,
              assertedValue: 'none',
              expectedValue: '^${fact.latestVersion}',
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
    runIdentity: {
      ..._runIdentity(
        options: options,
        oracle: oracle,
        worldFacts: selectedWorldFacts.isEmpty ? null : worldFacts,
      ),
      // The exact bytes each production arm carried, so the verdicts can be
      // tied to the block rather than to the builder's later behavior.
      if (production.isNotEmpty)
        'productionBlocks': {
          for (final entry in production.entries) entry.key.name: entry.value,
        },
    },
    productionCoverage: {
      for (final testCase in selected)
        testCase.id: {
          for (final entry in production.entries)
            entry.key.name: testCase.coverageSymbols.any(entry.value.contains),
        },
    },
    digestCoverage: {
      for (final testCase in selected)
        testCase.id: digestCovers(testCase, oracle),
    },
  );
}

const _systemPrompt =
    'You are a coding assistant. Answer with code only, no explanation.';

String _truthSourceFor(
  CutoffCase testCase,
  CutoffOracle oracle,
) => switch (testCase.id) {
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
  WorldFactSnapshot? worldFacts,
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
    // A world fact expires, so the snapshot a class 1 verdict was scored
    // against is part of what the run was.
    if (worldFacts != null) 'worldFacts': worldFacts.toJson(),
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
    this.offline = false,
    this.worldFactsPath,
    this.saveWorldFactsPath,
    this.production = false,
    this.armFilter = const {},
  });

  static const usage =
      'Usage: dart run tool/kc1_cutoff_exposure_census.dart \\\n'
      '  --endpoint http://host:1234/v1/chat/completions --model <id> \\\n'
      '  [--repeats 3] [--temperature 0.7] [--timeout 180] [--json] \\\n'
      '  [--out build/kc1/census.json] [--dump-dir build/kc1/raw] \\\n'
      '  [--case <id>]... [--verify-only] \\\n'
      '  [--offline | --world-facts snapshot.json] [--save-world-facts <path>] \\\n'
      '  [--production [--arm <productionArm>]...]\n'
      '--production replaces the prototype arms with the KC2 production block '
      'at each usable-context budget.\n'
      '--verify-only checks every fixture against the installed toolchain and '
      'the world-fact snapshot, and sends nothing to the model.\n'
      'Class 1 reads pub.dev unless --offline leaves it out or --world-facts '
      'replays a frozen snapshot.';

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

  /// Leave class 1 out, so the run touches no network but the model endpoint.
  final bool offline;

  /// A frozen class 1 snapshot to replay instead of fetching one.
  final String? worldFactsPath;

  /// Where to write the class 1 snapshot this run used, to freeze it.
  final String? saveWorldFactsPath;

  /// Run the KC2 production arms instead of the prototype arms.
  final bool production;

  /// With [production], run only these production arms (by name).
  final Set<String> armFilter;

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
    var offline = false;
    var production = false;
    final armFilter = <String>{};
    String? worldFactsPath;
    String? saveWorldFactsPath;
    String? outputPath;
    String? dumpDir;
    final caseFilter = <String>{};
    var projectRoot = Directory.current.path;

    String? value(int index) =>
        index + 1 < args.length ? args[index + 1] : null;
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
        case '--offline':
          offline = true;
        case '--production':
          production = true;
        case '--arm':
          final arm = value(i);
          if (arm != null) armFilter.add(arm);
          i++;
        case '--world-facts':
          worldFactsPath = value(i);
          i++;
        case '--save-world-facts':
          saveWorldFactsPath = value(i);
          i++;
        case '--help':
          return null;
      }
    }
    if (repeats < 1) return null;
    if (offline && worldFactsPath != null) return null;
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
      offline: offline,
      worldFactsPath: worldFactsPath,
      saveWorldFactsPath: saveWorldFactsPath,
      production: production,
      armFilter: armFilter,
    );
  }
}
