import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:path/path.dart' as path;

import '../entities/tool_call_info.dart';
import 'literal_environment_inspection_policy.dart';
import 'literal_shell_segments.dart';
import 'literal_shell_words.dart';
import 'python/pytest_metadata_inspection_policy.dart';

/// Classifies execution evidence only, never approval or mutation freshness.
abstract final class VerificationMetadataQueryPolicy {
  static bool applies(String command) {
    final segments = LiteralShellSegments.parse(command);
    if (segments == null) return false;
    var queried = false;
    for (final segment in segments) {
      if (LiteralEnvironmentInspectionPolicy.applies(segment) ||
          _isVersionQuery(segment)) {
        queried = true;
        continue;
      }
      // A literal `echo` only separates a probe's output. Session d27e7528's
      // `pip list | grep -i pytest; echo "---"; python -c "import pytest; ..."`
      // otherwise read as a check that had to pass.
      if (LiteralShellWords.parse(segment.trim())?.first == 'echo') continue;
      // Discovery probes mix version queries with plain reads such as
      // `cat requirements.txt` or `ls -a | grep venv`. Those verify nothing
      // either, so they must not turn the probe into required verification:
      // in session 1afd70a6 a probe of a broken host interpreter became the
      // check the turn had to make pass. A lone read never sets [queried].
      if (const ToolCapabilityClassifier()
              .classify(
                'local_execute_command',
                arguments: {'command': segment},
              )
              .commandEffect !=
          ToolCommandEffect.inspection) {
        return false;
      }
    }
    return queried;
  }

  static bool _isVersionQuery(String segment) {
    final query = segment
        .trim()
        .replaceFirst(
          RegExp(r'\s*\|\s*(?:head|tail)\s+-(?:n\s*)?[1-9]\d*\s*$'),
          '',
        )
        // A package-name filter only narrows what the query prints.
        .replaceFirst(
          RegExp(r'\s*\|\s*grep(?:\s+-i)?\s+[A-Za-z0-9_.-]+\s*$'),
          '',
        )
        .replaceFirst(RegExp(r'\s+(?:2>\s*/dev/null|2>&1)\s*$'), '');
    final words = LiteralShellWords.parse(query.trim());
    if (words == null) return false;
    final executable = path.basename(words.first);
    final args = words.skip(1).toList();
    if (RegExp(r'^python(?:\d+(?:\.\d+)*)?$').hasMatch(executable)) {
      return args.length == 3 &&
              args[0] == '-m' &&
              (const {'pip', 'pytest'}.contains(args[1]) &&
                      args[2] == '--version' ||
                  args[1] == 'pip' && args[2] == 'list') ||
          PytestMetadataInspectionPolicy.applies(args);
    }
    return RegExp(r'^(?:pip|pytest)(?:\d+(?:\.\d+)*)?$').hasMatch(executable) &&
            args.length == 1 &&
            args.single == '--version' ||
        RegExp(r'^pip\d*(?:\.\d+)*$').hasMatch(executable) &&
            args.length == 1 &&
            args.single == 'list';
  }

  static bool appliesTo(ToolResultInfo result) {
    if ((result.outcome?.effectiveTestFailedCount ?? 0) > 0 ||
        (result.outcome?.diagnosticErrorCount ?? 0) > 0) {
      return false;
    }
    Map? payload;
    try {
      final decoded = jsonDecode(result.result);
      if (decoded is Map) payload = decoded;
    } on FormatException {
      // Retain the literal captured request when output was budgeted.
    }
    return applies(
      (payload?['command'] ?? result.arguments['command'] ?? '').toString(),
    );
  }
}
