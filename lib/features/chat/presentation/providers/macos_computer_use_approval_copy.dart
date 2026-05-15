import '../../../../core/services/macos_computer_use_tool_policy.dart';

class MacosComputerUseApprovalCopy {
  const MacosComputerUseApprovalCopy({
    required this.title,
    required this.riskLabel,
    required this.warningMessage,
    required this.approveLabel,
  });

  final String title;
  final String riskLabel;
  final String warningMessage;
  final String approveLabel;

  static MacosComputerUseApprovalCopy from({
    required String toolName,
    required MacosComputerUseToolPolicyDecision? policy,
  }) {
    final riskCategory = policy?.riskCategory;
    return MacosComputerUseApprovalCopy(
      title: switch (toolName) {
        'computer_focus_window' => 'Approve Window Focus',
        'computer_move_mouse' => 'Approve Pointer Move',
        'computer_click' => 'Approve Pointer Click',
        'computer_drag' => 'Approve Pointer Drag',
        'computer_scroll' => 'Approve Pointer Scroll',
        'computer_type_text' => 'Approve Text Input',
        'computer_press_key' => 'Approve Key Press',
        'computer_start_system_audio_recording' =>
          'Approve System Audio Recording',
        'computer_stop_system_audio_recording' => 'Approve System Audio Stop',
        _ => switch (riskCategory) {
          MacosComputerUseRiskCategory.observe => 'Approve Screen Observation',
          MacosComputerUseRiskCategory.input => 'Approve macOS Input',
          MacosComputerUseRiskCategory.publicAction => 'Approve Public Action',
          MacosComputerUseRiskCategory.sensitive =>
            'Approve Sensitive Recording',
          MacosComputerUseRiskCategory.recovery => 'Approve Recovery Action',
          MacosComputerUseRiskCategory.setup => 'Approve macOS Setup',
          null => 'Approve macOS Computer Use',
        },
      },
      riskLabel: switch (riskCategory) {
        MacosComputerUseRiskCategory.observe => 'Observation',
        MacosComputerUseRiskCategory.input => 'Input Control',
        MacosComputerUseRiskCategory.publicAction => 'Public Action',
        MacosComputerUseRiskCategory.sensitive => 'Sensitive Recording',
        MacosComputerUseRiskCategory.recovery => 'Recovery',
        MacosComputerUseRiskCategory.setup => 'Setup',
        null => 'Computer Use',
      },
      warningMessage: switch (riskCategory) {
        MacosComputerUseRiskCategory.observe =>
          'This action can capture visible screen or window contents, but it does not send input.',
        MacosComputerUseRiskCategory.input =>
          'This action can focus windows, move the pointer, click, scroll, or send keyboard input on your Mac.',
        MacosComputerUseRiskCategory.publicAction =>
          'This action can submit, post, send, publish, or otherwise change external state. Approve it separately from text entry.',
        MacosComputerUseRiskCategory.sensitive =>
          'This action can capture system audio. Make sure the current audio is safe to record before approving it.',
        MacosComputerUseRiskCategory.recovery =>
          'This recovery action stops active computer-use work so you can regain a safe state quickly.',
        MacosComputerUseRiskCategory.setup =>
          'This action changes helper-owned setup state, such as permissions or System Settings navigation.',
        null =>
          'This action can control or inspect your macOS desktop. Approve only if the target and content look correct.',
      },
      approveLabel: switch (riskCategory) {
        MacosComputerUseRiskCategory.observe => 'Allow Observation',
        MacosComputerUseRiskCategory.input => 'Allow Input Action',
        MacosComputerUseRiskCategory.publicAction => 'Approve Public Action',
        MacosComputerUseRiskCategory.sensitive => 'Allow Recording',
        MacosComputerUseRiskCategory.recovery => 'Run Recovery Action',
        MacosComputerUseRiskCategory.setup => 'Continue Setup',
        null => 'Approve Action',
      },
    );
  }
}
