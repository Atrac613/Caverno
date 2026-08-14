import 'dart:io';

import 'package:caverno/features/chat/data/datasources/project_read_path_fence.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory project;
  late Directory sibling;
  const fence = ProjectReadPathFence();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('project-read-fence-');
    project = await Directory(p.join(sandbox.path, 'project')).create();
    sibling = await Directory(p.join(sandbox.path, 'project-secrets')).create();
    await File(p.join(project.path, 'inside.txt')).writeAsString('inside');
    await File(p.join(sibling.path, 'secret.txt')).writeAsString('secret');
  });

  tearDown(() => sandbox.delete(recursive: true));

  test(
    'allows relative and absolute existing targets inside the root',
    () async {
      final relative = await fence.authorize(
        projectRoot: project.path,
        rawPath: 'inside.txt',
      );
      final absolute = await fence.authorize(
        projectRoot: project.path,
        rawPath: p.join(project.path, 'inside.txt'),
      );

      expect(relative.isAllowed, isTrue);
      expect(relative.canonicalPath, absolute.canonicalPath);
      expect(absolute.isAllowed, isTrue);
    },
  );

  test('fails closed without a root or an existing target', () async {
    final noRoot = await fence.authorize(
      projectRoot: null,
      rawPath: 'inside.txt',
    );
    final missing = await fence.authorize(
      projectRoot: project.path,
      rawPath: 'missing.txt',
    );

    expect(noRoot.denial, ProjectReadPathDenial.projectRootRequired);
    expect(missing.denial, ProjectReadPathDenial.pathUnavailable);
  });

  test(
    'rejects home paths, traversal, siblings, and prefix collisions',
    () async {
      for (final rawPath in [
        '~',
        '~/secret',
        '../project-secrets/secret.txt',
      ]) {
        final result = await fence.authorize(
          projectRoot: project.path,
          rawPath: rawPath,
        );
        expect(result.isAllowed, isFalse, reason: rawPath);
      }

      final siblingResult = await fence.authorize(
        projectRoot: project.path,
        rawPath: p.join(sibling.path, 'secret.txt'),
      );
      expect(siblingResult.denial, ProjectReadPathDenial.outsideProject);
    },
  );

  test('rejects direct and intermediate symlink escapes', () async {
    final directLink = Link(p.join(project.path, 'direct-secret'));
    final directoryLink = Link(p.join(project.path, 'linked-secrets'));
    try {
      await directLink.create(p.join(sibling.path, 'secret.txt'));
      await directoryLink.create(sibling.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }

    for (final rawPath in [
      directLink.path,
      p.join(directoryLink.path, 'secret.txt'),
    ]) {
      final result = await fence.authorize(
        projectRoot: project.path,
        rawPath: rawPath,
      );
      expect(result.denial, ProjectReadPathDenial.outsideProject);
    }
  });

  test('accepts a selected root and target reached through symlinks', () async {
    final rootLink = Link(p.join(sandbox.path, 'selected-project'));
    final insideLink = Link(p.join(project.path, 'inside-link'));
    try {
      await rootLink.create(project.path);
      await insideLink.create(p.join(project.path, 'inside.txt'));
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable on this platform.');
      return;
    }

    final result = await fence.authorize(
      projectRoot: rootLink.path,
      rawPath: insideLink.path,
    );

    expect(result.isAllowed, isTrue);
    expect(result.canonicalRoot, await project.resolveSymbolicLinks());
    expect(
      result.canonicalPath,
      await File(p.join(project.path, 'inside.txt')).resolveSymbolicLinks(),
    );
  });
}
