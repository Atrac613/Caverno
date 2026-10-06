import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/kc1_cutoff_exposure_census.dart';
import '../../tool/kc1_cutoff_oracle.dart';
import '../../tool/kc1_world_fact_oracle.dart';

/// KC1 class 1: world facts, scored against a registry snapshot.
///
/// Everything here runs offline. The live census reads pub.dev; these tests
/// inject a snapshot, because a test whose expected value moves whenever a
/// package publishes would be measuring the registry, not the instrument.

WorldFact _fact(String package, String version) => WorldFact(
  package: package,
  latestVersion: version,
  publishedAt: '2026-09-18T21:14:49Z',
  source: 'https://pub.dev/api/packages/$package',
  fetchedAt: '2026-09-23T00:00:00Z',
);

final _snapshot = WorldFactSnapshot({
  'freezed': _fact('freezed', '4.0.2'),
  'go_router': _fact('go_router', '18.0.1'),
  'flutter_riverpod': _fact('flutter_riverpod', '3.4.3'),
  'dio': _fact('dio', '5.11.1'),
});

WorldFactCase _case(String package) =>
    worldFactCases.firstWhere((testCase) => testCase.package == package);

WorldFactVerdict _verdict(String constraint, String latest) =>
    scoreVersionConstraint(
      constraint: constraint,
      latest: ReleaseVersion.tryParse(latest)!,
    );

ClaimRecord _score(
  String response, {
  String package = 'freezed',
  CensusArm arm = CensusArm.bare,
  WorldFactSnapshot? snapshot,
}) => scoreWorldFactClaim(
  testCase: _case(package),
  arm: arm,
  repeat: 1,
  response: response,
  fact: (snapshot ?? _snapshot)[package]!,
  truthSource: 'test',
);

CensusOptions _options([List<String> extra = const []]) => CensusOptions.parse([
  '--endpoint',
  'http://scripted/v1/chat/completions',
  '--model',
  'scripted',
  '--repeats',
  '1',
  ...extra,
], const {})!;

void main() {
  group('a constraint is scored by the release line it names', () {
    test('the latest line is current, whatever the patch', () {
      expect(_verdict('^4.0.2', '4.0.2'), WorldFactVerdict.current);
      expect(_verdict('^4.0.0', '4.0.2'), WorldFactVerdict.current);
      expect(_verdict('4.0.0', '4.0.2'), WorldFactVerdict.current);
    });

    test('an older line is behind', () {
      expect(_verdict('^3.2.5', '4.0.2'), WorldFactVerdict.behind);
      expect(_verdict('^2.5.7', '4.0.2'), WorldFactVerdict.behind);
    });

    test('a version newer than anything published is ahead, not current', () {
      expect(_verdict('^5.0.0', '4.0.2'), WorldFactVerdict.ahead);
      expect(_verdict('^4.0.9', '4.0.2'), WorldFactVerdict.ahead);
    });

    test('an explicit range is current when it admits the latest release', () {
      expect(_verdict('>=3.0.0 <5.0.0', '4.0.2'), WorldFactVerdict.current);
      expect(_verdict("'>=3.0.0 <4.0.0'", '4.0.2'), WorldFactVerdict.behind);
      expect(_verdict('>=3.0.0 <=4.0.2', '4.0.2'), WorldFactVerdict.current);
    });

    test('pre-1.0 lines are compared on the minor, as caret does', () {
      expect(_verdict('^0.13.0', '0.13.4'), WorldFactVerdict.current);
      expect(_verdict('^0.12.9', '0.13.4'), WorldFactVerdict.behind);
    });

    test('quotes and trailing comments are not part of the claim', () {
      expect(_verdict('"^4.0.0"', '4.0.2'), WorldFactVerdict.current);
      expect(_verdict('^3.0.0 # stable', '4.0.2'), WorldFactVerdict.behind);
    });

    test('no version claim is unscorable rather than either side', () {
      for (final constraint in ['', 'any', 'latest', '^four']) {
        expect(
          _verdict(constraint, '4.0.2'),
          WorldFactVerdict.unscorable,
          reason: constraint,
        );
      }
    });
  });

  group('the pubspec is read by entry, never by prose', () {
    test('a package name inside a longer one is not its entry', () {
      const response = '''
dependencies:
  flutter_riverpod: ^3.4.0
  freezed_annotation: ^2.4.0
''';
      expect(pubspecConstraintsFor(response, 'riverpod'), isEmpty);
      expect(pubspecConstraintsFor(response, 'freezed'), isEmpty);
      expect(pubspecConstraintsFor(response, 'flutter_riverpod'), ['^3.4.0']);
    });

    test('freezed is found where it belongs, under dev_dependencies', () {
      const response = '''
dependencies:
  freezed_annotation: ^3.0.0
dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^4.0.0
''';
      expect(_score(response).worldFactVerdict, WorldFactVerdict.current);
      expect(_score(response).assertedValue, '^4.0.0');
    });

    test('two entries on different lines are unscorable', () {
      const response = 'freezed: ^3.2.5\n\n# or\nfreezed: ^4.0.0\n';
      expect(_score(response).truth, TruthVerdict.unscorable);
    });

    test('a response with no entry asserts nothing', () {
      final record = _score('Use the latest freezed.');
      expect(record.truth, TruthVerdict.unscorable);
      expect(record.assertedValue, 'none');
    });
  });

  group('truth and grounding stay separate axes', () {
    test('correct and stale claims with nothing behind them differ only in '
        'truth', () {
      final correct = _score('freezed: ^4.0.2');
      final stale = _score('freezed: ^3.2.5');
      expect(correct.truth, TruthVerdict.correct);
      expect(stale.truth, TruthVerdict.stale);
      expect(correct.grounding, GroundingVerdict.absent);
      expect(stale.grounding, GroundingVerdict.absent);
      expect(stale.provenance, GroundingProvenance.none);
    });

    test('the world-fact arm is prompt context, and a stale answer there '
        'contradicts it', () {
      final supported = _score(
        'freezed: ^4.0.2',
        arm: CensusArm.worldFactGrounded,
      );
      final contradicted = _score(
        'freezed: ^3.2.5',
        arm: CensusArm.worldFactGrounded,
      );
      expect(supported.grounding, GroundingVerdict.supported);
      expect(supported.provenance, GroundingProvenance.promptContext);
      expect(contradicted.grounding, GroundingVerdict.contradicted);
    });

    test('the installed-toolchain block does not ground a world fact', () {
      final record = _score('freezed: ^4.0.2', arm: CensusArm.grounded);
      expect(record.grounding, GroundingVerdict.absent);
      expect(record.provenance, GroundingProvenance.none);
    });

    test('a fabricated version is not correct, and keeps its own verdict', () {
      final record = _score('freezed: ^9.0.0');
      expect(record.truth, TruthVerdict.stale);
      expect(record.worldFactVerdict, WorldFactVerdict.ahead);
    });
  });

  group('the negative control', () {
    test('a stale snapshot flips the verdict on the same response', () {
      final expired = WorldFactSnapshot({'freezed': _fact('freezed', '3.2.5')});
      const response = 'freezed: ^4.0.2';
      expect(_score(response).truth, TruthVerdict.correct);
      expect(
        _score(response, snapshot: expired).truth,
        isNot(TruthVerdict.correct),
        reason:
            'The expected value comes from the snapshot, not from the '
            'fixture. If a stale snapshot could not change the verdict, the '
            'fixture would be encoding the answer it claims to measure.',
      );
    });

    test('a snapshot missing a package fails verification', () {
      final partial = WorldFactSnapshot({'dio': _fact('dio', '5.11.1')});
      final problems = verifyWorldFactFixtures(worldFactCases, partial);
      expect(problems, hasLength(worldFactCases.length - 1));
      expect(verifyWorldFactFixtures(worldFactCases, _snapshot), isEmpty);
    });

    test('an unparseable latest version fails verification', () {
      final broken = WorldFactSnapshot({
        for (final testCase in worldFactCases)
          testCase.package: _fact(testCase.package, 'latest'),
      });
      expect(
        verifyWorldFactFixtures(worldFactCases, broken),
        hasLength(worldFactCases.length),
      );
    });
  });

  group('the fixtures', () {
    test('ask for a new app, so this repository is not the answer', () {
      for (final testCase in worldFactCases) {
        expect(testCase.task, contains('new Flutter app'));
        expect(testCase.task, contains(testCase.package));
        expect(testCase.task, isNot(contains(RegExp(r'\d+\.\d+\.\d+'))));
      }
    });

    test('the world-fact block names versions, not an expected answer', () {
      final block = worldFactBlock(_snapshot);
      expect(block, contains('freezed: 4.0.2 (published 2026-09-18)'));
      expect(block, isNot(contains('^')));
    });
  });

  group('the replay', () {
    test(
      'class 1 runs its own arms, each carrying what it is meant to',
      () async {
        final oracle = CutoffOracle.resolve();
        final installed = oracle.packageVersion('freezed');
        expect(installed, isNotNull);
        final seen = <String>[];
        final summary = await runCutoffCensus(
          options: _options(['--case', 'pub-latest-freezed']),
          oracle: oracle,
          worldFactCases: worldFactCases,
          worldFacts: _snapshot,
          send: (system, user) async {
            seen.add(
              user.contains('Latest stable releases on pub.dev')
                  ? 'world'
                  : user.contains('freezed: $installed')
                  ? 'grounded'
                  : 'bare',
            );
            return 'dev_dependencies:\n  freezed: ^4.0.2\n';
          },
        );

        expect(seen, ['bare', 'grounded', 'world']);
        expect(summary.claims.map((c) => c.cutoffClass).toSet(), {
          CutoffClass.worldFact,
        });
        expect(summary.staleRateFor(CutoffClass.worldFact, CensusArm.bare), 0);
        final identity = summary.runIdentity['worldFacts'] as Map;
        expect(
          (identity['facts'] as Map)['freezed']['latestVersion'],
          '4.0.2',
          reason:
              'A world fact expires; the run must record what it scored '
              'against.',
        );
        expect(summary.claims.first.truthSource, contains('installed here'));
        final json = summary.toJson();
        expect(json['schemaVersion'], 4);
        expect(
          (json['arms'] as Map)['worldFactGrounded']['worldFactVerdicts'],
          containsPair('current', 1),
        );
        expect(summary.report(), contains('world fact current=1'));
      },
    );

    test('a run without class 1 records no snapshot', () async {
      final summary = await runCutoffCensus(
        options: _options(['--case', 'riverpod-notifier']),
        oracle: CutoffOracle.resolve(),
        send: (system, user) async => 'final p = NotifierProvider(...);',
      );
      expect(summary.runIdentity.containsKey('worldFacts'), isFalse);
      expect(
        summary.claims.map((c) => c.arm).toSet(),
        idiomArms.toSet(),
        reason: 'Adding class 1 must not change the idiom replay baseline.',
      );
    });

    test('class 1 fixtures without a snapshot are refused', () {
      expect(
        () => runCutoffCensus(
          options: _options(),
          oracle: CutoffOracle.resolve(),
          worldFactCases: worldFactCases,
          send: (system, user) async => '',
        ),
        throwsArgumentError,
      );
    });

    test('--offline and --world-facts are mutually exclusive', () {
      expect(
        CensusOptions.parse([
          '--verify-only',
          '--offline',
          '--world-facts',
          'x.json',
        ], const {}),
        isNull,
      );
      final options = CensusOptions.parse([
        '--verify-only',
        '--world-facts',
        'x.json',
        '--save-world-facts',
        'y.json',
      ], const {})!;
      expect(options.worldFactsPath, 'x.json');
      expect(options.saveWorldFactsPath, 'y.json');
      expect(options.offline, isFalse);
    });
  });

  group('the snapshot', () {
    test('round-trips through its frozen form', () {
      final decoded = WorldFactSnapshot.fromJson(
        jsonDecode(jsonEncode(_snapshot.toJson())) as Map<String, dynamic>,
      );
      expect(decoded['freezed']!.latestVersion, '4.0.2');
      expect(decoded['freezed']!.fetchedAt, '2026-09-23T00:00:00Z');
      expect(decoded.facts.keys, _snapshot.facts.keys);
    });

    test(
      'is read from the registry API, and a missing package is an error',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final accepts = <String?>[];
        server.listen((request) {
          accepts.add(request.headers.value(HttpHeaders.acceptHeader));
          if (request.uri.path.endsWith('/freezed')) {
            request.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode({
                  'latest': {
                    'version': '4.0.2',
                    'published': '2026-09-18T21:14:49Z',
                  },
                }),
              );
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          request.response.close();
        });
        final client = HttpClient();
        addTearDown(() async {
          client.close(force: true);
          await server.close(force: true);
        });
        final registry = 'http://127.0.0.1:${server.port}';

        final snapshot = await WorldFactSnapshot.fetch(
          client: client,
          packages: ['freezed'],
          registry: registry,
          now: () => DateTime.utc(2026, 9, 23),
        );
        expect(snapshot['freezed']!.latestVersion, '4.0.2');
        expect(snapshot['freezed']!.fetchedAt, '2026-09-23T00:00:00.000Z');
        expect(snapshot['freezed']!.source, '$registry/api/packages/freezed');
        expect(accepts.single, 'application/vnd.pub.v2+json');

        await expectLater(
          WorldFactSnapshot.fetch(
            client: client,
            packages: ['nope'],
            registry: registry,
          ),
          throwsA(isA<HttpException>()),
        );
      },
    );
  });
}
