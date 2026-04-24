import 'plan_mode_report_summary.dart';

class PlanModeApprovalFallbackDecision {
  const PlanModeApprovalFallbackDecision({
    required this.shouldBypassUi,
    required this.approvalPath,
    required this.fallbackPath,
  });

  final bool shouldBypassUi;
  final String approvalPath;
  final String fallbackPath;
}

enum PlanModeApprovalUiWaitTimeoutAction {
  failUiExpectation,
  useArtifactReadyFallback,
  useLiveHarnessValidationFallback,
}

PlanModeApprovalFallbackDecision resolvePlanModeApprovalFallbackDecision({
  required bool proposalUiReady,
  required bool usesLiveLlm,
}) {
  if (proposalUiReady) {
    return const PlanModeApprovalFallbackDecision(
      shouldBypassUi: false,
      approvalPath: planModeApprovalPathUi,
      fallbackPath: planModeFallbackPathNone,
    );
  }

  if (usesLiveLlm) {
    return const PlanModeApprovalFallbackDecision(
      shouldBypassUi: true,
      approvalPath: planModeApprovalPathLiveHarnessFallback,
      fallbackPath: planModeFallbackPathLiveHarnessApproval,
    );
  }

  return const PlanModeApprovalFallbackDecision(
    shouldBypassUi: false,
    approvalPath: planModeApprovalPathUnknown,
    fallbackPath: planModeFallbackPathNone,
  );
}

PlanModeApprovalUiWaitTimeoutAction resolvePlanModeApprovalUiWaitTimeoutAction({
  required bool allowArtifactReadyFallback,
  required bool artifactReady,
}) {
  if (!allowArtifactReadyFallback) {
    return PlanModeApprovalUiWaitTimeoutAction.failUiExpectation;
  }
  if (artifactReady) {
    return PlanModeApprovalUiWaitTimeoutAction.useArtifactReadyFallback;
  }
  return PlanModeApprovalUiWaitTimeoutAction.useLiveHarnessValidationFallback;
}
