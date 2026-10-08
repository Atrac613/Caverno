import 'package:caverno/features/chat/domain/services/local_command/local_command_approval_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gateTitle = 'This command has host-wide filesystem access';
  const gateRationale = 'It runs through the native shell.';

  test('keeps the gate heading and body for other prompts', () {
    final prompt = LocalCommandApprovalPrompt.compose(
      command: 'bash tool/x.sh',
      decisionSource: 'auto_review',
      gateTitle: 'Auto-review escalated',
      gateRationale: 'Reviewer was unsure.',
      riskTitle: 'Recursive file deletion',
      riskMessage: 'Removes files.',
    );
    expect(prompt.title, 'Auto-review escalated');
    expect(prompt.message, 'Reviewer was unsure.\n\nRemoves files.');
  });

  test('falls back to the risk text when the gate has none', () {
    final prompt = LocalCommandApprovalPrompt.compose(
      command: 'rm -rf build',
      decisionSource: null,
      gateTitle: null,
      gateRationale: null,
      riskTitle: 'Recursive file deletion',
      riskMessage: 'Removes files.',
    );
    expect(prompt.title, 'Recursive file deletion');
    expect(prompt.message, 'Removes files.');
  });

  test('puts the specific risk first on a SEC4.4g prompt', () {
    final prompt = LocalCommandApprovalPrompt.compose(
      command: 'rm -rf build > log.txt',
      decisionSource: 'opaque_host_write',
      gateTitle: gateTitle,
      gateRationale: gateRationale,
      riskTitle: 'Recursive file deletion',
      riskMessage: 'Removes files.',
    );
    expect(prompt.title, 'Recursive file deletion');
    expect(
      prompt.message,
      '$gateRationale\n\nRemoves files.\n\n• Writes output to `log.txt`.',
    );
  });

  test('tells two SEC4.4g prompts apart by their effects', () {
    String? messageFor(String command) => LocalCommandApprovalPrompt.compose(
      command: command,
      decisionSource: 'opaque_host_write',
      gateTitle: gateTitle,
      gateRationale: gateRationale,
      riskTitle: null,
      riskMessage: null,
    ).message;

    expect(messageFor('git status --short'), gateRationale);
    expect(
      messageFor("python3 -c 'print(1)'"),
      '$gateRationale\n\n• Runs an inline `python3` program; what it reads '
      'or writes is decided by that program.',
    );
  });
}
