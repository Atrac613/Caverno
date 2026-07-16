import 'dart:convert';

import 'package:caverno/features/terminal/application/caverno_cli_contract.dart';
import 'package:caverno/features/terminal/application/caverno_cli_doctor.dart';
import 'package:caverno/features/terminal/presentation/caverno_cli_doctor_presenter.dart';
import 'package:caverno/features/terminal/presentation/caverno_cli_redactor.dart';
import 'package:caverno/features/terminal/presentation/caverno_terminal_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final report = CavernoCliDoctorReport(
    configuration: const <String, Object?>{
      'endpoint': 'http://localhost:1234/v1',
      'model': 'qwen',
    },
    checks: const <CavernoCliDoctorCheck>[
      CavernoCliDoctorCheck(
        id: 'configuration',
        status: CavernoCliDoctorCheckStatus.pass,
        message: 'Credential doctor-secret is configured.',
        durationMs: 0,
      ),
    ],
  );

  test('emits one redacted schema-versioned JSON line', () {
    final output = _RecordingOutput();
    CavernoCliDoctorPresenter(
      outputMode: CavernoCliOutputMode.json,
      output: output,
      redactor: CavernoCliRedactor(secrets: const <String>['doctor-secret']),
    ).present(report);

    expect('\n'.allMatches(output.stdout.toString()), hasLength(1));
    final decoded =
        jsonDecode(output.stdout.toString()) as Map<String, dynamic>;
    expect(decoded['schemaName'], CavernoCliDoctorReport.schemaName);
    expect(decoded['schemaVersion'], CavernoCliDoctorReport.schemaVersion);
    expect(decoded['type'], 'doctor_report');
    expect(output.stdout.toString(), isNot(contains('doctor-secret')));
    expect(output.stderr, isEmpty);
  });

  test('emits concise redacted human checks', () {
    final output = _RecordingOutput();
    CavernoCliDoctorPresenter(
      outputMode: CavernoCliOutputMode.human,
      output: output,
      redactor: CavernoCliRedactor(secrets: const <String>['doctor-secret']),
    ).present(report);

    expect(output.stdout.toString(), contains('Caverno doctor: ready'));
    expect(output.stdout.toString(), contains('[PASS'));
    expect(output.stdout.toString(), contains('[REDACTED]'));
    expect(output.stdout.toString(), isNot(contains('doctor-secret')));
  });
}

final class _RecordingOutput implements CavernoTerminalOutputPort {
  final stdout = StringBuffer();
  final stderr = StringBuffer();

  @override
  void writeStderr(String value) => stderr.write(value);

  @override
  void writeStdout(String value) => stdout.write(value);
}
