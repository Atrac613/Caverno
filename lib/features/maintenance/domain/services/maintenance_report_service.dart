import 'maintenance_pipeline.dart';
import 'maintenance_report_formatter.dart';

/// Sink that delivers a formatted morning report (e.g. a local notification).
typedef MaintenanceReportSink =
    Future<void> Function(String title, String body);

/// LL18: formats a [MaintenanceRunReport] and delivers it through the injected
/// [MaintenanceReportSink]. Always delivers — even an empty, all-skipped, or
/// cancelled run produces a report — so the user gets a single morning summary.
class MaintenanceReportService {
  const MaintenanceReportService({
    required MaintenanceReportSink sink,
    MaintenanceReportFormatter formatter = const MaintenanceReportFormatter(),
  }) : _sink = sink,
       _formatter = formatter;

  final MaintenanceReportSink _sink;
  final MaintenanceReportFormatter _formatter;

  Future<void> deliver(MaintenanceRunReport report) async {
    final formatted = _formatter.format(report);
    await _sink(formatted.title, formatted.body);
  }
}
