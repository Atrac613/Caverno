import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

/// The facts a first-party command tool encoded in its own JSON payload.
///
/// Command tools know their exit status and streams as typed values and then
/// flatten them into a JSON string, so every consumer that needs one of those
/// facts decodes the string again — sometimes by matching phrases in the
/// output. This type is the single place that reading happens: it decodes the
/// payload once, at the producer boundary, against a schema Caverno itself
/// writes, and hands the facts to `McpToolResultNormalizer` to attach to the
/// result.
///
/// It reads first-party payloads only. A third-party MCP server's output has
/// no schema we can rely on, so it yields no facts rather than guessed ones.
///
/// This is a staging step, not the end state: tool functions currently return
/// `Future<String>`, so the facts have to be recovered after serialization.
/// When tools return typed results directly, this adapter goes away. See LL34
/// in `docs/local_llm_agent_roadmap.md`.
class CommandPayloadFacts {
  const CommandPayloadFacts({
    this.exitCode,
    this.explicitError,
    this.stdout,
    this.stderr,
  });

  /// Process exit status, when the payload reported one.
  ///
  /// Absent when the command never reached an exit — it was denied, timed out,
  /// or failed to spawn. That is not the same as exiting zero.
  final int? exitCode;

  /// An error the tool reported directly, which outranks the exit status: it
  /// describes a failure to run the command rather than the command's own
  /// result.
  final String? explicitError;

  final String? stdout;
  final String? stderr;

  /// Reads the payload, or returns null when it is not a JSON object — a
  /// third-party result, or plain text.
  static CommandPayloadFacts? tryParse(String payload) {
    final decoded = tryDecodeMap(payload);
    if (decoded == null) {
      return null;
    }
    final exitCode = decoded['exit_code'];
    final error = decoded['error'];
    return CommandPayloadFacts(
      exitCode: exitCode is num ? exitCode.toInt() : null,
      explicitError: error is String && error.trim().isNotEmpty
          ? error.trim()
          : null,
      stdout: decoded['stdout'] is String ? decoded['stdout'] as String : null,
      stderr: decoded['stderr'] is String ? decoded['stderr'] as String : null,
    );
  }

  /// Reads a file-mutation payload's `changed` flag as an outcome.
  ///
  /// Returns null when the tool did not report it — an older payload, a failed
  /// write, or a mutation whose effect could not be determined. Absent means
  /// unknown, never "unchanged".
  static ToolOutcome? mutationOutcome(String payload) {
    final changed = tryDecodeMap(payload)?['changed'];
    return changed is bool ? ToolOutcome(fileChanged: changed) : null;
  }

  /// Reads a file-read payload's whole-file `content_hash` as an outcome.
  ///
  /// Absent for an error payload, a file too large to hash, or a legacy result
  /// written before the field existed. Every one of those means unknown, so a
  /// consumer must fall back rather than treat the file as changed.
  static ToolOutcome? readOutcome(String payload) {
    final hash = tryDecodeMap(payload)?['content_hash'];
    return hash is String && hash.isNotEmpty
        ? ToolOutcome(contentHash: hash)
        : null;
  }

  /// Reads a single background process payload's lifecycle state.
  ///
  /// Only successful first-party status envelopes are eligible. Running jobs
  /// deliberately carry no exit status, while exited jobs retain the status
  /// the process backend reported.
  static ToolOutcome? backgroundProcessOutcome(String payload) {
    final decoded = tryDecodeMap(payload);
    if (decoded == null || decoded['ok'] != true) {
      return null;
    }
    final processState = switch (decoded['status']) {
      'running' => ToolProcessState.running,
      'exited' => ToolProcessState.exited,
      _ => null,
    };
    if (processState == null) {
      return null;
    }
    final rawExitCode = decoded['exit_code'];
    return ToolOutcome(
      processState: processState,
      exitCode: processState == ToolProcessState.exited && rawExitCode is num
          ? rawExitCode.toInt()
          : null,
    );
  }

  static Map<String, dynamic>? tryDecodeMap(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// The structured outcome to attach to the tool result, or null when the
  /// payload reported no fact worth carrying.
  ///
  /// A timed-out or never-started command deliberately yields no exit status,
  /// so consumers cannot read one where none exists.
  ToolOutcome? toOutcome() {
    if (exitCode == null || explicitError != null) {
      return null;
    }
    return ToolOutcome(exitCode: exitCode);
  }

  /// A user-facing failure message, or null when the command succeeded.
  ///
  /// Preserves the existing precedence: an explicit error wins, then a
  /// non-zero exit status annotated with whichever stream carries detail.
  String? failureMessage(String toolLabel) {
    if (explicitError != null) {
      return explicitError;
    }
    if (exitCode == null || exitCode == 0) {
      return null;
    }
    final detail = _firstNonEmpty(stderr) ?? _firstNonEmpty(stdout);
    return detail == null
        ? '$toolLabel exited with code $exitCode'
        : '$toolLabel exited with code $exitCode: $detail';
  }

  static String? _firstNonEmpty(String? value) =>
      value != null && value.trim().isNotEmpty ? value.trim() : null;
}
