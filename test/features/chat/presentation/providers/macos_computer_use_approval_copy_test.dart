import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:caverno/features/chat/presentation/providers/macos_computer_use_approval_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds input approval copy for pointer actions', () {
    final policy = MacosComputerUseToolPolicy.decision('computer_click');
    final copy = MacosComputerUseApprovalCopy.from(
      toolName: 'computer_click',
      policy: policy,
    );

    expect(copy.title, 'Approve Pointer Click');
    expect(copy.riskLabel, 'Input Control');
    expect(copy.approveLabel, 'Allow Input Action');
    expect(copy.warningMessage, contains('move the pointer'));
  });

  test('builds sensitive approval copy for system audio recording', () {
    final policy = MacosComputerUseToolPolicy.decision(
      'computer_start_system_audio_recording',
    );
    final copy = MacosComputerUseApprovalCopy.from(
      toolName: 'computer_start_system_audio_recording',
      policy: policy,
    );

    expect(copy.title, 'Approve System Audio Recording');
    expect(copy.riskLabel, 'Sensitive Recording');
    expect(copy.approveLabel, 'Allow Recording');
    expect(copy.warningMessage, contains('capture system audio'));
  });

  test('builds recovery approval copy for stop actions', () {
    final policy = MacosComputerUseToolPolicy.decision(
      'computer_stop_system_audio_recording',
    );
    final copy = MacosComputerUseApprovalCopy.from(
      toolName: 'computer_stop_system_audio_recording',
      policy: policy,
    );

    expect(copy.title, 'Approve System Audio Stop');
    expect(copy.riskLabel, 'Recovery');
    expect(copy.approveLabel, 'Run Recovery Action');
    expect(copy.warningMessage, contains('safe state'));
  });
}
