import 'dart:convert';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';

enum ProjectTaskReviewDisposition { clean, findings, incomplete }

/// The dedicated review's first terminal report, never a regenerated summary.
final class ProjectTaskReviewVerdict {
  ProjectTaskReviewVerdict({required this.disposition, required this.report});

  static const cleanMarker = 'PROJECT_TASK_REVIEW_CLEAN';
  static const findingsMarker = 'PROJECT_TASK_REVIEW_FINDINGS';
  static const instructions =
      '''Return one JSON object with exactly these fields:
"status": "clean", "findings", or "incomplete";
"findings": an array of actionable finding strings with file locations;
"verificationLimits": an array of verification limit strings;
"summary": a concise review summary string.
Use "clean" only after current inspection with no actionable findings. Use "findings" whenever actionable findings remain. Use "incomplete" when inspection or the review cannot finish. Do not include a prose wrapper or task completion markers. The harness renders this report and records its verdict; it does not regenerate the review.''';

  final ProjectTaskReviewDisposition disposition;
  final String report;
  bool get isComplete => disposition != ProjectTaskReviewDisposition.incomplete;

  factory ProjectTaskReviewVerdict.fromResponse(String response) {
    final visible = ContentParser.stripModelHistoryArtifacts(response).trim();
    var json = visible;
    if (json.startsWith('```json\n') && json.endsWith('\n```')) {
      json = json.substring(8, json.length - 4).trim();
    }
    try {
      final value = jsonDecode(json);
      if (value is Map<String, dynamic> &&
          value.length == 4 &&
          value['summary'] is String &&
          (value['summary'] as String).trim().isNotEmpty &&
          value['findings'] is List &&
          value['verificationLimits'] is List) {
        final findings = value['findings'] as List;
        final limits = value['verificationLimits'] as List;
        if (findings.every(
              (item) => item is String && item.trim().isNotEmpty,
            ) &&
            limits.every((item) => item is String && item.trim().isNotEmpty)) {
          final status = switch (value['status']) {
            'clean' when findings.isEmpty => ProjectTaskReviewDisposition.clean,
            'findings' when findings.isNotEmpty =>
              ProjectTaskReviewDisposition.findings,
            _ => ProjectTaskReviewDisposition.incomplete,
          };
          return ProjectTaskReviewVerdict(
            disposition: status,
            report: [
              value['summary'] as String,
              for (final finding in findings) '- $finding',
              if (limits.isNotEmpty) 'Verification limits:',
              for (final limit in limits) '- $limit',
            ].where((line) => line.trim().isNotEmpty).join('\n\n'),
          );
        }
      }
    } on FormatException {
      // Older review routes can still use the explicit terminal protocol.
    }
    final lastLine = visible.split('\n').last.trim();
    final conflicting =
        visible.split('\n').any((line) => line.trim() == cleanMarker) &&
        visible.split('\n').any((line) => line.trim() == findingsMarker);
    final status = switch (conflicting ? '' : lastLine) {
      cleanMarker => ProjectTaskReviewDisposition.clean,
      findingsMarker => ProjectTaskReviewDisposition.findings,
      _ => ProjectTaskReviewDisposition.incomplete,
    };
    return ProjectTaskReviewVerdict(
      disposition: visible == lastLine
          ? ProjectTaskReviewDisposition.incomplete
          : status,
      report: visible
          .split('\n')
          .where(
            (line) =>
                line.trim() != cleanMarker && line.trim() != findingsMarker,
          )
          .join('\n')
          .trim(),
    );
  }

  String get response => switch (disposition) {
    ProjectTaskReviewDisposition.clean => '$report\n\n$cleanMarker',
    ProjectTaskReviewDisposition.findings => '$report\n\n$findingsMarker',
    ProjectTaskReviewDisposition.incomplete =>
      'The dedicated review is incomplete.\n\n$report',
  };

  ProjectTaskReviewVerdict incomplete(String reason) =>
      ProjectTaskReviewVerdict(
        disposition: ProjectTaskReviewDisposition.incomplete,
        report: '$reason\n\n$report',
      );
}
