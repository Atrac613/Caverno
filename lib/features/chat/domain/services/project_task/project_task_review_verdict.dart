import 'dart:convert';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import '../../entities/tool_call_info.dart';

enum ProjectTaskReviewDisposition { clean, findings, incomplete }

/// The dedicated review's first terminal report, never a regenerated summary.
final class ProjectTaskReviewVerdict {
  ProjectTaskReviewVerdict({
    required this.disposition,
    required this.report,
    this.findings = const [],
    this.verificationLimits = const [],
  });

  static const memoryToolName = 'coding_review_status';

  static const cleanMarker = 'PROJECT_TASK_REVIEW_CLEAN';
  static const findingsMarker = 'PROJECT_TASK_REVIEW_FINDINGS';
  static const instructions =
      '''Return one JSON object with exactly these fields:
"status": "clean", "findings", or "incomplete";
"findings": an array of actionable finding strings with file locations;
"verificationLimits": an array of verification limit strings;
"summary": a concise review summary string.
Review the changed behavior independently of the implementation's success claims. Identify relevant boundaries and failure paths in the current code, then inspect or exercise them through the available read-only tools. A passing existing test suite alone does not establish that the new behavior is correct.
When changes introduce numeric configuration, examine missing/default values, zero, negative values, non-finite values, invalid types or conversions, and exception handling where relevant. Check conversion overflow before finite-value validation and the downstream API's representable range; exercise a focused counterexample when ordinary tests omit these paths. For other changes, choose boundaries appropriate to the actual behavior rather than mechanically applying this numeric checklist. Preserve project settings and do not edit files or install dependencies during review.
In "summary", state which changed behavior and boundary or failure paths were checked, with file locations or observed tool results. Put relevant checks that could not be performed in "verificationLimits"; successful checks belong in "summary". Do not invent execution evidence.
Use "clean" only after current inspection with no actionable findings. Use "findings" whenever actionable findings remain. Use "incomplete" when inspection or the review cannot finish. Do not include a prose wrapper or task completion markers. The harness renders this report and records its verdict; it does not regenerate the review.''';

  final ProjectTaskReviewDisposition disposition;
  final String report;
  final List<String> findings;
  final List<String> verificationLimits;
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
            findings: List<String>.unmodifiable(findings.cast<String>()),
            verificationLimits: List<String>.unmodifiable(
              limits.cast<String>(),
            ),
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
        findings: findings,
        verificationLimits: [...verificationLimits, reason],
      );

  String get memorySummary => switch (disposition) {
    ProjectTaskReviewDisposition.findings =>
      'The dedicated project review found defects; repair remains pending.',
    ProjectTaskReviewDisposition.incomplete =>
      'The dedicated project review remains incomplete.',
    ProjectTaskReviewDisposition.clean =>
      'The dedicated project review is clean; commit preparation remains pending.',
  };

  String get memoryNextStep => switch (disposition) {
    ProjectTaskReviewDisposition.findings =>
      'Resolve the actionable findings from the dedicated code review.',
    ProjectTaskReviewDisposition.incomplete =>
      'Finish the dedicated code review before committing the project task.',
    ProjectTaskReviewDisposition.clean =>
      'Continue the project task\'s commit preparation.',
  };

  ToolResultInfo toMemoryToolResult(String id) => ToolResultInfo(
    id: id,
    name: memoryToolName,
    arguments: const {},
    result: jsonEncode({
      'result_origin': 'harness',
      'status': disposition.name,
      'findings': _bounded(findings),
      'verificationLimits': _bounded(verificationLimits),
      'report': report.substring(0, report.length.clamp(0, 4000)),
    }),
  );

  static List<String> _bounded(List<String> values) => [
    for (final value in values.take(3))
      value.substring(0, value.length.clamp(0, 1000)),
  ];

  static ProjectTaskReviewVerdict? fromToolResults(
    List<ToolResultInfo> results,
  ) {
    for (final result in results.reversed) {
      if (result.name != memoryToolName) continue;
      try {
        final payload = jsonDecode(result.result);
        if (payload is! Map || payload['result_origin'] != 'harness') continue;
        final status = ProjectTaskReviewDisposition.values
            .where((value) => value.name == payload['status'])
            .firstOrNull;
        if (status == null ||
            payload['report'] is! String ||
            payload['findings'] is! List ||
            payload['verificationLimits'] is! List) {
          continue;
        }
        return ProjectTaskReviewVerdict(
          disposition: status,
          report: payload['report'] as String,
          findings: (payload['findings'] as List? ?? const [])
              .whereType<String>()
              .toList(),
          verificationLimits:
              (payload['verificationLimits'] as List? ?? const [])
                  .whereType<String>()
                  .toList(),
        );
      } on FormatException {
        // Untrusted or malformed payloads cannot supply a native verdict.
      }
    }
    return null;
  }
}
