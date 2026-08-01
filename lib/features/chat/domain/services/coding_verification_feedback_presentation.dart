import 'dart:convert';

import '../entities/conversation_workflow.dart';
import '../entities/tool_call_info.dart';
import 'coding_verification_feedback_service.dart';
import 'dart_project_tooling.dart';
import 'hidden_assistant_evidence_scorer.dart';

// ChatNotifier decomposition collaborator: coding-verification-feedback-presentation

/// Formats coding-verification evidence for persistence, repair, and telemetry.
abstract final class CodingVerificationFeedbackPresentation {
  static String commandSummary(CodingVerificationSnapshot snapshot) {
    final command = snapshot.selectedAttempt?.command;
    if (command != null) {
      return [command.executable, ...command.arguments].join(' ');
    }
    final targets = snapshot.targetBatches
        .expand((batch) => batch.targets)
        .toList(growable: false);
    if (targets.isEmpty) {
      return 'coding verification';
    }
    return 'coding verification ${targets.join(' ')}';
  }

  static String progressSummary(CodingVerificationSnapshot snapshot) {
    final counts = countsSummary(snapshot);
    final suffix = counts.isEmpty ? '' : ' ($counts)';
    return switch (snapshot.validationStatus) {
      ConversationExecutionValidationStatus.passed =>
        'Coding verification passed$suffix.',
      ConversationExecutionValidationStatus.failed =>
        'Coding verification failed$suffix.',
      ConversationExecutionValidationStatus.unknown =>
        'Coding verification was inconclusive${snapshot.reason == null ? '' : ': ${snapshot.reason}'}$suffix.',
    };
  }

  static String validationSummary(CodingVerificationSnapshot snapshot) {
    if (snapshot.validationStatus ==
            ConversationExecutionValidationStatus.failed &&
        snapshot.failures.isNotEmpty) {
      final failure = snapshot.failures.first;
      final locationParts = [
        failure.absolutePath == null
            ? null
            : DartProjectPath.relativePath(
                failure.absolutePath!,
                snapshot.projectRoot,
              ),
        if (failure.line != null) 'line ${failure.line}',
      ].whereType<String>().where((part) => part.trim().isNotEmpty);
      final location = locationParts.join(':');
      final label = [
        if (location.isNotEmpty) location,
        if (failure.testName.trim().isNotEmpty) failure.testName.trim(),
      ].join(' ');
      final message = failure.message.trim().isEmpty
          ? 'Test failed.'
          : failure.message.trim();
      return label.isEmpty ? message : '$label: $message';
    }
    return progressSummary(snapshot);
  }

  static String countsSummary(CodingVerificationSnapshot snapshot) {
    final parts = <String>[
      if (snapshot.passedCount > 0) '${snapshot.passedCount} passed',
      if (snapshot.failedCount > 0) '${snapshot.failedCount} failed',
      if (snapshot.skippedCount > 0) '${snapshot.skippedCount} skipped',
    ];
    return parts.join(', ');
  }

  static bool shouldVerifyCompletionClaim(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }
    final normalized = candidate.toLowerCase();
    if (normalized.contains('not complete') ||
        normalized.contains('not completed') ||
        normalized.contains('incomplete')) {
      return false;
    }
    return HiddenAssistantEvidenceScorer.score(candidate) >= 2 ||
        normalized.contains('done');
  }

  static String? failureSignature(ToolResultInfo feedback) {
    final decoded = _tryDecodeMap(feedback.result);
    if (decoded == null) {
      return null;
    }
    final failingTests = decoded['failing_tests'];
    if (failingTests is! List || failingTests.isEmpty) {
      return null;
    }
    final entries = <Map<String, Object?>>[];
    for (final test in failingTests) {
      if (test is! Map) {
        continue;
      }
      entries.add({
        'relative_path': test['relative_path'] ?? test['path'],
        'test_name': test['test_name'],
        'line': test['line'],
        'column': test['column'],
        'message': test['message'],
      });
    }
    if (entries.isEmpty) {
      return null;
    }
    return jsonEncode({
      'provider': decoded['provider'],
      'validation_status': decoded['validation_status'],
      'failures': entries,
    });
  }

  static String convergenceBlocker(
    ToolResultInfo feedback, {
    required int maxRepairAttempts,
  }) {
    final decoded = _tryDecodeMap(feedback.result);
    final failingTests = decoded?['failing_tests'];
    final buffer = StringBuffer(
      'The coding task is not complete. The same failing tests persisted after '
      '$maxRepairAttempts repair attempts, so I am '
      'stopping the automatic repair loop.',
    );
    if (failingTests is List && failingTests.isNotEmpty) {
      buffer.writeln();
      buffer.writeln();
      buffer.writeln('Remaining failing tests:');
      for (final test in failingTests.take(5)) {
        if (test is! Map) {
          continue;
        }
        final path = test['relative_path'] ?? test['path'];
        final name = test['test_name'];
        final line = test['line'];
        final message = test['message'];
        final location = [
          if (path is String && path.isNotEmpty) path,
          if (line != null) 'line $line',
        ].join(':');
        final label = [
          if (location.isNotEmpty) location,
          if (name is String && name.isNotEmpty) name,
        ].join(' ');
        buffer.write('- ');
        if (label.isNotEmpty) {
          buffer.write(label);
          buffer.write(': ');
        }
        buffer.write(
          message is String && message.isNotEmpty ? message : 'Test failed.',
        );
        buffer.writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  static Map<String, Object?>? telemetrySummary(ToolResultInfo feedback) {
    final decoded = _tryDecodeMap(feedback.result);
    if (decoded == null) {
      return null;
    }
    final telemetry = decoded['telemetry'];
    final telemetryMap = telemetry is Map<String, dynamic> ? telemetry : null;
    final counts = decoded['counts'];
    final countsMap = counts is Map<String, dynamic> ? counts : null;
    return <String, Object?>{
      'toolName': feedback.name,
      'provider': decoded['provider'],
      'trigger': decoded['trigger'],
      'validationStatus': decoded['validation_status'],
      'files': decoded['changed_paths'],
      if (countsMap != null) ...{
        'passedCount': countsMap['passed'],
        'failedCount': countsMap['failed'],
        'skippedCount': countsMap['skipped'],
      },
      if (telemetryMap != null) ...{
        'durationMs': telemetryMap['duration_ms'],
        'commandAttemptCount': telemetryMap['command_attempt_count'],
        'fallbackCommandCount': telemetryMap['fallback_command_count'],
        'timedOutCommandCount': telemetryMap['timed_out_command_count'],
        'startErrorCommandCount': telemetryMap['start_error_command_count'],
      },
    };
  }

  static Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
