import '../entities/tool_call_info.dart';
import 'tool_loop_context_digest.dart';

/// Builds the assistant text a tool-result follow-up carries.
///
/// The turn's visible text and the "already gathered this turn" digest travel
/// in one field, and the joining rule is not obvious: an empty digest must
/// leave the visible text exactly as it was, because a trailing separator on
/// its own reads to the model as a dropped sentence.
///
/// [ToolLoopContextDigest] needs to know which results the same request sends
/// in full, so building the digest and choosing what to say about it belong
/// together rather than at the call site.
final class FollowUpAssistantContent {
  const FollowUpAssistantContent({
    ToolLoopContextDigest digest = const ToolLoopContextDigest(),
  }) : _digest = digest;

  final ToolLoopContextDigest _digest;

  String? build({
    required String? assistantContent,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> carried,
  }) {
    final digest = _digest.build(executedToolResults, carried: carried);
    if (digest.isEmpty) return assistantContent;
    final trimmed = assistantContent?.trim();
    return <String>[
      if (trimmed != null && trimmed.isNotEmpty) trimmed,
      digest,
    ].join('\n\n');
  }
}
