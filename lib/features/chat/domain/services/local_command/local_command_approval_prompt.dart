import 'shell_command_effect_notes.dart';

/// The heading and body a local command approval prompt shows.
///
/// Every other prompt keeps its historical shape: the gate's heading wins and
/// its rationale leads the body. A SEC4.4g prompt is different in two ways.
/// Its gate heading is the same sentence for every shell command, so a
/// command-specific risk heading ("Recursive file deletion") replaces it when
/// there is one, and the effect notes from [ShellCommandEffectNotes] are
/// appended so the prompts stop reading identically.
abstract final class LocalCommandApprovalPrompt {
  /// Audit sources whose approval is fresh and may not be remembered as an
  /// allow. Both reach the native shell or name an out-of-project path.
  static const Set<String> freshApprovalSources = {
    'opaque_host_write',
    'out_of_scope_path',
  };

  static ({String? title, String? message}) compose({
    required String command,
    required String? decisionSource,
    required String? gateTitle,
    required String? gateRationale,
    required String? riskTitle,
    required String? riskMessage,
  }) {
    final opaque = decisionSource == 'opaque_host_write';
    final notes = freshApprovalSources.contains(decisionSource)
        ? ShellCommandEffectNotes.describe(command)
        : const <String>[];
    final parts = [
      ?gateRationale,
      ?riskMessage,
      if (notes.isNotEmpty) notes.map((note) => '• $note').join('\n'),
    ].where((part) => part.isNotEmpty);
    return (
      title: opaque && riskTitle != null ? riskTitle : gateTitle ?? riskTitle,
      message: parts.isEmpty ? null : parts.join('\n\n'),
    );
  }
}
