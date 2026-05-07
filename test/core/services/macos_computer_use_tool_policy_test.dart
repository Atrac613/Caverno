import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires approval for pointer movement', () {
    final decision = MacosComputerUseToolPolicy.decision('computer_move_mouse');

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.pointerInput);
    expect(decision.riskCategory, MacosComputerUseRiskCategory.input);
    expect(decision.requiresUserApproval, isTrue);
    expect(decision.requiresSmokeArming, isTrue);
    expect(decision.allowedInPlanning, isFalse);
    expect(decision.requiresPostActionObservation, isTrue);
  });

  test('allows screenshots during planning without approval', () {
    final decision = MacosComputerUseToolPolicy.decision('computer_screenshot');

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.observation);
    expect(decision.riskCategory, MacosComputerUseRiskCategory.observe);
    expect(decision.requiresUserApproval, isFalse);
    expect(decision.requiresSmokeArming, isFalse);
    expect(decision.allowedInPlanning, isTrue);
    expect(decision.requiresPostActionObservation, isFalse);
  });

  test('allows vision observations during planning without approval', () {
    final decision = MacosComputerUseToolPolicy.decision(
      'computer_vision_observe',
    );

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.observation);
    expect(decision.riskCategory, MacosComputerUseRiskCategory.observe);
    expect(decision.requiresUserApproval, isFalse);
    expect(decision.requiresSmokeArming, isFalse);
    expect(decision.allowedInPlanning, isTrue);
    expect(decision.requiresPostActionObservation, isFalse);
  });

  test('blocks permission prompts during planning', () {
    final decision = MacosComputerUseToolPolicy.decision(
      'computer_request_permissions',
    );

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.setup);
    expect(decision.riskCategory, MacosComputerUseRiskCategory.setup);
    expect(decision.requiresUserApproval, isFalse);
    expect(decision.requiresSmokeArming, isFalse);
    expect(decision.allowedInPlanning, isFalse);
  });

  test('treats stop recording as recovery outside planning', () {
    final decision = MacosComputerUseToolPolicy.decision(
      'computer_stop_system_audio_recording',
    );

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.audio);
    expect(decision.riskCategory, MacosComputerUseRiskCategory.recovery);
    expect(decision.requiresUserApproval, isFalse);
    expect(decision.requiresSmokeArming, isFalse);
    expect(decision.allowedInPlanning, isFalse);
    expect(decision.requiresPostActionObservation, isTrue);
    expect(decision.emergencyStop, isTrue);
  });

  test('requires both approval and smoke arming for unsafe input tools', () {
    for (final toolName in const [
      'computer_move_mouse',
      'computer_click',
      'computer_drag',
      'computer_scroll',
      'computer_type_text',
      'computer_press_key',
    ]) {
      final decision = MacosComputerUseToolPolicy.decision(toolName);

      expect(decision, isNotNull, reason: toolName);
      expect(decision!.requiresUserApproval, isTrue, reason: toolName);
      expect(
        decision.riskCategory,
        MacosComputerUseRiskCategory.input,
        reason: toolName,
      );
      expect(decision.requiresSmokeArming, isTrue, reason: toolName);
      expect(decision.requiresPostActionObservation, isTrue, reason: toolName);
      expect(decision.allowedInPlanning, isFalse, reason: toolName);
    }
  });

  test('requires approval and arming to start system audio recording', () {
    final decision = MacosComputerUseToolPolicy.decision(
      'computer_start_system_audio_recording',
    );

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.audio);
    expect(decision.riskCategory, MacosComputerUseRiskCategory.sensitive);
    expect(decision.requiresUserApproval, isTrue);
    expect(decision.requiresSmokeArming, isTrue);
    expect(decision.requiresPostActionObservation, isTrue);
    expect(decision.emergencyStop, isFalse);
  });
}
