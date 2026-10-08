import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps cross-layer imports inside `lib/features/` from growing.
///
/// The rules are the ones the feature layout implies:
///
/// - `domain/` imports neither `data/`, `presentation/`, `application/` nor
///   `package:flutter/`;
/// - `data/` does not import `presentation/`.
///
/// Every edge that broke a rule when this test was written is listed in
/// [_reviewedEdges]. The list is a ratchet, not an allowlist to grow: a new
/// edge fails with the rule it breaks, and an edge that no longer exists
/// fails until its entry is deleted, so each fix tightens the ceiling.
///
/// Matching reads `import` / `export` directives textually, resolving both
/// `package:caverno/` and relative URIs. Generated `.g.dart` and
/// `.freezed.dart` files are skipped; their imports follow their sources.
const Set<String> _reviewedEdges = <String>{
  // domain -> data, data -> presentation, domain -> presentation and
  // domain -> package:flutter, measured 2026-10-08.
  'lib/features/chat/data/repositories/coding_project_repository.dart -> lib/features/settings/presentation/providers/settings_notifier.dart',
  'lib/features/chat/data/repositories/context_window_observation_store.dart -> lib/features/settings/presentation/providers/settings_notifier.dart',
  'lib/features/chat/data/repositories/retry_until_green_report_repository.dart -> lib/features/settings/presentation/providers/settings_notifier.dart',
  'lib/features/chat/data/repositories/worktree_agent_task_repository.dart -> lib/features/settings/presentation/providers/settings_notifier.dart',
  'lib/features/chat/domain/services/background_process_tool_handler.dart -> lib/features/chat/data/datasources/local_shell_tools.dart',
  'lib/features/chat/domain/services/changed_file_evidence.dart -> lib/features/chat/data/datasources/filesystem_tools.dart',
  'lib/features/chat/domain/services/coding_verification_mutation_signature.dart -> lib/features/chat/data/datasources/filesystem_path_resolver.dart',
  'lib/features/chat/domain/services/duplicate_tool_result_recovery.dart -> lib/features/chat/data/datasources/filesystem_path_resolver.dart',
  'lib/features/chat/domain/services/feedback_submission_service.dart -> lib/features/chat/data/datasources/llm_session_log_store.dart',
  'lib/features/chat/domain/services/file_mutation_tool_handler.dart -> lib/features/chat/data/datasources/project_mutation_path_fence.dart',
  'lib/features/chat/domain/services/file_turn_rollback_service.dart -> lib/features/chat/data/datasources/file_rollback_checkpoint_store.dart',
  'lib/features/chat/domain/services/flutter_run/flutter_run_device_lister.dart -> lib/features/chat/data/datasources/flutter_run_process_runner.dart',
  'lib/features/chat/domain/services/flutter_run/flutter_run_issue_analyser.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/chat/domain/services/flutter_run/flutter_run_issue_collector.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/chat/domain/services/flutter_run/flutter_run_session_controller.dart -> lib/features/chat/data/datasources/flutter_run_process_runner.dart',
  'lib/features/chat/domain/services/git/git_tag_format_inspection_guard.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/git/git_tool_handler.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/git/git_tool_handler.dart -> lib/features/chat/data/datasources/project_scoped_tool_argument_resolver.dart',
  'lib/features/chat/domain/services/git/git_write_confirmation_policy.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/html_preview_session_controller.dart -> package:flutter/foundation.dart',
  'lib/features/chat/domain/services/local_command_execution_plan.dart -> lib/features/chat/data/datasources/local_command_workspace_containment.dart',
  'lib/features/chat/domain/services/local_command_execution_plan.dart -> lib/features/chat/data/datasources/local_shell_tools.dart',
  'lib/features/chat/domain/services/local_command_request_preparation.dart -> lib/features/chat/data/datasources/local_shell_tools.dart',
  'lib/features/chat/domain/services/local_command_tool_handler.dart -> lib/features/chat/data/datasources/local_shell_tools.dart',
  'lib/features/chat/domain/services/lsp_go_to_definition_tool_handler.dart -> lib/features/chat/data/datasources/project_scoped_tool_argument_resolver.dart',
  'lib/features/chat/domain/services/memory_extraction_coordinator.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/chat/domain/services/outside_root_read_grants.dart -> lib/features/chat/data/datasources/project_read_tool_authorizer.dart',
  'lib/features/chat/domain/services/pending_approval_summary.dart -> lib/features/chat/presentation/providers/chat_state.dart',
  'lib/features/chat/domain/services/planning_tool_policy.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/planning_tool_policy.dart -> lib/features/chat/data/datasources/local_shell_tools.dart',
  'lib/features/chat/domain/services/pro_reasoning_candidate_explorer.dart -> lib/features/chat/data/datasources/llama_cpp_slot_discovery.dart',
  'lib/features/chat/domain/services/pro_reasoning_candidate_explorer.dart -> lib/features/chat/data/datasources/llama_cpp_slot_transport.dart',
  'lib/features/chat/domain/services/pro_reasoning_candidate_explorer.dart -> lib/features/chat/data/datasources/parallel_slot_executor.dart',
  'lib/features/chat/domain/services/pro_reasoning_investigator.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/chat/domain/services/production_release_approval_coordinator.dart -> package:flutter/foundation.dart',
  'lib/features/chat/domain/services/production_release_approval_policy.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/production_release_canonical_arguments.dart -> lib/features/chat/data/datasources/local_shell_tools.dart',
  'lib/features/chat/domain/services/project_scoped_read_tool_handler.dart -> lib/features/chat/data/datasources/project_read_tool_authorizer.dart',
  'lib/features/chat/domain/services/project_scoped_read_tool_handler.dart -> lib/features/chat/data/datasources/project_scoped_tool_argument_resolver.dart',
  'lib/features/chat/domain/services/project_task_commit_tool_policy.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/recent_read_result_carry.dart -> lib/features/chat/data/datasources/filesystem_path_resolver.dart',
  'lib/features/chat/domain/services/recent_read_result_carry.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/run_tests_tool_handler.dart -> lib/features/chat/data/datasources/filesystem_tools.dart',
  'lib/features/chat/domain/services/save_skill_tool_handler.dart -> lib/features/chat/data/datasources/filesystem_diff_builder.dart',
  'lib/features/chat/domain/services/saved_task_target_scope_guard.dart -> lib/features/chat/data/datasources/filesystem_path_resolver.dart',
  'lib/features/chat/domain/services/saved_validation_command_guard.dart -> lib/features/chat/data/datasources/filesystem_tools.dart',
  'lib/features/chat/domain/services/saved_validation_command_guard.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/saved_validation_evidence.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/secondary_completion_router.dart -> lib/features/chat/data/datasources/mesh_secondary_completion_runner.dart',
  'lib/features/chat/domain/services/session_memory_service.dart -> lib/features/chat/data/repositories/chat_memory_repository.dart',
  'lib/features/chat/domain/services/subagent_execution_service.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/chat/domain/services/subagent_execution_service.dart -> lib/features/routines/data/routine_tool_runner.dart',
  'lib/features/chat/domain/services/task_proposal_parser.dart -> lib/features/chat/presentation/providers/chat_state.dart',
  'lib/features/chat/domain/services/task_proposal_quality_gate_fallback.dart -> lib/features/chat/presentation/providers/chat_state.dart',
  'lib/features/chat/domain/services/tool_call_execution_policy.dart -> lib/features/chat/data/datasources/git_tools.dart',
  'lib/features/chat/domain/services/tool_call_execution_policy.dart -> lib/features/chat/data/datasources/local_shell_tools.dart',
  'lib/features/chat/domain/services/tool_loop_recovery_policy.dart -> lib/features/chat/data/datasources/filesystem_path_resolver.dart',
  'lib/features/chat/domain/services/truncated_tool_call_arguments_guard.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/chat/domain/services/workflow_task_proposal_quality_service.dart -> lib/features/chat/presentation/providers/chat_state.dart',
  'lib/features/dashboard/domain/services/model_usage_stats_calculator.dart -> lib/features/chat/data/datasources/app_database.dart',
  'lib/features/remote_coding/data/remote_coding_notification_relay_providers.dart -> lib/features/settings/presentation/providers/settings_notifier.dart',
  'lib/features/remote_coding/data/remote_coding_repository.dart -> lib/features/settings/presentation/providers/settings_notifier.dart',
  'lib/features/remote_coding/domain/remote_coding_session_policy.dart -> lib/features/remote_coding/data/remote_coding_security.dart',
  'lib/features/remote_coding/domain/remote_coding_transport_policy.dart -> lib/features/remote_coding/data/remote_coding_security.dart',
  'lib/features/routines/data/routine_execution_service.dart -> lib/features/chat/presentation/providers/chat_notifier.dart',
  'lib/features/routines/data/routine_execution_service.dart -> lib/features/chat/presentation/providers/mcp_tool_provider.dart',
  'lib/features/routines/data/routine_execution_service.dart -> lib/features/settings/presentation/providers/settings_notifier.dart',
  'lib/features/routines/data/routine_repository.dart -> lib/features/settings/presentation/providers/settings_notifier.dart',
  'lib/features/routines/data/routine_retry_until_green_service.dart -> lib/features/chat/presentation/providers/mcp_tool_provider.dart',
  'lib/features/routines/domain/services/routine_computer_use_action_allowlist.dart -> lib/features/chat/data/datasources/chat_remote_datasource.dart',
  'lib/features/routines/domain/services/routine_tool_policy.dart -> lib/features/chat/data/datasources/chat_remote_datasource.dart',
  'lib/features/settings/domain/entities/built_in_tool_info.dart -> package:flutter/material.dart',
  'lib/features/settings/domain/services/app_language_resolver.dart -> package:flutter/material.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_evidence.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_response_scoring.dart -> lib/features/chat/data/datasources/chat_remote_datasource.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> lib/features/chat/data/datasources/chat_remote_datasource.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> lib/features/chat/data/datasources/embeddings_client.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> lib/features/chat/data/datasources/mcp_goal_routine_tool_definitions.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> lib/features/chat/data/datasources/mcp_tool_service.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> lib/features/chat/data/datasources/openai_modalities_probe.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> lib/features/chat/data/datasources/openai_parameter_support_probe.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> lib/features/chat/data/datasources/strict_tool_choice_policy.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_service.dart -> package:flutter/foundation.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_thinking_observer.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_diagnostic_thinking_observer.dart -> lib/features/chat/data/datasources/chat_remote_datasource.dart',
  'lib/features/settings/domain/services/live_llm_edit_format_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_effective_context_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_embedding_probe.dart -> lib/features/chat/data/datasources/embeddings_client.dart',
  'lib/features/settings/domain/services/live_llm_embedding_probe.dart -> lib/features/chat/data/datasources/embeddings_math.dart',
  'lib/features/settings/domain/services/live_llm_exact_preservation_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_goal_update_fidelity_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_multi_round_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_sampler_calibration_trials.dart -> lib/features/chat/data/datasources/chat_remote_datasource.dart',
  'lib/features/settings/domain/services/live_llm_streaming_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_structured_output_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_structured_output_probe.dart -> lib/features/chat/data/datasources/openai_parameter_support_probe.dart',
  'lib/features/settings/domain/services/live_llm_thinking_control_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_tool_depth_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_tool_recovery_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_tool_result_probe.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/settings/domain/services/live_llm_vision_probes.dart -> lib/features/chat/data/datasources/chat_datasource.dart',
  'lib/features/watch/domain/watch_approval_mapper.dart -> lib/features/chat/presentation/providers/chat_state.dart',
};

const String _packagePrefix = 'package:caverno/';

final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

final RegExp _layerPath = RegExp(
  r'^lib/features/[^/]+/(domain|data|presentation|application)/',
);

/// Returns the rule an import from [sourceLayer] into [targetLayer] breaks,
/// or null when the import is allowed.
String? _brokenRule(String sourceLayer, String targetLayer) {
  if (sourceLayer == 'domain' &&
      const {
        'data',
        'presentation',
        'application',
        'flutter',
      }.contains(targetLayer)) {
    return 'domain must not import $targetLayer';
  }
  if (sourceLayer == 'data' && targetLayer == 'presentation') {
    return 'data must not import presentation';
  }
  return null;
}

String? _layerOf(String path) => _layerPath.firstMatch(path)?.group(1);

/// Collapses `.` and `..` segments of a `/`-separated relative path.
String _normalize(String path) {
  final segments = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

/// Maps every rule-breaking `source -> target` edge to the rule it breaks.
Map<String, String> _currentViolations() {
  final violations = <String, String>{};
  final files =
      Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.replaceAll(r'\', '/'))
          .where(
            (path) =>
                path.endsWith('.dart') &&
                !path.endsWith('.g.dart') &&
                !path.endsWith('.freezed.dart'),
          )
          .toList()
        ..sort();

  for (final source in files) {
    final sourceLayer = _layerOf(source);
    if (sourceLayer != 'domain' && sourceLayer != 'data') continue;
    final directory = source.substring(0, source.lastIndexOf('/'));
    final contents = File(source).readAsStringSync();
    for (final match in _directive.allMatches(contents)) {
      final uri = match.group(1)!;
      final String target;
      final String? targetLayer;
      if (uri.startsWith('package:flutter/')) {
        target = uri;
        targetLayer = 'flutter';
      } else if (uri.startsWith(_packagePrefix)) {
        target = 'lib/${uri.substring(_packagePrefix.length)}';
        targetLayer = _layerOf(target);
      } else if (!uri.startsWith('package:') && !uri.startsWith('dart:')) {
        target = _normalize('$directory/$uri');
        targetLayer = _layerOf(target);
      } else {
        continue;
      }
      if (targetLayer == null) continue;
      final rule = _brokenRule(sourceLayer!, targetLayer);
      if (rule != null) violations['$source -> $target'] = rule;
    }
  }
  return violations;
}

void main() {
  test('cross-layer imports do not grow', () {
    final current = _currentViolations();
    final added = current.keys.where((e) => !_reviewedEdges.contains(e));

    expect(
      added,
      isEmpty,
      reason:
          'New cross-layer imports:\n'
          '${added.map((edge) => '  $edge  (${current[edge]})').join('\n')}\n'
          'Move the shared type to the lower layer, or inject it, instead of '
          'adding the edge to _reviewedEdges.',
    );
  });

  test('fixed cross-layer imports are removed from the ratchet', () {
    final current = _currentViolations();
    final stale = _reviewedEdges.where((e) => !current.containsKey(e));

    expect(
      stale,
      isEmpty,
      reason:
          'These edges no longer exist; delete them from _reviewedEdges so '
          'they cannot come back:\n${stale.map((e) => '  $e').join('\n')}',
    );
  });

  test('resolves relative and package imports to the same edge', () {
    expect(
      _normalize('lib/features/a/domain/../data/x.dart'),
      'lib/features/a/data/x.dart',
    );
    expect(_brokenRule('domain', 'data'), isNotNull);
    expect(_brokenRule('domain', 'flutter'), isNotNull);
    expect(_brokenRule('data', 'presentation'), isNotNull);
    expect(_brokenRule('data', 'domain'), isNull);
    expect(_brokenRule('presentation', 'data'), isNull);
  });
}
