import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'file_mutation_evidence_policy.dart';

/// One file mutation the turn attempted and the runtime refused.
final class BlockedMutation {
  const BlockedMutation({required this.path, this.code});

  final String path;

  /// Structured refusal code, when the result carried one.
  final String? code;
}

final class BlockedMutationAssessment {
  const BlockedMutationAssessment({required this.blocked});

  final List<BlockedMutation> blocked;

  bool get hasBlockedMutations => blocked.isNotEmpty;

  String buildNotice() {
    final details = blocked
        .map((mutation) {
          final path = '`${mutation.path}`';
          final code = mutation.code;
          return code == null || code.isEmpty ? path : '$path ($code)';
        })
        .join(', ');
    return 'File change check: this turn changed no files, because every file '
        'mutation it attempted was refused: $details.';
  }
}

/// States what a turn actually did to files when it did nothing.
///
/// This is deliberately not a claim guard. A claim guard has to decide whether
/// a sentence asserts completion, and that decision is made by a vocabulary.
/// `UnwrittenFileClaimGuard` carries three Japanese verbs for create, update
/// and add, and none for fix or apply, so in session a0ca65b7 an answer
/// reporting that a fix had been applied to `main.js` reached the user
/// unflagged — in a turn whose every `edit_file` had been refused with
/// `saved_task_target_scope_violation`, and whose successful mutation count
/// was zero. The real edit landed 49 minutes later, in a different turn.
///
/// So this states the fact instead of judging the prose. The trigger is the
/// turn's own tool results — mutations attempted, none successful — which
/// makes it independent of wording, of language, and of whichever verb the
/// model reaches for next. It accuses nobody: appended to an honest answer it
/// is redundant, and appended to a false one it is the record.
///
/// It is correspondingly weaker than a guard, and knowingly so. It informs
/// rather than corrects: a reader who trusts confident prose over a terse
/// footer is still misled. Correcting would mean judging, which is the part
/// being removed.
///
/// Measured over the grounded session corpus, 8 of 180 turns qualify — the
/// turns spent fighting a scope fence, which is where a reader most needs to
/// know what state their files are actually in.
final class BlockedMutationNotice {
  const BlockedMutationNotice({
    FileMutationEvidencePolicy mutations = const FileMutationEvidencePolicy(),
  }) : _mutations = mutations;

  final FileMutationEvidencePolicy _mutations;

  /// Assesses one turn's whole result list.
  ///
  /// Returns nothing as soon as any mutation succeeded: a turn that changed
  /// even one file is not a turn that changed nothing, and the paths it did
  /// change are reported elsewhere.
  BlockedMutationAssessment assess(List<ToolResultInfo> toolResults) {
    final blocked = <String, BlockedMutation>{};
    for (final toolResult in toolResults) {
      if (!_mutations.isMutationToolName(toolResult.name)) continue;
      if (_mutations.isSuccessfulResult(toolResult)) {
        return const BlockedMutationAssessment(blocked: []);
      }
      final path =
          _mutations.resultPayloadPath(toolResult.result) ??
          _mutations.argumentPath(toolResult.arguments);
      if (path == null || path.isEmpty) continue;
      final code = _refusalCode(toolResult.result);
      blocked.putIfAbsent(
        '$path $code',
        () => BlockedMutation(path: path, code: code),
      );
    }
    return BlockedMutationAssessment(
      blocked: List<BlockedMutation>.unmodifiable(blocked.values),
    );
  }

  static String? _refusalCode(String result) {
    if (!result.contains('"code"')) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(result);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final code = decoded['code'];
    return code is String && code.trim().isNotEmpty ? code.trim() : null;
  }
}
