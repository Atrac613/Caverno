import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_report_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = MaintenanceReportFormatter();

  MaintenanceRunReport report(List<MaintenanceStageResult> stages) {
    return MaintenanceRunReport(
      startedAt: DateTime(2026, 6, 16, 3),
      finishedAt: DateTime(2026, 6, 16, 3, 0, 5),
      stages: stages,
    );
  }

  test('summarizes counts in the title and table in the body', () {
    final formatted = formatter.format(
      report([
        const MaintenanceStageResult(
          name: 'probe',
          status: MaintenanceStageStatus.completed,
          detail: 'profiled',
          duration: Duration(milliseconds: 1200),
        ),
        const MaintenanceStageResult(
          name: 'adopt',
          status: MaintenanceStageStatus.skipped,
          detail: 'gate not passed',
        ),
      ]),
    );

    expect(formatted.title, 'Idle maintenance: 1 done');
    expect(formatted.body, contains('# Idle maintenance report'));
    expect(formatted.body, contains('Duration: 5.0s'));
    expect(
      formatted.body,
      contains('completed 1, skipped 1, failed 0, cancelled 0'),
    );
    expect(formatted.body, contains('| probe | completed | profiled | 1.2s |'));
    expect(formatted.body, contains('| adopt | skipped | gate not passed |'));
  });

  test('surfaces failures and cancellations in the title', () {
    final formatted = formatter.format(
      report([
        const MaintenanceStageResult(
          name: 'probe',
          status: MaintenanceStageStatus.failed,
          detail: 'endpoint down',
        ),
        const MaintenanceStageResult(
          name: 'eval',
          status: MaintenanceStageStatus.cancelled,
        ),
      ]),
    );

    expect(formatted.title, 'Idle maintenance: 0 done, 1 failed, 1 cancelled');
  });

  test('escapes pipes/newlines in a detail so the table stays intact', () {
    final formatted = formatter.format(
      report([
        const MaintenanceStageResult(
          name: 'eval',
          status: MaintenanceStageStatus.failed,
          detail: 'a | b\nc',
        ),
      ]),
    );
    expect(formatted.body, contains(r'a \| b c'));
  });

  test('still produces a report when no stages were configured', () {
    final formatted = formatter.format(report(const []));
    expect(formatted.title, 'Idle maintenance: nothing to do');
    expect(formatted.body, contains('No maintenance stages were configured.'));
  });
}
