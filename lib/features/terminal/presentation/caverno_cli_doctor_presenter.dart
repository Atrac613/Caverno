import 'dart:convert';

import '../application/caverno_cli_contract.dart';
import '../application/caverno_cli_doctor.dart';
import 'caverno_cli_redactor.dart';
import 'caverno_terminal_presenter.dart';

final class CavernoCliDoctorPresenter {
  const CavernoCliDoctorPresenter({
    required this.outputMode,
    required this.output,
    required this.redactor,
  });

  final CavernoCliOutputMode outputMode;
  final CavernoTerminalOutputPort output;
  final CavernoCliRedactor redactor;

  void present(CavernoCliDoctorReport report) {
    if (outputMode == CavernoCliOutputMode.json) {
      final safe = redactor.redactJson(report.toJson());
      output.writeStdout('${jsonEncode(safe)}\n');
      return;
    }

    output.writeStdout('Caverno doctor: ${report.status.name}\n');
    for (final check in report.checks) {
      final label = check.status.name.toUpperCase().padRight(7);
      output.writeStdout(
        redactor.redact('[$label] ${check.id}: ${check.message}\n'),
      );
      final remediation = check.remediation;
      if (remediation != null) {
        output.writeStdout(redactor.redact('          $remediation\n'));
      }
    }
  }
}
