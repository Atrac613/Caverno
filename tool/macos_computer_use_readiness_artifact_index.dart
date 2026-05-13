import 'dart:io';

import '../integration_test/test_support/macos_computer_use_readiness_artifact_index.dart';

Future<void> main(List<String> args) async {
  var reportRootPath = 'build/integration_test_reports';
  String? outputJsonPath;
  String? outputMarkdownPath;

  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    switch (arg) {
      case '--root':
        index += 1;
        if (index >= args.length) {
          return _usageError('--root requires a value.');
        }
        reportRootPath = args[index];
      case '--output-json':
        index += 1;
        if (index >= args.length) {
          return _usageError('--output-json requires a value.');
        }
        outputJsonPath = args[index];
      case '--output-md':
        index += 1;
        if (index >= args.length) {
          return _usageError('--output-md requires a value.');
        }
        outputMarkdownPath = args[index];
      case '--help':
        _printUsage();
        return;
      default:
        return _usageError('Unknown option: $arg');
    }
  }

  final reportRoot = Directory(reportRootPath);
  final index = await writeReadinessArtifactIndex(
    reportRoot,
    outputJsonPath: outputJsonPath,
    outputMarkdownPath: outputMarkdownPath,
  );
  stdout.writeln('Readiness artifact index written under ${reportRoot.path}');
  final outputJson =
      outputJsonPath ??
      '${reportRoot.path}/macos_computer_use_readiness_artifact_index.json';
  final outputMarkdown =
      outputMarkdownPath ??
      '${reportRoot.path}/macos_computer_use_readiness_artifact_index.md';
  stdout.writeln('Artifact index outputs:');
  stdout.writeln('- JSON: $outputJson');
  stdout.writeln('- Markdown: $outputMarkdown');
  stdout.writeln('Artifact index PR Review Summary: $outputMarkdown');
  final rehearsal = index.mvpFinalSignoffRehearsal;
  stdout.writeln(
    'MVP final sign-off rehearsal: ${rehearsal.ready ? 'ready' : 'blocked'}',
  );
  stdout.writeln(
    'Missing MVP artifacts: ${rehearsal.missingArtifactIds.isEmpty ? 'none' : rehearsal.missingArtifactIds.join(', ')}',
  );
  stdout.writeln('Required artifact paths:');
  for (final artifact in rehearsal.requiredArtifacts) {
    stdout.writeln(
      '- ${artifact.id}: ${artifact.exists ? artifact.path : 'missing'}',
    );
  }
  final prSummary = rehearsal.prReviewSummary;
  stdout.writeln('PR review summary:');
  stdout.writeln('- Status: ${prSummary.status}');
  stdout.writeln(
    '- Ready artifacts: ${_joinedOrNone(prSummary.readyArtifactIds)}',
  );
  stdout.writeln(
    '- Missing artifacts: ${_joinedOrNone(prSummary.missingArtifactIds)}',
  );
  stdout.writeln(
    '- Pending user-operated evidence: ${_joinedOrNone(prSummary.pendingUserOperatedEvidenceIds)}',
  );
  stdout.writeln(
    '- Pending automation-safe evidence: ${_joinedOrNone(prSummary.pendingAutomationSafeEvidenceIds)}',
  );
  stdout.writeln('- Boundary: ${prSummary.operationBoundarySummary}');
  stdout.writeln(
    '- Report-only preflight command: ${rehearsal.reportOnlyPreflightCommand}',
  );
  stdout.writeln('Operation boundary:');
  for (final entry in rehearsal.operationBoundary.entries) {
    stdout.writeln('- ${entry.key}: ${entry.value}');
  }
  if (rehearsal.finalAggregationCommand != null) {
    stdout.writeln('Final MVP aggregation command:');
    stdout.writeln(rehearsal.finalAggregationCommand);
  }
  if (rehearsal.m15ActionProposalCommand != null) {
    stdout.writeln('M15 action proposal command:');
    stdout.writeln(rehearsal.m15ActionProposalCommand);
  }
  if (rehearsal.m15LlmReviewCommand != null) {
    stdout.writeln('M15 LLM review command:');
    stdout.writeln(rehearsal.m15LlmReviewCommand);
  }
  if (rehearsal.m16ApprovalPacketCommand != null) {
    stdout.writeln('M16 approval packet command:');
    stdout.writeln(rehearsal.m16ApprovalPacketCommand);
  }
  if (rehearsal.m17ExecutionRehearsalCommand != null) {
    stdout.writeln('M17 execution rehearsal command:');
    stdout.writeln(rehearsal.m17ExecutionRehearsalCommand);
  }
  if (rehearsal.m18ExecutionHandoffCommand != null) {
    stdout.writeln('M18 execution handoff command:');
    stdout.writeln(rehearsal.m18ExecutionHandoffCommand);
  }
  if (rehearsal.m20ExecutionResultIntakeCommand != null) {
    stdout.writeln('M20 execution result intake command:');
    stdout.writeln(rehearsal.m20ExecutionResultIntakeCommand);
  }
  if (rehearsal.m22PostActionReviewCommand != null) {
    stdout.writeln('M22 post-action review command:');
    stdout.writeln(rehearsal.m22PostActionReviewCommand);
  }
  if (rehearsal.m23CycleOutcomeHandoffCommand != null) {
    stdout.writeln('M23 cycle outcome handoff command:');
    stdout.writeln(rehearsal.m23CycleOutcomeHandoffCommand);
  }
  if (rehearsal.m25NextCycleSeedHandoffCommand != null) {
    stdout.writeln('M25 next-cycle seed handoff command:');
    stdout.writeln(rehearsal.m25NextCycleSeedHandoffCommand);
  }
  if (rehearsal.m26ObserveRestartPacketCommand != null) {
    stdout.writeln('M26 observe restart packet command:');
    stdout.writeln(rehearsal.m26ObserveRestartPacketCommand);
  }
  if (rehearsal.m27ScreenshotRequestHandoffCommand != null) {
    stdout.writeln('M27 screenshot request handoff command:');
    stdout.writeln(rehearsal.m27ScreenshotRequestHandoffCommand);
  }
  if (rehearsal.m28ScreenshotEvidenceIntakeCommand != null) {
    stdout.writeln('M28 screenshot evidence intake command:');
    stdout.writeln(rehearsal.m28ScreenshotEvidenceIntakeCommand);
  }
  if (rehearsal.m29ObserveCanaryRunPacketCommand != null) {
    stdout.writeln('M29 observe canary run packet command:');
    stdout.writeln(rehearsal.m29ObserveCanaryRunPacketCommand);
  }
  if (rehearsal.m30ObserveResultIntakeCommand != null) {
    stdout.writeln('M30 observe result intake command:');
    stdout.writeln(rehearsal.m30ObserveResultIntakeCommand);
  }
  if (rehearsal.missingArtifactActions.isNotEmpty) {
    stdout.writeln('Missing MVP artifact checklist:');
    for (final action in rehearsal.missingArtifactActions) {
      stdout.writeln(
        '- ${action.artifactId} (${action.label}): ${action.nextAction}',
      );
    }
  }
  if (rehearsal.nextActions.isNotEmpty) {
    stdout.writeln('MVP rehearsal next actions:');
    for (final action in rehearsal.nextActions) {
      stdout.writeln('- $action');
    }
  }
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/macos_computer_use_readiness_artifact_index.dart '
    '[--root path] [--output-json path] [--output-md path]',
  );
}

void _usageError(String message) {
  stderr.writeln(message);
  _printUsage();
  exitCode = 64;
}

String _joinedOrNone(List<String> values) {
  if (values.isEmpty) {
    return 'none';
  }
  return values.join(', ');
}
