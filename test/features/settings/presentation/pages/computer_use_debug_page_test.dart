import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_audit_log.dart';
import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:caverno/features/settings/presentation/pages/computer_use_debug_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MacosComputerUseAuditLog.instance.clear();
  });

  testWidgets('shows helper boundary while using helper IPC backend', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('User-Operated Runtime Boundary'), findsOneWidget);
    expect(
      find.text(
        'Use this page to inspect helper readiness and run smoke checks. TCC grants, System Settings changes, and real desktop actions must be performed by the user.',
      ),
      findsOneWidget,
    );
    expect(find.text('Computer Use App Boundary'), findsOneWidget);
    expect(find.text('Current executor'), findsOneWidget);
    expect(find.text('Accessibility owner'), findsOneWidget);
    expect(find.text('Screen/audio owner'), findsOneWidget);
    expect(find.text('Target helper'), findsOneWidget);
    expect(find.text('Caverno Computer Use (helper_ipc)'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Reachable'), findsOneWidget);
    expect(
      find.text('Caverno Computer Use (com.noguwo.apps.caverno.computer-use)'),
      findsOneWidget,
    );
    expect(service.helperStatusCallCount, 1);
    expect(service.pingHelperCallCount, 1);
  });

  testWidgets('shows onboarding checklist progress and production XPC status', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Computer Use Smoke Sequence'), findsOneWidget);
    await _scrollUntilVisible(tester, find.text('Computer Use Onboarding'));
    expect(find.text('Computer Use Onboarding'), findsOneWidget);
    expect(find.text('2 of 10 complete'), findsOneWidget);
    expect(find.text('Launch Caverno Computer Use'), findsOneWidget);
    expect(find.text('MVP Sign-Off Path'), findsOneWidget);
    expect(find.text('MVP Evidence Preflight'), findsOneWidget);
    expect(find.text('MVP Missing Evidence Checklist'), findsOneWidget);
    expect(find.text('User-Operated MVP Commands'), findsOneWidget);
    expect(find.text('MVP Artifact Paths'), findsOneWidget);
    expect(find.text('MVP PR Review Summary'), findsOneWidget);
    expect(
      find.textContaining('M37 audit/privacy controls: defined'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Explicit payload export required: true'),
      findsOneWidget,
    );
    expect(find.textContaining('Redacts: secrets, api_keys'), findsOneWidget);
    expect(
      find.textContaining('M38 install/migration guardrails: ready'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Old helper action requests blocked: true'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'release_artifact, canary_history, manual_tcc, desktop_action_canary, llm_canary',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('User-operated: manual_tcc, desktop_action_canary'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Optional review evidence: m15_llm_review_canary, m16_approval_packet, m17_execution_rehearsal, m18_execution_handoff, m20_execution_result_intake, m22_post_action_review',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('m36_live_llm_eval'), findsNWidgets(2));
    expect(
      find.textContaining('m46_element_grounded_llm_eval'),
      findsNWidgets(2),
    );
    expect(find.textContaining('m47_real_app_observe_pilot'), findsNWidgets(2));
    expect(
      find.textContaining('m48_user_operated_action_pilot'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('m49_privacy_audit_release_pack'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining(
        'Report-only preflight: bash tool/run_macos_computer_use_mvp_readiness_preflight.sh',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M31 next-step navigator: dart run tool/macos_computer_use_next_step_navigator.dart',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M33 release packaging: bash tool/run_macos_computer_use_release_packaging.sh',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'macOS Spaces canary handoff: bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window --switch-space-next --release-helper-signoff --handoff-only',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'macOS Spaces canary command: bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window --switch-space-next --release-helper-signoff',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('M35 production action policy: defined'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'observe > approval_packet > action_time_confirmation > emergency_stop_available > execution_result_intake > post_action_review',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M15 LLM review command: bash tool/run_macos_computer_use_m15_llm_review_canary.sh --handoff <action_proposal_handoff.json>',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M16 approval packet command: bash tool/run_macos_computer_use_m16_approval_packet.sh --m15-handoff <action_proposal_handoff.json> --m15-llm-review <canary_summary.json>',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M17 execution rehearsal command: bash tool/run_macos_computer_use_m17_execution_rehearsal.sh --m16-packet <approval_packet.json>',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M18 execution handoff command: bash tool/run_macos_computer_use_m18_execution_handoff.sh --m17-rehearsal <execution_rehearsal.json>',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M20 execution result intake command: bash tool/run_macos_computer_use_m20_execution_result_intake.sh --m18-handoff <execution_handoff.json>',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M22 post-action review command: bash tool/run_macos_computer_use_m22_post_action_review.sh --m20-intake <execution_result_intake.json>',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('release_artifact: Refresh safe release inputs'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'canary_history: Run the automation-safe Computer Use canary',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'manual_tcc: Run `bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only` first',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'desktop_action_canary: Run `bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target --handoff-only` first',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'llm_canary: Run `bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh`, run `bash tool/run_macos_computer_use_real_app_observe_canary.sh`',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'dart run tool/macos_computer_use_readiness_artifact_index.dart --root build/integration_test_reports',
      ),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('run_macos_computer_use_mvp_signoff.sh'),
      findsOneWidget,
    );
    expect(find.textContaining('--final-signoff'), findsOneWidget);
    expect(find.textContaining('--manual-tcc-report'), findsNWidgets(2));
    expect(
      find.textContaining('--desktop-action-canary-summary'),
      findsOneWidget,
    );
    expect(find.textContaining('--llm-canary-summary'), findsOneWidget);
    expect(
      find.textContaining(
        'Required inputs: manual TCC manual_tcc_report_summary.json, desktop action canary_summary.json, and MVP fixture LLM canary_summary.json',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('run_macos_computer_use_manual_tcc_signoff.sh'),
      findsNWidgets(3),
    );
    expect(
      find.textContaining(
        'run_macos_computer_use_desktop_action_canary.sh --fixture-target',
      ),
      findsNWidgets(2),
    );
    expect(
      find.textContaining(
        'macOS Spaces preview: bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window --switch-space-next --release-helper-signoff --handoff-only',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_mvp_handoff.md'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('macos_computer_use_mvp_readiness.json'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('macos_computer_use_mvp_readiness.md'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('MVP readiness JSON (final sign-off output):'),
      findsOneWidget,
    );
    expect(
      find.textContaining('MVP readiness Markdown (final sign-off output):'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_readiness_artifact_index.json'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_readiness_artifact_index.md'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('macos_computer_use_next_step_navigator.json'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_next_step_navigator.md'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'macos_computer_use_next_step_navigator_automation_safe.json',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'macos_computer_use_next_step_navigator_automation_safe.md',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_release_packaging.json'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('macos_computer_use_release_packaging.md'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_release_readiness_ci.md'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('macos_computer_use_release_readiness_signoff.md'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('macos_computer_use_mvp_fixture_llm_canary_'),
      findsOneWidget,
    );
    expect(find.textContaining('MVP fixture LLM summary:'), findsOneWidget);
    expect(
      find.textContaining('macos_computer_use_spaces_canary_'),
      findsOneWidget,
    );
    expect(find.textContaining('macOS Spaces summary:'), findsOneWidget);
    expect(
      find.textContaining('macos_computer_use_m15_action_proposal_handoff_'),
      findsOneWidget,
    );
    expect(find.textContaining('M15 action proposal handoff:'), findsOneWidget);
    expect(
      find.textContaining('action_proposal_handoff.json'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('macos_computer_use_m15_llm_review_canary_'),
      findsOneWidget,
    );
    expect(find.textContaining('M15 LLM review summary:'), findsOneWidget);
    expect(
      find.textContaining('macos_computer_use_m16_approval_packet_'),
      findsOneWidget,
    );
    expect(find.textContaining('M16 approval packet:'), findsOneWidget);
    expect(find.textContaining('approval_packet.json'), findsNWidgets(2));
    expect(
      find.textContaining('macos_computer_use_m17_execution_rehearsal_'),
      findsOneWidget,
    );
    expect(find.textContaining('M17 execution rehearsal:'), findsOneWidget);
    expect(find.textContaining('execution_rehearsal.json'), findsNWidgets(2));
    expect(
      find.textContaining('macos_computer_use_m18_execution_handoff_'),
      findsOneWidget,
    );
    expect(find.textContaining('M18 execution handoff:'), findsOneWidget);
    expect(find.textContaining('execution_handoff.json'), findsNWidgets(2));
    expect(
      find.textContaining('macos_computer_use_m20_execution_result_intake_'),
      findsOneWidget,
    );
    expect(find.textContaining('M20 execution result intake:'), findsOneWidget);
    expect(
      find.textContaining('execution_result_intake.json'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('macos_computer_use_m22_post_action_review_'),
      findsOneWidget,
    );
    expect(find.textContaining('M22 post-action review:'), findsOneWidget);
    expect(find.textContaining('post_action_review.json'), findsOneWidget);
    expect(
      find.textContaining('macos_computer_use_m30_observe_result_intake_'),
      findsOneWidget,
    );
    expect(find.textContaining('M30 observe result intake:'), findsOneWidget);
    expect(
      find.textContaining('M30 observe result intake command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M30 returns ready observe evidence to the M15 action proposal handoff',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('M36 Live LLM eval command:'), findsOneWidget);
    expect(
      find.textContaining('M46 element-grounded LLM eval command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M47 real-app observe pilot command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M48 user-operated action pilot command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M49 privacy and audit release pack command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M50 signed beta gate command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M51 production launch gate command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M52 product release rollout command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M53 post-release guardrails command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M54 rollout expansion gate command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M55 post-expansion monitoring gate command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M56 rollout decision handoff gate command:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m36_live_llm_eval_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m46_element_grounded_llm_eval_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m47_real_app_observe_pilot_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m48_user_operated_action_pilot_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m49_privacy_audit_release_pack_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m50_signed_beta_gate_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m51_production_launch_gate_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m52_product_release_rollout_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m53_post_release_guardrails_'),
      findsOneWidget,
    );
    expect(
      find.textContaining('macos_computer_use_m54_rollout_expansion_gate_'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'macos_computer_use_m55_post_expansion_monitoring_gate_',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'macos_computer_use_m56_rollout_decision_handoff_gate_',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('M36 Live LLM eval summary:'), findsOneWidget);
    expect(
      find.textContaining('M46 element-grounded LLM eval summary:'),
      findsOneWidget,
    );
    expect(find.textContaining('M47 real-app observe pilot:'), findsOneWidget);
    expect(
      find.textContaining('M48 user-operated action pilot:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M49 privacy and audit release pack:'),
      findsOneWidget,
    );
    expect(find.textContaining('M50 signed beta gate:'), findsOneWidget);
    expect(find.textContaining('M51 production launch gate:'), findsOneWidget);
    expect(find.textContaining('M52 product release rollout:'), findsOneWidget);
    expect(find.textContaining('M53 post-release guardrails:'), findsOneWidget);
    expect(find.textContaining('M54 rollout expansion gate:'), findsOneWidget);
    expect(
      find.textContaining('M55 post-expansion monitoring gate:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('M56 rollout decision handoff gate:'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'M23-M29 restart artifact paths are listed by the artifact index',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('observe_result_intake.json'), findsOneWidget);
    expect(
      find.textContaining(
        'Review `PR Review Summary` in `macos_computer_use_mvp_handoff.md`',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '`macos_computer_use_readiness_artifact_index.md` before PR review',
      ),
      findsNothing,
    );
    expect(
      find.textContaining(
        '`macos_computer_use_release_readiness_ci.md`, and `macos_computer_use_release_readiness_signoff.md` before PR review',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'After final sign-off aggregation, inspect `macos_computer_use_mvp_readiness.json` and `macos_computer_use_mvp_readiness.md`.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'ready artifacts, missing evidence, user-operated blockers',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M15 action-proposal review evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M15 LLM review evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M16 approval packet evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M17 execution rehearsal evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M18 execution handoff evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M20 execution result intake evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M22 post-action review evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M23 cycle outcome evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M25 next-cycle seed evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M26 observe restart evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M27 screenshot request evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M28 screenshot evidence intake'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M29 observe run packet evidence'),
      findsOneWidget,
    );
    expect(
      find.textContaining('blocked M30 observe result intake evidence'),
      findsOneWidget,
    );
    expect(find.textContaining('M15 review/gate consistency'), findsOneWidget);
    expect(
      find.textContaining('manual_tcc_report_summary.json'),
      findsNWidgets(3),
    );
    expect(find.textContaining('canary_summary.json'), findsNWidgets(4));
    expect(
      find.textContaining('/tmp/caverno-macos-computer-use-smoke.json'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Grant Screen & System Audio Recording to Caverno Computer Use',
      ),
      findsOneWidget,
    );
    expect(find.text('XPC Production Ready'), findsOneWidget);
    expect(find.text('XPC is production ready.'), findsOneWidget);
  });

  testWidgets('shows manual TCC handoff from the latest smoke report', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Manual TCC Handoff'), findsOneWidget);
    expect(
      find.textContaining(
        'manual_required | bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('--m8-runtime-signoff', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'tool/macos_computer_use_manual_tcc_report.dart',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows the manual boundary before smoke sequence actions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _scrollUntilVisible(tester, find.text('Manual Smoke Boundary'));

    expect(find.text('Manual Smoke Boundary'), findsOneWidget);
    expect(
      find.text(
        'Run Smoke Sequence uses the permissions already granted to Caverno Computer Use. TCC grants and desktop actions stay user-operated; input and audio checks run only after explicit arming.',
      ),
      findsOneWidget,
    );
    expect(find.text('Run Smoke Sequence'), findsOneWidget);
  });

  testWidgets('shows helper path mismatch next action', (tester) async {
    final service = _FakeMacosComputerUseService(helperPathMismatch: true);
    await _pumpPage(tester, service);

    expect(find.text('Helper Path Mismatch'), findsOneWidget);
    expect(
      find.textContaining(
        'Next: Keep using the currently granted helper for this session',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Sign-off: blocked until helper path matches'),
      findsOneWidget,
    );
  });

  testWidgets('shows overlay canary summary from the latest smoke report', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    expect(find.text('Overlay Canary'), findsOneWidget);
    expect(
      find.textContaining('foreground accessory_overlay_front'),
      findsOneWidget,
    );
    expect(find.textContaining('floating true'), findsOneWidget);
    expect(find.textContaining('hides false'), findsOneWidget);
  });

  testWidgets('refreshes permission and audio recording state', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Refresh');

    expect(find.text('Granted'), findsNWidgets(2));
    expect(find.text('Reachable'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget);
    expect(
      find.text('Action required: Screen & System Audio Recording'),
      findsOneWidget,
    );

    await _tapSwitch(tester, 'System Audio Armed');
    await _tapButton(tester, 'Start Recording');

    expect(find.text('Recording active'), findsOneWidget);
    expect(service.startAudioCallCount, 1);

    await _tapButton(tester, 'Stop Recording');

    expect(find.text('Not recording'), findsOneWidget);
    expect(service.stopAudioCallCount, 1);
  });

  testWidgets('failed audio start disarms without entering recording state', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(startAudioSucceeds: false);
    await _pumpPage(tester, service);

    await _tapSwitch(tester, 'System Audio Armed');
    await _tapButton(tester, 'Start Recording');

    expect(service.startAudioCallCount, 1);
    expect(find.text('Not recording'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('System Audio Armed'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(switchTile.value, isFalse);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start Recording'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('pings and stops helper work from the permission panel', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Ping Helper');
    await _tapButton(tester, 'Stop Helper Work');

    expect(service.pingHelperCallCount, 2);
    expect(service.stopHelperWorkCallCount, 1);
  });

  testWidgets('launches helper and refreshes split permissions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Launch Helper');

    expect(service.launchHelperCallCount, 1);
    expect(service.helperStatusCallCount, 2);
    expect(service.pingHelperCallCount, 3);
    expect(service.getPermissionsCallCount, 1);
  });

  testWidgets('restarts helper and waits for IPC readiness', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Restart Helper');

    expect(service.restartHelperCallCount, 1);
    expect(service.helperStatusCallCount, 2);
    expect(service.pingHelperCallCount, 3);
    expect(service.getPermissionsCallCount, 1);
  });

  testWidgets('opens macOS permission settings shortcuts', (tester) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Open Accessibility Settings');
    await _tapButton(tester, 'Open Screen Recording Settings');

    expect(service.openedSettingsSections, [
      'accessibility',
      'screen_recording',
    ]);
  });

  testWidgets('uses display preview taps for move pointer arguments', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'Capture Display');
    await _tapPreview(tester, 'computer-use-display-preview-tap-area');
    await _tapSwitch(tester, 'Input Events Armed');
    await _tapButton(tester, 'Move Pointer');

    expect(service.lastMoveArguments, isNotNull);
    expect(service.lastMoveArguments, containsPair('x', 1.0));
    expect(service.lastMoveArguments, containsPair('y', 1.0));
    expect(service.lastMoveArguments, containsPair('source_width', 1));
    expect(service.lastMoveArguments, containsPair('source_height', 1));
    expect(service.lastMoveArguments!.containsKey('window_id'), isFalse);
  });

  testWidgets('normalizes display screenshot max-width arguments', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    final field = find.widgetWithText(TextField, 'Max image width');
    for (final value in const ['640', '', 'invalid', '0', '-1']) {
      await _scrollUntilVisible(tester, field);
      await tester.enterText(field, value);
      await _tapButton(tester, 'Capture Display');
    }

    expect(
      service.screenshotArguments.map((arguments) => arguments['max_width']),
      [640, 1200, 1200, 1200, 1200],
    );
  });

  testWidgets('rejects blank text without disarming input actions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    final field = find.widgetWithText(TextField, 'Text to type');
    await _scrollUntilVisible(tester, field);
    await tester.enterText(field, '   ');
    await _tapSwitch(tester, 'Input Events Armed');
    await _tapButton(tester, 'Type Text');

    expect(service.lastTypeTextArguments, isNull);
    expect(find.text('Enter text before running Type Text.'), findsOneWidget);
    final switchTile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('Input Events Armed'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(switchTile.value, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Type Text'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('forwards original text and disarms after an attempted action', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    final field = find.widgetWithText(TextField, 'Text to type');
    await _scrollUntilVisible(tester, field);
    await tester.enterText(field, '  Caverno  ');
    await _tapSwitch(tester, 'Input Events Armed');
    await _tapButton(tester, 'Type Text');

    expect(service.lastTypeTextArguments, {'text': '  Caverno  '});
    final switchTile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('Input Events Armed'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(switchTile.value, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Type Text'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('uses selected window preview taps for click arguments', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'List Windows');
    expect(find.text('Terminal - Shell (#42)'), findsOneWidget);

    await _tapButton(tester, 'Capture Selected');
    await _tapPreview(tester, 'computer-use-window-preview-tap-area');
    await _tapSwitch(tester, 'Input Events Armed');
    await _tapButton(tester, 'Click Point');

    expect(
      service.lastWindowScreenshotArguments,
      containsPair('window_id', 42),
    );
    expect(service.lastClickArguments, isNotNull);
    expect(service.lastClickArguments, containsPair('window_id', 42));
    expect(service.lastClickArguments, containsPair('x', 1.0));
    expect(service.lastClickArguments, containsPair('y', 1.0));
    expect(service.lastClickArguments, containsPair('source_width', 1));
    expect(service.lastClickArguments, containsPair('source_height', 1));
    expect(service.lastClickArguments, containsPair('button', 'left'));
    expect(service.lastClickArguments, containsPair('click_count', 1));
  });

  testWidgets('lists, focuses, and switches selected windows safely', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapButton(tester, 'List Windows');
    expect(service.lastListWindowsArguments, {
      'include_current_app': true,
      'max_windows': 80,
    });
    expect(find.text('Terminal - Shell (#42)'), findsOneWidget);
    expect(
      find.text('Bounds: x=10, y=20, width=800, height=600'),
      findsOneWidget,
    );

    await _tapButton(tester, 'Focus Selected');
    expect(service.lastFocusWindowArguments, {
      'window_id': 42,
      'reason': 'Debug smoke test',
    });
    await _tapButton(tester, 'Capture Selected');
    expect(
      find.byKey(const ValueKey('computer-use-window-preview')),
      findsOneWidget,
    );

    final dropdownFinder = find.byType(DropdownButtonFormField<int>);
    await _scrollUntilVisible(tester, dropdownFinder);
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      dropdownFinder,
    );
    dropdown.onChanged!(43);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('computer-use-window-preview')),
      findsNothing,
    );
    await _scrollUntilVisible(tester, find.text('Active source: none'));
    expect(find.text('Active source: none'), findsOneWidget);

    await _tapButton(tester, 'Focus Selected');
    expect(service.lastFocusWindowArguments?['window_id'], 43);
    await _tapButton(tester, 'Capture Selected');
    expect(service.lastWindowScreenshotArguments?['window_id'], 43);
    expect(find.textContaining('Safari - Docs (1x1'), findsOneWidget);

    final selectedBrowserDropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byType(DropdownButtonFormField<int>),
    );
    selectedBrowserDropdown.onChanged!(43);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('computer-use-window-preview')),
      findsOneWidget,
    );
  });

  testWidgets('runs smoke sequence without unsafe armed actions', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapByKey(tester, 'computer-use-run-smoke-sequence');

    expect(service.launchHelperCallCount, 1);
    expect(service.pingHelperCallCount, 2);
    expect(service.getPermissionsCallCount, 1);
    expect(service.screenshotCallCount, 1);
    expect(service.listWindowsCallCount, 1);
    expect(
      service.lastWindowScreenshotArguments,
      containsPair('window_id', 42),
    );
    expect(service.lastMoveArguments, isNull);
    expect(service.startAudioCallCount, 0);
    expect(service.stopAudioCallCount, 0);
    await _scrollUntilVisible(tester, find.text('Last Native Result'));
    expect(
      find.textContaining('Input events were not armed.', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'System audio recording was not armed.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('runs armed input and audio during smoke sequence', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);

    await _tapSwitch(tester, 'Input Events Armed');
    await _tapSwitch(tester, 'System Audio Armed');
    await _tapByKey(
      tester,
      'computer-use-run-smoke-sequence',
      wait: const Duration(milliseconds: 500),
    );

    expect(service.lastMoveArguments, containsPair('window_id', 42));
    expect(service.lastMoveArguments, containsPair('source_width', 1));
    expect(service.lastMoveArguments, containsPair('source_height', 1));
    expect(service.startAudioCallCount, 1);
    expect(service.stopAudioCallCount, 1);
  });

  testWidgets('always attempts to stop audio during armed smoke sequence', (
    tester,
  ) async {
    final service = _FakeMacosComputerUseService(startAudioSucceeds: false);
    await _pumpPage(tester, service);

    await _tapSwitch(tester, 'System Audio Armed');
    await _tapByKey(
      tester,
      'computer-use-run-smoke-sequence',
      wait: const Duration(milliseconds: 500),
    );

    expect(service.startAudioCallCount, 1);
    expect(service.stopAudioCallCount, 1);
    await _scrollUntilVisible(tester, find.text('Last Native Result'));
    expect(
      find.textContaining('"stopAttempted": true', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('copies and exports redacted diagnostics', (tester) async {
    final service = _FakeMacosComputerUseService();
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpPage(tester, service);
    await _tapButton(tester, 'Capture Display');
    await _tapByKey(tester, 'computer-use-copy-diagnostics');

    final clipboardCall = platformCalls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    final arguments = clipboardCall.arguments as Map<Object?, Object?>;
    final text = arguments['text'] as String;

    expect(text, contains('"schemaName": "macos_computer_use_onboarding"'));
    expect(text, contains('"schemaVersion": 1'));
    expect(text, contains('"coordinateTarget": "display"'));
    expect(text, contains('"setupChecklist"'));
    expect(text, contains('"onboardingSmokeChecklist"'));
    expect(text, contains('"operationBoundary"'));
    expect(text, contains('"tccGrants": "user_operated"'));
    expect(text, contains('"desktopActions": "user_operated"'));
    expect(text, contains('"inputSmokeRequiresArming": true'));
    expect(text, contains('"systemAudioSmokeRequiresArming": true'));
    expect(text, contains('"id": "capture_display"'));
    expect(text, contains('"id": "run_smoke_sequence"'));
    expect(text, contains('"id": "run_input_smoke"'));
    expect(text, contains('"id": "run_audio_smoke"'));
    expect(text, contains('"manualSmokeSteps"'));
    expect(text, contains('"helperIpcProtocol"'));
    expect(text, contains('"preferredTransport": "xpc_service"'));
    expect(text, contains('"xpcReady": true'));
    expect(text, contains('"xpcProductionReady": true'));
    expect(text, contains('"xpcStatus": "production"'));
    expect(text, contains('"migratedCommands"'));
    expect(text, contains('"command": "startSystemAudioRecording"'));
    expect(text, contains('"helperStatus"'));
    expect(text, contains('"helperStatusPersistence"'));
    expect(text, contains('"xpcTimingReport"'));
    expect(
      text,
      contains('"schemaName": "macos_computer_use_xpc_timing_report_summary"'),
    );
    expect(text, contains('"auditLog"'));
    expect(text, contains('"auditPrivacyControls"'));
    expect(
      text,
      contains('"schemaName": "macos_computer_use_audit_privacy_controls"'),
    );
    expect(text, contains('"m37AuditPrivacyGate"'));
    expect(text, contains('"explicitPayloadExportRequired": true'));
    expect(text, contains('"lastLiveSmokeReport"'));
    expect(text, contains('"targetHelperName": "Caverno Computer Use"'));
    expect(text, contains('"displayScreenshot"'));
    expect(text, isNot(contains(_png1x1Base64)));

    await _pumpPage(tester, service);
    await _tapByKey(tester, 'computer-use-export-diagnostics');

    expect(
      find.textContaining('Last export:', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('shows recent audit entries in the diagnostics card', (
    tester,
  ) async {
    MacosComputerUseAuditLog.instance.record(
      toolName: 'computer_list_windows',
      policy: MacosComputerUseToolPolicy.decision('computer_list_windows'),
      approvalResult: 'not_required',
      success: true,
      result: '{"selectedIpcTransport":"xpc_service","code":"ok"}',
    );
    MacosComputerUseAuditLog.instance.record(
      toolName: 'computer_click',
      policy: MacosComputerUseToolPolicy.decision('computer_click'),
      approvalResult: 'approved',
      success: false,
      result:
          '{"selectedIpcTransport":"distributed_notification_center","preferredIpcTransport":"xpc_service","fallbackIpcTransport":"distributed_notification_center","preferredIpcAttempt":{"status":"xpc_timeout","errorCode":"helper_xpc_timeout"},"code":"click_failed"}',
      postActionObservation: const MacosComputerUsePostActionObservation(
        toolName: 'computer_screenshot',
        success: false,
        errorCode: 'screen_capture_denied',
      ),
    );

    final service = _FakeMacosComputerUseService();
    await _pumpPage(tester, service);
    await _scrollUntilVisible(tester, find.text('Recent audit entries'));

    expect(find.text('Recent audit entries'), findsOneWidget);
    expect(find.text('computer_list_windows'), findsOneWidget);
    expect(find.text('not_required • observe'), findsOneWidget);
    expect(find.text('computer_click'), findsOneWidget);
    expect(find.text('approved • input'), findsOneWidget);
    expect(
      find.text(
        'Transport: distributed_notification_center • Response: click_failed',
      ),
      findsOneWidget,
    );
    expect(find.text('Policy: observation'), findsOneWidget);
    expect(
      find.text('Policy: pointer_input • Requires: approval, arming'),
      findsOneWidget,
    );
    expect(
      find.text('Fallback: xpc_timeout (helper_xpc_timeout)'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Post-action observation: failed (computer_screenshot, screen_capture_denied)',
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeMacosComputerUseService service,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 3200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [macosComputerUseServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: ComputerUseDebugPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label);
  await _scrollUntilVisible(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapByKey(
  WidgetTester tester,
  String key, {
  Duration wait = const Duration(milliseconds: 100),
}) async {
  final finder = find.byKey(ValueKey(key));
  await _scrollUntilVisible(tester, finder);
  final widget = tester.widget(finder);
  if (widget is FilledButton) {
    expect(widget.onPressed, isNotNull);
    await tester.runAsync(() async {
      widget.onPressed!();
      await Future<void>.delayed(wait);
    });
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapSwitch(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await _scrollUntilVisible(tester, finder);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _tapPreview(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _scrollUntilVisible(tester, finder);
  await tester.tapAt(tester.getCenter(finder));
  await tester.pumpAndSettle();
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  if (!tester.any(finder)) {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

class _FakeMacosComputerUseService extends MacosComputerUseService {
  _FakeMacosComputerUseService({
    this.startAudioSucceeds = true,
    this.helperPathMismatch = false,
  });

  final bool startAudioSucceeds;
  final bool helperPathMismatch;

  int helperStatusCallCount = 0;
  int launchHelperCallCount = 0;
  int restartHelperCallCount = 0;
  int pingHelperCallCount = 0;
  int stopHelperWorkCallCount = 0;
  int getPermissionsCallCount = 0;
  int screenshotCallCount = 0;
  final List<Map<String, dynamic>> screenshotArguments = [];
  int listWindowsCallCount = 0;
  int startAudioCallCount = 0;
  int stopAudioCallCount = 0;
  final List<String> openedSettingsSections = [];
  Map<String, dynamic>? lastMoveArguments;
  Map<String, dynamic>? lastClickArguments;
  Map<String, dynamic>? lastTypeTextArguments;
  Map<String, dynamic>? lastListWindowsArguments;
  Map<String, dynamic>? lastFocusWindowArguments;
  Map<String, dynamic>? lastWindowScreenshotArguments;

  @override
  bool get isAvailable => true;

  @override
  Future<String> getHelperStatus() async {
    helperStatusCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperDisplayName': 'Caverno Computer Use',
      'helperBundleIdentifier': 'com.noguwo.apps.caverno.computer-use',
      'helperInstalled': true,
      'helperRunning': true,
      'helperPath':
          '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'embeddedHelperPath':
          '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'runningHelperPath': helperPathMismatch
          ? '/Users/noguwo/Documents/Workspace/Flutter/caverno-worktrees/macos-computer-use/build/macos/Build/Products/Debug/Caverno Computer Use.app'
          : '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
      'helperPathMatchesRunningHelper': !helperPathMismatch,
      'helperPathMismatch': helperPathMismatch,
      if (helperPathMismatch)
        'helperPathMismatchDetails': {
          'expectedHelperPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          'runningHelperPath':
              '/Users/noguwo/Documents/Workspace/Flutter/caverno-worktrees/macos-computer-use/build/macos/Build/Products/Debug/Caverno Computer Use.app',
          'nextAction':
              'Keep using the currently granted helper for this session, then restart from the installed Caverno bundle before release sign-off.',
        },
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> launchHelper() async {
    launchHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperInstalled': true,
      'helperRunning': true,
      'launched': true,
    });
  }

  @override
  Future<String> restartHelper() async {
    restartHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperInstalled': true,
      'helperRunning': true,
      'restarted': true,
    });
  }

  @override
  Future<String> getPermissions() async {
    getPermissionsCallCount += 1;
    return _json({
      'backend': 'helper',
      'helperReachable': true,
      'accessibilityGranted': true,
      'screenCaptureGranted': false,
      'systemAudioRecordingSupported': true,
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> pingHelper() async {
    pingHelperCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperReachable': true,
      'message': 'pong',
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    openedSettingsSections.add(section);
    return _json({'ok': true, 'section': section});
  }

  @override
  Future<String> stopHelperWork() async {
    stopHelperWorkCallCount += 1;
    return _json({
      'ok': true,
      'backend': 'helper',
      'helperStatusPersistence': _persistence,
    });
  }

  @override
  Future<String> getLastLiveSmokeReport() async {
    return _json({
      'ok': true,
      'path': '/tmp/caverno-macos-computer-use-smoke.json',
      'report': {
        'ok': true,
        'coreOk': true,
        'captureOk': false,
        'generatedAt': '2026-04-25T12:01:00Z',
        'manualTccHandoff': {
          'status': 'manual_required',
          'handoffCommand':
              'bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only',
          'manualCommand':
              'bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m8-runtime-signoff',
          'summaryCommand':
              'dart run tool/macos_computer_use_manual_tcc_report.dart <user-produced-m8-report-or-summary.json>',
          'helperPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
        },
        'overlaySmoke': {
          'status': 'ready',
          'accessibility': {
            'status': 'ready',
            'overlayForegroundPolicy': 'accessory_overlay_front',
            'overlayIsFloatingPanel': true,
            'overlayHidesOnDeactivate': false,
          },
          'screenRecording': {
            'status': 'ready',
            'overlayForegroundPolicy': 'accessory_overlay_front',
            'overlayIsFloatingPanel': true,
            'overlayHidesOnDeactivate': false,
          },
          'blockers': <String>[],
        },
      },
    });
  }

  @override
  Future<String> getLastExistingHelperProbeReport() async {
    return _json({
      'ok': true,
      'path': '/tmp/caverno-macos-computer-use-existing-helper-probe.json',
      'report': {
        'ok': true,
        'noRebuild': true,
        'captureReady': true,
        'inputReady': true,
        'helperPathMatchesExpected': true,
        'failedRequiredChecks': <String>[],
        'helper': {
          'expectedPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          'runningPath':
              '/Applications/Caverno.app/Contents/Helpers/Caverno Computer Use.app',
          'pathMatchesExpected': true,
        },
      },
    });
  }

  Map<String, dynamic> get _persistence => {
    'updatedAt': '2026-04-25T12:00:30Z',
    'activeWork': {'systemAudioRecording': false},
  };

  @override
  Future<String> screenshot(Map<String, dynamic> arguments) async {
    screenshotCallCount += 1;
    screenshotArguments.add(Map<String, dynamic>.from(arguments));
    return _imageResult(title: 'Display');
  }

  @override
  Future<String> listWindows(Map<String, dynamic> arguments) async {
    listWindowsCallCount += 1;
    lastListWindowsArguments = Map<String, dynamic>.from(arguments);
    return _json({
      'windows': [
        {
          'windowId': 42,
          'ownerPid': 100,
          'appName': 'Terminal',
          'title': 'Shell',
          'bounds': {'x': 10, 'y': 20, 'width': 800, 'height': 600},
          'layer': 0,
          'alpha': 1,
          'isOnScreen': true,
        },
        {
          'windowId': 43,
          'ownerPid': 101,
          'appName': 'Safari',
          'title': 'Docs',
          'bounds': {'x': 30, 'y': 40, 'width': 900, 'height': 700},
          'layer': 0,
          'alpha': 1,
          'isOnScreen': true,
        },
      ],
      'count': 2,
      'coordinateSpace': 'window_pixels',
      'inputOrigin': 'top_left',
    });
  }

  @override
  Future<String> focusWindow(Map<String, dynamic> arguments) async {
    lastFocusWindowArguments = Map<String, dynamic>.from(arguments);
    return _json({'ok': true});
  }

  @override
  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    lastWindowScreenshotArguments = Map<String, dynamic>.from(arguments);
    final isBrowser = arguments['window_id'] == 43;
    return _imageResult(
      title: isBrowser ? 'Docs' : 'Shell',
      extra: {
        'windowId': isBrowser ? 43 : 42,
        'ownerPid': isBrowser ? 101 : 100,
        'appName': isBrowser ? 'Safari' : 'Terminal',
        'windowBounds': isBrowser
            ? {'x': 30, 'y': 40, 'width': 900, 'height': 700}
            : {'x': 10, 'y': 20, 'width': 800, 'height': 600},
      },
    );
  }

  @override
  Future<String> moveMouse(Map<String, dynamic> arguments) async {
    lastMoveArguments = Map<String, dynamic>.from(arguments);
    return _json({'ok': true});
  }

  @override
  Future<String> click(Map<String, dynamic> arguments) async {
    lastClickArguments = Map<String, dynamic>.from(arguments);
    return _json({'ok': true});
  }

  @override
  Future<String> typeText(Map<String, dynamic> arguments) async {
    lastTypeTextArguments = Map<String, dynamic>.from(arguments);
    return _json({'ok': true});
  }

  @override
  Future<String> startSystemAudioRecording(
    Map<String, dynamic> arguments,
  ) async {
    startAudioCallCount += 1;
    return _json({
      'ok': startAudioSucceeds,
      if (startAudioSucceeds) 'path': '/tmp/system-audio.caf',
      if (!startAudioSucceeds) 'code': 'system_audio_permission_denied',
    });
  }

  @override
  Future<String> stopSystemAudioRecording() async {
    stopAudioCallCount += 1;
    return _json({'ok': true, 'path': '/tmp/system-audio.caf'});
  }

  String _imageResult({
    required String title,
    Map<String, dynamic> extra = const {},
  }) {
    return _json({
      'imageBase64': _png1x1Base64,
      'imageMimeType': 'image/png',
      'width': 1,
      'height': 1,
      'title': title,
      'coordinateSpace': 'screenshot_pixels',
      'inputOrigin': 'top_left',
      ...extra,
    });
  }
}

String _json(Map<String, dynamic> value) => jsonEncode(value);

const _png1x1Base64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=';
