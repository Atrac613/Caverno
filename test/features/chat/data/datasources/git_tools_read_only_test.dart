import 'package:caverno/features/chat/data/datasources/git_tools.dart';
import 'package:test/test.dart';

void main() {
  test('a trailing head or tail is stripped before classification', () {
    for (final command in [
      "tag --list '[0-9]*' --sort=-version:refname | head -3",
      'show --stat HEAD | tail -2',
      'branch -a | head -3',
      'log --oneline | head -n 5',
    ]) {
      expect(GitTools.isReadOnly(command), isTrue, reason: command);
    }
    for (final command in [
      'log --oneline | grep fix',
      'log --oneline | wc -l',
      'log --output=out.txt | head -3',
      'tag -a 1.0.0 -m release | head -1',
      'log --oneline | head -3 | tail -1',
    ]) {
      expect(GitTools.isReadOnly(command), isFalse, reason: command);
    }
  });

  test('ls-files accepts the long spellings of its vetted flags', () {
    // Session e3a9f3f0: a `/review` listed untracked files with the long
    // form, which went to auto-review and could not be re-run.
    for (final command in [
      'ls-files --others --exclude-standard',
      'ls-files --modified --deleted',
      'ls-files --cached --stage -z',
    ]) {
      expect(GitTools.isReadOnly(command), isTrue, reason: command);
    }
    expect(GitTools.isReadOnly('ls-files --others --made-up-flag'), isFalse);
  });

  test('unknown flags on conditional verbs require approval', () {
    for (final command in [
      'branch --made-up-flag',
      'tag --list --made-up-flag',
      'stash list --made-up-flag',
      'config --get user.name --made-up-flag',
      'remote show --made-up-flag origin',
      'symbolic-ref --made-up-flag HEAD',
      'reflog show --made-up-flag HEAD',
      'fsck --made-up-flag',
      'branch --list --edit-description feature/test',
      'tag --list --create-reflog',
      'stash show --output=out.txt',
      'config --get user.name --file=out.txt',
      'reflog show --output=out.txt',
    ]) {
      expect(GitTools.isReadOnly(command), isFalse, reason: command);
    }
  });

  test('conditional inspection keeps vetted shapes', () {
    for (final command in [
      'branch',
      'branch -a -vv',
      'branch --list "feature/*"',
      'tag --list --sort=-version:refname',
      'tag --points-at HEAD',
      'tag -n1 --list',
      'stash list --oneline',
      'stash show --stat stash@{0}',
      'config --get user.name',
      'config --get-regexp user.*',
      'config --list',
      'reflog show --all HEAD',
      'fsck --strict --no-lost-found',
    ]) {
      expect(GitTools.isReadOnly(command), isTrue, reason: command);
    }
  });

  group('GitTools.isReadOnly inspection option allowlist', () {
    test('keeps observed inspection shapes read-only', () {
      for (final command in [
        'log --oneline -20',
        'log --format=%h%x09%s -1',
        'log --pretty=oneline --decorate --stat --no-merges',
        'log --date=short --name-only --skip=2 --all --count',
        'log -n 5 -- lib/',
        'log -n5 --oneline',
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
        'log --format --made-up-flag',
        'log --pretty --made-up-flag',
        'log --date --made-up-flag',
        'show --format --made-up-flag',
        'for-each-ref --sort --made-up-flag',
        'log --skip=two',
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
