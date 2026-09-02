import 'dart:convert';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/chat_turn_owner.dart';
import '../entities/tool_call_info.dart';
import 'fenced_tool_arguments_detector.dart';
import 'immutable_json_snapshot.dart';

// ChatNotifier decomposition collaborator: unexecuted-command-action-retry-policy

/// The structured code the claim detector writes when an answer describes a
/// command run that no tool result backs.
const String unexecutedCommandActionCode = 'unexecuted_command_action';

/// Immutable evidence for deciding whether to ask once more for the command.
final class UnexecutedCommandActionRetryInput {
  UnexecutedCommandActionRetryInput({
    required this.owner,
    required List<ToolResultInfo> ownerToolResults,
    required this.offersCommandExecution,
    required this.hasSuccessfulCommandExecution,
    required Set<String> attemptedOwners,
    required this.feedbackId,
    this.fencedToolArguments,
  }) : ownerToolResults = List<ToolResultInfo>.unmodifiable(
         ownerToolResults.map(_freezeToolResult),
       ),
       attemptedOwners = Set<String>.unmodifiable(attemptedOwners);

  final ChatTurnOwner owner;
  final List<ToolResultInfo> ownerToolResults;

  /// Whether this turn actually offers command-execution tools. Asking for a
  /// command the turn cannot run would only produce another apology.
  final bool offersCommandExecution;

  /// Whether any command did run in this turn. The claim may be about that
  /// run, so a turn with real command evidence is left alone.
  final bool hasSuccessfulCommandExecution;
  final Set<String> attemptedOwners;
  final String feedbackId;

  /// A command the answer printed in a ```json fence instead of calling. This
  /// is structural evidence of one specific unissued call, so it outranks the
  /// recorded claim: it fires even in a turn where other commands did run,
  /// because the fenced one demonstrably did not.
  final FencedToolArguments? fencedToolArguments;

  static ToolResultInfo _freezeToolResult(ToolResultInfo result) {
    return ToolResultInfo(
      id: result.id,
      name: result.name,
      arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
      result: result.result,
    );
  }
}

/// Why no retry was planned, for logging and tests.
enum UnexecutedCommandActionRetryNoPlanReason {
  noUnexecutedClaim,
  noCommandTools,
  commandAlreadyExecuted,
  alreadyAttempted,
}

/// A deterministic request to issue the described command, or name the blocker.
final class UnexecutedCommandActionRetryPlan {
  const UnexecutedCommandActionRetryPlan._({
    required this.owner,
    required this.feedback,
  });

  final ChatTurnOwner owner;
  final ToolResultInfo feedback;
}

/// The outcome of evaluating one turn.
final class UnexecutedCommandActionRetryDisposition {
  const UnexecutedCommandActionRetryDisposition.plan(this.plan)
    : noPlanReason = null;

  const UnexecutedCommandActionRetryDisposition.noPlan(this.noPlanReason)
    : plan = null;

  final UnexecutedCommandActionRetryPlan? plan;
  final UnexecutedCommandActionRetryNoPlanReason? noPlanReason;
}

/// Gives the tool loop one more pass when an answer describes a command run
/// that never happened.
///
/// Measured on the session-log corpus: 25 of 130 turn exits ended with the
/// "treat this as unverified" notice, 19 of them with no tool call at all in
/// the final request, and *none* of them had a recovery attempt in the same
/// turn. The existing recovery is gated on the user's wording — "continue",
/// "proceed", 続けて — so real replies like "はい" or "iOS + macOS 両方を実行"
/// never reached it. This policy triggers on the recorded claim instead.
///
/// The lexical claim detector stays a trigger, never the judge: the retry does
/// not decide that the answer lied, it hands the question back to the tool loop
/// where a real result settles it. An answer that was truthful is proven by
/// running the command; one that was not shows its failure.
///
/// The feedback deliberately accepts "name the blocker" as an outcome. A turn
/// that stopped to ask for approval is a pause worth keeping, and pushing the
/// model through it would be worse than the notice this replaces.
final class UnexecutedCommandActionRetryPolicy {
  const UnexecutedCommandActionRetryPolicy();

  UnexecutedCommandActionRetryDisposition evaluate(
    UnexecutedCommandActionRetryInput input,
  ) {
    final fenced = input.fencedToolArguments;
    if (fenced == null && !_hasUnexecutedClaim(input.ownerToolResults)) {
      return const UnexecutedCommandActionRetryDisposition.noPlan(
        UnexecutedCommandActionRetryNoPlanReason.noUnexecutedClaim,
      );
    }
    if (!input.offersCommandExecution) {
      return const UnexecutedCommandActionRetryDisposition.noPlan(
        UnexecutedCommandActionRetryNoPlanReason.noCommandTools,
      );
    }
    // A turn that ran commands may well be describing those runs, so the
    // recorded claim alone is not enough. A fenced command is different: that
    // exact call is on the page and was never issued.
    if (fenced == null && input.hasSuccessfulCommandExecution) {
      return const UnexecutedCommandActionRetryDisposition.noPlan(
        UnexecutedCommandActionRetryNoPlanReason.commandAlreadyExecuted,
      );
    }
    if (input.attemptedOwners.contains(ownerKey(input.owner))) {
      return const UnexecutedCommandActionRetryDisposition.noPlan(
        UnexecutedCommandActionRetryNoPlanReason.alreadyAttempted,
      );
    }

    return UnexecutedCommandActionRetryDisposition.plan(
      UnexecutedCommandActionRetryPlan._(
        owner: input.owner,
        feedback: _buildFeedback(input.feedbackId, fenced),
      ),
    );
  }

  /// One retry per turn. A second pass on the same turn would trade a wrong
  /// answer for a loop.
  String ownerKey(ChatTurnOwner owner) =>
      'unexecuted_command_action_retry:${owner.conversationId}:'
      '${owner.interactionGeneration}';

  bool _hasUnexecutedClaim(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      final decoded = _decodeJsonObject(toolResult.result);
      return decoded != null && decoded['code'] == unexecutedCommandActionCode;
    });
  }

  ToolResultInfo _buildFeedback(
    String feedbackId,
    FencedToolArguments? fenced,
  ) {
    if (fenced != null) {
      return ToolResultInfo(
        id: feedbackId,
        name: 'local_execute_command',
        arguments: {
          'reason':
              'The answer printed tool arguments in a JSON code fence instead '
              'of issuing a tool call.',
        },
        result: jsonEncode({
          'ok': false,
          'code': 'fenced_tool_arguments_not_a_call',
          'error':
              'A JSON code fence is text, not a tool call. Nothing executed '
              'it, so the command below has not run.',
          'command': fenced.command,
          'fenced_arguments': fenced.rawJson,
          'required_action':
              'Issue this as a real tool call using the tool-calling API, '
              'naming the tool (for example local_execute_command or '
              'process_start) and passing the arguments above. Do not print '
              'the arguments in a code fence again. If the call cannot be '
              'issued, reply with the one concrete reason instead.',
        }),
      );
    }
    return ToolResultInfo(
      id: feedbackId,
      name: 'local_execute_command',
      arguments: {
        'reason':
            'The answer described a command run that no tool result in this '
            'turn backs.',
      },
      result: jsonEncode({
        'ok': false,
        'code': 'unexecuted_command_action_retry_required',
        ...ToolResultOrigin.harness.marker,
        'error':
            'No successful command-execution tool result exists for the run '
            'described above, so the description is not evidence that anything '
            'ran.',
        'required_action':
            'Either issue the tool call that performs the described command '
            'now, or reply with the one concrete reason it cannot be issued '
            '(for example: it needs approval you do not have, or a required '
            'input is missing). Do not describe a run, report results, or '
            'restate the plan.',
      }),
    );
  }

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
