import 'dart:async';

import '../../domain/services/ask_user_question_policy.dart';
import 'pending_tool_approvals.dart';

/// A model-initiated question waiting for the user to answer it.
///
/// Extracted from `chat_state.dart`, which sat at its ratchet ceiling with no
/// margin, so ANA0's assumption-confirmation field could not be added without
/// either raising that budget or extracting. Re-exported from `chat_state.dart`
/// so no importer changed.
///
/// Unlike the [PendingToolApproval] hierarchy this is not an approval: nothing
/// is being authorised, and there is no cancellation *value* to complete with,
/// which is why it never joined that sealed family.
class PendingAskUserQuestion {
  PendingAskUserQuestion({
    required this.id,
    required this.conversationId,
    required this.question,
    required this.help,
    required this.options,
    required this.allowMultiple,
    required this.allowOther,
    required this.otherPlaceholder,
    required this.completer,
    this.origin = ChatInteractionOrigin.local,
    this.remoteDeviceId,
  });

  final String id;
  final String? conversationId;
  final String question;
  final String help;
  final List<AskUserQuestionOption> options;
  final bool allowMultiple;
  final bool allowOther;
  final String otherPlaceholder;
  final Completer<AskUserQuestionAnswer?> completer;

  /// Where the turn that raised this question originated. Mirrors the pending
  /// approval models so a question is only surfaced to a paired remote device
  /// when the turn itself came from that device.
  final ChatInteractionOrigin origin;
  final String? remoteDeviceId;
}
