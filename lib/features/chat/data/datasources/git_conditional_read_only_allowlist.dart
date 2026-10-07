/// Exact read-only shapes for git verbs that also have mutating forms.
class GitConditionalReadOnlyAllowlist {
  GitConditionalReadOnlyAllowlist._();

  static final RegExp _tagAnnotationLines = RegExp(r'^-n[0-9]*$');

  static bool branch(List<String> args) {
    final parsed = _scan(
      args.skip(1),
      flags: const {
        '-a',
        '--all',
        '-r',
        '--remotes',
        '-v',
        '-vv',
        '--verbose',
        '-l',
        '--list',
        '--show-current',
        '--ignore-case',
        '-i',
      },
      attachedValues: const {'--sort', '--format'},
      optionalValues: const {
        '--contains',
        '--no-contains',
        '--merged',
        '--no-merged',
        '--points-at',
      },
    );
    if (parsed == null) return false;
    if (parsed.positionals.isEmpty) return true;
    return parsed.flags.contains('-l') || parsed.flags.contains('--list');
  }

  static bool tag(List<String> args) {
    final parsed = _scan(
      args.skip(1),
      flags: const {'-l', '--list', '--ignore-case', '-i', '--no-column'},
      attachedValues: const {'--list', '--sort', '--format'},
      optionalValues: const {
        '--contains',
        '--no-contains',
        '--points-at',
        '--merged',
        '--no-merged',
      },
      tagAnnotationLines: true,
    );
    if (parsed == null) return false;
    if (parsed.positionals.isEmpty) return true;
    return parsed.flags.any(
      const {
        '-l',
        '--list',
        '-n',
        '--contains',
        '--no-contains',
        '--points-at',
        '--merged',
        '--no-merged',
      }.contains,
    );
  }

  static bool stash(List<String> args) {
    if (args.length < 2) return false;
    final action = args[1];
    final parsed = switch (action) {
      'list' => _scan(
        args.skip(2),
        flags: const {'--oneline', '--all'},
        attachedValues: const {'--format', '--pretty'},
      ),
      'show' => _scan(
        args.skip(2),
        flags: const {
          '--stat',
          '--oneline',
          '-p',
          '--patch',
          '--no-color',
          '--include-untracked',
        },
      ),
      _ => null,
    };
    if (parsed == null) return false;
    return action == 'list'
        ? parsed.positionals.isEmpty
        : parsed.positionals.length <= 1;
  }

  static bool config(List<String> args) {
    final parsed = _scan(
      args.skip(1),
      flags: const {
        '--get',
        '--get-all',
        '--get-regexp',
        '--list',
        '-l',
        '--get-urlmatch',
        '--name-only',
        '--null',
        '-z',
      },
    );
    if (parsed == null) return false;
    const modes = {
      '--get',
      '--get-all',
      '--get-regexp',
      '--list',
      '-l',
      '--get-urlmatch',
    };
    final selected = parsed.flags.intersection(modes);
    if (selected.length > 1) return false;
    if (selected.contains('--list') || selected.contains('-l')) {
      return parsed.positionals.isEmpty;
    }
    if (selected.contains('--get-urlmatch')) {
      return parsed.positionals.length == 2;
    }
    return parsed.positionals.length == 1;
  }

  static bool reflog(List<String> args) {
    if (args.length == 1) return true;
    final action = args[1];
    if (!const {'show', 'list', 'exists'}.contains(action)) return false;
    final parsed = _scan(
      args.skip(2),
      flags: action == 'show'
          ? const {'--all', '--oneline', '--no-abbrev'}
          : const <String>{},
      attachedValues: action == 'show' ? const {'--date'} : const <String>{},
    );
    if (parsed == null) return false;
    return switch (action) {
      'show' => parsed.positionals.length <= 1,
      'list' => parsed.positionals.isEmpty,
      _ => parsed.positionals.length == 1,
    };
  }

  static bool fsck(List<String> args) =>
      _scan(
        args.skip(1),
        flags: const {
          '--strict',
          '--no-lost-found',
          '--full',
          '--no-full',
          '--connectivity-only',
          '--no-reflogs',
          '--unreachable',
          '--dangling',
          '--root',
          '--tags',
          '--no-progress',
        },
      ) !=
      null;

  static _Parsed? _scan(
    Iterable<String> args, {
    required Set<String> flags,
    Set<String> attachedValues = const {},
    Set<String> optionalValues = const {},
    bool tagAnnotationLines = false,
  }) {
    final tokens = args.toList();
    final seen = <String>{};
    final positionals = <String>[];
    var optionsEnded = false;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (!optionsEnded && token == '--') {
        optionsEnded = true;
        continue;
      }
      if (optionsEnded || !token.startsWith('-')) {
        positionals.add(token);
        continue;
      }
      if (tagAnnotationLines && _tagAnnotationLines.hasMatch(token)) {
        seen.add('-n');
        continue;
      }
      if (flags.contains(token)) {
        seen.add(token);
        continue;
      }
      final equals = token.indexOf('=');
      final name = equals < 0 ? token : token.substring(0, equals);
      if (equals >= 0 &&
          (attachedValues.contains(name) || optionalValues.contains(name)) &&
          token.substring(equals + 1).isNotEmpty) {
        seen.add(name);
        continue;
      }
      if (equals < 0 && optionalValues.contains(name)) {
        seen.add(name);
        // These options accept a detached ref. Never consume another option.
        if (i + 1 < tokens.length &&
            tokens[i + 1].isNotEmpty &&
            !tokens[i + 1].startsWith('-')) {
          i += 1;
        }
        continue;
      }
      return null;
    }
    return _Parsed(seen, positionals);
  }
}

class _Parsed {
  const _Parsed(this.flags, this.positionals);
  final Set<String> flags;
  final List<String> positionals;
}
