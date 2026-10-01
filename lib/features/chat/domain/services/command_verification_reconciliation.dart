import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/tool_call_info.dart';
import 'pytest_verification_identity.dart';
import 'verification_scope.dart';

/// Settles earlier invocations only after the same verification actually passes.
abstract final class CommandVerificationReconciliation {
  static List<ToolResultInfo> currentResults(List<ToolResultInfo> results) {
    final successfulScopes = <String>{};
    final supersededIds = <String>{};
    for (var index = results.length - 1; index >= 0; index--) {
      final result = results[index];
      final scope = VerificationScope.of(
        result,
        _decode(result.result),
        isVerification: isVerification,
      );
      if (scope == null) continue;
      if (successfulScopes.contains(scope.key)) {
        supersededIds.add(result.id);
      }
      if (scope.passed) successfulScopes.add(scope.key);
    }
    if (supersededIds.isEmpty) return results;
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
        final settled = sourceId is String
            ? supersededIds.contains(sourceId)
            : sourceIndex >= 0 &&
                  supersededIds.contains(results[sourceIndex].id);
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

  static bool isVerification(ToolResultInfo result) {
    final name = result.name.trim().toLowerCase();
    if (name == 'local_execute_command') {
      final decoded = _decode(result.result);
      if (PytestVerificationIdentity.parse(
            (decoded?['command'] ?? result.arguments['command'])?.toString() ??
                '',
            (decoded?['working_directory'] ??
                        result.arguments['working_directory'])
                    ?.toString() ??
                '',
          ) !=
          null) {
        return true;
      }
    }
    if (name == 'local_execute_command' || name == 'git_execute_command') {
      return const ToolCapabilityClassifier()
              .classify(result.name, arguments: result.arguments)
              .commandEffect ==
          ToolCommandEffect.verification;
    }
    return const {
      'analyze_project',
      'run_tests',
      'process_start',
      'process_wait',
    }.contains(name);
  }

  static bool hasFailedFeedback(List<ToolResultInfo> results, int afterIndex) =>
      results.skip(afterIndex + 1).any((result) {
        if (result.name.trim().toLowerCase() != 'coding_output_feedback') {
          return false;
        }
        final decoded = _decode(result.result);
        return decoded?['success'] == false ||
            decoded?['validation_status']?.toString().trim().toLowerCase() ==
                'failed';
      });

  static Map<String, dynamic>? _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
