import 'dart:convert';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'background_process_monitor_service.dart';
import 'mcp_tool_result_normalizer.dart';

Future<McpToolResult> executeBackgroundProcessList({
  required BackgroundProcessMonitorService? monitor,
  required ChatTurnOwner owner,
  required String toolName,
  required Map<String, dynamic> arguments,
  required DateTime Function() clock,
}) async {
  if (monitor == null) {
    return McpToolResultNormalizer.structuredFailure(
      toolName: toolName,
      payload: const {
        'ok': false,
        'code': 'background_process_monitor_unavailable',
        'error': 'Background process monitor is not available',
      },
      errorMessage: 'Background process monitor is not available',
    );
  }
  final jobIds = switch (arguments['job_ids']) {
    null => const <String>[],
    final List<dynamic> values =>
      values
          .whereType<String>()
          .map((jobId) => jobId.trim())
          .where((jobId) => jobId.isNotEmpty)
          .toList(growable: false),
    _ => null,
  };
  if (jobIds == null) {
    return McpToolResultNormalizer.structuredFailure(
      toolName: toolName,
      payload: const {
        'ok': false,
        'code': 'invalid_job_ids',
        'error': 'job_ids must be an array of strings',
      },
      errorMessage: 'job_ids must be an array of strings',
    );
  }
  if (arguments['refresh'] == true) {
    await (jobIds.isEmpty
        ? monitor.refreshActiveJobs(owner)
        : monitor.refreshJobs(owner, jobIds));
  }
  final snapshots = monitor.listJobs(
    owner,
    jobIds: jobIds,
    includeFinished: arguments['include_finished'] is bool
        ? arguments['include_finished'] as bool
        : true,
    limit: (arguments['limit'] as num?)?.toInt(),
  );
  return McpToolResultNormalizer.success(
    toolName: toolName,
    result: jsonEncode({
      'ok': true,
      'generated_at': clock().toIso8601String(),
      'job_count': snapshots.length,
      'jobs': snapshots.map((snapshot) => snapshot.toJson()).toList(),
      'active_count': monitor.activeSnapshots(owner).length,
      'finished_count': snapshots
          .where((snapshot) => !snapshot.isRunning)
          .length,
    }),
  );
}
