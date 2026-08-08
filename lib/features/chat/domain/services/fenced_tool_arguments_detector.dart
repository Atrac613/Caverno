import 'dart:convert';

// ChatNotifier decomposition collaborator: fenced-tool-arguments-detector

/// A fenced JSON object that carries a command the model meant to run.
final class FencedToolArguments {
  const FencedToolArguments({required this.command, required this.rawJson});

  /// The `command` value, echoed back verbatim so the retry can name it.
  final String command;

  /// The fenced object as the model wrote it.
  final String rawJson;
}

/// Finds tool arguments the model printed in a ```json fence instead of
/// issuing a tool call.
///
/// Observed in a 2h26m session (6035277f, 2026-08-08) five times, including
/// once for a plain `grep '^version:'`, so this is not an approval dodge — the
/// model simply emits the argument object and stops. `ContentParser` handles
/// `<tool_call>` and `<tool_use>` markup; a bare fence is neither, so nothing
/// downstream sees a request at all and the turn ends looking like prose.
///
/// The detector deliberately refuses to name a tool. An object with `command`
/// and `label` fits several tools, and picking one would mean *executing* a
/// guess made from prose. What it produces is evidence for asking the model to
/// re-issue the call properly.
final class FencedToolArgumentsDetector {
  const FencedToolArgumentsDetector();

  /// Keys that would make this a tool call rather than a bare argument bag. If
  /// the model named the tool, the content-tag parsers own the case.
  static const Set<String> _toolNameKeys = {'name', 'tool', 'tool_name'};

  static final RegExp _jsonFence = RegExp(
    r'```(?:json|JSON)\s*(\{[\s\S]*?\})\s*```',
    multiLine: true,
  );

  /// The first fenced argument object in [content], or null.
  FencedToolArguments? detect(String content) {
    if (content.isEmpty || !content.contains('```')) {
      return null;
    }
    for (final match in _jsonFence.allMatches(content)) {
      final raw = match.group(1);
      if (raw == null) continue;
      final decoded = _decodeJsonObject(raw);
      if (decoded == null) continue;
      if (decoded.keys.any(
        (key) => _toolNameKeys.contains(key.trim().toLowerCase()),
      )) {
        continue;
      }
      final command = decoded['command'];
      if (command is! String || command.trim().isEmpty) continue;
      return FencedToolArguments(
        command: command.trim(),
        rawJson: raw.trim(),
      );
    }
    return null;
  }

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
