import '../entities/tool_call_info.dart';
import 'execution_snapshot_projector.dart';
import 'tool_result_prompt_builder.dart';

class CommandDiagnosticStreakObservation {
  const CommandDiagnosticStreakObservation({
    required this.streak,
    required this.signatureChanged,
    required this.repairFocus,
  });

  final int streak;
  final bool signatureChanged;
  final CommandDiagnosticRepairFocus repairFocus;
}

class CommandDiagnosticRepairFocus {
  const CommandDiagnosticRepairFocus({
    required this.commandKey,
    required this.streak,
    required this.diagnosticSummary,
    required this.hasPathBackedDiagnostic,
  });

  final String commandKey;
  final int streak;
  final String diagnosticSummary;
  final bool hasPathBackedDiagnostic;
}

class CommandDiagnosticStreakTracker {
  final Map<String, _CommandDiagnosticStreakState> _states = {};

  CommandDiagnosticStreakObservation? observe({
    required String commandKey,
    required ToolResultInfo toolResult,
  }) {
    final evidence = ToolResultPromptBuilder.completionEvidence([toolResult]);
    final signature = evidence.diagnosticSignature;
    if (!evidence.hasAuthoritativeDiagnosticSnapshot || signature.isEmpty) {
      return null;
    }
    final diagnosticSummary = _diagnosticSummary(evidence);
    if (diagnosticSummary == null) {
      return null;
    }
    final previous = _states[commandKey];
    final signatureChanged =
        previous != null && previous.signature != signature;
    final streak = previous?.signature == signature ? previous!.streak + 1 : 1;
    _states[commandKey] = _CommandDiagnosticStreakState(signature, streak);
    return CommandDiagnosticStreakObservation(
      streak: streak,
      signatureChanged: signatureChanged,
      repairFocus: CommandDiagnosticRepairFocus(
        commandKey: commandKey,
        streak: streak,
        diagnosticSummary: diagnosticSummary,
        hasPathBackedDiagnostic: evidence.unresolvedErrorDiagnostics.any(
          (item) => item.path.trim().isNotEmpty,
        ),
      ),
    );
  }

  void reset(String commandKey) {
    _states.remove(commandKey);
  }

  String? _diagnosticSummary(ToolResultCompletionEvidence evidence) {
    final details = evidence.unresolvedErrorDiagnostics
        .where(
          (item) =>
              item.path.isNotEmpty ||
              item.code.isNotEmpty ||
              item.message.isNotEmpty,
        )
        .take(4)
        .map((item) {
          final location = item.path.isEmpty ? '' : '${item.path}: ';
          final code = item.code.isEmpty ? '' : '[${item.code}] ';
          final message = _sanitizeDiagnosticMessage(item.message, item.path);
          return _clip('$location$code$message', 300);
        })
        .toList(growable: false);
    return details.isEmpty ? null : details.join(' | ');
  }

  String _clip(String value, int limit) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= limit
        ? normalized
        : '${normalized.substring(0, limit)}...';
  }

  String _sanitizeDiagnosticMessage(String message, String displayPath) {
    final replacement = displayPath.isEmpty ? '<absolute-path>' : displayPath;
    return message
        .replaceAllMapped(
          RegExp(r'''(^|[\s(=\["':])/(?:[^\s:]+)'''),
          (match) => '${match.group(1) ?? ''}$replacement',
        )
        .replaceAllMapped(
          RegExp(r'''(^|[\s(=\["'])[A-Za-z]:\\[^\s:]+'''),
          (match) => '${match.group(1) ?? ''}$replacement',
        );
  }
}

class _CommandDiagnosticStreakState {
  const _CommandDiagnosticStreakState(this.signature, this.streak);

  final String signature;
  final int streak;
}

class StalledDiagnosticRepairContract {
  const StalledDiagnosticRepairContract();

  int nextSignatureStreak({
    required String previousSignature,
    required String currentSignature,
    required int currentStreak,
  }) {
    if (currentSignature.isEmpty || currentSignature != previousSignature) {
      return 0;
    }
    return currentStreak + 1;
  }

  String? build({
    required ToolResultCompletionEvidence evidence,
    required ExecutionSnapshot executionSnapshot,
    required int noProgressStreak,
  }) {
    if (!evidence.hasDiagnosticEvidence || noProgressStreak < 1) {
      return null;
    }
    final paths = evidence.unresolvedErrorPaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .take(8)
        .join(', ');
    final diagnostic = executionSnapshot.latestDiagnostic?.trim();
    final diagnosticDetails = evidence.unresolvedErrorDiagnostics
        .where(
          (item) =>
              item.path.isNotEmpty ||
              item.code.isNotEmpty ||
              item.message.isNotEmpty,
        )
        .take(4)
        .map((item) {
          final location = item.path.isEmpty ? '' : '${item.path}: ';
          final code = item.code.isEmpty ? '' : '[${item.code}] ';
          return _clip('$location$code${item.message}', 300);
        })
        .toList(growable: false);
    return [
      '<repair_contract>',
      'State: authoritative diagnostics did not improve after the previous repair turn.',
      'Required action: make one concrete file repair that directly addresses the diagnostics below.',
      'Unresolved error count: ${evidence.unresolvedErrorCount}',
      if (paths.isNotEmpty) 'Diagnostic paths: $paths',
      if (diagnosticDetails.isNotEmpty)
        'Diagnostic details: ${diagnosticDetails.join(' | ')}',
      if (diagnostic != null && diagnostic.isNotEmpty)
        'Latest diagnostic: ${_clip(diagnostic, 600)}',
      if (executionSnapshot.activeTaskTargetFiles.isNotEmpty)
        'Contract target files: ${executionSnapshot.activeTaskTargetFiles.take(8).join(', ')}',
      if (executionSnapshot.acceptanceCriteria.isNotEmpty)
        'Relevant acceptance criteria: ${executionSnapshot.acceptanceCriteria.take(4).join(' | ')}',
      'Do not run an alternative command or merely explain the fix. Choose one '
          'mutation from the diagnostic: use write_file when a required file is '
          'missing, edit_file when an existing file is faulty, or delete_file '
          'only when a file is explicitly unexpected. Read only the source '
          'needed to make that mutation. The harness will re-run the recorded '
          'verifier after the mutation.',
      '</repair_contract>',
    ].join('\n');
  }

  String _clip(String value, int limit) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= limit
        ? normalized
        : '${normalized.substring(0, limit)}...';
  }
}
