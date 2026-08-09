import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../../core/utils/logger.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../domain/services/tool_outcome_shadow_comparison.dart';

/// Observes LL34 exit-code migration coverage without affecting tool behavior.
Future<void> observeToolOutcomeShadow({
  required LlmSessionLogStore store,
  required bool settingsEnabled,
  required LlmSessionLogContext context,
  required String toolName,
  required ToolOutcome? outcome,
  required String renderedPayload,
  required String toolCallId,
  required int loopIndex,
}) async {
  final shadow = compareToolOutcomeExitCode(
    toolName: toolName,
    outcome: outcome,
    parsedExitCode: parseExitCodeFromPayload(renderedPayload),
  );
  if (shadow.agreement == ToolOutcomeAgreement.bothAbsent) return;

  appLog(shadow.logLine);
  if (!LlmSessionLogStore.isEnabled(settingsEnabled: settingsEnabled)) return;
  await store.recordToolOutcomeShadow(
    context: context,
    at: DateTime.now(),
    toolName: shadow.toolName,
    agreement: shadow.agreement.name,
    verdictSource: shadow.verdictSource.name,
    structuredExitCode: shadow.structuredExitCode,
    parsedExitCode: shadow.parsedExitCode,
    toolCallId: toolCallId,
    loopIndex: loopIndex,
  );
}
