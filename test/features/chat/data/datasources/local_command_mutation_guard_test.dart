import 'dart:io';

import 'package:caverno/features/chat/data/datasources/local_command_mutation_guard.dart';
import 'package:caverno/features/chat/data/datasources/turn_project_root.dart';
import 'package:test/test.dart';

void main() {
  group('LocalCommandMutationGuard.writePathCandidates', () {
    test('collects escaping operands and skips the executable', () {
      expect(
        LocalCommandMutationGuard.writePathCandidates(
          'touch ../sibling/secret',
        ),
        ['../sibling/secret'],
      );
      expect(
        LocalCommandMutationGuard.writePathCandidates('touch /tmp/secret'),
        ['/tmp/secret'],
      );
      expect(
        LocalCommandMutationGuard.writePathCandidates('touch output.txt'),
        isEmpty,
      );
      expect(
        LocalCommandMutationGuard.writePathCandidates(
          '/usr/bin/python3 script.py',
        ),
        isEmpty,
      );
      expect(
        LocalCommandMutationGuard.writePathCandidates(
          "/usr/bin/python3 -c \"open('/tmp/secret', 'w')\"",
        ),
        ['/tmp/secret'],
      );
    });

    test('ignores a heredoc body written into an in-root file', () {
      // Session a0ca65b7 wrote JavaScript this way and the body's `//`
      // comment markers were read as absolute paths, so an in-root write was
      // denied with `path: "//"`.
      const command =
          "cat > js/cave.js << 'CAVE_EOF'\n"
          '// Procedural cave geometry generator.\n'
          '/** doc */\n'
          'function noise(seed) { return seed >>> 0; }\n'
          '// see ../sibling for the older version\n'
          'CAVE_EOF';
      expect(LocalCommandMutationGuard.writePathCandidates(command), isEmpty);
    });

    test('keeps collecting operands after a heredoc closes', () {
      const command =
          "cat > notes.txt << 'EOF'\n"
          '// body\n'
          'EOF\n'
          'touch /tmp/secret';
      expect(LocalCommandMutationGuard.writePathCandidates(command), [
        '/tmp/secret',
      ]);
    });

    test('still sees an outside path a heredoc body names', () {
      const command =
          "python3 << 'EOF'\n"
          "open('/tmp/secret', 'w')\n"
          'EOF';
      expect(LocalCommandMutationGuard.writePathCandidates(command), [
        '/tmp/secret',
      ]);
    });

    test('treats a quoted `<<` as text rather than a heredoc', () {
      const command =
          'echo "a << EOF"\n'
          'touch /tmp/secret';
      expect(LocalCommandMutationGuard.writePathCandidates(command), [
        '/tmp/secret',
      ]);
    });

    test('collects a write after a command separator', () {
      expect(
        LocalCommandMutationGuard.writePathCandidates(
          'echo ok && touch ../outside',
        ),
        ['../outside'],
      );
    });
  });

  group('LocalCommandMutationGuard.authorizedProjectRoot', () {
    test('prefers an explicit root over the turn scope', () {
      expect(
        TurnProjectRoot.runScoped(
          const TurnProjectRoot('/turn/root'),
          () => LocalCommandMutationGuard.authorizedProjectRoot('/explicit'),
        ),
        '/explicit',
      );
    });

    test('uses the turn-scoped root when the explicit root is empty', () {
      expect(
        TurnProjectRoot.runScoped(
          const TurnProjectRoot('/turn/root'),
          () => LocalCommandMutationGuard.authorizedProjectRoot(''),
        ),
        '/turn/root',
      );
    });

    test('returns null when no project is selected', () {
      expect(LocalCommandMutationGuard.authorizedProjectRoot(null), isNull);
      expect(LocalCommandMutationGuard.authorizedProjectRoot('  '), isNull);
    });
  });

  group('LocalCommandMutationGuard.authorizeWorkingDirectory', () {
    late Directory sandbox;
    late Directory project;
    late Directory sibling;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp(
        'local_command_mutation_cwd_',
      );
      project = await Directory('${sandbox.path}/project').create();
      sibling = await Directory('${sandbox.path}/project-secrets').create();
    });

    tearDown(() async {
      if (sandbox.existsSync()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('allows an in-root working directory', () async {
      final auth = await LocalCommandMutationGuard.authorizeWorkingDirectory(
        toolName: 'local_execute_command',
        projectRoot: project.path,
        workingDirectory: project.path,
      );
      expect(auth.isAllowed, isTrue);
      expect(auth.canonicalPath, isNotNull);
    });

    test('rejects a sibling working directory', () async {
      final auth = await LocalCommandMutationGuard.authorizeWorkingDirectory(
        toolName: 'local_execute_command',
        projectRoot: project.path,
        workingDirectory: sibling.path,
      );
      expect(auth.isAllowed, isFalse);
      expect(auth.denial?.code, 'project_mutation_outside_root');
    });

    test('rejects a symlink working directory that escapes the root', () async {
      final link = Link('${project.path}/escape');
      try {
        await link.create(sibling.path);
      } on FileSystemException {
        return;
      }
      final auth = await LocalCommandMutationGuard.authorizeWorkingDirectory(
        toolName: 'local_execute_command',
        projectRoot: project.path,
        workingDirectory: link.path,
      );
      expect(auth.isAllowed, isFalse);
      expect(auth.denial?.code, 'project_mutation_outside_root');
    });
  });

  group('LocalCommandMutationGuard.authorizeWritePaths', () {
    late Directory sandbox;
    late Directory project;
    late Directory sibling;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp(
        'local_command_mutation_argv_',
      );
      project = await Directory('${sandbox.path}/project').create();
      sibling = await Directory('${sandbox.path}/project-secrets').create();
      await File('${sibling.path}/secret.txt').writeAsString('secret\n');
    });

    tearDown(() async {
      if (sandbox.existsSync()) {
        await sandbox.delete(recursive: true);
      }
    });

    test('allows an in-root relative write', () async {
      final auth = await LocalCommandMutationGuard.authorizeWritePaths(
        toolName: 'local_execute_command',
        projectRoot: project.path,
        command: 'touch output.txt',
        workingDirectory: project.path,
      );
      expect(auth, isNull);
    });

    test('rejects a parent-relative write that leaves the project', () async {
      final auth = await LocalCommandMutationGuard.authorizeWritePaths(
        toolName: 'local_execute_command',
        projectRoot: project.path,
        command: 'touch ../project-secrets/secret.txt',
        workingDirectory: project.path,
      );
      expect(auth?.isAllowed, isFalse);
      expect(auth?.denial?.code, 'project_mutation_outside_root');
    });

    test('resolves relatives against cwd, not the project root', () async {
      final nested = await Directory('${project.path}/lib').create();
      final auth = await LocalCommandMutationGuard.authorizeWritePaths(
        toolName: 'local_execute_command',
        projectRoot: project.path,
        command: 'touch ../output.txt',
        workingDirectory: nested.path,
      );
      expect(auth, isNull);
    });
  });
}
