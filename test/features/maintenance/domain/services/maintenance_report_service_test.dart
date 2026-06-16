import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/maintenance/domain/services/maintenance_report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats the report and delivers it through the sink', () async {
    String? sentTitle;
    String? sentBody;
    final service = MaintenanceReportService(
      sink: (title, body) async {
        sentTitle = title;
        sentBody = body;
      },
    );

    await service.deliver(
      MaintenanceRunReport(
        startedAt: DateTime(2026, 6, 16, 3),
        finishedAt: DateTime(2026, 6, 16, 3, 0, 2),
        stages: const [
          MaintenanceStageResult(
            name: 'probe',
            status: MaintenanceStageStatus.completed,
          ),
        ],
      ),
    );

    expect(sentTitle, 'Idle maintenance: 1 done');
    expect(sentBody, contains('# Idle maintenance report'));
  });

  test('delivers a report even when the run had no stages', () async {
    var delivered = false;
    final service = MaintenanceReportService(
      sink: (title, body) async {
        delivered = true;
        expect(title, 'Idle maintenance: nothing to do');
      },
    );

    await service.deliver(
      MaintenanceRunReport(
        startedAt: DateTime(2026, 6, 16, 3),
        finishedAt: DateTime(2026, 6, 16, 3),
        stages: const [],
      ),
    );

    expect(delivered, isTrue);
  });
}
