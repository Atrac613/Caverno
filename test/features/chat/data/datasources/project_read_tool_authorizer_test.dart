import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/project_read_path_fence.dart';
import 'package:caverno/features/chat/data/datasources/project_read_tool_authorizer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory project;
  late File outside;
  const authorizer = ProjectReadToolAuthorizer();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('project-read-authorizer-');
    project = await Directory(p.join(sandbox.path, 'project')).create();
    await File(p.join(project.path, 'inside.txt')).writeAsString('inside');
    outside = File(p.join(sandbox.path, 'outside.txt'));
    await outside.writeAsString('outside');
  });

  tearDown(() => sandbox.delete(recursive: true));

  Future<Map<String, dynamic>> deny({
    required String path,
    String? projectRoot,
  }) async {
    final authorization = await authorizer.authorize(
      toolName: 'inspect_file',
      arguments: {'path': path},
      projectRoot: projectRoot,
    );
    expect(authorization.isAllowed, isFalse);
    return jsonDecode(authorization.deniedResult!.result)
        as Map<String, dynamic>;
  }

  test(
    'an out-of-root read names the root and forecloses the tool hunt',
    () async {
      // Session 12b739d6: the model was told only "outside the authorized
      // project", so it ran four tool_search queries looking for a read tool
      // that could reach ~/.caverno. There is none, and the message now says so.
      final payload = await deny(path: outside.path, projectRoot: project.path);

      expect(payload['code'], 'project_read_outside_root');
      expect(payload['project_root'], isNotNull);
      expect(payload['error'], contains('do not search for one'));
      expect(payload['error'], contains('paste the contents'));
      expect(
        payload['error'],
        contains(await project.resolveSymbolicLinks()),
        reason: 'a boundary that is never named cannot be complied with',
      );
    },
  );

  test('a missing file is not reported as an authorization failure', () async {
    final payload = await deny(
      path: p.join(project.path, 'no-such-file.txt'),
      projectRoot: project.path,
    );

    expect(payload['code'], 'project_read_path_unavailable');
    expect(payload['error'], contains('does not exist'));
    expect(
      payload['error'],
      isNot(contains('outside')),
      reason: 'the old shared sentence blamed the project boundary for this',
    );
  });

  test('a missing project root says so instead of blaming the path', () async {
    final payload = await deny(path: outside.path, projectRoot: '');

    expect(payload['code'], 'project_read_root_required');
    expect(payload['error'], contains('No coding project is selected'));
    expect(payload['error'], isNot(contains('outside')));
  });

  test('a traversal path is told which form to retry with', () async {
    final payload = await deny(
      path: '~/secrets.txt',
      projectRoot: project.path,
    );

    expect(payload['code'], 'project_read_traversal_not_allowed');
    expect(payload['error'], contains('absolute path'));
    expect(payload['error'], contains(project.path));
  });

  test('every denial code produces a distinct message', () async {
    final messages = ProjectReadPathDenial.values
        .map((denial) => ProjectReadToolAuthorizer.denialMessage(denial, '/x'))
        .toSet();

    expect(
      messages.length,
      ProjectReadPathDenial.values.length,
      reason: 'one shared sentence for four causes misreports three of them',
    );
  });

  test('an approved canonical path is released, and only that path', () async {
    final canonicalOutside = await outside.resolveSymbolicLinks();
    final sibling = File(p.join(sandbox.path, 'other.txt'));
    await sibling.writeAsString('other');

    final granted = await authorizer.authorize(
      toolName: 'read_file',
      arguments: {'path': outside.path},
      projectRoot: project.path,
      approvedOutsideRootPaths: {canonicalOutside},
    );
    final neighbour = await authorizer.authorize(
      toolName: 'read_file',
      arguments: {'path': sibling.path},
      projectRoot: project.path,
      approvedOutsideRootPaths: {canonicalOutside},
    );

    expect(granted.isAllowed, isTrue);
    expect(granted.arguments!['path'], canonicalOutside);
    expect(
      neighbour.isAllowed,
      isFalse,
      reason: 'a grant is one file, not the directory it sits in',
    );
  });

  test('a grant is keyed on the resolved path, so a symlink cannot smuggle '
      'an unapproved target', () async {
    final secret = File(p.join(sandbox.path, 'secret.txt'));
    await secret.writeAsString('secret');
    final link = Link(p.join(sandbox.path, 'decoy.txt'));
    await link.create(secret.path);

    // The user approved the decoy's own name; the link resolves elsewhere.
    final authorization = await authorizer.authorize(
      toolName: 'read_file',
      arguments: {'path': link.path},
      projectRoot: project.path,
      approvedOutsideRootPaths: {link.path},
    );

    expect(authorization.isAllowed, isFalse);
    expect(authorization.canonicalPath, await secret.resolveSymbolicLinks());
  });

  test('only an out-of-root denial is approvable', () async {
    final outsideRoot = await authorizer.authorize(
      toolName: 'read_file',
      arguments: {'path': outside.path},
      projectRoot: project.path,
    );
    final missing = await authorizer.authorize(
      toolName: 'read_file',
      arguments: {'path': p.join(project.path, 'nope.txt')},
      projectRoot: project.path,
    );
    final traversal = await authorizer.authorize(
      toolName: 'read_file',
      arguments: const {'path': '~/secrets.txt'},
      projectRoot: project.path,
    );

    expect(outsideRoot.isApprovable, isTrue);
    expect(
      missing.isApprovable,
      isFalse,
      reason: 'a missing file is a mistake to fix, not a decision to take',
    );
    expect(traversal.isApprovable, isFalse);
  });

  test(
    'an authorized read still passes through with a canonical path',
    () async {
      final authorization = await authorizer.authorize(
        toolName: 'inspect_file',
        arguments: {'path': 'inside.txt'},
        projectRoot: project.path,
      );

      expect(authorization.isAllowed, isTrue);
      expect(authorization.arguments!['path'], endsWith('inside.txt'));
    },
  );
}
