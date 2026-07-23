import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F1 line-count ratchet (docs/local_llm_agent_roadmap.md).
///
/// Each budgeted file may only shrink. When a refactor slice reduces a file,
/// lower its budget here in the same PR so growth cannot creep back. Never
/// raise a budget to make this test pass; extract code instead, following
/// docs/large_file_refactor_plan.md.
///
/// Budgets match the latest tracked boundaries from the 2026-07-18 inventory.
/// Primary-file budgets prevent local regrowth, while library budgets include
/// declared `part` files so a move into shared private state cannot hide
/// aggregate growth.
const Map<String, int> _lineBudgets = {
  // 9468 + 6 for LL35 shadow wiring (completion-outcome field, import, turn-
  // start clear, and threading the lexical result to the shadow comparison),
  // +1 for the verification-cadence import used by the auto-continue fix.
  // +15 promotes update_goal out of shadow so an accepted completion actually
  // completes the goal: the turn-scoped claim field (which must live on the
  // class, not in a part-file extension), its turn-start clear, the import,
  // and the two finalization call sites. The offsetting extraction is in the
  // library budget below; nothing here could move without a separate refactor
  // of this file.
  // +3 for the completion-elicitation imports and dispatch, +8 for the
  // turn-scoped allowed-tool set the unexecuted-action guard reads so it
  // stops faulting claims the turn had no tool to substantiate, +6 to clear
  // that set on the queued-message drain, which reaches dispatch without
  // passing sendMessage.
  'lib/features/chat/presentation/providers/chat_notifier.dart': 9507,
  // +1 import for ConversationGoalStatusPresentation, which absorbed the
  // status->label/colour/icon mapping duplicated across three files.
  // Lowered from 2046 by the coding-terminal dock slice: the panel, its split
  // geometry and the session all live outside this library, and the inline
  // error banner moved to ChatErrorBanner, so the page kept only the dock call
  // site and the working-directory gate.
  'lib/features/chat/presentation/pages/chat_page.dart': 2037,
  // Lowered from 2332 by the same extraction (label, colour and icon).
  'lib/features/chat/presentation/widgets/message_input.dart': 2318,
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
      364,
  'lib/features/chat/presentation/coordinators/plan_review_action_coordinator.dart':
      198,
  'lib/features/chat/presentation/coordinators/workflow_editor_action_coordinator.dart':
      88,
  'lib/features/chat/presentation/coordinators/workflow_task_action_coordinator.dart':
      258,
  'lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart':
      2380,
  'lib/features/chat/domain/services/workflow_task_run_lifecycle_policy.dart':
      56,
  'lib/features/chat/domain/services/workflow_task_turn_route_policy.dart': 43,
  'lib/features/chat/domain/services/workflow_tool_result_failure_detector.dart':
      54,
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
  'lib/features/chat/presentation/slash_commands/slash_command_catalog.dart':
      100,
  'lib/features/chat/data/datasources/mcp_tool_service.dart': 1202,
  'lib/features/chat/data/datasources/filesystem_tools.dart': 1243,
  'lib/features/chat/data/datasources/filesystem_diff_builder.dart': 213,
  'lib/features/chat/data/datasources/chat_remote_datasource.dart': 1164,
  'lib/features/chat/data/datasources/chat_completion_response_normalizer.dart':
      183,
  'lib/features/chat/data/datasources/built_in_network_tool_handler.dart': 978,
  'lib/features/chat/data/datasources/built_in_filesystem_tool_handler.dart':
      343,
  'lib/features/chat/data/datasources/built_in_local_command_tool_handler.dart':
      341,
  'lib/features/chat/data/datasources/built_in_ble_tool_handler.dart': 360,
  'lib/features/chat/data/datasources/built_in_browser_tool_handler.dart': 395,
  'lib/features/chat/data/datasources/built_in_computer_use_tool_handler.dart':
      714,
  'lib/features/chat/data/datasources/built_in_wifi_tool_handler.dart': 65,
  'lib/features/chat/data/datasources/built_in_lan_scan_tool_handler.dart': 77,
  'lib/features/chat/data/datasources/built_in_serial_tool_handler.dart': 141,
  'lib/features/chat/data/datasources/built_in_ssh_tool_handler.dart': 183,
  'lib/features/chat/data/datasources/mcp_tool_result_normalizer.dart': 106,
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
  'lib/core/services/lan_scan_service.dart': 843,
  'lib/core/services/lan_ip_network.dart': 199,
  'lib/features/chat/data/datasources/network_tools.dart': 968,
  'lib/features/chat/data/datasources/network_address_utils.dart': 34,
  'lib/features/chat/data/datasources/network_http_tools.dart': 287,
  'lib/features/chat/data/datasources/network_neighbor_tools.dart': 266,
  'lib/features/chat/data/datasources/network_route_tools.dart': 1128,
  'lib/features/chat/data/datasources/network_socket_tools.dart': 204,
  'lib/features/chat/data/datasources/network_tool_dependencies.dart': 10,
  'test/features/chat/presentation/providers/chat_notifier_test.dart': 18648,
};

const Map<String, int> _libraryLineBudgets = {
  // Raised for LL35 update_goal wiring (+17 tool dispatch, +27 shadow
  // comparison) and LL36 firing audit (+4 to record the coding-continuation
  // recovery as a countable transform). Not god-file growth: the
  // mcp_tool_service side took an offsetting definitions extraction and the
  // decision logic lives in the pure GoalUpdateAckResolver /
  // GoalCompletionShadow services, not here. See LL35/LL36. A further +21
  // wires the verification cadence into goal auto-continue (a reused projector
  // call plus its doc), fixing a real skip observed in session 2659093b, and
  // +15 logs the cadence and both generations on the auto-continue record —
  // without them a skip is undiagnosable, as session cfaa8297 showed — and +3
  // documents why the cadence is derived directly rather than read off a
  // snapshot that can early-return.
  // A net +64 adds the one-shot goal-completion elicitation: the turn-scoped
  // guard, the trigger, and the dispatcher. Offset by extracting the
  // session-log evidence marker (a triage-tooling contract, which belongs
  // beside the policy) and by folding this slice's rationale into
  // GoalCompletionElicitationPrompt rather than repeating it inline. Earlier
  // slices in the same session took 73 lines (the prompt builder) and 30 (the
  // stop presentation) out of this library, so it is net smaller than it
  // started even though each slice reads as growth.
  'lib/features/chat/presentation/providers/chat_notifier.dart': 23156,
  // +9 for the awaitingConfirmation status: one import plus the goal-builders
  // label delegating to the shared presentation. The offsetting extraction
  // lowered two other budgets above; this library keeps only the call site.
  'lib/features/chat/presentation/pages/chat_page.dart': 8866,
  'lib/features/chat/data/datasources/mcp_tool_service.dart': 1294,
  // +3 for the LL35 return-type change threaded through the goal test doubles.
  // +35 adds the toolCompletionClaimed parameter and an observable field to
  // the three goal test doubles, so a test can assert what finalization passed
  // to recordCurrentGoalTurn.
  'test/features/chat/presentation/providers/chat_notifier_test.dart': 33227,
};

final RegExp _partDirectivePattern = RegExp(
  r"^part\s+'([^']+)';",
  multiLine: true,
);

void main() {
  group('file size ratchet', () {
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
