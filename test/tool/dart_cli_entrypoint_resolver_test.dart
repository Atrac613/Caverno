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
