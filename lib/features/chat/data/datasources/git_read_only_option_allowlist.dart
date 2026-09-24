/// Safe option shapes for git inspection commands that bypass approval.
class GitReadOnlyOptionAllowlist {
  GitReadOnlyOptionAllowlist._();

  // Only options with no path, command, helper, or output destination belong
  // here. Unknown options take the normal approval path.
  static const Map<String, Set<String>> _readOnlyFlags = {
    'status': {'--short', '-s', '--branch', '-b', '--porcelain', '-z'},
    'log': {
      '--oneline',
      '--decorate',
      '--stat',
      '--no-merges',
      '--name-only',
      '--name-status',
      '--shortstat',
      '--numstat',
      '--all',
      '--count',
      '--graph',
      '--reverse',
      '--first-parent',
      '--abbrev-commit',
      '--no-color',
      '-p',
      '--patch',
    },
    'diff': {
      '--stat',
      '--cached',
      '--staged',
      '--check',
      '--name-only',
      '--name-status',
      '--shortstat',
      '--numstat',
      '--no-color',
      '-p',
      '--patch',
      '-z',
    },
    'show': {
      '--stat',
      '--oneline',
      '-s',
      '--name-only',
      '--name-status',
      '--shortstat',
      '--numstat',
      '--no-color',
      '-p',
      '--patch',
    },
    'blame': {'--porcelain', '--line-porcelain', '-w'},
    'rev-parse': {
      '--show-toplevel',
      '--is-inside-work-tree',
      '--short',
      '--abbrev-ref',
      '--verify',
      '--symbolic',
      '--git-dir',
      '--show-prefix',
    },
    'describe': {'--tags', '--always', '--dirty', '--long', '--exact-match'},
    'shortlog': {'-s', '-n', '-e', '--summary', '--numbered', '--email'},
    'ls-files': {'-m', '-o', '-c', '-d', '-s', '-z', '--exclude-standard'},
    'ls-tree': {'-r', '-t', '-d', '-l', '--name-only', '--name-status', '-z'},
    'cat-file': {'-t', '-s', '-e', '-p'},
    'for-each-ref': {'--ignore-case'},
    'name-rev': {'--tags', '--all', '--always', '--no-undefined'},
    'rev-list': {'--count', '--all', '--first-parent', '--reverse'},
    'show-ref': {'--head', '--tags', '--heads', '--verify', '--quiet'},
    'count-objects': {'-v', '--verbose', '-H', '--human-readable'},
    'verify-pack': {'-v', '--verbose', '-s', '--stat-only'},
    'diff-tree': {'--stat', '--name-only', '--name-status', '-p', '-z', '-r'},
    'diff-files': {'--stat', '--name-only', '--name-status', '-p', '-z'},
    'diff-index': {
      '--stat',
      '--name-only',
      '--name-status',
      '-p',
      '-z',
      '--cached',
    },
  };

  static const Map<String, Set<String>> _readOnlyValueFlags = {
    'log': {
      '--format',
      '--pretty',
      '--date',
      '--skip',
      '--max-count',
      '--since',
      '--until',
      '--author',
      '--grep',
      '-n',
    },
    'show': {'--format', '--pretty'},
    'for-each-ref': {'--format', '--sort', '--count'},
    'rev-list': {'--max-count', '--skip'},
  };

  static bool accepts(String subcommand, List<String> args) {
    final flags = _readOnlyFlags[subcommand]!;
    final valueFlags = _readOnlyValueFlags[subcommand] ?? const <String>{};
    for (var i = 1; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--') return true; // Remaining tokens are fenced pathspecs.
      if (!arg.startsWith('-')) continue; // Revision, range, or path.
      if (subcommand == 'log' && RegExp(r'^-[0-9]+$').hasMatch(arg)) continue;
      if (flags.contains(arg)) continue;

      final equals = arg.indexOf('=');
      final option = equals < 0 ? arg : arg.substring(0, equals);
      if (!valueFlags.contains(option)) return false;
      final value = equals < 0
          ? (i + 1 < args.length ? args[++i] : '')
          : arg.substring(equals + 1);
      if (value.isEmpty) return false;
      if ({'-n', '--skip', '--max-count', '--count'}.contains(option) &&
          !RegExp(r'^[0-9]+$').hasMatch(value)) {
        return false;
      }
    }
    return true;
  }
}
