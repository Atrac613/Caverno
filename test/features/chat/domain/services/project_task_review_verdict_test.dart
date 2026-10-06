import 'dart:convert';

import 'package:caverno/features/chat/domain/services/project_task_review_verdict.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String report(String status, List<Object?> findings) => jsonEncode({
    'status': status,
    'findings': findings,
    'verificationLimits': ['The runtime check could not run.'],
    'summary': 'Inspected the current patch.',
  });

  test('renders a structured finding and preserves verification limits', () {
    final verdict = ProjectTaskReviewVerdict.fromResponse(
      report('findings', ['watcher.py:163: reject non-finite intervals.']),
    );
    expect(verdict.disposition, ProjectTaskReviewDisposition.findings);
    expect(verdict.response, contains('reject non-finite intervals'));
    expect(verdict.response, contains('The runtime check could not run.'));
    expect(verdict.response, endsWith(ProjectTaskReviewVerdict.findingsMarker));
  });

  test('clean cannot discard structured findings', () {
    final verdict = ProjectTaskReviewVerdict.fromResponse(
      report('clean', ['watcher.py:163: reject Infinity.']),
    );
    expect(verdict.isComplete, isFalse);
    expect(verdict.response, contains('reject Infinity'));
    expect(
      verdict.response,
      isNot(contains(ProjectTaskReviewVerdict.cleanMarker)),
    );
  });

  for (final raw in [
    '**Review findings: fixes required**\nwatcher.py:163 accepts Infinity.',
    '{"status":"clean"}',
    report('findings', []),
    report('unknown', []),
    report('findings', [1]),
    '${ProjectTaskReviewVerdict.cleanMarker}\n${ProjectTaskReviewVerdict.findingsMarker}',
    ProjectTaskReviewVerdict.cleanMarker,
  ]) {
    test('fails closed for an incomplete or conflicting report: $raw', () {
      expect(ProjectTaskReviewVerdict.fromResponse(raw).isComplete, isFalse);
    });
  }

  test('accepts fenced JSON and the legacy explicit marker protocol', () {
    expect(
      ProjectTaskReviewVerdict.fromResponse(
        '```json\n${report('clean', [])}\n```',
      ).disposition,
      ProjectTaskReviewDisposition.clean,
    );
    expect(
      ProjectTaskReviewVerdict.fromResponse(
        'Fix the null case.\n${ProjectTaskReviewVerdict.findingsMarker}',
      ).disposition,
      ProjectTaskReviewDisposition.findings,
    );
  });
}
