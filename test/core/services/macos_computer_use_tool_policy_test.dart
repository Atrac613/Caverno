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

  test('keeps observation proposals inside planning', () {
    final decision = MacosComputerUseToolPolicy.actionProposalDecision(
      toolName: 'computer_vision_observe',
    );

    expect(decision, isNotNull);
    expect(decision!.allowedAsObserveOnlyProposal, isTrue);
    expect(decision.requiresUserApproval, isFalse);
    expect(decision.boundaries, isEmpty);
    expect(decision.blockerCodes, isEmpty);
    expect(decision.nextAction, contains('planning phase'));
  });

  test('requires exact text and target approval for text input proposals', () {
    final decision = MacosComputerUseToolPolicy.actionProposalDecision(
      toolName: 'computer_type_text',
      target: const {
        'label': "What's happening?",
        'role': 'compose_text_field',
        'risk': 'input',
      },
      exactText: 'Good morning',
    );

    expect(decision, isNotNull);
    expect(decision!.allowedAsObserveOnlyProposal, isFalse);
    expect(decision.requiresUserApproval, isTrue);
    expect(decision.requiresTargetApproval, isTrue);
    expect(decision.requiresExactTextApproval, isTrue);
    expect(decision.requiresSeparatePublicActionApproval, isFalse);
    expect(
      decision.boundaries,
      containsAll([
        MacosComputerUseApprovalBoundary.target,
        MacosComputerUseApprovalBoundary.exactText,
      ]),
    );
    expect(decision.blockerCodes, isEmpty);
    expect(decision.nextAction, contains('exact text'));
  });

  test('blocks text input proposals without exact text or target', () {
    final decision = MacosComputerUseToolPolicy.actionProposalDecision(
      toolName: 'computer_type_text',
    );

    expect(decision, isNotNull);
    expect(
      decision!.blockerCodes,
      containsAll(['exact_text_missing', 'target_missing']),
    );
  });

  test('requires separate approval for public action targets', () {
    final decision = MacosComputerUseToolPolicy.actionProposalDecision(
      toolName: 'computer_click',
      target: const {
        'label': 'Post',
        'role': 'public_submit',
        'risk': 'public_action',
      },
    );

    expect(decision, isNotNull);
    expect(decision!.requiresUserApproval, isTrue);
    expect(decision.requiresTargetApproval, isTrue);
    expect(decision.requiresSeparatePublicActionApproval, isTrue);
    expect(
      decision.boundaries,
      containsAll([
        MacosComputerUseApprovalBoundary.target,
        MacosComputerUseApprovalBoundary.publicAction,
      ]),
    );
    expect(
      decision.blockerCodes,
      contains('separate_public_action_approval_required'),
    );
    expect(decision.nextAction, contains('separate explicit approval'));
  });

  test('classifies submit-like controls as public actions', () {
    expect(
      MacosComputerUseToolPolicy.isPublicActionTarget(const {
        'label': 'Publish',
        'role': 'button',
      }),
      isTrue,
    );
    expect(
      MacosComputerUseToolPolicy.isPublicActionTarget(const {
        'label': 'Search',
        'role': 'search_field',
        'risk': 'input',
      }),
      isFalse,
    );
  });
}
