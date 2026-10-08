import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'verification/command_verification_reconciliation.dart';

/// Settles only notices explicitly based on the absence of execution evidence.
abstract final class UnexecutedCommandClaimReconciliation {
  static const evidenceRequirement = 'successful_verification_after_claim';

  static List<ToolResultInfo> currentResults(List<ToolResultInfo> results) {
    final stale = CommandVerificationReconciliation.staleBackgroundResultIds(
      results,
    );
    var laterVerificationPassed = false;
    final settled = <String>{};
    for (final result in results.reversed) {
      final payload = _decode(result.result);
      if (laterVerificationPassed &&
          payload?['result_origin'] == 'harness' &&
          payload?['code'] == 'unexecuted_command_action' &&
          payload?['evidence_requirement'] == evidenceRequirement &&
          !result.arguments.containsKey('command') &&
          !payload!.containsKey('command')) {
        settled.add(result.id);
      }
      // Replayed output and stale background polls cannot execute a recovery.
      if (!stale.contains(result.id) &&
          payload?['execution_reused'] != true &&
          CommandVerificationReconciliation.scopeOf(result)?.passed == true) {
        laterVerificationPassed = true;
      }
    }
    return settled.isEmpty
        ? results
        : results.where((result) => !settled.contains(result.id)).toList();
  }

  static Map<String, dynamic>? _decode(String source) {
    try {
      final value = jsonDecode(source);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
