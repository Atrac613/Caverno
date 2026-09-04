import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/model_usage_role.dart';
import '../entities/tool_call_info.dart';

/// Keeps the Anabasis parent to inspection, verification and delegation.
///
/// The parent orchestrates; it does not edit. Delegation is its only route to
/// effect, and the child it spawns inherits mutation rights and escalates to
/// the user's approval dialog exactly as the main loop does.
///
/// **The executing role arrives as an argument, not from the zone.**
/// `ModelUsageRole` is ambient and defaults to [ModelUsageRole.unknown], which
/// is the right shape for accounting — an unclaimed path shows up as a visible
/// gap — and the wrong shape for authority, where a missed `runWith` would
/// silently drop the parent out of its own restrictions. The call site reads
/// the ambient value and passes it in; this guard is a pure function of what
/// it is told.
///
/// **`unknown` is refused, unlike in `MaterialContractAssumptionGuard`, and the
/// asymmetry is deliberate.** There, an unclassified tool is not treated as a
/// mutation because a false positive would block ordinary work. Here, an
/// unclassified tool is not proof of safety: the parent boundary is easier to
/// keep closed from the start than to retrofit once the parent has learned to
/// edit.
final class AnabasisParentAuthorityGuard {
  const AnabasisParentAuthorityGuard();

  static const refusedCode = 'anabasis_parent_authority_refused';

  /// Tools that *are* the parent's route to effect.
  ///
  /// A named exception because `spawn_subagent` does not classify cleanly under
  /// `ToolCommandEffect`. Adding a `delegation` effect is the tidy-up, and per
  /// the track rule it is justified only once the classifier is shown unable to
  /// express it — not before.
  static const delegationTools = <String>{'spawn_subagent'};

  static const _classifier = ToolCapabilityClassifier();

  McpToolResult? evaluate(
    ToolCallInfo toolCall, {
    required ModelUsageRole executingRole,
  }) {
    if (executingRole != ModelUsageRole.anabasisParent) return null;
    if (delegationTools.contains(toolCall.name)) return null;

    final effect = _classifier
        .classify(toolCall.name, arguments: toolCall.arguments)
        .commandEffect;
    if (effect == ToolCommandEffect.inspection ||
        effect == ToolCommandEffect.verification) {
      return null;
    }

    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': refusedCode,
        'effect': effect.name,
        'error':
            'The Anabasis parent may inspect, verify and delegate. It may not '
            'change the workspace itself.',
        'required_action':
            'Delegate this to a child with spawn_subagent, or inspect and '
            'verify to decide what the child should do.',
      }),
      isSuccess: false,
      errorMessage: 'The Anabasis parent cannot run ${toolCall.name}.',
    );
  }
}
