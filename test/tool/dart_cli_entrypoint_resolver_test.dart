import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/canaries/support/dart_cli_entrypoint_resolver.dart';

void main() {
  const resolver = DartCliEntrypointResolver();

  test('fixed policy selects the canonical entrypoint', () {
    final root = _fixtureRoot();
    addTearDown(() => root.deleteSync(recursive: true));
    _write(root, 'bin/todo_cli.dart');

    final resolution = resolver.resolve(
      root: root,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.fixed,
    );

    expect(resolution.isResolved, isTrue);
    expect(resolution.selectedRelativePath, 'bin/todo_cli.dart');
    expect(resolution.issues, isEmpty);
  });

  test('fixed policy reports missing and unexpected entrypoints', () {
    final missingRoot = _fixtureRoot();
    final extraRoot = _fixtureRoot();
    addTearDown(() => missingRoot.deleteSync(recursive: true));
    addTearDown(() => extraRoot.deleteSync(recursive: true));
    _write(extraRoot, 'bin/todo_cli.dart');
    _write(extraRoot, 'bin/todo.dart');

    final missing = resolver.resolve(
      root: missingRoot,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.fixed,
    );
    final unexpected = resolver.resolve(
      root: extraRoot,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.fixed,
    );

    expect(missing.issues.single.kind, DartCliEntrypointIssueKind.missing);
    expect(missing.issues.single.relativePath, 'bin/todo_cli.dart');
    expect(
      unexpected.issues.single.kind,
      DartCliEntrypointIssueKind.unexpected,
    );
    expect(unexpected.issues.single.relativePath, 'bin/todo.dart');
  });

  test('adaptive policy selects one alternate entrypoint', () {
    final root = _fixtureRoot();
    addTearDown(() => root.deleteSync(recursive: true));
    _write(root, 'bin/todo.dart');

    final resolution = resolver.resolve(
      root: root,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.singleUnderBin,
    );

    expect(resolution.isResolved, isTrue);
    expect(resolution.selectedRelativePath, 'bin/todo.dart');
    expect(resolution.candidates, ['bin/todo.dart']);
  });

  test('adaptive policy reports zero and multiple candidates', () {
    final emptyRoot = _fixtureRoot();
    final ambiguousRoot = _fixtureRoot();
    addTearDown(() => emptyRoot.deleteSync(recursive: true));
    addTearDown(() => ambiguousRoot.deleteSync(recursive: true));
    _write(ambiguousRoot, 'bin/a.dart');
    _write(ambiguousRoot, 'bin/b.dart');
    _write(ambiguousRoot, 'bin/readme.txt');

    final missing = resolver.resolve(
      root: emptyRoot,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.singleUnderBin,
    );
    final ambiguous = resolver.resolve(
      root: ambiguousRoot,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.singleUnderBin,
    );

    expect(missing.issues.single.kind, DartCliEntrypointIssueKind.missing);
    expect(ambiguous.isResolved, isFalse);
    expect(ambiguous.issues.single.kind, DartCliEntrypointIssueKind.ambiguous);
    expect(ambiguous.issues.single.relativePath, 'bin/a.dart');
    expect(ambiguous.candidates, ['bin/a.dart', 'bin/b.dart']);
  });

  test('conventional policy accepts lib or root main entrypoints', () {
    final libRoot = _fixtureRoot();
    final rootMain = _fixtureRoot();
    addTearDown(() => libRoot.deleteSync(recursive: true));
    addTearDown(() => rootMain.deleteSync(recursive: true));
    _write(libRoot, 'lib/main.dart');
    _write(rootMain, 'main.dart');

    final libResolution = resolver.resolve(
      root: libRoot,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.singleConventional,
    );
    final rootResolution = resolver.resolve(
      root: rootMain,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.singleConventional,
    );

    expect(libResolution.selectedRelativePath, 'lib/main.dart');
    expect(rootResolution.selectedRelativePath, 'main.dart');
  });

  test('conventional policy rejects ambiguous entrypoints across layouts', () {
    final root = _fixtureRoot();
    addTearDown(() => root.deleteSync(recursive: true));
    _write(root, 'bin/todo.dart');
    _write(root, 'lib/main.dart');

    final resolution = resolver.resolve(
      root: root,
      canonicalRelativePath: 'bin/todo_cli.dart',
      policy: DartCliEntrypointPolicy.singleConventional,
    );

    expect(resolution.isResolved, isFalse);
    expect(resolution.issues.single.kind, DartCliEntrypointIssueKind.ambiguous);
    expect(resolution.candidates, ['bin/todo.dart', 'lib/main.dart']);
  });

  test('resolver rejects unsafe canonical paths', () {
    final root = _fixtureRoot();
    addTearDown(() => root.deleteSync(recursive: true));

    expect(
      () => resolver.resolve(
        root: root,
        canonicalRelativePath: '../todo.dart',
        policy: DartCliEntrypointPolicy.singleUnderBin,
      ),
      throwsArgumentError,
    );
  });
}

Directory _fixtureRoot() =>
    Directory.systemTemp.createTempSync('dart_cli_entrypoint_resolver_test_');

void _write(Directory root, String relativePath) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('void main() {}\n');
}
