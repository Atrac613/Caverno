import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Approved external GitHub Actions, resolved from each action's official Git
/// remote. Update a row only after reviewing the upstream release and resolving
/// the immutable commit again.
const _approvedActions = <String, ({String sha, String version})>{
  'actions/checkout': (
    sha: '3d3c42e5aac5ba805825da76410c181273ba90b1',
    version: 'v7.0.1',
  ),
  'actions/setup-java': (
    sha: 'dd06d9cba3e5552c54d9f8ea23572deb30010f7c',
    version: 'v6.0.0',
  ),
  'subosito/flutter-action': (
    sha: '1a449444c387b1966244ae4d4f8c696479add0b2',
    version: 'v2.23.0',
  ),
  'actions/upload-artifact': (
    sha: '043fb46d1a93c77aae656e7c1c64a875d1fc6a0a',
    version: 'v7.0.1',
  ),
  'peter-evans/create-pull-request': (
    sha: '5f6978faf089d4d20b00c7766989d076bb2fc7f1',
    version: 'v8.1.1',
  ),
};

/// Every workflow, with the exact number of external action invocations it is
/// allowed to make. A new workflow or a new step fails here before it can run
/// unreviewed third-party code.
const _expectedActionUses = <String, int>{
  // 11 since main added a setup-java invocation after SEC4.7c was written.
  // The count is asserted so a new action cannot arrive unpinned and unnoticed;
  // raise it only alongside the pin and the approval below.
  'flutter_ci.yml': 11,
  'flutter_sdk_update.yml': 4,
  'plan_mode_smoke_manual.yml': 3,
};

final _pinnedUses = RegExp(
  r'^\s*uses:\s*([^/@\s]+/[^@\s]+)@([^\s#]+)\s+#\s+(\S+)\s*$',
  multiLine: true,
);

final _anyUses = RegExp(r'^\s*uses:\s*\S+@([^\s#]+)', multiLine: true);

void main() {
  group('GitHub Actions pinning', () {
    late Map<String, String> workflows;

    setUpAll(() {
      workflows = <String, String>{
        for (final entry
            in Directory('.github/workflows')
                .listSync()
                .whereType<File>()
                .where((file) => file.path.endsWith('.yml')))
          entry.uri.pathSegments.last: entry.readAsStringSync(),
      };
    });

    test('covers every workflow file', () {
      expect(workflows.keys.toSet(), _expectedActionUses.keys.toSet());
    });

    test('pins every external action to an approved commit SHA', () {
      for (final MapEntry(key: name, value: workflow) in workflows.entries) {
        final pinned = _pinnedUses.allMatches(workflow).toList();
        expect(
          pinned,
          hasLength(_expectedActionUses[name]),
          reason: 'Unexpected action invocation count in $name',
        );
        for (final match in pinned) {
          final action = match.group(1)!;
          final approved = _approvedActions[action];
          expect(approved, isNotNull, reason: 'Unapproved action: $action');
          expect(match.group(2), approved!.sha, reason: '$name: $action');
          expect(match.group(3), approved.version, reason: '$name: $action');
          expect(match.group(2), matches(RegExp(r'^[0-9a-f]{40}$')));
        }
      }
    });

    test('contains no mutable action tag or branch references', () {
      for (final MapEntry(key: name, value: workflow) in workflows.entries) {
        final references = _anyUses
            .allMatches(workflow)
            .map((match) => match.group(1)!);
        expect(references, isNotEmpty, reason: name);
        for (final reference in references) {
          expect(
            reference,
            matches(RegExp(r'^[0-9a-f]{40}$')),
            reason: '$name uses a mutable reference: $reference',
          );
        }
      }
    });

    test('no workflow grants the job token write access', () {
      // The least-privilege half of SEC4.7c had no test, and pinning alone does
      // not cover it: restoring `contents: write` here passed every other
      // assertion. That combination is the one the pinning exists to prevent —
      // a moved tag in a write-capable job can push to the default branch.
      //
      // Every write this repository's workflows make runs through
      // AUTOMATION_GITHUB_TOKEN inside create-pull-request, behind a preflight
      // that fails the job closed when the secret is absent, so no job needs a
      // write scope on GITHUB_TOKEN.
      final writeScope = RegExp(
        r'^\s*(contents|pull-requests|packages|deployments|actions|'
        r'issues|checks|statuses|security-events):\s*write\s*$',
        multiLine: true,
      );
      for (final MapEntry(key: name, value: workflow) in workflows.entries) {
        final granted = writeScope
            .allMatches(workflow)
            .map((match) => match.group(1))
            .toList();
        expect(
          granted,
          isEmpty,
          reason:
              '$name grants write scope to GITHUB_TOKEN: '
              '${granted.join(', ')}. Route the write through '
              'AUTOMATION_GITHUB_TOKEN instead.',
        );
      }
    });

    test('pins the FVM version installed by the write-capable workflow', () {
      final workflow = workflows['flutter_sdk_update.yml']!;
      expect(
        workflow,
        contains(RegExp(r'dart pub global activate fvm \d+\.\d+\.\d+')),
      );
    });
  });

  group('Gradle distribution', () {
    late List<String> properties;

    setUpAll(() {
      properties = File(
        'android/gradle/wrapper/gradle-wrapper.properties',
      ).readAsLinesSync();
    });

    test('downloads over HTTPS and verifies a distribution checksum', () {
      final distributionUrl = properties.firstWhere(
        (line) => line.startsWith('distributionUrl='),
      );
      expect(distributionUrl, contains(r'https\://services.gradle.org/'));

      final checksum = properties.firstWhere(
        (line) => line.startsWith('distributionSha256Sum='),
        orElse: () => '',
      );
      expect(
        checksum.split('=').last,
        matches(RegExp(r'^[0-9a-f]{64}$')),
        reason: 'The Gradle distribution must be checksum-verified.',
      );
    });
  });

  group('Dependency monitoring', () {
    test('monitors every tracked npm package', () {
      final tracked = Process.runSync('git', ['ls-files', '*package.json']);
      expect(tracked.exitCode, 0, reason: tracked.stderr.toString());

      final directories = (tracked.stdout as String)
          .split('\n')
          .where((path) => path.isNotEmpty)
          .map((path) => '/${path.substring(0, path.lastIndexOf('/'))}')
          .toSet();
      expect(
        directories,
        isNotEmpty,
        reason: 'Expected at least the notification relay package.',
      );

      final dependabot = File('.github/dependabot.yml').readAsStringSync();
      final npmDirectories = RegExp(
        r'package-ecosystem:\s*npm\s*\n\s*directory:\s*(\S+)',
      ).allMatches(dependabot).map((match) => match.group(1)!).toSet();

      expect(
        npmDirectories,
        containsAll(directories),
        reason: 'Every tracked npm package needs a Dependabot update policy.',
      );
    });
  });
}
