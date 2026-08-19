import 'dart:io';

import 'package:caverno/features/chat/data/datasources/project_mutation_path_fence.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory project;
  late Directory sibling;
  const fence = ProjectMutationPathFence();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('project-mutation-fence-');
    project = await Directory(p.join(sandbox.path, 'project')).create();
    sibling = await Directory(p.join(sandbox.path, 'project-secrets')).create();
    await File(p.join(project.path, 'inside.txt')).writeAsString('inside');
    await File(p.join(sibling.path, 'secret.txt')).writeAsString('secret');
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('allows existing and new targets inside the root', () async {
    final existing = await fence.authorize(
      toolName: 'edit_file',
      projectRoot: project.path,
      rawPath: 'inside.txt',
    );
    final created = await fence.authorize(
      toolName: 'write_file',
      projectRoot: project.path,
      rawPath: p.join('lib', 'new.dart'),
    );

    expect(existing.isAllowed, isTrue);
    expect(created.isAllowed, isTrue);
    expect(
      created.canonicalPath,
      p.join(await project.resolveSymbolicLinks(), 'lib', 'new.dart'),
    );
  });

  test('fails closed without a root', () async {
    final result = await fence.authorize(
      toolName: 'write_file',
      projectRoot: null,
      rawPath: 'inside.txt',
    );

    expect(result.denial, ProjectMutationPathDenial.projectRootRequired);
  });

  test(
    'rejects home paths, traversal, siblings, and prefix collisions',
    () async {
      for (final rawPath in [
        '~',
        '~/secret',
        '../project-secrets/secret.txt',
        p.join(sibling.path, 'secret.txt'),
        p.join(sibling.path, 'new-secret.txt'),
      ]) {
        final result = await fence.authorize(
          toolName: 'write_file',
          projectRoot: project.path,
          rawPath: rawPath,
        );
        expect(result.isAllowed, isFalse, reason: rawPath);
      }
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
      p.join(directoryLink.path, 'new-secret.txt'),
    ]) {
      final result = await fence.authorize(
        toolName: 'write_file',
        projectRoot: project.path,
        rawPath: rawPath,
      );
      expect(
        result.denial,
        ProjectMutationPathDenial.outsideProject,
        reason: rawPath,
      );
    }
  });
}
