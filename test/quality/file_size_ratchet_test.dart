import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F1 line-count ratchet (docs/local_llm_agent_roadmap.md).
///
/// Each budget may only shrink. When a refactor slice reduces a file, lower its
/// budget here in the same PR so growth cannot creep back. Never raise a budget
/// to make this test pass; extract code instead, following
/// docs/large_file_refactor_plan.md.
///
/// Budgets are tight non-increasing ceilings refreshed after each extraction.
/// Primary-file budgets prevent local regrowth, while library budgets include
/// declared `part` files so a move into shared private state cannot hide
/// aggregate growth. A small explicit margin may remain below a lowered ceiling
/// so adjacent maintenance does not require raising the ratchet.
///
/// Test files are budgeted per primary file only, never per library; see the
/// note above [_isTestPath] for why an aggregate ceiling on a test library is a
/// ceiling on coverage.
const Map<String, int> _lineBudgets = {
  // WS7-20 moves runtime sampler feedback behind immutable owner events.
  // The head carries one import line the extracted verifier-replay policy needs
  // on the part's behalf: parts share the library's import scope, so a
  // collaborator used only by a part is still paid for here. The library
  // aggregate below records the offsetting removal.
  // +4 for the turn-release scope registry and its rationale. The turn now
  // holds what it owes instead of a distant destructor holding it.
  // +23 to route plan and task drafting to the thread that asked for it.
  // Both ended with a bare `state = state.copyWith(...)` after awaiting the
  // model, which put the draft on whichever thread was visible when it
  // returned -- reproduced, then fixed. Routing is structurally longer than
  // assigning: the callback form costs three lines per write and there are
  // seven of them. Nothing was extractable; the alternative is the bug.
  // +1 import for the shadow comparator.
  'lib/features/chat/presentation/providers/chat_notifier.dart': 8984,
  'lib/features/chat/domain/services/coding_continuation_recovery_policy.dart':
      423,
  'lib/features/chat/domain/services/content_tool_failure_formatter.dart': 32,
  'lib/features/chat/domain/services/content_tool_formatters.dart': 2,
  'lib/features/chat/domain/services/chat_tool_handler_catalog.dart': 271,
  'lib/features/chat/domain/services/ask_user_question_option_parser.dart': 99,
  'lib/features/chat/domain/services/ask_user_question_policy.dart': 383,
  'lib/features/chat/domain/services/ask_user_question_turn_cache.dart': 99,
  'lib/features/chat/domain/services/background_process_tool_handler.dart': 450,
  'lib/features/chat/domain/services/ble_connection_tool_handler.dart': 252,
  'lib/features/chat/domain/services/browser_session_ownership_coordinator.dart':
      461,
  'lib/features/chat/domain/services/browser_tool_handler.dart': 415,
  'lib/features/chat/domain/services/computer_use_action_policy.dart': 474,
  'lib/features/chat/domain/services/computer_use_runtime_coordinator.dart':
      469,
  'lib/features/chat/domain/services/computer_use_tool_handler.dart': 473,
  'lib/features/chat/domain/services/git_process_execution_coordinator.dart':
      480,
  'lib/features/chat/domain/services/git_tool_handler.dart': 315,
  'lib/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart':
      494,
  'lib/features/chat/domain/services/goal_auto_continue_safe_boundary_builder.dart':
      72,
  'lib/features/chat/domain/services/goal_auto_continue_tracker_registry.dart':
      486,
  'lib/features/chat/domain/services/goal_continuation_log_record_builder.dart':
      137,
  'lib/features/chat/domain/services/goal_update_tool_handler.dart': 64,
  'lib/features/chat/domain/services/participant_message_finalizer.dart': 364,
  'lib/features/chat/domain/services/participant_tool_executor.dart': 349,
  'lib/features/chat/data/datasources/participant_tool_production_ports.dart':
      259,
  'lib/features/chat/domain/services/participant_turn_planner.dart': 304,
  'lib/features/chat/domain/services/production_release_approval_policy.dart':
      388,
  'lib/features/chat/domain/services/production_release_approval_coordinator.dart':
      170,
  'lib/features/chat/domain/services/project_scoped_read_tool_handler.dart':
      102,
  'lib/features/chat/domain/services/run_tests_tool_handler.dart': 465,
  'lib/features/chat/domain/services/serial_connection_attempt_coordinator.dart':
      463,
  'lib/features/chat/domain/services/serial_connection_tool_handler.dart': 462,
  'lib/features/chat/domain/services/ssh_session_ownership_coordinator.dart':
      493,
  'lib/features/chat/domain/services/ssh_tool_handler.dart': 348,
  'lib/features/chat/domain/services/subagent_tool_handler.dart': 419,
  'lib/features/chat/domain/services/truncated_tool_call_arguments_guard.dart':
      69,
  'lib/features/chat/domain/services/turn_tool_approval_coordinator.dart': 489,
  'lib/features/chat/domain/services/lsp_go_to_definition_tool_contract.dart':
      252,
  'lib/features/chat/domain/services/lsp_go_to_definition_tool_handler.dart':
      259,
  'lib/features/chat/domain/services/local_command_execution_authority.dart':
      258,
  'lib/features/chat/domain/services/local_command_tool_contract.dart': 320,
  'lib/features/chat/domain/services/local_command_tool_handler.dart': 417,
  'lib/features/chat/domain/services/turn_finalization_recovery_policy.dart':
      268,
  'lib/features/chat/domain/services/coding_verification_mutation_signature.dart':
      64,
  'lib/features/chat/domain/services/unexecuted_final_answer_tool_request_policy.dart':
      281,
  'lib/features/chat/domain/services/blocked_production_release_retry_policy.dart':
      261,
  'lib/features/chat/domain/services/fenced_tool_arguments_detector.dart': 74,
  'lib/features/chat/domain/services/unexecuted_command_action_retry_policy.dart':
      223,
  'lib/features/chat/domain/services/turn_tool_catalog_cache.dart': 44,
  'lib/features/chat/domain/services/final_answer_claim_notice_applicator.dart':
      136,
  'lib/features/chat/domain/services/narrated_transcript_repair_planner.dart':
      179,
  'lib/features/chat/domain/services/file_mutation_effect_coordinator.dart':
      371,
  'lib/features/chat/domain/services/file_mutation_tool_handler.dart': 434,
  'lib/features/chat/domain/services/file_rollback_tool_contract.dart': 304,
  'lib/features/chat/domain/services/file_rollback_tool_handler.dart': 225,
  'lib/features/chat/domain/services/file_turn_rollback_service.dart': 111,
  'lib/features/chat/domain/services/process_start_result_policy.dart': 73,
  'lib/features/chat/domain/services/referenced_specification_loader.dart': 75,
  // Route value types moved to secondary_completion_route_snapshot.dart when
  // the usage role joined them.
  'lib/features/chat/domain/services/secondary_completion_router.dart': 124,
  'lib/features/chat/domain/services/execution_snapshot_observer.dart': 179,
  'lib/features/chat/domain/services/analysis_options_lint_edit_guard.dart':
      380,
  'lib/features/chat/domain/services/command_diagnostic_verifier_replay_guard.dart':
      142,
  'lib/features/chat/domain/services/chat_command_guardrail_collaborators.dart':
      3,
  'lib/features/chat/domain/services/git_tag_format_inspection_guard.dart': 151,
  'lib/features/chat/domain/services/goal_validation_probe_guard.dart': 53,
  'lib/features/chat/domain/services/material_contract_assumption_guard.dart':
      64,
  'lib/features/chat/domain/services/model_edit_apply_telemetry_recorder.dart':
      191,
  'lib/features/chat/domain/services/saved_validation_command_guard.dart': 178,
  'lib/features/chat/domain/services/saved_task_target_scope_guard.dart': 135,
  'lib/features/chat/domain/services/timed_out_command_retry_guard.dart': 96,
  'lib/features/chat/domain/services/git_write_confirmation_policy.dart': 93,
  'lib/features/chat/domain/services/context_surgery_observation_accumulator.dart':
      130,
  'lib/features/chat/domain/services/context_surgery_protected_path_policy.dart':
      20,
  'lib/features/chat/domain/services/model_switch_handoff_registry.dart': 89,
  'lib/features/chat/domain/services/model_switch_settings_policy.dart': 71,
  'lib/features/chat/domain/services/request_tool_observation_collector.dart':
      116,
  'lib/features/chat/domain/services/runtime_sampler_feedback_recorder.dart':
      245,
  'lib/features/chat/domain/services/proposal_option_extraction.dart': 621,
  'lib/features/chat/domain/services/proposal_parsing_text_utils.dart': 693,
  'lib/features/chat/domain/services/tool_loop_exhaustion_policy.dart': 55,
  'lib/features/chat/domain/services/unexecuted_file_mutation_before_command_guard.dart':
      115,
  'lib/features/chat/data/datasources/execution_snapshot_log_runtime_adapter.dart':
      32,
  'lib/features/chat/data/datasources/turn_tool_approval_runtime_ports.dart':
      70,
  'lib/features/chat/data/datasources/lsp_go_to_definition_runtime_adapter.dart':
      296,
  'lib/features/chat/data/datasources/local_command_tool_runtime_adapter.dart':
      653,
  'lib/features/chat/data/datasources/lsp_json_rpc_session_registry.dart': 603,
  'lib/features/chat/data/datasources/model_capability_profile_store_runtime_adapter.dart':
      58,
  'lib/features/chat/data/datasources/file_rollback_tool_runtime_adapter.dart':
      225,
  'lib/features/chat/data/datasources/built_in_filesystem_mutation_compensation.dart':
      116,
  'lib/features/chat/data/datasources/built_in_filesystem_mutation_effect_boundary.dart':
      499,
  'lib/features/chat/data/datasources/built_in_filesystem_mutation_runtime_facade.dart':
      30,
  'lib/features/chat/data/datasources/file_mutation_effect_runtime_contract.dart':
      156,
  'lib/features/chat/data/datasources/file_mutation_path_fence.dart': 447,
  'lib/features/chat/data/datasources/file_mutation_runtime_approval_port.dart':
      202,
  'lib/features/chat/data/datasources/file_mutation_runtime_contract.dart': 470,
  'lib/features/chat/data/datasources/file_mutation_runtime_effect_settlement.dart':
      223,
  'lib/features/chat/data/datasources/file_mutation_runtime_ports.dart': 395,
  'lib/features/chat/data/datasources/file_mutation_runtime_state.dart': 171,
  'lib/features/chat/data/datasources/file_mutation_tool_runtime_adapter.dart':
      180,
  'lib/features/chat/data/datasources/filesystem_text_snapshot.dart': 108,
  'lib/features/chat/data/datasources/file_rollback_store_lifecycle.dart': 50,
  'lib/features/chat/data/datasources/mcp_tool_service_facade_base.dart': 10,
  'lib/features/chat/data/datasources/mcp_tool_service_facade_capabilities.dart':
      4,
  'lib/features/chat/data/datasources/mcp_tool_service_file_mutation_facade.dart':
      34,
  'lib/features/chat/data/datasources/mcp_tool_service_file_rollback_facade.dart':
      37,
  'lib/features/chat/presentation/providers/file_mutation_approval_cache_runtime_adapter.dart':
      101,
  'lib/features/chat/presentation/providers/model_edit_apply_telemetry_runtime_adapter.dart':
      82,
  'lib/features/chat/data/datasources/python_execution_authority.dart': 328,
  'lib/features/chat/data/datasources/python_input_staging_runtime_adapter.dart':
      231,
  'lib/features/chat/data/datasources/python_script_runtime_approval_ports.dart':
      285,
  'lib/features/chat/data/datasources/python_script_runtime_contract.dart': 476,
  'lib/features/chat/data/datasources/python_script_runtime_execution_settlement.dart':
      60,
  'lib/features/chat/data/datasources/python_script_runtime_ports.dart': 446,
  'lib/features/chat/data/datasources/python_script_tool_runtime_adapter.dart':
      335,
  'lib/features/chat/domain/services/python_script_tool_contract.dart': 407,
  'lib/features/chat/domain/services/python_script_tool_handler.dart': 492,
  'lib/features/chat/domain/services/python_staging_lease_registry.dart': 335,
  'lib/features/chat/domain/services/python_staging_lease_types.dart': 220,
  'lib/features/chat/presentation/providers/python_script_approval_cache_runtime_adapter.dart':
      85,
  'lib/features/chat/domain/services/create_routine_tool_handler.dart': 490,
  'lib/features/chat/domain/services/save_skill_tool_handler.dart': 217,
  'lib/features/chat/domain/services/immutable_json_snapshot.dart': 53,
  'lib/features/chat/domain/services/ble_connect_attempt_coordinator.dart': 506,
  // +5 for a read-only isEmpty and its comment. The turn destructor runs 21
  // manual steps and nothing asserted that any of them happened; this is the
  // one store of nine that exposed no way to check. Observability for an
  // untested teardown, not behaviour.
  'lib/features/chat/presentation/providers/tool_approval_cache.dart': 213,
  'lib/features/chat/presentation/providers/turn_finalization_state_registry.dart':
      117,
  'lib/features/chat/presentation/providers/turn_goal_completion_evidence_registry.dart':
      211,
  'lib/features/chat/domain/services/file_mutation_evidence_policy.dart': 65,
  'lib/features/chat/domain/services/python_attachment_repair_policy.dart': 145,
  'lib/features/chat/domain/services/coding_verification_feedback_presentation.dart':
      206,
  'lib/features/chat/domain/services/duplicate_tool_result_recovery.dart': 209,
  'lib/core/security/conversation_taint_state.dart': 82,
  'lib/core/services/ssh_service.dart': 317,
  'lib/features/chat/presentation/providers/subagent_task_notifier.dart': 210,
  'lib/features/chat/domain/entities/chat_turn_owner.dart': 43,
  // TokenUsage moved to token_usage.dart when it grew the full provider
  // breakdown; this file is now just the terminal metadata wrapper.
  'lib/features/chat/domain/entities/chat_completion_terminal_metadata.dart':
      20,
  'lib/features/chat/presentation/providers/turn_owner_snapshot_registry.dart':
      273,
  'lib/features/chat/presentation/providers/active_response_registry.dart': 329,
  'lib/features/chat/presentation/providers/participant_turn_control_registry.dart':
      129,
  'lib/features/chat/presentation/providers/response_metadata_registry.dart':
      107,
  'lib/features/chat/presentation/providers/chat_state.dart': 763,
  'lib/features/chat/data/datasources/ask_user_question_runtime_adapter.dart':
      361,
  'lib/features/chat/presentation/providers/thread_scoped_chat_state.dart': 238,
  'lib/features/chat/domain/services/tool_approval_auto_review_service.dart':
      339,
  'lib/features/chat/domain/services/lsp_diagnostic_feedback_provider.dart':
      290,
  'lib/features/chat/presentation/providers/turn_tool_result_ledger.dart': 151,
  'lib/features/chat/presentation/providers/content_tool_turn_state_registry.dart':
      187,
  'lib/features/chat/presentation/providers/hidden_assistant_evidence_registry.dart':
      105,
  'lib/features/chat/domain/services/hidden_assistant_evidence_scorer.dart': 21,
  'lib/features/chat/presentation/providers/turn_message_persistence_coordinator.dart':
      156,
  'lib/features/chat/presentation/providers/thread_scoped_message_queue.dart':
      138,
  'lib/features/chat/presentation/providers/chat_error_message_builder.dart':
      102,
  'lib/features/chat/presentation/providers/turn_context_retry_coordinator.dart':
      76,
  'lib/features/chat/presentation/providers/runtime_turn_evidence_publisher.dart':
      16,
  // +10 to take a read-only view of the notifier's turn-handle map instead of
  // the map itself. Two objects held one mutable map with no ownership rule;
  // the import, the wrapping constructor and the comment saying why are the
  // whole of the growth. Nothing was extractable -- the class got stricter.
  'lib/features/chat/presentation/providers/runtime_turn_event_publisher.dart':
      120,
  'lib/features/chat/domain/services/content_tool_continuation_prompt_builder.dart':
      61,
  'lib/features/chat/presentation/providers/tool_dedupe_keys.dart': 62,
  'lib/features/chat/domain/services/fenced_tool_name_blocks.dart': 19,
  // +1 import for ConversationGoalStatusPresentation, which absorbed the
  // status->label/colour/icon mapping duplicated across three files.
  // Lowered from 2046 by the coding-terminal dock slice: the panel, its split
  // geometry and the session all live outside this library, and the inline
  // error banner moved to ChatErrorBanner, so the page kept only the dock call
  // site and the working-directory gate.
  // -97: the ten approval dialogs moved to chat_page_approval_listeners.dart,
  // where the listeners that raise them already live. The page keeps the
  // layout; the part keeps the approval flow.
  'lib/features/chat/presentation/pages/chat_page.dart': 1975,
  'lib/features/chat/domain/services/flutter_run_command_builder.dart': 140,
  // The device listing moved to flutter_run_device_lister.dart when it grew
  // a stream, a timeout and a drain.
  'lib/features/chat/domain/services/flutter_run_session_controller.dart': 225,
  'lib/features/chat/domain/services/flutter_run_device_lister.dart': 145,
  'lib/features/chat/domain/entities/flutter_run_session.dart': 130,
  'lib/features/chat/domain/entities/flutter_run_device.dart': 50,
  'lib/features/chat/data/datasources/flutter_run_process_runner.dart': 140,
  'lib/features/chat/presentation/widgets/flutter_run_control_section.dart': 145,
  'lib/features/chat/presentation/widgets/flutter_run_device_sheet.dart': 130,
  // The panel owns the scrollback; its tab strip and actions live in
  // flutter_run_log_panel_header.dart.
  'lib/features/chat/presentation/widgets/flutter_run_log_panel.dart': 155,
  'lib/features/chat/presentation/widgets/flutter_run_log_panel_header.dart':
      125,
  'lib/features/chat/presentation/widgets/flutter_run_issue_list.dart': 195,
  'lib/features/chat/domain/services/flutter_run_log_segmenter.dart': 240,
  'lib/features/chat/domain/services/flutter_run_issue_analyser.dart': 130,
  'lib/features/chat/domain/services/flutter_run_issue_collector.dart': 165,
  'lib/features/chat/domain/entities/flutter_run_issue.dart': 125,
  // Lowered from 2332 by the same extraction (label, colour and icon).
  'lib/features/chat/presentation/widgets/message_input.dart': 2368,
  'lib/features/chat/presentation/widgets/message_input_slash_suggestion_state.dart':
      131,
  'lib/features/chat/presentation/coordinators/chat_page_workspace_navigation_coordinator.dart':
      127,
  'lib/features/chat/presentation/coordinators/feedback_slash_command_coordinator.dart':
      95,
  // Lowered from 243: the goal status->label mapping was duplicated here, in
  // the goal builders and in the goal chip; it now lives in
  // ConversationGoalStatusPresentation.
  'lib/features/chat/presentation/coordinators/goal_slash_command_coordinator.dart':
      239,
  'lib/features/chat/presentation/coordinators/slash_command_action_coordinator.dart':
      331,
  'lib/features/chat/presentation/coordinators/plan_review_action_coordinator.dart':
      198,
  'lib/features/chat/presentation/coordinators/workflow_editor_action_coordinator.dart':
      88,
  'lib/features/chat/presentation/coordinators/workflow_task_action_coordinator.dart':
      258,
  // +2 for LL34: four call sites now hand the tool's reported outcome to
  // validation inference instead of letting it re-derive one from the payload.
  'lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart':
      2382,
  'lib/features/chat/domain/services/content_tool_result_formatter.dart': 132,
  'lib/features/chat/domain/services/verifier_replay_candidate_policy.dart': 56,
  'lib/features/chat/domain/services/workflow_task_run_lifecycle_policy.dart':
      56,
  'lib/features/chat/domain/services/workflow_task_turn_route_policy.dart': 43,
  'lib/features/chat/domain/services/workflow_tool_result_failure_detector.dart':
      54,
  'lib/features/chat/domain/services/coding_command_output_guardrail_service.dart':
      161,
  'lib/features/chat/domain/services/coding_command_output_issue_detector.dart':
      298,
  'lib/features/chat/domain/services/coding_command_preflight_issue_detector.dart':
      356,
  'lib/features/chat/presentation/widgets/workflow/workflow_editor_sheet.dart':
      218,
  'lib/features/chat/presentation/widgets/workflow/workflow_task_editor_sheet.dart':
      209,
  'lib/features/chat/presentation/widgets/slash_command_help_sheet.dart': 42,
  'lib/features/chat/presentation/widgets/chat_page_scaffold.dart': 87,
  'lib/features/chat/presentation/widgets/chat_right_sidebar.dart': 114,
  'lib/features/chat/presentation/widgets/file_workspace_viewer_sheet.dart':
      1559,
  'lib/features/chat/presentation/widgets/file_workspace_diff_parser.dart': 97,
  'lib/features/chat/presentation/widgets/turn_rollback_confirmation_dialog.dart':
      90,
  'lib/features/chat/presentation/slash_commands/slash_command_catalog.dart':
      100,
  'lib/features/chat/presentation/slash_commands/worktree_agent_command_args.dart':
      63,
  'lib/features/chat/data/datasources/mcp_tool_service.dart': 1131,
  'lib/features/chat/data/datasources/mcp_tool_service_owner_facade.dart': 94,
  'lib/features/chat/data/datasources/mcp_tool_service_ssh_facade.dart': 14,
  'lib/features/chat/data/datasources/mcp_tool_service_facades.dart': 1,
  'lib/features/chat/data/datasources/chat_turn_owner_required_tool_result.dart':
      17,
  'lib/features/chat/data/datasources/background_process_tools.dart': 471,
  'lib/features/chat/data/datasources/background_process_monitor_service.dart':
      457,
  'lib/features/chat/data/datasources/background_process_tool_executor.dart':
      206,
  'lib/features/chat/data/datasources/background_process_completion_monitor.dart':
      74,
  'lib/features/chat/data/datasources/lsp_server_process_manager.dart': 375,
  'lib/features/chat/data/datasources/filesystem_tools.dart': 1184,
  'lib/features/chat/data/datasources/filesystem_overview_format.dart': 55,
  'lib/features/chat/data/datasources/filesystem_diff_builder.dart': 213,
  'lib/features/chat/data/datasources/project_scoped_tool_argument_resolver.dart':
      152,
  // Response telemetry (chat_response_telemetry.dart) and request logging
  // (chat_request_logger.dart) extracted alongside per-model usage accounting,
  // which is a concern of the response, not of sending. Net -23 against the
  // previous 1164 ceiling: the extractions paid for the usage attribution each
  // request method now captures at issue time.
  'lib/features/chat/data/datasources/chat_remote_datasource.dart': 1141,
  // -23: embedded tool-call recovery moved to
  // chat_completion_embedded_tool_call_parser.dart, which owns both the tagged
  // forms and the advertised-name gate that makes recovering an untagged call
  // object safe. The normalizer keeps two delegating lines.
  'lib/features/chat/data/datasources/chat_completion_response_normalizer.dart':
      160,
  'lib/features/chat/data/datasources/chat_completion_embedded_tool_call_parser.dart':
      70,
  'lib/features/chat/domain/services/printed_tool_call_recovery.dart': 45,
  'lib/features/chat/data/datasources/built_in_network_tool_handler.dart': 978,
  'lib/features/chat/data/datasources/file_rollback_checkpoint_store.dart': 402,
  'lib/features/chat/presentation/providers/mcp_tool_provider.dart': 176,
  'lib/features/chat/presentation/providers/conversations_notifier.dart': 1838,
  'lib/features/chat/data/datasources/built_in_filesystem_tool_handler.dart':
      329,
  'lib/features/chat/data/datasources/built_in_local_command_tool_handler.dart':
      191,
  'lib/features/chat/data/datasources/built_in_ble_tool_handler.dart': 360,
  'lib/features/chat/data/datasources/built_in_browser_tool_handler.dart': 395,
  'lib/features/chat/data/datasources/built_in_computer_use_tool_handler.dart':
      714,
  'lib/features/chat/data/datasources/built_in_wifi_tool_handler.dart': 65,
  'lib/features/chat/data/datasources/built_in_lan_scan_tool_handler.dart': 77,
  'lib/features/chat/data/datasources/built_in_serial_tool_handler.dart': 141,
  'lib/features/chat/data/datasources/built_in_ssh_tool_handler.dart': 183,
  'lib/features/chat/data/datasources/mcp_tool_result_normalizer.dart': 100,
  'lib/features/chat/data/datasources/remote_mcp_connection_manager.dart': 317,
  'lib/features/chat/data/datasources/remote_mcp_tool_name_policy.dart': 120,
  'lib/features/settings/presentation/pages/computer_use_settings_page.dart':
      1725,
  'lib/features/settings/data/model_remote_datasource.dart': 1710,
  'lib/features/settings/data/model_metadata_parser.dart': 120,
  'lib/features/settings/presentation/widgets/computer_use_action_gate_plan.dart':
      203,
  'lib/features/settings/presentation/widgets/computer_use_ipc_runtime_summary.dart':
      582,
  'lib/features/settings/presentation/widgets/computer_use_live_smoke_summary.dart':
      302,
  'lib/features/settings/presentation/widgets/computer_use_persistence_summary.dart':
      124,
  'lib/features/settings/presentation/widgets/computer_use_verification_summary.dart':
      107,
  'lib/features/settings/presentation/widgets/computer_use_xpc_timing_summary.dart':
      176,
  'lib/features/settings/presentation/widgets/computer_use_permission_trust_panel.dart':
      318,
  'lib/features/settings/presentation/pages/computer_use_debug_page.dart': 1910,
  'lib/features/settings/presentation/widgets/computer_use_debug_audio_card.dart':
      99,
  'lib/features/settings/presentation/widgets/computer_use_debug_display_screenshot_card.dart':
      81,
  'lib/features/settings/presentation/widgets/computer_use_debug_input_card.dart':
      133,
  'lib/features/settings/presentation/widgets/computer_use_debug_window_targeting_card.dart':
      163,
  'lib/features/settings/presentation/widgets/computer_use_debug_diagnostics_cards.dart':
      149,
  'lib/features/settings/presentation/widgets/computer_use_debug_image_preview.dart':
      153,
  'lib/features/settings/presentation/widgets/computer_use_debug_onboarding_card.dart':
      94,
  'lib/features/settings/presentation/widgets/computer_use_debug_permission_actions.dart':
      119,
  'lib/features/settings/presentation/widgets/computer_use_debug_permission_checklist.dart':
      94,
  'lib/features/settings/presentation/widgets/computer_use_debug_status_primitives.dart':
      424,
  'lib/features/routines/presentation/pages/routine_detail_view.dart': 948,
  'lib/features/routines/presentation/widgets/routine_run_history_section.dart':
      525,
  // -42 after hostname resolution (unicast PTR, link-layer, mDNS) moved to
  // lan_hostname_resolver.dart, where the DNS step could be bounded.
  'lib/core/services/lan_scan_service.dart': 801,
  'lib/core/services/lan_ip_network.dart': 199,
  // -98 after dns_lookup/dns_query moved to network_dns_tools.dart, which owns
  // the shared DNS budget the rest of the network tools now borrow.
  'lib/features/chat/data/datasources/network_tools.dart': 870,
  'lib/features/chat/data/datasources/network_address_utils.dart': 34,
  'lib/features/chat/data/datasources/network_http_tools.dart': 287,
  'lib/features/chat/data/datasources/network_neighbor_tools.dart': 265,
  'lib/features/chat/data/datasources/network_route_tools.dart': 1128,
  'lib/features/chat/data/datasources/network_socket_tools.dart': 204,
  'lib/features/chat/data/datasources/network_tool_dependencies.dart': 10,
  'test/features/chat/presentation/providers/chat_notifier_test.dart': 18613,
  'test/features/chat/presentation/providers/mcp_tool_provider_rollback_store_test.dart':
      152,
  'test/support/mcp_file_tool_test_delegate.dart': 16,
  // The TurnRuntime prototype boundary. Registering these as decomposition
  // collaborators requires a declared budget, which is the point: the
  // boundary landed outside both the turn-scope audit and this ratchet, so
  // moving code across it improved the audited metrics without either
  // instrument seeing the destination.
  // Raised once, on 2026-08-04, when the five goal-continuation ports stopped
  // re-taking the owner on every call and became owner-bound at creation.
  // These budgets were snapshots taken the previous day on files two days old,
  // and the growth is the change itself: binding an owner needs a bound-lease
  // type and an owner field. The measurement this was run for moved the right
  // way -- turn-scope identity parameters 328 -> 317 -- and the two files this
  // ratchet actually guards both shrank (chat_notifier.dart 8907 -> 8905, the
  // composition 95 -> 88). Two real extractions came first; a third would have
  // existed only to fit these numbers.
  // The turn's eleven owner-scoped releases, moved from the destructor to the
  // turn that owes them.
  'lib/features/chat/application/runtime/turn_release_scope.dart': 98,
  'lib/features/chat/application/runtime/turn_runtime.dart': 445,
  'lib/features/chat/application/runtime/turn_runtime_conversation_goal_adapter.dart':
      47,
  'lib/features/chat/application/runtime/turn_runtime_goal_tracker_adapter.dart':
      55,
  'lib/features/chat/application/runtime/turn_runtime_owner_lease_registry.dart':
      59,
  'lib/features/chat/presentation/providers/turn_runtime_production_composition.dart':
      88,
  // Owner binding and the two binder interfaces live here, so the composition
  // shrank rather than grew when the ports stopped re-taking the owner.
  'lib/features/chat/application/runtime/turn_runtime_goal_continuation_ports_factory.dart':
      57,
  'lib/features/chat/data/datasources/turn_runtime_goal_continuation_log_adapter.dart':
      82,
};

const Map<String, int> _libraryLineBudgets = {
  // WS6-5 moves local command policy and execution into an owner-aware handler.
  // +15 to make the stalled-diagnostic-repair feature reachable: a shell
  // command that exits non-zero is normalized to a successful tool result,
  // which used to reset the diagnostic streak on exactly the runs it counts.
  // The comment explaining that is most of the addition and is load-bearing.
  // +17 for a read-only teardown report and its rationale. The 21-step
  // destructor had no observability at all; this is the affordance the
  // characterization test needed, and the slice will need it to prove the
  // steps still happen.
  // +20 to route the start-failure path through the release scope. The turn
  // start had a third destructor -- four of the eleven obligations undone by
  // hand -- which had to be kept in step with the other two by inspection. It
  // is now one call, plus the invariant that a registered scope is always
  // dropped: held across the throwing paths, and observed for the first time
  // by the report. Nothing was extractable here; the function got simpler and
  // the additions are the comments carrying the ordering and the invariant.
  // The last 7 record that the finally is untested: mutating it away leaves
  // the suite green, so a reader who checks coverage before deleting it would
  // otherwise conclude it is dead code.
  // +32 for the drafting routing above; see the primary-file note.
  // +4 for LL34: the tool loop hands its ToolResultInfo the outcome the
  // McpToolResult beside it already carried.
  // +20 to move the six owner-keyed releases out of the generation-keyed
  // destructor, which reached them by looking the owner back up. The turn now
  // has one destructor per key. The generation one lost nine lines; the scope
  // gained those six registrations plus the note explaining why the paused
  // participant guard travels with them.
  // +13 for the tool-loop shadow point. No canary reaches the validation
  // consumer, so this is the only place a live run can answer whether the
  // producer attaches an exit status a consumer would otherwise re-derive.
  'lib/features/chat/presentation/providers/chat_notifier.dart': 19840,
  // +9 for the awaitingConfirmation status: one import plus the goal-builders
  // label delegating to the shared presentation. The offsetting extraction
  // lowered two other budgets above; this library keeps only the call site.
  'lib/features/chat/presentation/pages/chat_page.dart': 8899,
  'lib/features/chat/data/datasources/mcp_tool_service.dart': 1223,
  // P3b's detached-owner target uses the shared exact-conversation resolver.
};

/// Test **libraries** are deliberately absent from [_libraryLineBudgets].
///
/// An aggregate ceiling over a test file and its parts is a ceiling on
/// coverage: the only way to add a scenario is to add lines, so every new
/// assertion pushes toward the limit and the cheapest way to stay green is to
/// not write the test. That is the opposite of what this suite is for. The
/// budget for `chat_notifier_test.dart`'s library was raised twice in one day
/// for exactly this reason -- once for turn-teardown characterization, once for
/// the participant pause/resume scenario the pilot gate requires -- and neither
/// raise recorded regrowth of anything.
///
/// The structural concern is real but different: new scenarios must not keep
/// growing one 18k-line file. That is guarded by the *primary-file* budget in
/// [_lineBudgets], which stays. It has worked -- it forced the test doubles and
/// the continuation-recovery scenarios into part files -- and it leaves the
/// aggregate free to grow with coverage.
bool _isTestPath(String path) => path.startsWith('test/');

final RegExp _partDirectivePattern = RegExp(
  r"^part\s+'([^']+)';",
  multiLine: true,
);

void main() {
  group('file size ratchet', () {
    // Keeps the exemption above from eroding: a future slice that hits a test
    // library ceiling must not restore one, because raising it and adding it
    // back are the same act.
    test('no test library carries an aggregate budget', () {
      expect(
        _libraryLineBudgets.keys.where(_isTestPath),
        isEmpty,
        reason:
            'An aggregate budget over a test library caps coverage. Guard the '
            'primary test file in _lineBudgets instead, which forces new '
            'scenarios into part files without limiting how many there are.',
      );
    });

    for (final entry in _lineBudgets.entries) {
      test('${entry.key} stays within ${entry.value} lines', () {
        final file = File(entry.key);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              '${entry.key} is budgeted but missing. If it was split or '
              'renamed, update _lineBudgets in this test.',
        );

        final lineCount = file.readAsLinesSync().length;
        expect(
          lineCount,
          lessThanOrEqualTo(entry.value),
          reason:
              '${entry.key} has $lineCount lines, over its ratchet budget of '
              '${entry.value}. Do not raise the budget. Extract code per '
              'docs/large_file_refactor_plan.md and '
              'docs/local_llm_agent_roadmap.md (F1).',
        );
      });
    }

    for (final entry in _libraryLineBudgets.entries) {
      test('${entry.key} library stays within ${entry.value} lines', () {
        final libraryFile = File(entry.key);
        expect(
          libraryFile.existsSync(),
          isTrue,
          reason: '${entry.key} is budgeted but missing.',
        );

        final partPaths = _partDirectivePattern
            .allMatches(libraryFile.readAsStringSync())
            .map((match) => match.group(1)!)
            .toList(growable: false);
        final partFiles = partPaths
            .map((path) => File('${libraryFile.parent.path}/$path'))
            .toList(growable: false);
        final missingParts = partFiles
            .where((file) => !file.existsSync())
            .map((file) => file.path)
            .toList(growable: false);

        expect(
          missingParts,
          isEmpty,
          reason: '${entry.key} declares missing part files.',
        );

        final lineCount = <File>[
          libraryFile,
          ...partFiles,
        ].fold<int>(0, (total, file) => total + file.readAsLinesSync().length);
        expect(
          lineCount,
          lessThanOrEqualTo(entry.value),
          reason:
              '${entry.key} and its declared parts have $lineCount lines, '
              'over their aggregate ratchet budget of ${entry.value}. '
              'Extract an independent service or widget instead of adding '
              'another part file.',
        );
      });
    }
  });
}
