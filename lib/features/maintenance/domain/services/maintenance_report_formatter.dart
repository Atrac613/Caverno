import 'maintenance_pipeline.dart';

/// A formatted morning report: a short notification [title] and a markdown
/// [body].
class FormattedMaintenanceReport {
  const FormattedMaintenanceReport({required this.title, required this.body});

  final String title;
  final String body;
}

/// LL18: turns a [MaintenanceRunReport] into a human-readable morning report.
///
/// Produces meaningful output for every outcome — including a fully skipped or
/// cancelled run, or one where nothing was adopted — so the report is always
/// emitted. Output is English technical text, matching the personal-eval
/// suite/handoff reports.
class MaintenanceReportFormatter {
  const MaintenanceReportFormatter();

  FormattedMaintenanceReport format(MaintenanceRunReport report) {
    return FormattedMaintenanceReport(
      title: _title(report),
      body: _body(report),
    );
  }

  String _title(MaintenanceRunReport report) {
    if (report.stages.isEmpty) {
      return 'Idle maintenance: nothing to do';
    }
    final parts = <String>['${report.completedCount} done'];
    if (report.failedCount > 0) {
      parts.add('${report.failedCount} failed');
    }
    if (report.wasCancelled) {
      parts.add('${report.cancelledCount} cancelled');
    }
    return 'Idle maintenance: ${parts.join(', ')}';
  }

  String _body(MaintenanceRunReport report) {
    final buffer = StringBuffer()
      ..writeln('# Idle maintenance report')
      ..writeln()
      ..writeln('- Duration: ${_seconds(report.duration)}')
      ..writeln(
        '- Stages: ${report.stages.length} '
        '(completed ${report.completedCount}, '
        'skipped ${report.skippedCount}, '
        'failed ${report.failedCount}, '
        'cancelled ${report.cancelledCount})',
      );

    if (report.stages.isEmpty) {
      buffer
        ..writeln()
        ..writeln('No maintenance stages were configured.');
      return buffer.toString().trimRight();
    }

    buffer
      ..writeln()
      ..writeln('| Stage | Status | Detail | Duration |')
      ..writeln('|-------|--------|--------|----------|');
    for (final stage in report.stages) {
      buffer.writeln(
        '| ${stage.name} '
        '| ${stage.status.name} '
        '| ${_cell(stage.detail)} '
        '| ${_seconds(stage.duration)} |',
      );
    }

    return buffer.toString().trimRight();
  }

  String _cell(String? detail) {
    final trimmed = detail?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '-';
    }
    // Keep the markdown table intact when a detail contains pipes/newlines.
    return trimmed.replaceAll('|', '\\|').replaceAll('\n', ' ');
  }

  String _seconds(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)}s';
  }
}
