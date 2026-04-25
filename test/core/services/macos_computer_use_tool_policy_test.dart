import 'package:caverno/core/services/macos_computer_use_tool_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires approval for pointer movement', () {
    final decision = MacosComputerUseToolPolicy.decision('computer_move_mouse');

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.pointerInput);
    expect(decision.requiresUserApproval, isTrue);
    expect(decision.allowedInPlanning, isFalse);
    expect(decision.requiresPostActionObservation, isTrue);
  });

  test('allows screenshots during planning without approval', () {
    final decision = MacosComputerUseToolPolicy.decision('computer_screenshot');

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.observation);
    expect(decision.requiresUserApproval, isFalse);
    expect(decision.allowedInPlanning, isTrue);
    expect(decision.requiresPostActionObservation, isFalse);
  });

  test('blocks permission prompts during planning', () {
    final decision = MacosComputerUseToolPolicy.decision(
      'computer_request_permissions',
    );

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.setup);
    expect(decision.requiresUserApproval, isFalse);
    expect(decision.allowedInPlanning, isFalse);
  });

  test('treats stop recording as recovery outside planning', () {
    final decision = MacosComputerUseToolPolicy.decision(
      'computer_stop_system_audio_recording',
    );

    expect(decision, isNotNull);
    expect(decision!.category, MacosComputerUseToolCategory.audio);
    expect(decision.requiresUserApproval, isFalse);
    expect(decision.allowedInPlanning, isFalse);
    expect(decision.requiresPostActionObservation, isTrue);
  });
}
