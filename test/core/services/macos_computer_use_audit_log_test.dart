import 'package:caverno/core/services/macos_computer_use_audit_log.dart';
import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records redacted computer-use audit entries', () {
    final auditLog = MacosComputerUseAuditLog(maxEntries: 2);
    final policy = MacosComputerUseToolPolicy.decision('computer_click');

    auditLog.record(
      toolName: 'computer_click',
      policy: policy,
      approvalResult: 'approved',
      success: true,
      result:
          '{"ok":true,"selectedIpcTransport":"xpc_service","imageBase64":"secret"}',
    );

    final entries = auditLog.redactedEntries;
    expect(entries, hasLength(1));
    expect(entries.single['toolName'], 'computer_click');
    expect(entries.single['riskCategory'], 'input');
    expect(entries.single['approvalResult'], 'approved');
    expect(entries.single['transport'], 'xpc_service');
    expect(entries.single.containsKey('imageBase64'), isFalse);
  });

  test('keeps a bounded audit ring buffer', () {
    final auditLog = MacosComputerUseAuditLog(maxEntries: 2);

    for (final toolName in const [
      'computer_move_mouse',
      'computer_click',
      'computer_start_system_audio_recording',
    ]) {
      auditLog.record(
        toolName: toolName,
        policy: MacosComputerUseToolPolicy.decision(toolName),
        approvalResult: 'approved',
        success: true,
        result: '{"ok":true,"ipcTransport":"distributed_notification_center"}',
      );
    }

    final entries = auditLog.redactedEntries;
    expect(entries, hasLength(2));
    expect(entries.first['toolName'], 'computer_click');
    expect(entries.last['riskCategory'], 'sensitive');
  });
}
