import 'package:caverno/features/chat/data/datasources/git_command_path_escape_guard.dart';
import 'package:caverno/features/chat/data/datasources/git_tools.dart';
import 'package:test/test.dart';

void main() {
  group('GitCommandPathEscapeGuard.relocationDenial', () {
    test('rejects relocating globals before the subcommand', () {
      expect(
        GitCommandPathEscapeGuard.relocationDenial(['-C', '/tmp', 'status']),
        '-C',
      );
      expect(
        GitCommandPathEscapeGuard.relocationDenial([
          '--git-dir',
          '/tmp/evil.git',
          'status',
        ]),
        '--git-dir',
      );
      expect(
        GitCommandPathEscapeGuard.relocationDenial([
          '--work-tree=/tmp/tree',
          'status',
        ]),
        '--work-tree',
      );
    });

    test('allows grep -C as a subcommand option', () {
      expect(
        GitCommandPathEscapeGuard.relocationDenial([
          'grep',
          '-C',
          '3',
          'pattern',
        ]),
        isNull,
      );
    });

    test('skips -c values before the subcommand', () {
      expect(
        GitCommandPathEscapeGuard.relocationDenial([
          '-c',
          'user.email=canary@example.com',
          'status',
        ]),
        isNull,
      );
      expect(
        GitCommandPathEscapeGuard.relocationDenial([
          '-c',
          'user.email=canary@example.com',
          '-C',
          '/tmp',
          'status',
        ]),
        '-C',
      );
    });
  });

  group('GitCommandPathEscapeGuard.pathspecCandidates', () {
    test('collects pathspecs after -- and escaping positionals', () {
      expect(
        GitCommandPathEscapeGuard.pathspecCandidates([
          'checkout',
          'HEAD',
          '--',
          '/etc/passwd',
        ]),
        ['/etc/passwd'],
      );
      expect(
        GitCommandPathEscapeGuard.pathspecCandidates([
          'add',
          '../sibling/secret',
        ]),
        ['../sibling/secret'],
      );
      expect(GitCommandPathEscapeGuard.pathspecCandidates(['add', '~']), ['~']);
    });

    test('does not treat branch names or in-root relatives as escapes', () {
      expect(
        GitCommandPathEscapeGuard.pathspecCandidates([
          'checkout',
          '-b',
          'feature/foo',
        ]),
        isEmpty,
      );
      expect(
        GitCommandPathEscapeGuard.pathspecCandidates(['add', 'lib/foo.dart']),
        isEmpty,
      );
    });
  });

  test('strips relocation variables from the git environment', () {
    final sanitized = GitCommandPathEscapeGuard.sanitizedEnvironment({
      'PATH': '/usr/bin',
      'GIT_DIR': '/tmp/evil.git',
      'GIT_WORK_TREE': '/tmp/tree',
      'HOME': '/home/user',
    });

    expect(sanitized, {'PATH': '/usr/bin', 'HOME': '/home/user'});
  });

  test('splitArgs keeps relocating globals intact for the guard', () {
    expect(GitTools.splitArgs('-C /tmp status'), ['-C', '/tmp', 'status']);
    expect(GitTools.splitArgs('--git-dir=/tmp/x.git status'), [
      '--git-dir=/tmp/x.git',
      'status',
    ]);
  });
}
