import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:crypto/crypto.dart';

import '../../data/datasources/filesystem_path_resolver.dart';
import '../../data/datasources/git_tools.dart';
import '../entities/tool_call_info.dart';
import 'sticky_tool_result_policy.dart';
import 'tool_call_execution_policy.dart';

/// Carries a bounded tail of recent read-only results into the next follow-up.
///
/// A follow-up otherwise holds the current batch and nothing else but
/// `ask_user_question` / `load_skill` (`StickyToolResultPolicy`), and
/// `ToolLoopContextDigest` names what an earlier call returned without its
/// output. One round trip therefore retains exactly one fact, so a step that
/// needs two at once can never assemble them.
///
/// Session 64bad560 is the failure: asked to bump a version, the model needed
/// the latest tag and the current `pubspec.yaml` together to decide the next
/// number. It read them alternately for 12 iterations and 9m29s, each fetch
/// evicting the one before it, and the turn ended without a version bumped.
/// Its own reasoning names the cause -- "the output wasn't carried over. Let
/// me run it again" -- which is the digest's instruction followed exactly. The
/// same prompt failed 3 of 3 runs on that model.
///
/// The two facts it needed were 522 B and 3.4 KB. The budget below is measured
/// against 1644 read-only results across 65 local session logs: an individual
/// result is 866 B at the median, 1.9 KB at p75 and 7.7 KB at p95, and a whole
/// log's distinct read-only results total 4.6 KB at the median. So 8 KB holds
/// nine median results, or four p75 ones, and covers the median turn entirely,
/// while the per-result cap stops one 41 KB outlier from evicting everything.
///
/// This costs prefill, not cache: in 64bad560 `cachedPromptTokens` was exactly
/// 8192 -- the system prompt -- on 10 of 12 requests, because the digest and
/// the tool results that follow it change every request anyway. The prefix is
/// already broken where this content lands.
///
/// The defaults fit the median turn, not every turn. A turn whose working set
/// is larger passes its own [budgetBytes] rather than moving the default.
final class RecentReadResultCarry {
  const RecentReadResultCarry({
    ToolCallExecutionPolicy executionPolicy = const ToolCallExecutionPolicy(),
    StickyToolResultPolicy stickyPolicy = const StickyToolResultPolicy(),
    this.budgetBytes = defaultBudgetBytes,
    this.maxResultBytes = defaultMaxResultBytes,
    this.projectRoot,
  }) : _executionPolicy = executionPolicy,
       _stickyPolicy = stickyPolicy;

  final ToolCallExecutionPolicy _executionPolicy;
  final StickyToolResultPolicy _stickyPolicy;

  /// Largest single result carried, at p95 of the measured corpus.
  static const int defaultMaxResultBytes = 8 * 1024;

  /// Total carried bytes, which covers the median turn's whole read-only set.
  static const int defaultBudgetBytes = 8 * 1024;

  /// Coding needs the source files and tests together. Session b82411f0's
  /// unchanged working set was about 30 KiB: the 8 KiB tail kept evicting the
  /// implementation before the next edit, leading to 54 reads in 58 calls.
  static const coding = RecentReadResultCarry(
    budgetBytes: 32 * 1024,
    maxResultBytes: 16 * 1024,
  );

  final int maxResultBytes;
  final int budgetBytes;
  final String? projectRoot;

  RecentReadResultCarry forProject(String? root) => RecentReadResultCarry(
    executionPolicy: _executionPolicy,
    stickyPolicy: _stickyPolicy,
    budgetBytes: budgetBytes,
    maxResultBytes: maxResultBytes,
    projectRoot: root,
  );

  /// Everything a follow-up request carries: the sticky results, the
  /// carryable tail, then the batch that just ran.
  List<ToolResultInfo> resolve({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolResultInfo> executedToolResults,
  }) => augment(
    // The sticky results are re-sent from earlier iterations too, so they are
    // marked the same way; only the batch that just ran is current.
    resolved: _stickyPolicy
        .resolve(
          batchToolResults: batchToolResults,
          executedToolResults: executedToolResults,
        )
        .map(
          (result) => batchToolResults.any((batch) => identical(batch, result))
              ? result
              : _asHistory(result),
        )
        .toList(growable: false),
    executedToolResults: executedToolResults,
  );

  /// Returns [resolved] with the carryable tail prepended.
  ///
  /// Newest first while the budget lasts, then restored to execution order so
  /// the model reads them the way they happened.
  List<ToolResultInfo> augment({
    required List<ToolResultInfo> resolved,
    required List<ToolResultInfo> executedToolResults,
  }) {
    if (resolved.isEmpty) return resolved;
    final present = resolved.map(_keyFor).toSet();
    final carried = <(ToolResultInfo, List<String>)>[];
    // Newest first, so these are the writes that ran after the result under
    // inspection.
    final laterWrites = <String>[];
    final writtenPaths = <String>{};
    var indexChanged = false;
    var remaining = budgetBytes;
    for (var index = executedToolResults.length - 1; index >= 0; index--) {
      final result = executedToolResults[index];
      // Feedback and refusals never reached a tool. A synthetic command
      // must not invalidate the code the recovery request needs to act on.
      if (ToolResultOrigin.fromPayload(
            _executionPolicy.tryDecodeMap(result.result),
          ) !=
          null) {
        continue;
      }
      final call = _callFor(result);
      if (_executionPolicy.isFileMutationToolCall(call)) {
        if (_unchangedEditSnapshot(executedToolResults, index)) continue;
        // A file tool names what it wrote, so only reads of that path are
        // known stale. Dropping everything older made a release turn lose the
        // latest tag and the commit list the moment it bumped pubspec.yaml,
        // and restart its skill from step 1: 7 of 17 capped turns re-ran
        // pre-write inspections, against 1 of 38 turns that ended normally
        // (session f76b5251 gen-5 reached the cap on its commit, untagged).
        final path = _pathOf(result);
        if (path == null) break;
        writtenPaths.add(path);
        laterWrites.insert(0, '${result.name} $path');
        continue;
      }
      // `git add` only stages: no file, branch, tag or HEAD moves, so what it
      // makes stale is what reads the index. Treating it as a scope-less
      // mutation dropped the version and tag facts at exactly the step that
      // writes the commit message from them -- sessions d84f819b and
      // e6b3d03c re-read both right after staging, and e6b3d03c's
      // loop-limit recovery committed "1.3.50+62" for a 1.3.50+64 bump.
      final stagedPaths = _stagedPathsOf(result);
      if (stagedPaths != null) {
        indexChanged = true;
        laterWrites.insert(0, 'git add $stagedPaths');
        continue;
      }
      // A process observer reports on a job, not on the workspace: it neither
      // changes files nor restates them.
      if (_executionPolicy.isRepeatableBackgroundProcessInspectionTool(call)) {
        continue;
      }
      // A mutating command has no declared scope -- it can move the branch or
      // rewrite any file -- so everything read before it is labelled with it
      // and the model judges what it may have made stale, as with a file
      // write. Dropping them instead cost session 1d76c878 seven re-reads
      // after `pytest --version`, and the command's own result went with
      // them: the passing `pytest -q` was gone one loop later, before the
      // status request that needed it.
      if (_executionPolicy.isCommandExecutionTool(result.name) &&
          !_executionPolicy.isReadOnlyCommandExecutionToolCall(call)) {
        final bytes = utf8.encode(result.result).length;
        if (_hasExitStatus(result) &&
            present.add(_keyFor(result)) &&
            bytes <= maxResultBytes &&
            bytes <= remaining) {
          remaining -= bytes;
          carried.add((result, List<String>.unmodifiable(laterWrites)));
        }
        laterWrites.insert(0, _commandLabel(result));
        // A mutating git command moves the index or HEAD, so an older
        // `status` or `diff` is known stale rather than possibly stale.
        if (result.name == 'git_execute_command') indexChanged = true;
        continue;
      }
      if (!present.add(_keyFor(result))) continue;
      if (!_isCarryable(result)) continue;
      if (writtenPaths.contains(_pathOf(result))) continue;
      if (indexChanged && _readsIndex(result)) continue;
      final bytes = utf8.encode(result.result).length;
      if (bytes > maxResultBytes) continue;
      // Skipped rather than ending the walk: stopping at the first result
      // that did not fit dropped every older one with it, however small. In
      // session e3a9f3f0 a 6.5 KB file read took the 178 B `git status` and
      // the 1.3 KB diff down, and the review re-ran both on the next loop.
      final retained = bytes <= remaining
          ? result
          : _boundedRead(result, remaining);
      if (retained == null) continue;
      remaining -= utf8.encode(retained.result).length;
      carried.add((retained, List<String>.unmodifiable(laterWrites)));
    }
    if (carried.isEmpty) return resolved;
    return <ToolResultInfo>[
      for (final (result, changes) in carried.reversed)
        _asHistory(result, changesSinceCapture: changes),
      ...resolved,
    ];
  }

  bool _unchangedEditSnapshot(List<ToolResultInfo> results, int index) {
    final edit = results[index];
    if (edit.name != 'edit_file' ||
        edit.outcome?.effectiveFileChanged == true) {
      return false;
    }
    final payload = _executionPolicy.tryDecodeMap(edit.result);
    if (payload?['error'] != 'old_text was not found in the target file' &&
        payload?['changed'] != false &&
        payload?['already_applied'] != true) {
      return false;
    }
    final digest = payload?['content_sha256'];
    final target = _pathOf(edit);
    if (digest is! String || target == null) return false;
    for (final previous in results.take(index).toList().reversed) {
      if (ToolResultOrigin.fromPayload(
            _executionPolicy.tryDecodeMap(previous.result),
          ) !=
          null) {
        continue;
      }
      final call = _callFor(previous);
      if (_executionPolicy.isCommandExecutionTool(previous.name) &&
          !_executionPolicy.isReadOnlyCommandExecutionToolCall(call) &&
          !_executionPolicy.isRepeatableBackgroundProcessInspectionTool(call)) {
        return false;
      }
      if (_executionPolicy.isFileMutationToolCall(call) &&
          (_pathOf(previous) == null || _pathOf(previous) == target)) {
        return false;
      }
      if (previous.name != 'read_file' || _pathOf(previous) != target) continue;
      final read = _executionPolicy.tryDecodeMap(previous.result);
      final content = read?['content'];
      if (content is! String ||
          read?['truncated'] == true ||
          read?['content_truncated'] == true ||
          (read?['offset'] ?? previous.arguments['offset'] ?? 1) != 1) {
        continue;
      }
      return sha256.convert(utf8.encode(content)).toString() == digest;
    }
    return false;
  }

  /// Keep an exact prefix with explicit range metadata instead of losing a
  /// whole source file when the remaining carry budget is slightly smaller.
  ToolResultInfo? _boundedRead(ToolResultInfo result, int budget) {
    if (result.name != 'read_file' || budget < 1024) return null;
    final payload = _executionPolicy.tryDecodeMap(result.result);
    final content = payload?['content'];
    if (payload == null || content is! String || payload['error'] != null) {
      return null;
    }
    final lines = content.split('\n');
    final start = payload['offset'] ?? result.arguments['offset'] ?? 1;
    if (start is! int || start < 1) return null;
    ToolResultInfo? retained;
    var low = 1;
    var high = lines.length - 1;
    while (low <= high) {
      final count = (low + high) ~/ 2;
      final body = jsonEncode({
        ...payload,
        'content': lines.take(count).join('\n'),
        'offset': start,
        'line_count': count,
        'truncated': true,
        'content_truncated': true,
        'read_more_hint': {
          'path': payload['path'] ?? result.arguments['path'],
          'offset': start + count,
          'limit': 60,
        },
      });
      if (utf8.encode(body).length <= budget) {
        retained = result.withResult(body);
        low = count + 1;
      } else {
        high = count - 1;
      }
    }
    return retained;
  }

  /// Marks a result as re-sent rather than newly arrived, so the request
  /// formatter can place it as its own earlier exchange.
  ToolResultInfo _asHistory(
    ToolResultInfo result, {
    List<String> changesSinceCapture = const <String>[],
  }) => ToolResultInfo(
    id: result.id,
    name: result.name,
    arguments: result.arguments,
    result: result.result,
    outcome: result.outcome,
    fromEarlierLoop: true,
    changesSinceCapture: changesSinceCapture,
  );

  String? _pathOf(ToolResultInfo result) {
    final path = result.arguments['path'];
    if (path is! String) return null;
    final trimmed = path.trim();
    return trimmed.isEmpty ? null : _resolveProjectPath(trimmed);
  }

  static const _maxLabelCommandChars = 120;

  /// A command without an exit status never finished, so its output is not
  /// a result to restate.
  bool _hasExitStatus(ToolResultInfo result) =>
      _executionPolicy.toolResultHasSuccessfulExit(result) ||
      _executionPolicy.toolResultHasFailedExit(result);

  String _commandLabel(ToolResultInfo result) {
    final command = _executionPolicy.toolCommandArgument(result.arguments);
    if (command == null) return result.name;
    final clipped = command.length <= _maxLabelCommandChars
        ? command
        : '${command.substring(0, _maxLabelCommandChars)}...';
    return '${result.name} `$clipped`';
  }

  bool _isCarryable(ToolResultInfo result) {
    final call = _callFor(result);
    if (_executionPolicy.isReadOnlyCommandExecutionToolCall(call)) {
      // An absent exit status means the command never reached one, which is
      // not the same as success and must not be presented as output.
      return result.outcome?.exitCode == 0;
    }
    if (!_executionPolicy.isReadOnlyInspectionTool(result.name)) return false;
    // A reuse payload is a pointer to content, not the content.
    return !result.result.contains('"duplicate_tool_call_result_reused"');
  }

  /// The pathspec of a `git add` run through the git tool (empty when none was
  /// given), or null for any other result.
  String? _stagedPathsOf(ToolResultInfo result) {
    final args = _gitArgs(result);
    if (args == null || args.isEmpty || args.first != 'add') return null;
    return args.skip(1).join(' ');
  }

  /// Whether [result] reported index state that a later `git add` changes.
  bool _readsIndex(ToolResultInfo result) {
    final args = _gitArgs(result);
    return args != null &&
        args.isNotEmpty &&
        (args.first == 'status' || args.first == 'diff');
  }

  List<String>? _gitArgs(ToolResultInfo result) {
    if (result.name != 'git_execute_command') return null;
    final command = result.arguments['command'];
    if (command is! String) return null;
    return GitTools.splitArgs(GitTools.normalizeCommand(command));
  }

  ToolCallInfo _callFor(ToolResultInfo result) => ToolCallInfo(
    id: result.id,
    name: result.name,
    arguments: result.arguments,
  );

  String _keyFor(ToolResultInfo result) => _executionPolicy.toolResultDedupKey(
    result,
    resolveProjectPath: _resolveProjectPath,
  );

  String _resolveProjectPath(String path) => projectRoot == null
      ? path
      : FilesystemPathResolver.resolve(path, defaultRoot: projectRoot) ?? path;
}
