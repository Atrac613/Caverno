import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

/// How a tool's own reported exit status compares with the one a consumer
/// derived from the payload text.
///
/// LL34's goal is that consumers read [ToolOutcome] instead of re-parsing the
/// result string. Four services parse it independently today. Before any of
/// them switches, the two sources have to be shown to agree on real runs —
/// and where they do not, the reason has to be understood rather than assumed,
/// because an earlier attempt to hand the exit code to validation inference was
/// reverted when stderr turned out to outrank a zero exit.
///
/// This compares; it never decides. Nothing here changes what a consumer does.
enum ToolOutcomeAgreement {
  /// Both sources reported an exit status and they matched.
  agree,

  /// Both reported an exit status and they differed. The interesting case.
  disagree,

  /// The tool reported nothing structured; only the text had a status.
  ///
  /// Expected wherever the producer does not attach an outcome — SSH and HTTP
  /// results, and commands whose invocation failed outright, which
  /// deliberately carry no exit status at all.
  structuredMissing,

  /// The tool reported a status the text did not carry.
  parsedMissing,

  /// Neither source had an exit status. Nothing to learn.
  bothAbsent,
}

/// The source that supplied an exit status to a migrated consumer.
///
/// Consumers keep the lexical path for third-party MCP results and older
/// first-party payloads, but first-party outcomes take precedence whenever
/// they carry an exit code. Exposing the source keeps that fallback measurable
/// instead of making it an invisible compatibility branch.
enum ToolOutcomeVerdictSource { typed, lexicalFallback, unavailable }

class ToolOutcomeExitCodeResolution {
  const ToolOutcomeExitCodeResolution({
    required this.exitCode,
    required this.source,
  });

  final int? exitCode;
  final ToolOutcomeVerdictSource source;
}

ToolOutcomeExitCodeResolution resolveToolOutcomeExitCode({
  required ToolOutcome? outcome,
  required int? parsedExitCode,
}) {
  final structuredExitCode = outcome?.exitCode;
  if (structuredExitCode != null) {
    return ToolOutcomeExitCodeResolution(
      exitCode: structuredExitCode,
      source: ToolOutcomeVerdictSource.typed,
    );
  }
  if (parsedExitCode != null) {
    return ToolOutcomeExitCodeResolution(
      exitCode: parsedExitCode,
      source: ToolOutcomeVerdictSource.lexicalFallback,
    );
  }
  return const ToolOutcomeExitCodeResolution(
    exitCode: null,
    source: ToolOutcomeVerdictSource.unavailable,
  );
}

/// One comparison, ready to be recorded.
class ToolOutcomeShadowRecord {
  const ToolOutcomeShadowRecord({
    required this.toolName,
    required this.agreement,
    this.structuredExitCode,
    this.parsedExitCode,
  });

  final String toolName;
  final ToolOutcomeAgreement agreement;
  final int? structuredExitCode;
  final int? parsedExitCode;

  ToolOutcomeVerdictSource get verdictSource => resolveToolOutcomeExitCode(
    outcome: structuredExitCode == null
        ? null
        : ToolOutcome(exitCode: structuredExitCode),
    parsedExitCode: parsedExitCode,
  ).source;

  /// Whether this record is worth a log line.
  ///
  /// Agreement is the expected case and would drown the signal; absence on
  /// both sides says nothing. A disagreement, or a status one side has and the
  /// other does not, is what decides whether a consumer can switch.
  bool get isNoteworthy =>
      agreement == ToolOutcomeAgreement.disagree ||
      agreement == ToolOutcomeAgreement.parsedMissing;

  /// A single greppable line. Deliberately carries no payload text: the point
  /// is the shape of the disagreement, and results are untrusted content.
  String get logLine =>
      '[ToolOutcomeShadow] tool=$toolName verdict=${agreement.name} '
      'structured=${structuredExitCode ?? '-'} parsed=${parsedExitCode ?? '-'}';

  @override
  String toString() => logLine;
}

/// Compares a tool's reported exit status against a text-derived one.
ToolOutcomeShadowRecord compareToolOutcomeExitCode({
  required String toolName,
  required ToolOutcome? outcome,
  required int? parsedExitCode,
}) {
  final structured = outcome?.exitCode;
  final agreement = switch ((structured, parsedExitCode)) {
    (null, null) => ToolOutcomeAgreement.bothAbsent,
    (null, _) => ToolOutcomeAgreement.structuredMissing,
    (_, null) => ToolOutcomeAgreement.parsedMissing,
    _ when structured == parsedExitCode => ToolOutcomeAgreement.agree,
    _ => ToolOutcomeAgreement.disagree,
  };
  return ToolOutcomeShadowRecord(
    toolName: toolName,
    agreement: agreement,
    structuredExitCode: structured,
    parsedExitCode: parsedExitCode,
  );
}

/// The exit status a command payload carries as text, independent of whatever
/// the producer chose to report.
///
/// Deliberately independent from first-party producers: comparing a producer
/// with itself would answer nothing. The point is to find where the typed and
/// lexical contracts diverge, including results that never reached a process
/// exit even when their compatibility payload carries a synthetic status.
int? parseExitCodeFromPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return null;
    final value = decoded['exit_code'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value.trim());
    return null;
  } on FormatException {
    return null;
  }
}
