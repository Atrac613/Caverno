import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Plan Mode MVP handoff docs', () {
    test('README links the canonical handoff and PM5 live gate', () {
      final readme = File('README.md').readAsStringSync();

      expect(readme, contains('docs/plan_mode_release_readiness_checklist.md'));
      expect(readme, contains('docs/plan_mode_release_candidate_gate.md'));
      expect(readme, contains('docs/plan_mode_mvp_handoff.md'));
      expect(readme, contains('docs/plan_mode_scenario_coverage.md'));
      expect(
        readme,
        contains('docs/plan_mode_model_endpoint_compatibility.md'),
      );
      expect(readme, contains('docs/plan_mode_release_package_2026-05-13.md'));
      expect(
        readme,
        contains(
          'docs/plan_mode_release_candidate_final_signoff_2026-05-13.md',
        ),
      );
      expect(readme, contains('Plan Mode support snapshot'));
      expect(
        readme,
        contains('docs/plan_mode_post_release_guardrails_2026-05-13.md'),
      );
      expect(readme, contains('tool/run_plan_mode_pm5_live_gate.sh'));
      expect(readme, contains('CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1'));
      expect(readme, contains('CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE=1'));
    });

    test('handoff records readiness signals and review blockers', () {
      final handoff = File('docs/plan_mode_mvp_handoff.md').readAsStringSync();

      expect(handoff, contains('Deterministic status'));
      expect(handoff, contains('Live status'));
      expect(handoff, contains('Warnings: `0` unexpected warnings'));
      expect(handoff, contains('There are no known Plan Mode MVP blockers'));
      expect(handoff, contains('plan_mode_release_readiness_checklist.md'));
      expect(handoff, contains('plan_mode_release_candidate_gate.md'));
      expect(handoff, contains('plan_mode_model_endpoint_compatibility.md'));
      expect(handoff, contains('tool/run_plan_mode_pm5_live_gate.sh'));
    });

    test('release readiness checklist records PM7 decision rules', () {
      final checklist = File(
        'docs/plan_mode_release_readiness_checklist.md',
      ).readAsStringSync();

      expect(checklist, contains('# Plan Mode Release Readiness Checklist'));
      expect(checklist, contains('plan_mode_release_candidate_gate.md'));
      expect(checklist, contains('## Required Command Order'));
      expect(checklist, contains('tool/run_plan_mode_pm5_live_gate.sh'));
      expect(checklist, contains('## External Prerequisites'));
      expect(checklist, contains('plan_mode_model_endpoint_compatibility.md'));
      expect(checklist, contains('## Release Decision Matrix'));
      expect(checklist, contains('## Pass Criteria'));
      expect(checklist, contains('## Warning Criteria'));
      expect(checklist, contains('## Blocker Criteria'));
      expect(checklist, contains('## Failure Triage Order'));
      expect(checklist, contains('Open the latest `canary_summary.md`'));
      expect(checklist, contains('blocked: environment'));
    });

    test('release candidate gate records PM12 sign-off flow', () {
      final gate = File(
        'docs/plan_mode_release_candidate_gate.md',
      ).readAsStringSync();

      expect(gate, contains('# Plan Mode Release Candidate Gate'));
      expect(gate, contains('## Entry Conditions'));
      expect(gate, contains('## Ordered Release Candidate Flow'));
      expect(gate, contains('## Required Artifact Bundle'));
      expect(gate, contains('## Decision Owners'));
      expect(gate, contains('## Exception Rules'));
      expect(gate, contains('## Release Candidate Sign-Off'));
      expect(gate, contains('## Repeatability Check'));
      expect(gate, contains('plan_mode_release_readiness_checklist.md'));
      expect(gate, contains('plan_mode_scenario_coverage.md'));
      expect(gate, contains('plan_mode_model_endpoint_compatibility.md'));
      expect(gate, contains('plan_mode_suite_macos_report.json'));
      expect(gate, contains('CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1'));
      expect(gate, contains('tool/run_plan_mode_pm5_live_gate.sh'));
      expect(gate, contains('live_readme_first_canary'));
      expect(gate, contains('tool/run_plan_mode_convergence_full_pass.sh'));
      expect(gate, contains('manual UX review notes'));
      expect(gate, contains('follow-up milestone or issue'));
    });

    test('stabilization playbook points to the PM5 gate', () {
      final playbook = File(
        'docs/plan_mode_ping_cli_stabilization_playbook.md',
      ).readAsStringSync();

      expect(playbook, contains('Latest validated result: PM5 gate passed'));
      expect(playbook, contains('tool/run_plan_mode_pm5_live_gate.sh'));
      expect(playbook, contains('PM5 Live Gate'));
      expect(playbook, contains('PM5 Gate Failure Triage'));
      expect(playbook, contains('docs/plan_mode_mvp_handoff.md'));
    });

    test('scenario coverage doc records PM10 promotion rules', () {
      final coverage = File(
        'docs/plan_mode_scenario_coverage.md',
      ).readAsStringSync();

      expect(coverage, contains('# Plan Mode Scenario Coverage'));
      expect(coverage, contains('Smoke'));
      expect(coverage, contains('Canary'));
      expect(coverage, contains('Long-run'));
      expect(coverage, contains('live_readme_first_canary'));
      expect(coverage, contains('Not ready for smoke promotion'));
      expect(coverage, contains('Promotion Rules'));
      expect(coverage, contains('three consecutive clean live runs'));
    });

    test('live LLM canary coverage doc records cross-surface gaps', () {
      final coverage = File(
        'docs/live_llm_canary_coverage.md',
      ).readAsStringSync();

      expect(coverage, contains('# Live LLM Canary Coverage'));
      expect(coverage, contains('| Chat |'));
      expect(coverage, contains('tool/run_tool_result_budget_live_canary.sh'));
      expect(coverage, contains('chat_basic_response_live_canary'));
      expect(coverage, contains('| Coding |'));
      expect(coverage, contains('tool/run_plan_mode_pm5_live_gate.sh'));
      expect(coverage, contains('live_readme_first_canary'));
      expect(coverage, contains('| Routines |'));
      expect(coverage, contains('tool/run_routine_live_llm_canary.sh'));
      expect(coverage, contains('routine_lan_no_new_ip_live_canary'));
      expect(coverage, contains('Baseline Model Switch Flow'));
      expect(coverage, contains('three consecutive clean runs'));
    });

    test('compatibility doc records PM11 endpoint and model boundaries', () {
      final compatibility = File(
        'docs/plan_mode_model_endpoint_compatibility.md',
      ).readAsStringSync();

      expect(
        compatibility,
        contains('# Plan Mode Model and Endpoint Compatibility'),
      );
      expect(compatibility, contains('Supported Endpoint Contract'));
      expect(compatibility, contains('Recommended Live Environment'));
      expect(compatibility, contains('Product Settings Preflight'));
      expect(compatibility, contains('Endpoint preflight failed'));
      expect(compatibility, contains('Plan Mode support snapshot'));
      expect(compatibility, contains('Model Behavior Assumptions'));
      expect(compatibility, contains('Risky Model Behaviors'));
      expect(compatibility, contains('Known Limitations'));
      expect(compatibility, contains('Evidence Snapshot'));
      expect(compatibility, contains('blocked: environment'));
      expect(compatibility, contains('CAVERNO_LLM_BASE_URL'));
      expect(compatibility, contains('gemma4-26b-vision'));
      expect(compatibility, contains('qwen3.6-27b-mtp-vision'));
      expect(compatibility, contains('artifact content fit'));
    });

    test('release package records PM18 user-facing release surface', () {
      final releasePackage = File(
        'docs/plan_mode_release_package_2026-05-13.md',
      ).readAsStringSync();

      expect(
        releasePackage,
        contains('# Plan Mode Release Package - 2026-05-13'),
      );
      expect(releasePackage, contains('## Release Notes'));
      expect(releasePackage, contains('## Requirements'));
      expect(releasePackage, contains('## Known Limitations'));
      expect(releasePackage, contains('## Demo And Screenshot Checklist'));
      expect(releasePackage, contains('Plan Mode support snapshot'));
      expect(
        releasePackage,
        contains('docs/plan_mode_supportability_2026-05-13.md'),
      );
      expect(
        releasePackage,
        contains('docs/plan_mode_post_release_guardrails_2026-05-13.md'),
      );
      expect(releasePackage, contains('Settings > General'));
    });

    test('post-release guardrails record PM19 cadence and hotfix rules', () {
      final guardrails = File(
        'docs/plan_mode_post_release_guardrails_2026-05-13.md',
      ).readAsStringSync();

      expect(
        guardrails,
        contains('# Plan Mode Post-Release Guardrails - 2026-05-13'),
      );
      expect(guardrails, contains('## Ownership'));
      expect(guardrails, contains('## Cadence'));
      expect(guardrails, contains('## Regression Checks'));
      expect(guardrails, contains('## Hotfix Rules'));
      expect(guardrails, contains('## Reusing PM12 And PM13'));
      expect(guardrails, contains('blocked: environment'));
      expect(guardrails, contains('Plan Mode support snapshot'));
    });

    test('final release candidate sign-off records PM20 pass decision', () {
      final signoff = File(
        'docs/plan_mode_release_candidate_final_signoff_2026-05-13.md',
      ).readAsStringSync();

      expect(
        signoff,
        contains('# Plan Mode Release Candidate Final Sign-Off - 2026-05-13'),
      );
      expect(signoff, contains('Decision: `pass`'));
      expect(signoff, contains('PM20 refreshes'));
      expect(signoff, contains('PM5 live smoke rerun: passed'));
      expect(signoff, contains('Ping CLI live canary: passed'));
      expect(signoff, contains('Manual product UX review: closed by PM15'));
      expect(signoff, contains('missingExpectedSavedTaskTargetFiles'));
      expect(signoff, contains('plan_mode_live_suite_macos_1778676005689'));
      expect(signoff, contains('plan_mode_ping_cli_canary_1778676312'));
      expect(
        signoff,
        contains('docs/plan_mode_product_ux_finalization_2026-05-13.md'),
      );
      expect(
        signoff,
        contains('docs/plan_mode_post_release_guardrails_2026-05-13.md'),
      );
    });

    test('release candidate sign-off records PM13 execution result', () {
      final signoff = File(
        'docs/plan_mode_release_candidate_signoff_2026-05-13.md',
      ).readAsStringSync();

      expect(
        signoff,
        contains('# Plan Mode Release Candidate Sign-Off - 2026-05-13'),
      );
      expect(signoff, contains('Decision: `blocked: environment`'));
      expect(signoff, contains('plan_mode_model_endpoint_compatibility.md'));
      expect(signoff, contains('plan_mode_suite_macos_report.json'));
      expect(signoff, contains('3 scenarios passed, 0 failed'));
      expect(signoff, contains('fvm flutter analyze'));
      expect(signoff, contains('tool/run_plan_mode_pm5_live_gate.sh'));
      expect(signoff, contains('Failed to connect to 192.168.100.241'));
      expect(signoff, contains('Selected canaries: not run'));
      expect(signoff, contains('Manual UX review: not run'));
      expect(signoff, contains('Rerun PM13 from the start'));
      expect(signoff, contains('## Endpoint Recheck'));
      expect(signoff, contains('HTTP/1.1 200 OK'));
      expect(signoff, contains('gemma4-26b-vision'));
    });

    test('release candidate rerun records PM13 live smoke blocker', () {
      final signoff = File(
        'docs/plan_mode_release_candidate_signoff_2026-05-13_rerun.md',
      ).readAsStringSync();

      expect(
        signoff,
        contains('# Plan Mode Release Candidate Sign-Off - 2026-05-13 Rerun'),
      );
      expect(signoff, contains('Decision: `blocked: environment`'));
      expect(signoff, contains('gemma4-26b-vision'));
      expect(signoff, contains('Preflight result: passed'));
      expect(
        signoff,
        contains('Live smoke result: 2 scenarios passed, 1 failed'),
      );
      expect(signoff, contains('Failure class: `streamDisconnect`'));
      expect(signoff, contains('Unexpected warnings: 5'));
      expect(signoff, contains('Report quality blockers: 7'));
      expect(signoff, contains('Task drift: 1 detected'));
      expect(signoff, contains('Selected canaries: not run'));
      expect(
        signoff,
        contains('Manual UX review: blocked before product sign-off'),
      );
      expect(signoff, contains('plan_mode_live_suite_macos_1778642789942'));
    });

    test('roadmap records productization milestones after PM6', () {
      final roadmap = File('docs/roadmap.md').readAsStringSync();

      expect(roadmap, contains('| Plan Mode | PM7 | done |'));
      expect(roadmap, contains('### PM7: Plan Mode Release Readiness'));
      expect(
        roadmap,
        contains('docs/plan_mode_release_readiness_checklist.md'),
      );
      expect(roadmap, contains('| Plan Mode | PM8 | done |'));
      expect(roadmap, contains('### PM8: Live Gate Failure Operations'));
      expect(roadmap, contains('| Plan Mode | PM9 | done |'));
      expect(roadmap, contains('### PM9: Plan Mode Product UX Polish'));
      expect(roadmap, contains('| Plan Mode | PM10 | done |'));
      expect(
        roadmap,
        contains('### PM10: Plan Mode Scenario Coverage Expansion'),
      );
      expect(roadmap, contains('docs/plan_mode_scenario_coverage.md'));
      expect(roadmap, contains('| Plan Mode | PM11 | done |'));
      expect(roadmap, contains('### PM11: Model and Endpoint Compatibility'));
      expect(
        roadmap,
        contains('docs/plan_mode_model_endpoint_compatibility.md'),
      );
      expect(roadmap, contains('| Plan Mode | PM12 | done |'));
      expect(roadmap, contains('### PM12: Plan Mode Release Candidate Gate'));
      expect(roadmap, contains('docs/plan_mode_release_candidate_gate.md'));
      expect(roadmap, contains('| Plan Mode | PM13 | done |'));
      expect(roadmap, contains('### PM13: Release Candidate Execution'));
      expect(
        roadmap,
        contains('docs/plan_mode_release_candidate_signoff_2026-05-13.md'),
      );
      expect(
        roadmap,
        contains(
          'docs/plan_mode_release_candidate_signoff_2026-05-13_rerun.md',
        ),
      );
      expect(roadmap, contains('blocked: environment'));
      expect(roadmap, contains('gemma4-26b-vision'));
      expect(roadmap, contains('streamDisconnect'));
      expect(roadmap, contains('| Plan Mode | PM14 | done |'));
      expect(roadmap, contains('### PM14: Release Blocker Burn-Down'));
      expect(roadmap, contains('| Plan Mode | PM15 | done |'));
      expect(roadmap, contains('### PM15: Product UX Finalization'));
      expect(
        roadmap,
        contains('docs/plan_mode_product_ux_finalization_2026-05-13.md'),
      );
      expect(roadmap, contains('| Plan Mode | PM16 | done |'));
      expect(roadmap, contains('### PM16: Settings and Compatibility UX'));
      expect(
        roadmap,
        contains('docs/plan_mode_settings_compatibility_ux_2026-05-13.md'),
      );
      expect(roadmap, contains('| Plan Mode | PM17 | done |'));
      expect(roadmap, contains('### PM17: Supportability'));
      expect(roadmap, contains('docs/plan_mode_supportability_2026-05-13.md'));
      expect(roadmap, contains('| Plan Mode | PM18 | done |'));
      expect(roadmap, contains('### PM18: Release Packaging'));
      expect(roadmap, contains('docs/plan_mode_release_package_2026-05-13.md'));
      expect(roadmap, contains('| Plan Mode | PM19 | done |'));
      expect(roadmap, contains('### PM19: Post-Release Guardrails'));
      expect(
        roadmap,
        contains('docs/plan_mode_post_release_guardrails_2026-05-13.md'),
      );
      expect(roadmap, contains('| Plan Mode | PM20 | done |'));
      expect(
        roadmap,
        contains('### PM20: Final Release Candidate Evidence Refresh'),
      );
      expect(
        roadmap,
        contains(
          'docs/plan_mode_release_candidate_final_signoff_2026-05-13.md',
        ),
      );
    });
  });
}
