import 'package:caverno/features/chat/data/datasources/git_tools.dart';
import 'package:test/test.dart';

void main() {
  group('GitTools.isReadOnly inspection option allowlist', () {
    test('keeps observed inspection shapes read-only', () {
      for (final command in [
        'log --oneline -20',
        'log --format=%h%x09%s -1',
        'log --pretty=oneline --decorate --stat --no-merges',
        'log --date=short --name-only --skip=2 --all --count',
        'log -n 5 -- lib/',
        'show --stat --oneline HEAD',
        'show -s --format=%h HEAD',
        'diff --cached --stat',
        'diff --check',
        'status --short --branch',
        'cat-file -t HEAD',
        'rev-list --count A..B',
      ]) {
        expect(GitTools.isReadOnly(command), isTrue, reason: command);
      }
    });

    test('routes unvetted options and remote access through approval', () {
      for (final command in [
        'log --output=out.txt',
        'diff --output=out.txt',
        'show --output=out.txt',
        'log --ext-diff',
        'log --made-up-flag',
        'log -sp',
        'log -n',
        'log -n --output=out.txt',
        'ls-remote origin',
        'ls-remote --upload-pack=helper .',
      ]) {
        expect(GitTools.isReadOnly(command), isFalse, reason: command);
      }
    });

    test('treats tokens after the pathspec separator as operands', () {
      expect(GitTools.isReadOnly('log -- --output=out.txt'), isTrue);
    });
  });

  group('GitTools.isReadOnly remote classification', () {
    test('allows explicit inspection forms', () {
      expect(GitTools.isReadOnly('remote'), isTrue);
      expect(GitTools.isReadOnly('remote --verbose'), isTrue);
      expect(GitTools.isReadOnly('remote show origin'), isTrue);
      expect(GitTools.isReadOnly('remote -v show -n origin'), isTrue);
      expect(GitTools.isReadOnly('remote get-url --all origin'), isTrue);
      expect(GitTools.isReadOnly('remote prune --dry-run origin'), isTrue);
    });

    test('rejects repository-mutating forms', () {
      expect(
        GitTools.isReadOnly('remote add origin https://example.com/repo.git'),
        isFalse,
      );
      expect(GitTools.isReadOnly('remote rename origin upstream'), isFalse);
      expect(GitTools.isReadOnly('remote remove origin'), isFalse);
      expect(GitTools.isReadOnly('remote rm origin'), isFalse);
      expect(GitTools.isReadOnly('remote set-head origin --auto'), isFalse);
      expect(GitTools.isReadOnly('remote set-branches origin main'), isFalse);
      expect(
        GitTools.isReadOnly(
          'remote set-url origin https://example.com/repo.git',
        ),
        isFalse,
      );
      expect(GitTools.isReadOnly('remote prune origin'), isFalse);
      expect(GitTools.isReadOnly('remote update'), isFalse);
    });
  });

  group('GitTools.isReadOnly symbolic-ref classification', () {
    test('allows one-ref inspection forms', () {
      expect(GitTools.isReadOnly('symbolic-ref HEAD'), isTrue);
      expect(GitTools.isReadOnly('symbolic-ref --short HEAD'), isTrue);
      expect(GitTools.isReadOnly('symbolic-ref -q --no-recurse HEAD'), isTrue);
    });

    test('rejects update and delete forms', () {
      expect(GitTools.isReadOnly('symbolic-ref HEAD refs/heads/main'), isFalse);
      expect(
        GitTools.isReadOnly('symbolic-ref -m reason HEAD refs/heads/main'),
        isFalse,
      );
      expect(GitTools.isReadOnly('symbolic-ref --delete HEAD'), isFalse);
      expect(GitTools.isReadOnly('symbolic-ref -d HEAD'), isFalse);
    });
  });

  group('GitTools.isReadOnly reflog classification', () {
    test('allows reflog inspection forms', () {
      expect(GitTools.isReadOnly('reflog'), isTrue);
      expect(GitTools.isReadOnly('reflog show HEAD'), isTrue);
      expect(GitTools.isReadOnly('reflog list'), isTrue);
      expect(GitTools.isReadOnly('reflog exists HEAD'), isTrue);
    });

    test('rejects reflog maintenance forms', () {
      expect(GitTools.isReadOnly('reflog expire --all'), isFalse);
      expect(GitTools.isReadOnly('reflog delete HEAD@{0}'), isFalse);
      expect(GitTools.isReadOnly('reflog drop --all'), isFalse);
      expect(
        GitTools.isReadOnly('reflog write HEAD deadbeef message'),
        isFalse,
      );
    });
  });

  group('GitTools.isReadOnly fsck classification', () {
    test('allows non-writing verification forms', () {
      expect(GitTools.isReadOnly('fsck --strict'), isTrue);
      expect(GitTools.isReadOnly('fsck --no-lost-found --full'), isTrue);
    });

    test('rejects lost-found writes and option abbreviations', () {
      expect(GitTools.isReadOnly('fsck --lost-found'), isFalse);
      expect(GitTools.isReadOnly('fsck --lost-f'), isFalse);
      expect(GitTools.isReadOnly('fsck --lo'), isFalse);
    });
  });

  group('GitTools.isReadOnly stash classification', () {
    test('allows list and show only', () {
      expect(GitTools.isReadOnly('stash list'), isTrue);
      expect(GitTools.isReadOnly('stash show stash@{0}'), isTrue);
    });

    test('rejects bare and mutating forms', () {
      expect(GitTools.isReadOnly('stash'), isFalse);
      expect(GitTools.isReadOnly('stash push'), isFalse);
      expect(GitTools.isReadOnly('stash save checkpoint'), isFalse);
      expect(GitTools.isReadOnly('stash -u'), isFalse);
      expect(GitTools.isReadOnly('stash pop'), isFalse);
      expect(GitTools.isReadOnly('stash apply'), isFalse);
      expect(GitTools.isReadOnly('stash drop'), isFalse);
      expect(GitTools.isReadOnly('stash clear'), isFalse);
      expect(GitTools.isReadOnly('stash create checkpoint'), isFalse);
      expect(GitTools.isReadOnly('stash branch recovery'), isFalse);
      expect(GitTools.isReadOnly('stash store deadbeef'), isFalse);
    });
  });
}
