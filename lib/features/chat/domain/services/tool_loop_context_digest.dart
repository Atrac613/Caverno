import 'dart:convert';

import '../entities/tool_call_info.dart';

/// Builds a compact "already gathered this turn" digest from the tool results
/// accumulated so far in a tool-calling loop.
///
/// The digest is injected into the follow-up request so the model does not
/// re-issue read-only inspections it already made. Re-reading an unchanged file
/// wastes a full round-trip and, after a recovery re-entry, the per-call dedup
/// memory is reset — so without this reminder the model tends to re-list the
/// same directories and re-read the same files it inspected earlier in the turn.
///
/// The digest is also content-aware: when the same inspection was repeated and
/// every repeat saw the same content, the line is flagged as `unchanged`. This
/// targets the non-converging edit→run→re-read debug loop (session 119292cb:
/// 11x identical full-file reads while no-op edits left the file untouched) —
/// the generic "unless a file was modified since" advisory is too weak there
/// because the model believes its edits changed the file.
///
/// "Same content" prefers the read's whole-file hash (`ToolOutcome.contentHash`)
/// and falls back to byte-identity of the rendered result. The hash matters
/// because the label for a read is the path alone, so reading one file through
/// two different paging windows lands on one label with two different bodies:
/// byte-identity calls that a change and says nothing, while the hash states
/// correctly that the file never moved.
class ToolLoopContextDigest {
  const ToolLoopContextDigest();

  /// Tools whose prior invocation is worth reminding the model about: stable
  /// read-only inspections. Volatile inspectors (`process_*`) are intentionally
  /// excluded because their output legitimately changes between identical calls.
  static const Set<String> _digestableTools = <String>{
    'list_directory',
    'read_file',
    'inspect_file',
    'find_files',
    'search_files',
  };

  /// Command tools, digested separately from file inspections.
  ///
  /// A turn spent investigating through the shell (`gh`, `git log`, a build)
  /// was invisible here until these were added, because the follow-up request
  /// carries only the *current* batch's results: at loop 10 the model could no
  /// longer see what a command returned at loop 3, so it re-issued it. Session
  /// 655e367f re-ran two `gh run view` calls and four `gh pr view` calls that
  /// way, 27 executions for 18 distinct calls, while the CI root cause sat in
  /// the loop-3 output.
  ///
  /// Commands are never flagged `unchanged`: that claim is about file content
  /// and says nothing about a command whose output depends on the world. These
  /// lines report history, they never forbid a re-run — a verification command
  /// must stay repeatable after an edit.
  ///
  /// The wording must not imply the earlier output is still readable, because
  /// it is not: only the current batch's results reach the model, which is the
  /// very gap this digest exists to name. Telling the model to "use what they
  /// returned" would invite it to answer from output it cannot see.
  ///
  /// The exit status is the exception, and it is reported. "Ran it" without
  /// "it worked" is what drives a *post-success task restart*: in session
  /// 0e94a103 `fvm use 3.47.1` succeeded at loop 2, and four loops later the
  /// model — seeing only that the command had run — planned the same update
  /// again from scratch and killed the turn on a repeated read, while the user
  /// was told the turn had aborted and never that the update had landed. An
  /// exit status is a fact about the run rather than its output, it comes from
  /// [ToolOutcome.exitCode] rather than from any phrase in the text, and it is
  /// the one fact that settles whether the work still needs doing.
  static const Set<String> _digestableCommandTools = <String>{
    'local_execute_command',
    'git_execute_command',
  };

  /// Longest command echoed into a digest line.
  static const int _maxCommandLabelChars = 120;

  /// Returns a short markdown block listing the read-only context already
  /// gathered this turn, or an empty string when there is nothing worth
  /// repeating (fewer than [minEntries] distinct reads).
  ///
  /// When more than [maxEntries] distinct inspections have accumulated the list
  /// is trimmed to a budget, but it keeps the entries that matter: every
  /// repeated inspection (the redundancy we most want to suppress) plus the
  /// *most-recently* inspected files. A large-codebase review can exceed the
  /// budget mid-turn, and the model re-reads the files it touched most recently
  /// far more often than the ones at the top of the list — so truncating the
  /// tail (the old head-only cap) dropped exactly the entries worth reminding
  /// about (session b73801da: 3 files at first-seen indices 15/18/19 fell off a
  /// 16-entry cap and were promptly re-read).
  String build(
    List<ToolResultInfo> results, {
    int maxEntries = 32,
    int minEntries = 2,
  }) {
    // Preserve first-seen order of distinct labels while collecting every
    // result body for each, so a label repeated with identical output can be
    // flagged as `unchanged`. Track each label's most recent position too, so
    // an over-budget list can keep the tail rather than the head.
    final order = <String>[];
    final resultsByLabel = <String, List<String>>{};
    final hashesByLabel = <String, List<String?>>{};
    final lastSeen = <String, int>{};
    final commandLabels = <String>{};
    final inspectionStatus = <String, _InspectionStatus>{};
    final commandExitCodes = <String, int?>{};
    var index = 0;
    for (final result in results) {
      final name = result.name.trim().toLowerCase();
      final isCommand = _digestableCommandTools.contains(name);
      if (!isCommand && !_digestableTools.contains(name)) {
        continue;
      }
      if (isCommand && _wasNeverExecuted(result.result)) {
        continue;
      }
      final label = isCommand
          ? _commandLabelFor(name, result.arguments)
          : _labelFor(name, result.arguments);
      if (label == null) {
        continue;
      }
      if (isCommand) {
        commandLabels.add(label);
        // Last run wins, and an absent status stays absent: a command that
        // never reached an exit must not read as one that exited cleanly.
        commandExitCodes[label] = result.outcome?.exitCode;
      } else {
        // Last write wins: a path that failed and then succeeded is gathered
        // context, and one that succeeded and then vanished is not.
        inspectionStatus[label] = _classifyInspection(result.result);
      }
      final bodies = resultsByLabel.putIfAbsent(label, () {
        order.add(label);
        return <String>[];
      });
      bodies.add(result.result);
      hashesByLabel
          .putIfAbsent(label, () => <String?>[])
          .add(result.outcome?.effectiveContentHash);
      lastSeen[label] = index++;
    }
    if (order.length < minEntries) {
      return '';
    }

    // Decide which labels survive the budget: always keep repeated labels, then
    // fill the remaining budget with the most-recently-seen labels.
    final Set<String> kept;
    if (order.length <= maxEntries) {
      kept = order.toSet();
    } else {
      kept = <String>{
        for (final label in order)
          if (resultsByLabel[label]!.length >= 2) label,
      };
      final byRecency = order.toList()
        ..sort((a, b) => lastSeen[b]!.compareTo(lastSeen[a]!));
      for (final label in byRecency) {
        if (kept.length >= maxEntries) break;
        kept.add(label);
      }
    }

    // Emit the surviving labels in first-seen order for a stable, readable
    // block, inspections and commands in their own sections.
    final lines = <String>[];
    final commandLines = <String>[];
    for (final label in order) {
      if (!kept.contains(label)) {
        continue;
      }
      final bodies = resultsByLabel[label]!;
      if (commandLabels.contains(label)) {
        final repeated = bodies.length >= 2;
        final exitCode = commandExitCodes[label];
        final facts = <String>[
          if (exitCode != null) repeated ? 'last exit $exitCode' : 'exit $exitCode',
          if (repeated) 'already run ${bodies.length}x this turn',
        ];
        commandLines.add(
          facts.isEmpty ? '- $label' : '- $label (${facts.join('; ')})',
        );
        continue;
      }
      final status = inspectionStatus[label] ?? const _InspectionStatus.ok();
      if (status.isRetryable) {
        // The runtime asked for this exact call to be repeated, so saying
        // anything here would argue against its own recovery instruction.
        continue;
      }
      if (status.failureCode case final code?) {
        lines.add(
          '- $label — FAILED ($code); no content was gathered, and '
          'repeating this exact call returns the same failure',
        );
        continue;
      }
      final unchangedRun = _unchangedRunLength(bodies, hashesByLabel[label]!);
      lines.add(
        unchangedRun >= 2
            ? '- $label (unchanged — the last $unchangedRun inspections '
                  'returned the same file; do not repeat it unless you modify '
                  'the underlying files)'
            : '- $label',
      );
    }
    if (lines.length + commandLines.length < minEntries) {
      return '';
    }
    final sections = <String>[
      if (lines.isNotEmpty)
        'Context already gathered this turn (do not re-read these unless a '
            'file was modified since):\n${lines.join('\n')}',
      if (commandLines.isNotEmpty)
        'Commands already run this turn — their output is not carried into '
            'this request. Do not re-issue one by reflex; run it again only '
            'when you need its output again or something it depends on has '
            'changed:\n${commandLines.join('\n')}',
    ];
    return sections.join('\n\n');
  }

  /// Label for a command execution, normalized so a reworded `reason` does not
  /// split one command into two entries.
  String? _commandLabelFor(String name, Map<String, dynamic> arguments) {
    final raw = arguments['command']?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final command = raw.replaceAll(RegExp(r'\s+'), ' ');
    final prefix = name == 'git_execute_command' ? 'git ' : '';
    final full = '$prefix$command';
    final label = full.length > _maxCommandLabelChars
        ? '${full.substring(0, _maxCommandLabelChars)}…'
        : full;
    return 'ran `$label`';
  }

  /// How many of the most recent inspections of one label saw the same file,
  /// counting back from the latest. `1` means the latest inspection stands
  /// alone and nothing is proven unchanged.
  ///
  /// Only the trailing run counts, because a file that legitimately changed
  /// once and then held still is exactly the file worth flagging: requiring
  /// *every* repeat to match let one early change mask every later repeat. In
  /// session 0e94a103 `.fvmrc` was read at 3.47.0, updated, then read twice
  /// more at 3.47.1 — the last two reads proved it settled, and the third read
  /// went out unflagged because the first one had seen a different version.
  ///
  /// The hash decides a comparison whenever both sides carry one, since it is
  /// a fact about the file rather than about the text that was rendered. A
  /// missing hash is unknown, and unknown never extends the run: an unhashed
  /// latest read falls back to byte-identity, and an unhashed earlier read
  /// ends the run where it sits.
  static int _unchangedRunLength(List<String> bodies, List<String?> hashes) {
    if (bodies.length < 2) {
      return 1;
    }
    final latestHash = hashes.length == bodies.length ? hashes.last : null;
    var run = 1;
    for (var i = bodies.length - 2; i >= 0; i--) {
      final same = latestHash != null
          ? hashes[i] == latestHash
          : bodies[i] == bodies.last;
      if (!same) {
        break;
      }
      run++;
    }
    return run;
  }

  /// Whether a command result describes a command that never ran.
  ///
  /// A blocked mutation is refused before the shell is reached, so listing it
  /// as "ran `cat > js/cave.js …`" states something untrue and, worse, tells
  /// the model not to re-issue by reflex — when re-issuing with a corrected
  /// path is exactly the recovery. Session a0ca65b7 carried two fence-blocked
  /// heredoc writes into the digest that way.
  ///
  /// Both executed paths render `stdout` (empty string included) alongside the
  /// exit status, and refusals carry `ok: false` without it, so the pair
  /// separates "refused" from "ran and failed" without reading any prose.
  static bool _wasNeverExecuted(String result) {
    if (!result.contains('"ok"')) {
      return false;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(result);
    } on FormatException {
      return false;
    }
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    return decoded['ok'] == false && !decoded.containsKey('stdout');
  }

  /// How one read-class result reported its own execution.
  ///
  /// A failed read used to be digested as a plain `- read <path>` line, which
  /// states that content was gathered when none was: the loop carries only the
  /// *current* batch's results, so by the next request the digest line is the
  /// only surviving trace of the call and the error text is gone. Session
  /// 03d25ba5 asked to update FVM, read a guessed `fvm/config.json` that does
  /// not exist, listed the project root (which shows `.fvmrc`), and then
  /// re-issued the identical dead read — at that request the model could see
  /// the path listed as gathered context with no content attached and no
  /// failure anywhere, and the turn died on `tool_failure_abort`.
  ///
  /// Dropping the entry instead would be no better: with no trace at all the
  /// path reads as never inspected, which invites the same re-read. So a
  /// terminal failure is stated as a failure, naming the structured `code`
  /// rather than any phrase from the message.
  ///
  /// A failure that prescribes a `next_action` is the exception. Those are
  /// transient runtime refusals whose documented recovery is to repeat the
  /// read in the same turn, so they are dropped rather than reported: telling
  /// the model not to repeat a call the runtime just told it to repeat is the
  /// [_wasNeverExecuted] mistake in the other direction.
  static _InspectionStatus _classifyInspection(String result) {
    if (!result.contains('"ok"')) {
      return const _InspectionStatus.ok();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(result);
    } on FormatException {
      return const _InspectionStatus.ok();
    }
    if (decoded is! Map<String, dynamic> || decoded['ok'] != false) {
      return const _InspectionStatus.ok();
    }
    if (decoded.containsKey('next_action')) {
      return const _InspectionStatus.retryable();
    }
    final code = decoded['code'];
    return _InspectionStatus.failed(
      code is String && code.trim().isNotEmpty ? code.trim() : 'unknown_error',
    );
  }

  String? _labelFor(String name, Map<String, dynamic> arguments) {
    final path = arguments['path']?.toString().trim();
    switch (name) {
      case 'list_directory':
        return path == null || path.isEmpty ? null : 'listed $path';
      case 'read_file':
      case 'inspect_file':
        return path == null || path.isEmpty ? null : 'read $path';
      case 'find_files':
      case 'search_files':
        final query = (arguments['query'] ?? arguments['pattern'])
            ?.toString()
            .trim();
        if (query != null && query.isNotEmpty) {
          return 'searched "$query"';
        }
        return path == null || path.isEmpty ? null : 'searched $path';
    }
    return null;
  }
}

/// What a read-class tool reported about one invocation.
class _InspectionStatus {
  const _InspectionStatus.ok() : failureCode = null, isRetryable = false;

  const _InspectionStatus.failed(String this.failureCode) : isRetryable = false;

  const _InspectionStatus.retryable() : failureCode = null, isRetryable = true;

  /// Structured failure code of a terminal failure, null when the call either
  /// succeeded or reported nothing about itself.
  final String? failureCode;

  /// Whether the runtime prescribed repeating this exact call.
  final bool isRetryable;
}
