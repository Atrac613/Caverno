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
    expect(entries.single['toolCategory'], 'pointerInput');
    expect(entries.single['riskCategory'], 'input');
    expect(entries.single['policyLabel'], 'pointer_input');
    expect(entries.single['requiresUserApproval'], isTrue);
    expect(entries.single['requiresSmokeArming'], isTrue);
    expect(entries.single['emergencyStop'], isFalse);
    expect(entries.single['approvalResult'], 'approved');
    expect(entries.single['transport'], 'xpc_service');
    expect(entries.single['postActionObservationRequired'], isTrue);
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
    expect(entries.last['requiresSmokeArming'], isTrue);
  });

  test('records recovery policy metadata for emergency stop tools', () {
    final auditLog = MacosComputerUseAuditLog(maxEntries: 2);

    auditLog.record(
      toolName: 'computer_stop_system_audio_recording',
      policy: MacosComputerUseToolPolicy.decision(
        'computer_stop_system_audio_recording',
      ),
      approvalResult: 'not_required',
      success: true,
      result: '{"ok":true,"ipcTransport":"distributed_notification_center"}',
    );

    final entry = auditLog.redactedEntries.single;
    expect(entry['toolCategory'], 'audio');
    expect(entry['riskCategory'], 'recovery');
    expect(entry['policyLabel'], 'system_audio');
    expect(entry['requiresUserApproval'], isFalse);
    expect(entry['requiresSmokeArming'], isFalse);
    expect(entry['emergencyStop'], isTrue);
  });

  test('records preferred XPC fallback metadata without payloads', () {
    final auditLog = MacosComputerUseAuditLog(maxEntries: 2);

    auditLog.record(
      toolName: 'computer_screenshot',
      policy: MacosComputerUseToolPolicy.decision('computer_screenshot'),
      approvalResult: 'not_required',
      success: true,
      result:
          '{"ok":true,"selectedIpcTransport":"distributed_notification_center","preferredIpcTransport":"xpc_service","fallbackIpcTransport":"distributed_notification_center","preferredIpcAttempt":{"status":"xpc_timeout","errorCode":"helper_xpc_timeout"},"imageBase64":"secret"}',
    );

    final entry = auditLog.redactedEntries.single;
    expect(entry['transport'], 'distributed_notification_center');
    expect(entry['preferredAttemptStatus'], 'xpc_timeout');
    expect(entry['preferredAttemptErrorCode'], 'helper_xpc_timeout');
    expect(entry['fallbackReason'], 'xpc_timeout (helper_xpc_timeout)');
    expect(entry.containsKey('imageBase64'), isFalse);
  });

  test('records post-action observation metadata without payloads', () {
    final auditLog = MacosComputerUseAuditLog(maxEntries: 2);

    auditLog.record(
      toolName: 'computer_click',
      policy: MacosComputerUseToolPolicy.decision('computer_click'),
      approvalResult: 'approved',
      success: true,
      result: '{"ok":true,"selectedIpcTransport":"xpc_service"}',
      postActionObservation: const MacosComputerUsePostActionObservation(
        toolName: 'computer_screenshot',
        success: true,
        result:
            '{"ok":true,"selectedIpcTransport":"xpc_service","imageBase64":"secret"}',
      ),
    );

    final entry = auditLog.redactedEntries.single;
    expect(entry['postActionObservationRequired'], isTrue);
    expect(entry['postActionObservationToolName'], 'computer_screenshot');
    expect(entry['postActionObservationSuccess'], isTrue);
    expect(entry['postActionObservationTransport'], 'xpc_service');
    expect(entry.containsKey('imageBase64'), isFalse);
  });

  test('does not store typed text bodies from input results', () {
    final auditLog = MacosComputerUseAuditLog(maxEntries: 2);

    auditLog.record(
      toolName: 'computer_type_text',
      policy: MacosComputerUseToolPolicy.decision('computer_type_text'),
      approvalResult: 'approved',
      success: true,
      result:
          '{"ok":true,"selectedIpcTransport":"xpc_service","characters":12,"text":"secret typed body"}',
      postActionObservation: const MacosComputerUsePostActionObservation(
        toolName: 'computer_screenshot',
        success: false,
        errorCode: 'screen_capture_denied',
      ),
    );

    final entry = auditLog.redactedEntries.single;
    expect(entry['toolName'], 'computer_type_text');
    expect(entry['transport'], 'xpc_service');
    expect(entry['postActionObservationRequired'], isTrue);
    expect(entry['postActionObservationResponseCode'], 'screen_capture_denied');
    expect(entry.containsKey('text'), isFalse);
  });
}
