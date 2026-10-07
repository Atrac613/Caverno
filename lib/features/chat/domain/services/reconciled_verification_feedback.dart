import 'dart:convert';

import '../entities/tool_call_info.dart';

/// Removes only feedback tied to superseded or advisory source invocations.
abstract final class ReconciledVerificationFeedback {
  static List<ToolResultInfo> filter(
    List<ToolResultInfo> results,
    Set<String> supersededIds,
    Set<String> advisorySourceIds,
  ) {
    final current = <ToolResultInfo>[];
    for (var resultIndex = 0; resultIndex < results.length; resultIndex++) {
      final result = results[resultIndex];
      if (supersededIds.contains(result.id)) continue;
      if (result.name != 'coding_output_feedback') {
        current.add(result);
        continue;
      }
      final decoded = _decode(result.result);
      final issues = decoded?['issues'];
      final diagnostics = decoded?['diagnostics'];
      if (issues is! List ||
          diagnostics is! List ||
          issues.length != diagnostics.length) {
        current.add(result);
        continue;
      }
      final retained = <int>[];
      for (var index = 0; index < issues.length; index++) {
        final issue = issues[index];
        final sourceId = issue is Map ? issue['tool_call_id'] : null;
        final sourceIndex = sourceId == null && issue is Map
            ? results
                  .take(resultIndex)
                  .toList()
                  .lastIndexWhere(
                    (source) =>
                        source.name == issue['tool_name'] &&
                        (_decode(source.result)?['command'] ??
                                source.arguments['command']) ==
                            issue['command'] &&
                        (_decode(source.result)?['working_directory'] ??
                                source.arguments['working_directory']) ==
                            issue['working_directory'],
                  )
            : -1;
        final source = sourceId is String
            ? sourceId
            : sourceIndex >= 0
            ? results[sourceIndex].id
            : null;
        final settled =
            source != null &&
            (supersededIds.contains(source) ||
                advisorySourceIds.contains(source));
        if (!settled) retained.add(index);
      }
      if (retained.length == issues.length) {
        current.add(result);
      } else if (retained.isNotEmpty) {
        current.add(
          ToolResultInfo(
            id: result.id,
            name: result.name,
            arguments: result.arguments,
            result: jsonEncode({
              ...decoded!,
              'issues': [for (final index in retained) issues[index]],
              'diagnostics': [for (final index in retained) diagnostics[index]],
            }),
          ),
        );
      }
    }
    return current;
  }

  static Map<String, dynamic>? _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
