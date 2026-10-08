import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../../core/utils/logger.dart';

import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/plan/proposal_parsing_text_utils.dart';

/// Hands a tool-loop iteration back when the batch only waited on a job that
/// is still running.
///
/// Waiting is not work. Session 23d19ede started an ~11 minute iOS/macOS
/// release and polled it with `process_wait` (120s each) seven times; those
/// polls spent 7 of the turn's 14 iterations, so the loop was exhausted the
/// moment the release finished. The model had just announced the commit and
/// tag the user asked for, and the turn was finalized without tools instead,
/// ending on "shall I run these?". The same shape exhausted release turns on
/// 2026-09-20 and 2026-09-21.
///
/// A refund needs evidence that the call actually blocked: every call in the
/// batch is a `process_wait` asking for at least [minWaitMs], and its result
/// still reports the job running -- a wait only returns early when the job
/// exits, so a running result means the full wait elapsed. Short polls and
/// `process_status` spins earn nothing. Refunds are capped at [maxRefunds]
/// (about an hour of 120s waits) and kept apart from `ExecutionBudgetPolicy`'s
/// extension budget, so a long job does not eat the recovery headroom.
final class BackgroundWaitIterationRefund {
  static const int minWaitMs = 60000;
  static const int maxRefunds = 30;

  int _refunded = 0;

  int get refunded => _refunded;

  /// Whether [batchToolResults] earns a refund, recording it when it does.
  bool claim(List<ToolResultInfo> batchToolResults) {
    if (_refunded >= maxRefunds ||
        batchToolResults.isEmpty ||
        !batchToolResults.every(_isBlockingWaitOnRunningJob)) {
      return false;
    }
    _refunded += 1;
    return true;
  }

  /// The iterations to add to a loop capped at [cap]: 1 when [claim] grants a
  /// refund, else 0. Logs the grant in the `[ExecutionBudget]` family.
  int iterationsFor(List<ToolResultInfo> batchToolResults, {required int cap}) {
    if (!claim(batchToolResults)) return 0;
    appLog(
      '[ExecutionBudget] reason=backgroundWaitRefund; '
      'refunded=$_refunded/$maxRefunds; cap=${cap + 1}',
    );
    return 1;
  }

  static bool _isBlockingWaitOnRunningJob(ToolResultInfo result) {
    if (result.name.trim().toLowerCase() != 'process_wait') return false;
    final waitMs = result.arguments['wait_ms'];
    final requested = waitMs is num ? waitMs : num.tryParse('$waitMs');
    if (requested == null || requested < minWaitMs) return false;
    final state = result.outcome?.processState;
    if (state != null) return state == ToolProcessState.running;
    final status = ProposalParsingTextUtils.tryDecodeMap(
      result.result,
    )?['status'];
    return '$status'.trim().toLowerCase() == 'running';
  }
}
