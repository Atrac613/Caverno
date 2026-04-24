import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_live_harness_fallback.dart';
import '../../integration_test/test_support/plan_mode_report_summary.dart';

void main() {
  group('resolvePlanModeApprovalFallbackDecision', () {
    test('keeps normal UI approval when the approval sheet is ready', () {
      final decision = resolvePlanModeApprovalFallbackDecision(
        proposalUiReady: true,
        usesLiveLlm: true,
      );

      expect(decision.shouldBypassUi, isFalse);
      expect(decision.approvalPath, planModeApprovalPathUi);
      expect(decision.fallbackPath, planModeFallbackPathNone);
    });

    test('uses harness fallback only for live LLM scenarios', () {
      final decision = resolvePlanModeApprovalFallbackDecision(
        proposalUiReady: false,
        usesLiveLlm: true,
      );

      expect(decision.shouldBypassUi, isTrue);
      expect(decision.approvalPath, planModeApprovalPathLiveHarnessFallback);
      expect(decision.fallbackPath, planModeFallbackPathLiveHarnessApproval);
    });

    test('does not hide deterministic approval UI failures', () {
      final decision = resolvePlanModeApprovalFallbackDecision(
        proposalUiReady: false,
        usesLiveLlm: false,
      );

      expect(decision.shouldBypassUi, isFalse);
      expect(decision.approvalPath, planModeApprovalPathUnknown);
      expect(decision.fallbackPath, planModeFallbackPathNone);
    });
  });

  group('resolvePlanModeApprovalUiWaitTimeoutAction', () {
    test('keeps deterministic UI wait failures visible', () {
      final action = resolvePlanModeApprovalUiWaitTimeoutAction(
        allowArtifactReadyFallback: false,
        artifactReady: true,
      );

      expect(action, PlanModeApprovalUiWaitTimeoutAction.failUiExpectation);
    });

    test('uses artifact fallback when the live plan artifact is ready', () {
      final action = resolvePlanModeApprovalUiWaitTimeoutAction(
        allowArtifactReadyFallback: true,
        artifactReady: true,
      );

      expect(
        action,
        PlanModeApprovalUiWaitTimeoutAction.useArtifactReadyFallback,
      );
    });

    test('defers missing live artifacts to harness validation', () {
      final action = resolvePlanModeApprovalUiWaitTimeoutAction(
        allowArtifactReadyFallback: true,
        artifactReady: false,
      );

      expect(
        action,
        PlanModeApprovalUiWaitTimeoutAction.useLiveHarnessValidationFallback,
      );
    });
  });
}
