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
/// every repeat returned byte-identical output, the line is flagged as
/// `unchanged`. This targets the non-converging edit→run→re-read debug loop
/// (session 119292cb: 11x identical full-file reads while no-op edits left the
/// file untouched) — the generic "unless a file was modified since" advisory
/// is too weak there because the model believes its edits changed the file.
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

  /// Returns a short markdown block listing the read-only context already
  /// gathered this turn, or an empty string when there is nothing worth
  /// repeating (fewer than [minEntries] distinct reads).
  String build(
    List<ToolResultInfo> results, {
    int maxEntries = 16,
    int minEntries = 2,
  }) {
    // Preserve first-seen order of distinct labels while collecting every
    // result body for each, so a label repeated with identical output can be
    // flagged as `unchanged`.
    final order = <String>[];
    final resultsByLabel = <String, List<String>>{};
    for (final result in results) {
      final name = result.name.trim().toLowerCase();
      if (!_digestableTools.contains(name)) {
        continue;
      }
      final label = _labelFor(name, result.arguments);
      if (label == null) {
        continue;
      }
      final bodies = resultsByLabel.putIfAbsent(label, () {
        order.add(label);
        return <String>[];
      });
      bodies.add(result.result);
    }

    final lines = <String>[];
    for (final label in order) {
      final bodies = resultsByLabel[label]!;
      final unchanged = bodies.length >= 2 && _allIdentical(bodies);
      lines.add(
        unchanged
            ? '- $label (unchanged — re-read returned identical content; do '
                  'not read it again unless you actually modify it)'
            : '- $label',
      );
      if (lines.length >= maxEntries) {
        break;
      }
    }
    if (lines.length < minEntries) {
      return '';
    }
    return 'Context already gathered this turn (do not re-read these unless a '
        'file was modified since):\n${lines.join('\n')}';
  }

  static bool _allIdentical(List<String> bodies) {
    final first = bodies.first;
    for (var i = 1; i < bodies.length; i++) {
      if (bodies[i] != first) {
        return false;
      }
    }
    return true;
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
