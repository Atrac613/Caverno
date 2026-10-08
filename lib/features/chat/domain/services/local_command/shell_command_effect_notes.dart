/// Plain-language notes on what a native-shell command will do that the
/// command text alone does not show a reviewer.
///
/// SEC4.4g asks a person to approve every command that reaches `sh -c`, and
/// until now each of those prompts said the same thing: `grep` and
/// `bash -c '...'` read identically. A reviewer shown the same warning 255
/// times learns to stop reading it. These notes point at the parts of a
/// command whose effect is decided somewhere the reviewer cannot see: an
/// inline program, a script file, a redirect target, a run-time expansion.
///
/// Display only. The notes never decide anything and never reduce friction: a
/// command with no notes still needs the same approval, and the prompt never
/// calls it safe. A missed construct costs a missing hint, not a decision.
abstract final class ShellCommandEffectNotes {
  static const int _maxNotes = 5;

  static const Set<String> _shells = {'sh', 'bash', 'zsh', 'dash', 'fish'};
  static const Set<String> _inlineWithE = {'node', 'ruby', 'perl', 'osascript'};
  static const Set<String> _wrappers = {
    'env',
    'time',
    'nohup',
    'exec',
    'command',
    'xargs',
  };

  /// Notes for [command], most consequential first, at most five.
  static List<String> describe(String command) {
    final notes = <String>[];
    void add(String note) {
      if (!notes.contains(note)) notes.add(note);
    }

    final scan = _scan(command);
    if (scan.substitution) {
      add(
        'Expands shell variables or command output when it runs, so the '
        'final arguments are not all visible here.',
      );
    }
    for (final target in scan.redirectTargets) {
      add('Writes output to `$target`.');
    }
    if (scan.hereDocument) {
      add('Feeds an inline here-document to a command.');
    }
    for (final segment in scan.segments) {
      final note = _segmentNote(segment.words, pipedInto: segment.pipedInto);
      if (note != null) add(note);
    }
    return notes.length > _maxNotes ? notes.sublist(0, _maxNotes) : notes;
  }

  static String? _segmentNote(List<String> words, {required bool pipedInto}) {
    var index = 0;
    var elevated = false;
    while (index < words.length) {
      final word = words[index];
      if (_isAssignment(word) || _wrappers.contains(word)) {
        index += 1;
      } else if (word == 'sudo' || word == 'doas') {
        elevated = true;
        index += 1;
      } else {
        break;
      }
    }
    if (elevated) return 'Asks for elevated (root) privileges.';
    if (index >= words.length) return null;

    final executable = words[index];
    final name = executable.split('/').last;
    final args = words.sublist(index + 1);
    final isShell = _shells.contains(name);
    final isPython = RegExp(r'^python(\d+(\.\d+)?)?$').hasMatch(name);

    if (isShell || isPython || _inlineWithE.contains(name)) {
      final inlineFlag = isShell || isPython ? '-c' : '-e';
      if (args.contains(inlineFlag) ||
          (isShell && args.any((a) => RegExp(r'^-[a-z]*c$').hasMatch(a)))) {
        return 'Runs an inline `$name` program; what it reads or writes is '
            'decided by that program.';
      }
      if (isPython && args.length >= 2 && args.first == '-m') {
        return 'Runs the Python module `${args[1]}`.';
      }
      if (pipedInto || args.isEmpty || args.contains('-')) {
        return 'Runs `$name` on program text fed through its input.';
      }
      // `bash -n` only parses the script.
      if (isShell && args.contains('-n')) return null;
      final script = args.firstWhere(
        (a) => !a.startsWith('-'),
        orElse: () => '',
      );
      if (script.isNotEmpty) {
        return 'Runs the script `$script`; its contents are not shown here.';
      }
      return null;
    }
    if (executable.contains('/')) {
      return 'Runs the program `$executable`; its contents are not shown '
          'here.';
    }
    return null;
  }

  static bool _isAssignment(String word) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=').hasMatch(word);

  /// One pass over [command] that honours quoting and collects the pieces
  /// the notes are built from.
  static _Scan _scan(String command) {
    final segments = <_Segment>[];
    final redirectTargets = <String>[];
    var substitution = false;
    var hereDocument = false;

    var words = <String>[];
    final word = StringBuffer();
    var wordStarted = false;
    var pipedInto = false;
    String? pendingRedirect;
    String? hereDelimiter;
    String? quote;

    void endWord() {
      if (!wordStarted) return;
      final text = word.toString();
      word.clear();
      wordStarted = false;
      switch (pendingRedirect) {
        case null:
          words.add(text);
        case '>':
          if (text != '/dev/null') redirectTargets.add(text);
        case '<<':
          hereDelimiter = text;
      }
      pendingRedirect = null;
    }

    void endSegment({required bool nextPipedInto}) {
      endWord();
      if (words.isNotEmpty) {
        segments.add(_Segment(words, pipedInto: pipedInto));
      }
      words = <String>[];
      pipedInto = nextPipedInto;
    }

    for (var index = 0; index < command.length; index++) {
      final char = command[index];
      final next = index + 1 < command.length ? command[index + 1] : '';

      if (quote == "'") {
        if (char == "'") {
          quote = null;
        } else {
          word.write(char);
        }
        continue;
      }
      if (quote == '"') {
        if (char == '"') {
          quote = null;
        } else {
          if (char == r'$' || char == '`') substitution = true;
          if (char == r'\' && next.isNotEmpty) {
            word.write(next);
            index += 1;
          } else {
            word.write(char);
          }
        }
        continue;
      }

      switch (char) {
        case "'" || '"':
          quote = char;
          wordStarted = true;
        case r'\':
          if (next.isNotEmpty) {
            word.write(next);
            wordStarted = true;
            index += 1;
          }
        case ' ' || '\t':
          endWord();
        case '\n':
          endSegment(nextPipedInto: false);
          final delimiter = hereDelimiter;
          if (delimiter != null) {
            // Skip the here-document body: it is program text, not commands.
            hereDelimiter = null;
            var end = command.indexOf('\n', index + 1);
            while (end >= 0 &&
                command.substring(index + 1, end).trim() != delimiter) {
              index = end;
              end = command.indexOf('\n', index + 1);
            }
            index = end < 0 ? command.length : end;
          }
        case ';':
          endSegment(nextPipedInto: false);
        case '&':
          if (next == '>') {
            // `&>` and `&>>` redirect both streams to one file.
            endWord();
            pendingRedirect = '>';
            index += 1;
            if (index + 1 < command.length && command[index + 1] == '>') {
              index += 1;
            }
          } else {
            if (next == '&') index += 1;
            endSegment(nextPipedInto: false);
          }
        case '|':
          if (next == '|') {
            index += 1;
            endSegment(nextPipedInto: false);
          } else {
            endSegment(nextPipedInto: true);
          }
        case '>':
          // A digit directly before `>` names a stream, not a word.
          if (wordStarted && RegExp(r'^\d+$').hasMatch(word.toString())) {
            word.clear();
            wordStarted = false;
          } else {
            endWord();
          }
          if (next == '>') index += 1;
          if (index + 1 < command.length && command[index + 1] == '&') {
            // `2>&1` duplicates a stream; there is no target file.
            index += 1;
            while (index + 1 < command.length &&
                RegExp(r'[0-9-]').hasMatch(command[index + 1])) {
              index += 1;
            }
          } else {
            pendingRedirect = '>';
          }
        case '<':
          endWord();
          if (next == '<') {
            hereDocument = true;
            index += 1;
            if (index + 1 < command.length && command[index + 1] == '<') {
              // A `<<<` here-string carries no body to skip.
              index += 1;
              pendingRedirect = '<';
            } else {
              if (index + 1 < command.length && command[index + 1] == '-') {
                index += 1;
              }
              pendingRedirect = '<<';
            }
          } else {
            pendingRedirect = '<';
          }
        case r'$' || '`':
          substitution = true;
          word.write(char);
          wordStarted = true;
        default:
          word.write(char);
          wordStarted = true;
      }
    }
    endSegment(nextPipedInto: false);

    return _Scan(
      segments: segments,
      redirectTargets: redirectTargets,
      substitution: substitution,
      hereDocument: hereDocument,
    );
  }
}

final class _Segment {
  const _Segment(this.words, {required this.pipedInto});

  final List<String> words;
  final bool pipedInto;
}

final class _Scan {
  const _Scan({
    required this.segments,
    required this.redirectTargets,
    required this.substitution,
    required this.hereDocument,
  });

  final List<_Segment> segments;
  final List<String> redirectTargets;
  final bool substitution;
  final bool hereDocument;
}
