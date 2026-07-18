import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F1 line-count ratchet (docs/local_llm_agent_roadmap.md).
///
/// Each budgeted file may only shrink. When a refactor slice reduces a file,
/// lower its budget here in the same PR so growth cannot creep back. Never
/// raise a budget to make this test pass; extract code instead, following
/// docs/large_file_refactor_plan.md.
///
/// Budgets match the exact 2026-07-17 baseline. Primary-file budgets prevent
/// local regrowth, while library budgets include declared `part` files so a
/// move into shared private state cannot hide aggregate growth.
const Map<String, int> _lineBudgets = {
  'lib/features/chat/presentation/providers/chat_notifier.dart': 9468,
  'lib/features/chat/presentation/pages/chat_page.dart': 2133,
  'lib/features/chat/presentation/coordinators/feedback_slash_command_coordinator.dart':
      95,
  'lib/features/chat/presentation/coordinators/goal_slash_command_coordinator.dart':
      243,
  'lib/features/chat/presentation/coordinators/slash_command_action_coordinator.dart':
      364,
  'lib/features/chat/presentation/coordinators/plan_review_action_coordinator.dart':
      198,
  'lib/features/chat/presentation/coordinators/workflow_editor_action_coordinator.dart':
      88,
  'lib/features/chat/presentation/coordinators/workflow_task_action_coordinator.dart':
      258,
  'lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart':
      2442,
  'lib/features/chat/presentation/widgets/workflow/workflow_editor_sheet.dart':
      218,
  'lib/features/chat/presentation/widgets/workflow/workflow_task_editor_sheet.dart':
      209,
  'lib/features/chat/presentation/widgets/slash_command_help_sheet.dart': 42,
  'lib/features/chat/presentation/widgets/chat_page_scaffold.dart': 87,
  'lib/features/chat/presentation/widgets/chat_right_sidebar.dart': 114,
  'lib/features/chat/presentation/slash_commands/slash_command_catalog.dart':
      100,
  'lib/features/chat/data/datasources/mcp_tool_service.dart': 1202,
  'lib/features/chat/data/datasources/built_in_network_tool_handler.dart': 978,
  'lib/features/chat/data/datasources/built_in_filesystem_tool_handler.dart':
      622,
  'lib/features/chat/data/datasources/built_in_local_command_tool_handler.dart':
      581,
  'lib/features/chat/data/datasources/built_in_ble_tool_handler.dart': 360,
  'lib/features/chat/data/datasources/built_in_browser_tool_handler.dart': 395,
  'lib/features/chat/data/datasources/built_in_computer_use_tool_handler.dart':
      714,
  'lib/features/chat/data/datasources/built_in_wifi_tool_handler.dart': 65,
  'lib/features/chat/data/datasources/built_in_lan_scan_tool_handler.dart': 77,
  'lib/features/chat/data/datasources/built_in_serial_tool_handler.dart': 141,
  'lib/features/chat/data/datasources/built_in_ssh_tool_handler.dart': 183,
  'lib/features/chat/data/datasources/mcp_tool_result_normalizer.dart': 126,
  'lib/features/chat/data/datasources/remote_mcp_connection_manager.dart': 317,
  'lib/features/chat/data/datasources/remote_mcp_tool_name_policy.dart': 120,
  'lib/features/settings/presentation/pages/computer_use_settings_page.dart':
      1725,
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
  'lib/features/settings/presentation/pages/computer_use_debug_page.dart': 2145,
  'lib/features/settings/presentation/widgets/computer_use_debug_audio_card.dart':
      99,
  'lib/features/settings/presentation/widgets/computer_use_debug_diagnostics_cards.dart':
      149,
  'lib/features/settings/presentation/widgets/computer_use_debug_image_preview.dart':
      153,
  'lib/features/settings/presentation/widgets/computer_use_debug_onboarding_card.dart':
      94,
  'lib/features/settings/presentation/widgets/computer_use_debug_status_primitives.dart':
      424,
  'lib/features/chat/data/datasources/network_tools.dart': 1996,
  'lib/features/chat/data/datasources/network_address_utils.dart': 34,
  'lib/features/chat/data/datasources/network_http_tools.dart': 287,
  'lib/features/chat/data/datasources/network_neighbor_tools.dart': 266,
  'lib/features/chat/data/datasources/network_socket_tools.dart': 204,
  'test/features/chat/presentation/providers/chat_notifier_test.dart': 18648,
};

const Map<String, int> _libraryLineBudgets = {
  'lib/features/chat/presentation/providers/chat_notifier.dart': 23005,
  'lib/features/chat/presentation/pages/chat_page.dart': 8945,
  'lib/features/chat/data/datasources/mcp_tool_service.dart': 1294,
  'test/features/chat/presentation/providers/chat_notifier_test.dart': 33189,
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
