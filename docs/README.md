# Docs

`docs/` holds **living documents**: material that describes how the project
works today, or how it is meant to work, and that is kept current.

Everything else lives elsewhere:

- [`worklog/`](worklog/README.md) — dated investigations, findings,
  measurements, decisions, inventories and release records. Read-only history;
  nothing there is guaranteed to match the current code.
- Agent task documents (`*_codex_task.md`, `*_task.md`, handoffs) are deleted
  once the task is finished. Git history keeps them. The ones still listed
  below under "Active agent tasks" are in progress.
- [`evidence/`](evidence/), [`releases/`](releases/) and
  [`coding_mvp_fixtures/`](coding_mvp_fixtures/README.md) are data referenced
  by tests and tools.

When adding a document, put it here only if someone will need to keep it
current. A one-off investigation goes to `worklog/` with a date in its name.

## Start here

- [architecture.md](architecture.md) — layering, data flow, tool-calling loop, plan system, session memory
- [roadmap.md](roadmap.md) — cross-track roadmap index
- [roadmap_completed_baselines.md](roadmap_completed_baselines.md) — completed roadmap baselines

## Development policy

- [macos_build_policy.md](macos_build_policy.md) — single canonical worktree for macOS builds
- [lint_policy.md](lint_policy.md) — adopted and rejected lints, `dart fix` rules
- [large_file_refactor_plan.md](large_file_refactor_plan.md) — how to slice a large-file refactor
- [text_heuristic_inventory.md](text_heuristic_inventory.md) — text heuristics and their removal plan
- [codex_task_template.md](codex_task_template.md) — template for agent task documents
- [external_config.md](external_config.md) — external configuration
- [embedded_python.md](embedded_python.md) — Python worker vendoring and `serious_python` setup

## Logs, canaries and diagnostics

- [session_logs.md](session_logs.md) — session log schema, redaction, retention, analysis
- [live_llm_canary_agent_runbook.md](live_llm_canary_agent_runbook.md) — live canary preflight and triage
- [live_llm_canary_coverage.md](live_llm_canary_coverage.md) — live canary surface coverage
- [routine_live_llm_canary.md](routine_live_llm_canary.md) — routine canary
- [firebase_crashlytics.md](firebase_crashlytics.md) — Crashlytics

## Release

- [ios_macos_release.md](ios_macos_release.md) — iOS and macOS release workflow
- [macos_sparkle_s3_updates.md](macos_sparkle_s3_updates.md) — Sparkle updates via CloudFront and S3
- [ios_app_privacy_disclosure.md](ios_app_privacy_disclosure.md) — App Store privacy disclosure

## Chat runtime and coding

- [chat_notifier_architecture_renewal_plan.md](chat_notifier_architecture_renewal_plan.md) — ChatNotifier renewal plan
- [execution_contract_design.md](execution_contract_design.md) — ExecutionContract
- [project_execution_boundary_design.md](project_execution_boundary_design.md) — project execution boundaries
- [evidence_driven_execution_orchestrator_plan.md](evidence_driven_execution_orchestrator_plan.md) — evidence-driven orchestrator
- [component_packaging_architecture.md](component_packaging_architecture.md) — `packages/` boundaries
- [turn_steering_midstream_design.md](turn_steering_midstream_design.md) — mid-stream steering
- [pro_reasoning_chat_mode_design.md](pro_reasoning_chat_mode_design.md) — Pro Reasoning mode (LL40)
- [local_llm_agent_roadmap.md](local_llm_agent_roadmap.md) — local LLM agent roadmap (LL tracks)
- [tools_mvp_roadmap.md](tools_mvp_roadmap.md) — built-in tools roadmap
- [conversation_fork_roadmap.md](conversation_fork_roadmap.md) — conversation fork
- [coding_verification_feedback_plan.md](coding_verification_feedback_plan.md) — test/build verification feedback
- [coding_verification_feedback_release_gate.md](coding_verification_feedback_release_gate.md) — its release gate
- [coding_diagnostic_feedback_release_gate.md](coding_diagnostic_feedback_release_gate.md) — diagnostic feedback release gate
- [coding_goal_composer_release_checklist.md](coding_goal_composer_release_checklist.md) — goal composer release checklist
- [feedback_review_worker.md](feedback_review_worker.md) — feedback review worker
- [codex_developer_efficiency_roadmap.md](codex_developer_efficiency_roadmap.md) — agent developer-efficiency roadmap

## Plan Mode

- [plan_mode_roadmap.md](plan_mode_roadmap.md)
- [plan_mode_mvp_handoff.md](plan_mode_mvp_handoff.md)
- [plan_mode_release_readiness_checklist.md](plan_mode_release_readiness_checklist.md)
- [plan_mode_release_candidate_gate.md](plan_mode_release_candidate_gate.md)
- [plan_mode_scenario_coverage.md](plan_mode_scenario_coverage.md)
- [plan_mode_model_endpoint_compatibility.md](plan_mode_model_endpoint_compatibility.md)
- [plan_mode_live_llm_model_canary_matrix.md](plan_mode_live_llm_model_canary_matrix.md)
- [plan_mode_live_smoke_compatibility_triage.md](plan_mode_live_smoke_compatibility_triage.md)
- [plan_mode_ping_cli_stabilization_playbook.md](plan_mode_ping_cli_stabilization_playbook.md)
- [long_running_process_mvp_tasks.md](long_running_process_mvp_tasks.md)

## Anabasis and Project Farm

- [anabasis_project_vision.md](anabasis_project_vision.md)
- [anabasis_brand_story.md](anabasis_brand_story.md)
- [anabasis_roadmap.md](anabasis_roadmap.md)
- [ANABASIS_ORCHESTRATOR_ARCHITECTURE.md](ANABASIS_ORCHESTRATOR_ARCHITECTURE.md)
- [project_farm_roadmap.md](project_farm_roadmap.md) — read at runtime by the Project Farm roadmap snapshot

## CLI

- [caverno_cli_roadmap.md](caverno_cli_roadmap.md)
- [caverno_cli_terminal_contract.md](caverno_cli_terminal_contract.md)

## Remote Coding and Apple Watch

- [remote_coding_notification_relay_contract.md](remote_coding_notification_relay_contract.md)
- [remote_coding_fcm_release_gate.md](remote_coding_fcm_release_gate.md)
- [remote_coding_p0_release_gate.md](remote_coding_p0_release_gate.md)
- [remote_coding_p1_release_gate.md](remote_coding_p1_release_gate.md)
- [apple_watch_companion.md](apple_watch_companion.md)
- [apple_watch_roadmap.md](apple_watch_roadmap.md)

## macOS Computer Use

- [macos_computer_use_helper_architecture.md](macos_computer_use_helper_architecture.md)
- [macos_computer_use_element_grounding_release_roadmap.md](macos_computer_use_element_grounding_release_roadmap.md)
- [macos_computer_use_mvp_checklist.md](macos_computer_use_mvp_checklist.md)
- [macos_computer_use_manual_process_checklist.md](macos_computer_use_manual_process_checklist.md)
- [macos_computer_use_mvp_fixture_runbook.md](macos_computer_use_mvp_fixture_runbook.md)
- [macos_computer_use_real_app_observe_runbook.md](macos_computer_use_real_app_observe_runbook.md)

## Security

- [sec4_4_write_containment_remainder.md](sec4_4_write_containment_remainder.md)
- [sec4_4i_os_write_containment_plan.md](sec4_4i_os_write_containment_plan.md)

## Knowledge currency and RAG

- [knowledge_currency_track_design.md](knowledge_currency_track_design.md) — KC1–KC5
- [rag1_retrieval_eval_contract.md](rag1_retrieval_eval_contract.md)
- [rag2_knowledge_object_contract_2026-08-25.md](rag2_knowledge_object_contract_2026-08-25.md)
- [rag2_provenance_attestation_contract_2026-08-25.md](rag2_provenance_attestation_contract_2026-08-25.md)
- [rag2_storage_replay_contract_2026-08-26.md](rag2_storage_replay_contract_2026-08-26.md)
- [rag3_post_v3_entry_contract_2026-09-01.md](rag3_post_v3_entry_contract_2026-09-01.md)
- [rag3_support_filter_latency_contract.md](rag3_support_filter_latency_contract.md)

## Pinned in place

These are worklog material, but a frozen fixture under `tool/fixtures/` cites
them by path, so they cannot move.

- [portable_memory_investigation_2026-09-06.md](portable_memory_investigation_2026-09-06.md)
- [rag_groundedness_detector_research_2026-09-01.md](rag_groundedness_detector_research_2026-09-01.md)

## Active agent tasks

Delete each one when its task is finished.

- F5 diagnostic probe extraction: `f5_*_codex_task.md`
- [ll39_multi_round_tool_loop_codex_tasks.md](ll39_multi_round_tool_loop_codex_tasks.md)
- [personal_eval_paired_statistics_codex_tasks.md](personal_eval_paired_statistics_codex_tasks.md) — cited by `tool/personal_eval_corpus/corpus.json`
- [chat_notifier_static_tool_manifest_codex_task.md](chat_notifier_static_tool_manifest_codex_task.md)
- [edit_anchor_recovery_measurement_codex_task.md](edit_anchor_recovery_measurement_codex_task.md)
- [rag2_hosted_passage_role_v2_task.md](rag2_hosted_passage_role_v2_task.md)
- [rag2_hosted_retrieval_eval_task.md](rag2_hosted_retrieval_eval_task.md)
- [sec4_5e_frame_and_rate_limits_task.md](sec4_5e_frame_and_rate_limits_task.md)
