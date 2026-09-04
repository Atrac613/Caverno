import '../../../../core/types/workspace_mode.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/model_usage_role.dart';
import '../entities/tool_call_info.dart';
import 'anabasis_parent_authority_guard.dart';
import 'material_assumption_confirmation_gate.dart';

/// The policies every tool call in a turn passes through, in order.
///
/// One entry point rather than a growing run of `if (refusal != null) return`
/// blocks in the tool loop: the loop is the file least able to afford another
/// one, and a chain can be asserted on its own.
///
/// **Order is policy, not convenience.** Parent authority is evaluated first.
/// The Anabasis parent cannot mutate at all, so asking the user to confirm an
/// assumption before refusing it would raise an approval whose answer changes
/// nothing — and a confirmation, once given, is durable state the user gave for
/// a reason that never applied.
final class TurnToolPolicyChain {
  const TurnToolPolicyChain({
    required this.executingRole,
    required this.assumptionGate,
    this.parentAuthority = const AnabasisParentAuthorityGuard(),
  });

  /// Read from the ambient zone by the caller and passed in, so the guards
  /// stay pure functions of what they are told.
  final ModelUsageRole executingRole;
  final MaterialAssumptionConfirmationGate assumptionGate;
  final AnabasisParentAuthorityGuard parentAuthority;

  /// The refusal for [toolCall], or `null` when nothing blocks it.
  Future<McpToolResult?> evaluate(
    ToolCallInfo toolCall, {
    required WorkspaceMode workspaceMode,
  }) async {
    final unauthorized = parentAuthority.evaluate(
      toolCall,
      executingRole: executingRole,
    );
    if (unauthorized != null) return unauthorized;
    return assumptionGate.evaluate(toolCall, workspaceMode: workspaceMode);
  }
}
