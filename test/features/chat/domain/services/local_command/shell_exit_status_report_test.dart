import 'package:caverno/features/chat/domain/services/local_command/shell_exit_status_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const invocation = '.venv/bin/python app.py --dry-run 2>&1 | head -40';
  const reporter = r'; echo "PIPELINE_EXIT=${PIPESTATUS[0]:-n/a}"';

  test('binds the final report to the preceding literal invocation', () {
    final report = ShellExitStatusReport.parse('$invocation$reporter')!;
    expect(report.command, invocation);
    expect(report.exitCode('usage error\nPIPELINE_EXIT=2\n'), 2);
    expect(report.exitCode('network failure\nPIPELINE_EXIT=120\n'), 120);
    expect(report.exitCode('done\nPIPELINE_EXIT=0\n'), 0);
  });

  test('missing or malformed reports cannot establish success', () {
    final report = ShellExitStatusReport.parse('$invocation$reporter')!;
    for (final output in [
      'done',
      'PIPELINE_EXIT=n/a',
      'OTHER_EXIT=0',
      'PIPELINE_EXIT=0\nmore output',
      'PIPELINE_EXIT=0 trailing text',
      'PIPELINE_EXIT=256',
    ]) {
      expect(report.exitCode(output), isNull, reason: output);
    }
  });

  test('a direct status report also identifies a literal command', () {
    final report = ShellExitStatusReport.parse(
      r'python3 app.py 2>&1; echo "RESULT=$?"',
    )!;
    expect(report.exitCode('RESULT=1'), 1);
  });

  test('unknown shell syntax never reconciles a different invocation', () {
    for (final command in [
      r'python3 app.py | head -40; echo "RESULT=$?"',
      r'python3 app.py | tee output.log; echo "RESULT=${PIPESTATUS[0]}"',
      r'python3 app.py; true; echo "RESULT=${PIPESTATUS[0]}"',
      r'python3 app.py && true; echo "RESULT=${PIPESTATUS[0]}"',
      r'python3 app.py | head -40; echo "RESULT=${PIPESTATUS[1]}"',
      r'python3 app.py; echo "RESULT=0"',
      r'! python3 app.py; echo "RESULT=${PIPESTATUS[0]}"',
      r'python3 $(choose.py); echo "RESULT=$?"',
      'python3 app.py\necho "RESULT=\$?"',
    ]) {
      expect(ShellExitStatusReport.parse(command), isNull, reason: command);
    }
  });
}
