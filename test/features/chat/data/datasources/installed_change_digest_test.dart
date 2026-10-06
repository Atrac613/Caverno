import 'dart:io';

import 'package:caverno/features/chat/data/datasources/dependency_inventory.dart';
import 'package:caverno/features/chat/data/datasources/environment_grounding_context_builder.dart';
import 'package:caverno/features/chat/data/datasources/installed_change_digest.dart';
import 'package:flutter_test/flutter_test.dart';

/// KC2 slice 4: what the installed versions changed, read from their own
/// sources. Defended here: only the installed release line counts, prose that
/// mentions the word "breaking" is not an entry, and the budget is spent in a
/// fixed order that no single package can monopolize.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kc2_digest_test_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  File changelog(String text) =>
      File('${root.path}/CHANGELOG.md')..writeAsStringSync(text);

  List<String> entries(String text, String installed) =>
      InstalledChangeDigest.breakingEntries(
        changelog(text),
        installedVersion: installed,
      );

  group('breaking entries', () {
    test('come from the installed release line, at or below the installed '
        'version', () {
      const text = '''
## 4.0.0
- **Breaking**: from a newer major the project does not have.

## 3.2.5
- Fix a bug.

## 3.0.0
- **Breaking**: classes should now be `abstract` or `sealed`.

## 2.0.0
- **Breaking**: an old migration this version is already past.
''';
      expect(entries(text, '3.2.5'), [
        'Breaking: classes should now be `abstract` or `sealed`.',
      ]);
    });

    test('below 1.0 the release line is the minor', () {
      const text = '''
## 0.14.0
- BREAKING: newer minor.

## 0.13.2
- BREAKING: this line.

## 0.12.0
- BREAKING: older minor.
''';
      expect(entries(text, '0.13.4'), ['BREAKING: this line.']);
    });

    test('prose that mentions the word is not an entry', () {
      const text = '''
## 2.34.0
- Non-breaking updates to `checkedCreate`.
- Revert the breaking change around `QueryRow.read`.
- Fix `exclusively` breaking the database connection.
- __Potentially breaking change__ Migrate to sqlite3 3.x.
- chore: **Breaking change** Remove the background service.
''';
      expect(entries(text, '2.34.4'), [
        'Potentially breaking change Migrate to sqlite3 3.x.',
        'chore: Breaking change Remove the background service.',
      ]);
    });

    test('nested and wrapped lines join their marker, and a breaking '
        'subheading marks its bullets', () {
      const text = '''
## 17.0.0
- **BREAKING CHANGE**
  - `GoRouteData` now defines `.location`.
- Unrelated fix.

## 16.0.0
### Breaking changes
- `ShellRoute` moved to `StatefulShellRoute`,
  which keeps state per branch.
''';
      expect(entries(text, '17.1.0'), [
        'BREAKING CHANGE `GoRouteData` now defines `.location`.',
      ]);
      expect(entries(text, '16.2.0'), [
        '`ShellRoute` moved to `StatefulShellRoute`, which keeps state per '
            'branch.',
      ]);
    });

    test('links, issue numbers and commit hashes are dropped', () {
      const text = '''
## 6.0.0
- **BREAKING** **FEAT**: bump iOS SDK ([#17549](https://example.com/17549)). ([b2619e68](https://example.com/b2619e68))
''';
      expect(entries(text, '6.8.1'), ['BREAKING FEAT: bump iOS SDK']);
    });
  });

  test('legacy symbols come from a legacy library and legacy directories', () {
    File('${root.path}/lib/legacy.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "export 'src/internals.dart'\n    show\n        StateProvider,\n"
        '        StateNotifierProvider;\n',
      );
    File('${root.path}/lib/src/legacy/controller.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('final class StateController {}\nclass _Hidden {}\n');
    expect(InstalledChangeDigest.legacySymbols(root.path), [
      'StateController',
      'StateNotifierProvider',
      'StateProvider',
    ]);
  });

  group('the renderer', () {
    DependencyRecord record(String name) => DependencyRecord(
      name: name,
      ecosystem: 'dart',
      dependencyKind: 'direct main',
      manifestPath: null,
      lockedVersion: '1.0.0',
      lockfilePath: 'pubspec.lock',
      installedVersion: '1.0.0',
      installedMetadataPath: null,
      resolvedRoot: '/nowhere',
      attestation: DependencyAttestation.exact,
    );

    PackageChange change(
      String name, {
      List<String> legacy = const [],
      List<String> breaking = const [],
    }) => PackageChange(
      record: record(name),
      legacySymbols: legacy,
      breakingEntries: breaking,
    );

    test('spends the budget in a fixed order, round-robin across packages', () {
      final digest = ChangeDigestRenderer.render(
        packages: [
          change('alpha', breaking: ['a1', 'a2', 'a3']),
          change('beta', legacy: ['OldThing'], breaking: ['b1']),
        ],
        sdkDeprecations: const [
          SdkDeprecation(
            symbol: 'withOpacity',
            advice: 'Use withValues.',
            since: 'v3.27',
          ),
        ],
        flutterVersion: '3.47.4',
        maxChars: 10000,
      );
      expect(
        digest,
        '${ChangeDigestRenderer.heading}\n'
        '- beta 1.0.0 keeps these only in its legacy library: OldThing\n'
        '- Flutter 3.47.4 deprecates withOpacity: Use withValues.\n'
        '- alpha 1.0.0: a1\n'
        '- beta 1.0.0: b1\n'
        '- alpha 1.0.0: a2\n'
        '- alpha 1.0.0: a3',
      );
    });

    test('a package early in the alphabet cannot crowd out later ones', () {
      final digest = ChangeDigestRenderer.render(
        packages: [
          change('alpha', breaking: List.generate(20, (i) => 'alpha entry $i')),
          change('zeta', breaking: ['zeta entry']),
        ],
        sdkDeprecations: const [],
        flutterVersion: null,
        maxChars: 200,
      )!;
      expect(digest, contains('zeta entry'));
      expect(digest.length, lessThanOrEqualTo(200));
    });

    test('an unattested SDK contributes nothing, and an identical entry is '
        'listed once', () {
      final digest = ChangeDigestRenderer.render(
        packages: [
          change('firebase_a', breaking: ['bump iOS SDK']),
          change('firebase_b', breaking: ['bump iOS SDK']),
        ],
        sdkDeprecations: const [
          SdkDeprecation(symbol: 'x', advice: 'y', since: 'v1'),
        ],
        flutterVersion: null,
        maxChars: 1000,
      )!;
      expect(digest, isNot(contains('Flutter')));
      expect('bump iOS SDK'.allMatches(digest).length, 1);
    });

    test('nothing to say means no digest', () {
      expect(
        ChangeDigestRenderer.render(
          packages: [change('quiet')],
          sdkDeprecations: const [],
          flutterVersion: '3.47.4',
          maxChars: 1000,
        ),
        isNull,
      );
    });
  });

  group('the budget', () {
    test('steps with usable context and drops the digest first', () {
      int digest(int? tokens) =>
          EnvironmentGroundingContextBuilder.digestMaxCharsForUsableContext(
            tokens,
          );
      expect(digest(null), 1600);
      expect(digest(8192), 0);
      expect(digest(16384), 1600);
      expect(digest(32768), 6000);
      expect(digest(65536), 10000);
    });

    test('on this repository a 64k window covers the three measured idioms '
        'and not the control', () {
      final block = EnvironmentGroundingContextBuilder().build(
        Directory.current.path,
        maxChars: EnvironmentGroundingContextBuilder.maxCharsForUsableContext(
          131072,
        ),
        digestMaxChars:
            EnvironmentGroundingContextBuilder.digestMaxCharsForUsableContext(
              131072,
            ),
      )!;
      final digest = block.substring(
        block.indexOf(ChangeDigestRenderer.heading),
      );
      expect(digest.length, lessThanOrEqualTo(10000));
      expect(digest, contains('withOpacity'));
      expect(digest, contains('StateNotifierProvider'));
      expect(digest, contains('`abstract`'));
      expect(
        digest,
        isNot(contains('WillPopScope')),
        reason:
            'deprecated at v3.12, outside the window: KC1 keeps it as the '
            'uncovered control',
      );
    });

    test('a zero digest budget leaves the dependency block alone', () {
      final builder = EnvironmentGroundingContextBuilder();
      final block = builder.build(Directory.current.path, digestMaxChars: 0)!;
      expect(block, isNot(contains(ChangeDigestRenderer.heading)));
    });
  });
}
