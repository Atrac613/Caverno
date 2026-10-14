# Model Input Inventory (LL46)

Every request Caverno sends to a model carries a session-log request label
(`request.label`, schema v3+). This inventory has one row per label: who
produces the request, what it adds to the model's input, and whether it keeps
the tool loop's cached prefix. `test/docs/model_input_inventory_docs_test.dart`
fails when a label in `lib/` has no row here.

Scope: requests, keyed by label; guidance written into tool-result
payloads, keyed by producer file; and system-prompt sections, keyed by
section id.

## How to read the columns

- **Shape**: *loop* requests append to the running turn's history and send
  the loop's tool catalog; *separate* requests build their own message list,
  usually with a different system prompt and no tools, so they cannot reuse
  the loop's cached prefix.
- **Measured**: counts, median prompt tokens, and the median size of the last
  user/system message (the injection) across grounded session logs on
  2026-10-14, personal-eval replays excluded. Rerun the measurement before
  relying on a number.
- **Prefix**: whether a schema v6 log (LL43 envelope digests) has shown the
  prefix kept. `unmeasured` means no v6 evidence yet, not a known break.

## Main tool loop

| Label | Producer | Adds | Shape | Measured | Prefix |
|---|---|---|---|---|---|
| `turn opening request` | `chat_notifier.dart` `_sendWithTools` | The user's message | loop | 511 req, ~17.4k tok, ~950 ch | kept (b053bddd, ca7f4499) |
| `tool-result follow-up` | `chat_notifier.dart` tool loop | Tool calls and their results | loop | 5,000 req, ~23.6k tok, ~1.2k ch | kept: 12,288 of 12,756 cached (b053bddd) |
| `content tool-result continuation` | `chat_notifier.dart` content-tool path | Results of tool calls printed in content | loop | not seen | unmeasured |
| `tool-loop exhaustion recovery` | `chat_notifier.dart` loop limit | Instruction to finish after the move budget | loop | 94 req, ~22.8k tok, ~490 ch | unmeasured |
| `duplicate inspection recovery` | `DuplicateRecoveryKind` | Notice that a read repeated, with the earlier result | loop | 69 req, ~26.9k tok, ~390 ch | unmeasured |
| `duplicate follow-up recovery` | `DuplicateRecoveryKind` | Notice that a follow-up repeated | loop | 66 req, ~22.7k tok, ~640 ch | unmeasured |
| `browser-action repair` | `chat_notifier.dart` | Instruction to act on a recovered browser snapshot | loop | not seen | unmeasured |
| `background process monitor feedback` | `chat_notifier.dart` | Running-process state and next check | loop | 1 req, ~22.4k tok, ~1.9k ch | unmeasured |
| `coding verification feedback` | `chat_notifier_coding_verification_feedback.dart` | Verification result to act on | loop | not seen | unmeasured |
| `unexecuted command action retry` | `chat_notifier_unexecuted_action_recovery.dart` | Claimed command with no execution, to run it | loop | 23 req, ~26.5k tok, ~1.4k ch | unmeasured |
| `blocked production release retry` | `chat_notifier_unexecuted_action_recovery.dart` | Blocked release and how to proceed | loop | 1 req, ~23.2k tok | unmeasured |
| `narrated transcript feedback` | `chat_notifier_unexecuted_action_recovery.dart` | Narrated commands that never ran | loop | 5 req, ~26.9k tok, ~1.4k ch | unmeasured |
| `python attachment analysis repair` | `chat_notifier_python_attachment_repair.dart` | Instruction to analyse an attached file with Python | loop | not seen | unmeasured |
| `python attachment path repair` | `chat_notifier_python_attachment_repair.dart` | Corrected attachment path | loop | not seen | unmeasured |

### Coding continuation recovery (`CodingRecoveryText`)

One producer, `coding_continuation_recovery_request.dart`, labelled by
recovery code. Each adds a recovery prompt naming what the previous response
left undone.

| Label | Shape | Measured | Prefix |
|---|---|---|---|
| `structured coding task status recovery` | loop | 81 req, ~18.8k tok, ~870 ch | unmeasured |
| `reasoning-only stop recovery` | loop | 39 req, ~28.0k tok, ~670 ch | unmeasured |
| `project verification repair recovery` | loop | 36 req, ~20.2k tok, ~2.4k ch | unmeasured |
| `structured project subtask recovery` | loop | 30 req, ~30.0k tok, ~1.4k ch | unmeasured |
| `prose-only coding continuation recovery` | loop | 19 req, ~20.3k tok, ~630 ch | unmeasured |
| `length-truncated pending action recovery` | loop | 15 req, ~27.2k tok, ~570 ch | unmeasured |
| `unexecuted delegation recovery` | loop | 1 req, ~9.3k tok, ~520 ch | unmeasured |
| `bracketed coding tool request recovery` | loop | not seen | unmeasured |

## Separate requests

| Label | Producer | Adds | Shape | Measured | Prefix |
|---|---|---|---|---|---|
| `tool-result final answer` | `chat_notifier_final_answer_recovery.dart` | User-role re-send of the tool results (`buildAnswerPrompt`) | separate, no tools | 600 req unlabeled before `fe107074e`; ~3.5k tok in b053bddd | breaks: 0 cached (b053bddd); skipped when the loop's answer is kept |
| `final answer concise retry` | `chat_notifier_final_answer_recovery.dart` | Retry prompt for a truncated or degenerate final answer | separate, no tools | 13 req unlabeled before `fe107074e` | breaks |
| `approval auto-review` | `SecondaryRequestLabel` | Approval review packet (JSON) | separate | 1,161 req unlabeled before `8d450db34` | separate prefix by design |
| `memory extraction` | `SecondaryRequestLabel` | Profile and recent turns | separate | 517 req unlabeled before `8d450db34` | separate prefix by design |
| `planning request` | `SecondaryRequestLabel` | Task or workflow proposal prompt | separate | 44 req unlabeled before `8d450db34` | separate prefix by design |
| `goal suggestion` | `SecondaryRequestLabel` | Conversation summary for a goal suggestion | separate | not seen | separate prefix by design |
| `pro_reasoning_frame` | `pro_reasoning_run_notifier.dart` | Problem framing prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_investigate` | `pro_reasoning_run_notifier.dart` | Investigation prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_candidate` | `pro_reasoning_run_notifier.dart` | Candidate generation prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_critique` | `pro_reasoning_run_notifier.dart` | Critique prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_synthesis` | `pro_reasoning_run_notifier.dart` | Synthesis prompt | separate | not measured | separate prefix by design |
| `pro_reasoning_summary` | `pro_reasoning_run_notifier.dart` | Summary of the run | separate | not measured | separate prefix by design |

## Routines

| Label | Producer | Adds | Shape | Measured | Prefix |
|---|---|---|---|---|---|
| `routine run` | `routine_execution_service.dart` `execute` | Routine prompt, its tool loop and final answer | separate (own session log) | 40 run logs, all schema v2 and unlabeled before this label | unmeasured |
| `routine plan draft` | `routine_execution_service.dart` `generatePlanDraft` | Plan-drafting prompt for a routine | separate | not measured | unmeasured |

## Project farm and worktree agents

Farm requests are labelled with their structured-output schema name, which
names the producer exactly. They log into the turn that started them, or the
`project-farm` session when none is in scope. A worktree agent run logs into
a session of its own, `worktree-agent-<task id>`. Neither reached the session
log before 2026-10-14; counts start from there.

| Label | Producer | Adds | Shape | Measured | Prefix |
|---|---|---|---|---|---|
| `caverno_roadmap_next_task` | `roadmap_next_task_extractor.dart` | Roadmap text, asks for the next task | separate, structured output | not yet logged | separate prefix by design |
| `caverno_roadmap_sections` | `roadmap_next_task_extractor.dart` | Roadmap text, asks for its sections | separate, structured output | not yet logged | separate prefix by design |
| `caverno_project_task_decomposition` | `project_task_decomposer.dart` | Task objective, asks for 1–6 subtasks | separate, structured output | not yet logged | separate prefix by design |
| `caverno_next_step_proposal` | `project_proposal_service.dart` | Project state, asks for a next-step proposal | separate, structured output | not yet logged | separate prefix by design |
| `worktree agent run` | `worktree_agent_task_executor.dart` | Delegated task prompt and its tool loop | separate session | not yet logged | unmeasured |

## Tool-result guidance

Text written into a tool result for the model to act on: a `required_action`
(or `requiredAction`) or an `instruction(s)` field, usually beside a refusal
`code`. Every one is appended to the turn as a tool result, so none rewrites
the cached prefix; each stays in history until compaction. Keyed by producer
file (under `lib/`); `test/docs/model_input_inventory_docs_test.dart` fails
when a file writing one of those fields has no row. Counts are distinct tool
results carrying the code across grounded session logs on 2026-10-14,
approximate.

| Producer | Codes (count) | Tells the model to |
|---|---|---|
| `core/services/apple_foundation_models_platform_client.dart` | — | Carries the system prompt to Apple Foundation Models as `instructions`; not a tool result |
| `features/chat/application/runtime/read_only_review_scope.dart` | read_only_review_refused (0) | Write the review from what was inspected; report a change as a finding |
| `features/chat/data/datasources/background_process_completion_monitor.dart` | caller-supplied | Refresh background jobs and inspect the specific job before reporting |
| `features/chat/data/datasources/git_tools.dart` | git_finish_worktree_base_dirty (0), git_worktree_force_remove_blocked (0), git_force_push_discards_remote_commits (0) | Clean the base worktree; finish worktrees through the session tool; integrate remote commits before pushing |
| `features/chat/data/datasources/local_command_tool_runtime_adapter.dart` | caller-supplied | Next action for a refused or failed local command |
| `features/chat/data/datasources/local_shell_tools.dart` | local_shell_git_write_blocked (4) | Use git_execute_command for git writes |
| `features/chat/data/datasources/run_tests_tool_runtime_adapter.dart` | caller-supplied | Re-select the project and inspect state before retrying tests |
| `features/chat/data/repositories/tool_result_artifact_store.dart` | — | Full result saved for the user outside the project; work from the preview or re-run narrower |
| `features/chat/domain/services/anabasis/anabasis_delegation_admission.dart` | anabasis_delegation_not_ready (13) | Pick an exact ready workflow task; resolve unmet preconditions |
| `features/chat/domain/services/anabasis/anabasis_parent_authority_guard.dart` | anabasis_parent_authority_refused (4) | The parent delegates or verifies instead of running the tool |
| `features/chat/domain/services/anabasis/subagent_result_payloads.dart` | subagent_task_unknown, worktree_child_already_running (0), worktree_delegation_unavailable (0) | Use a known task id; poll the running child instead of starting another |
| `features/chat/domain/services/anabasis/task_acceptance_decision.dart` | caller-supplied refusal codes | Only Anabasis accepts; give a rationale; verify or delegate before accepting |
| `features/chat/domain/services/anabasis/task_acceptance_payloads.dart` | acceptance_write_failed (0) | Retry the acceptance once |
| `features/chat/domain/services/approval/tool_approval_review_packet.dart` | — | Output contract for the approval auto-review request (separate request, label `approval auto-review`) |
| `features/chat/domain/services/claims/narrated_transcript_repair_planner.dart` | narrated_transcript_commands_not_executed (12) | Run the narrated commands or say plainly they were not run |
| `features/chat/domain/services/claims/unexecuted_command_action_retry_policy.dart` | unexecuted_command_action_retry_required (52), fenced_tool_arguments_not_a_call (0) | Issue the described command as a real tool call, or give the concrete reason it cannot be |
| `features/chat/domain/services/claims/unexecuted_file_mutation_block_payload.dart` | unexecuted_file_save (16) | Perform the claimed file change before the command, or say it was not made |
| `features/chat/domain/services/claims/unexecuted_final_answer_tool_request_policy.dart` | tool_call_not_executed (0) | Retry the tool through the tool-aware continuation |
| `features/chat/domain/services/claims/uninspected_commit_guard.dart` | commit_without_diff_inspection_blocked (24) | Read the staged diff, then commit |
| `features/chat/domain/services/code_intelligence/analysis_options_lint_edit_guard.dart` | analysis_options_lint_evidence_required (0) | Evidence required before adding a lint suppression |
| `features/chat/domain/services/coding/coding_command_output_guardrail_service.dart` | command_output_failure (0) | Treat the task as incomplete; repair and rerun before claiming completion |
| `features/chat/domain/services/coding/coding_command_preflight_issue_detector.dart` | — | Per-issue instruction for a command preflight problem |
| `features/chat/domain/services/coding/coding_continuation_recovery_policy.dart` | recovery codes (see the coding continuation table above) | Required action for each coding recovery; call only update_goal for a rejected batch |
| `features/chat/domain/services/coding/coding_diagnostic_feedback_service.dart` | — | New analyzer diagnostics after edits; fix them before claiming completion |
| `features/chat/domain/services/coding/coding_verification_feedback_service.dart` | — | Failing tests after edits; fix them before claiming completion |
| `features/chat/domain/services/git/git_tag_format_inspection_guard.dart` | git_tag_format_inspection_required (26) | List existing tags first, then pick a matching name |
| `features/chat/domain/services/goal/goal_validation_probe_guard.dart` | goal_validation_probe_requires_verifier (0) | Run one project verification command now |
| `features/chat/domain/services/local_command/background_completion_evidence.dart` | background_process_partial_failure (2), caller-supplied | Report the partial failure; wait for pending subagents before claiming completion |
| `features/chat/domain/services/local_command/process_start_result_policy.dart` | background_process_start_stale_result (0) | Monitor the existing job; do not report it as newly started |
| `features/chat/domain/services/local_command/timed_out_command_retry_guard.dart` | command_retry_after_timeout_blocked (0) | Ask the user or inspect the previous process before retrying |
| `features/chat/domain/services/plan/material_contract_assumption_guard.dart` | material_contract_assumption_unconfirmed (0) | Do not mutate state until the assumption is confirmed |
| `features/chat/domain/services/production_release/blocked_production_release_retry_policy.dart` | blocked_production_release_retry_required (1) | Issue exactly one release call with the approved arguments |
| `features/chat/domain/services/production_release/production_release_approval_conflict_result.dart` | production_release_approval_conflict (18) | Do not ask again; continue with the pending release only |
| `features/chat/domain/services/production_release/production_release_blocked_result.dart` | production_release_explicit_approval_required (65) | Explicit approval required for the release |
| `features/chat/domain/services/production_release/production_release_dispatch_result.dart` | production_release_already_executed (0) | Do not re-issue; report the release that already ran |
| `features/chat/domain/services/project_task/saved_task_target_scope_guard.dart` | saved_task_target_scope_violation (9) | Modify only the active saved task's target files |
| `features/chat/domain/services/python/verified_pytest_replay_policy.dart` | — | Reuse the earlier passing verification; the command was not re-executed |
| `features/chat/domain/services/tool_loop/truncated_tool_call_arguments_guard.dart` | tool_call_arguments_truncated (0) | Re-issue the call, split into smaller calls |
| `features/chat/domain/services/verification/command_diagnostic_verifier_replay_guard.dart` | unchanged_verifier_replay_before_repair_blocked (0) | Make one mutation for the diagnostic, then rerun the verifier |
| `features/chat/domain/services/verification/project_verification_repair_policy.dart` | project_verification_repair_protocol_violation (0) | Diagnose or repair with a project tool; report a concrete blocker |
| `features/chat/domain/services/verification/saved_validation_command_guard.dart` | saved_validation_command_modified (4) | Run the saved validation command exactly as saved |

## System prompt sections

`SystemPromptBuilder.build` renders the system prompt as named sections, in
this order; `onSections` reports each one's size for a render. Sizes are
characters in one coding render with the full tool catalog and a project and
nothing else (2026-10-14); `—` means the section was absent from it. The
repo map and AGENTS.md sizes come from the session-log census in
`docs/worklog/system_prompt_size_census_2026-10-14.md`. Every section sits in
the system prompt, so a change to one rewrites the cached prefix from that
point on. `test/docs/model_input_inventory_docs_test.dart` fails when a
section id in the builder has no row.

| Section | Present when | Chars |
|---|---|---|
| `anabasis_parent` | The turn runs as the Anabasis parent | — |
| `core_principles` | Always | 1,529 |
| `participant_role` | A participant role prompt is set | — |
| `model_capability_profile` | The routed model has a probed capability profile | — |
| `model_harness` | The model has a harness config | — |
| `response_style` | Not voice mode | 1,188 |
| `mode_instruction` | Always (general, or coding plus plan mode) | 186 |
| `coding_project_context` | Coding or plan mode with a project name or root | 286 |
| `repo_map` | A repository map was built | median 297, p90 8,500 |
| `agents_md` | The project has an AGENTS.md | median 0, p90 6,608 |
| `active_goal` | The thread has an active goal | — |
| `project_read_tools` | Read tools offered | 2,438 |
| `dependency_grounding` | `resolve_installed_dependency` offered | 253 |
| `project_write_tools` | Write or edit tools offered | 1,455 |
| `rollback_tool` | `rollback_last_file_change` offered | 139 |
| `run_tests_tool` | `run_tests` offered | 180 |
| `local_shell_tool` | `local_execute_command` offered | 678 |
| `background_process_tools` | Any `process_*` tool offered | 1,404 |
| `subagent_tools` | `spawn_subagent` offered | 189 |
| `os_system_info_tool` | `os_get_system_info` offered | — |
| `os_log_tool` | `os_log_read` offered | — |
| `os_system_info_and_log` | Both OS tools offered | — |
| `git_tool` | `git_execute_command` offered | 880 |
| `git_finish_worktree_tool` | `git_finish_worktree_session` offered | 224 |
| `project_inspection` | Read, shell or git tools offered | 221 |
| `workflow` | A workflow stage other than idle, or a saved workflow | — |
| `idle_plan_document` | Idle with no workflow but a plan document | — |
| `skills` | Skills context and `load_skill` offered | — |
| `voice_mode` | Voice mode | — |
| `tools` | Any tool offered | 929 |
| `tool_search` | `tool_search` offered | 535 |
| `datetime_tool` | `get_current_datetime` offered | 140 |
| `memory_tools` | Memory search or recall offered | — |
| `load_skill_tool` | `load_skill` offered | 117 |
| `save_skill_tool` | `save_skill` offered | 182 |
| `create_routine_tool` | `create_routine` offered | 211 |
| `python_script_tool` | `run_python_script` offered | 357 |
| `browser_tools` | Any `browser_*` tool offered | 1,340 |
| `computer_use_tools` | Any `computer_*` tool offered | 3,446 |
| `web_research` | A search tool or `web_url_read` offered | 422 |
| `execution_snapshot` | Coding or plan mode with an execution contract | — |
| `temporal_context` | Always | 683 |
| `environment_grounding` | Environment grounding was resolved | — |
| `session_memory` | Session memory context exists | — |

## Known gaps

- Eval requests keep their own reports and are not in the session log.
  Subagents started from a chat turn were already logged under the role
  `subagent`, labelled by the turn they run in; none appears in the corpus
  because none has run since usage roles were recorded.
- Prefix behaviour of the main-loop recovery labels is unmeasured until schema
  v6 logs exercise them. `tool/triage_session_logs.py` reports a cache-read
  fall against the changed envelope digest.
