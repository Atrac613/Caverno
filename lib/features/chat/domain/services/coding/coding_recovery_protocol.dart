import '../../entities/tool_call_info.dart';
import '../project_verification_repair_policy.dart';
import '../status_recovery_verification.dart';

/// Chooses the matching call contract for repair and status-only requests.
abstract final class CodingRecoveryProtocol {
  static bool accepts(
    List<ToolCallInfo> calls,
    List<Map<String, dynamic>> tools, {
    required bool repair,
  }) => repair
      ? ProjectVerificationRepairPolicy.accepts(calls, tools)
      : const StatusRecoveryVerification().accepts(calls, tools);
  static Map<String, dynamic> violation(
    List<ToolCallInfo> calls,
    List<Map<String, dynamic>> tools, {
    required bool repair,
  }) => repair
      ? ProjectVerificationRepairPolicy.violation(calls, tools)
      : const StatusRecoveryVerification().violation(calls, tools);
}
