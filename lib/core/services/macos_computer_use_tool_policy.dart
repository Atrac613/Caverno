enum MacosComputerUseToolCategory {
  setup,
  observation,
  windowFocus,
  pointerInput,
  keyboardInput,
  audio,
}

enum MacosComputerUseRiskCategory {
  setup,
  observe,
  input,
  publicAction,
  sensitive,
  recovery,
}

enum MacosComputerUseApprovalBoundary {
  target,
  exactText,
  publicAction,
  systemAudio,
}

class MacosComputerUseToolPolicyDecision {
  const MacosComputerUseToolPolicyDecision({
    required this.toolName,
    required this.category,
    required this.riskCategory,
    required this.requiresUserApproval,
    required this.requiresSmokeArming,
    required this.allowedInPlanning,
    required this.requiresPostActionObservation,
    required this.emergencyStop,
    required this.policyLabel,
  });

  final String toolName;
  final MacosComputerUseToolCategory category;
  final MacosComputerUseRiskCategory riskCategory;
  final bool requiresUserApproval;
  final bool requiresSmokeArming;
  final bool allowedInPlanning;
  final bool requiresPostActionObservation;
  final bool emergencyStop;
  final String policyLabel;

  Map<String, dynamic> toJson() {
    return {
      'toolName': toolName,
      'category': category.name,
      'riskCategory': riskCategory.name,
      'requiresUserApproval': requiresUserApproval,
      'requiresSmokeArming': requiresSmokeArming,
      'allowedInPlanning': allowedInPlanning,
      'requiresPostActionObservation': requiresPostActionObservation,
      'emergencyStop': emergencyStop,
      'policyLabel': policyLabel,
    };
  }
}

class MacosComputerUseActionProposalPolicyDecision {
  const MacosComputerUseActionProposalPolicyDecision({
    required this.toolName,
    required this.requiresUserApproval,
    required this.requiresTargetApproval,
    required this.requiresExactTextApproval,
    required this.requiresSeparatePublicActionApproval,
    required this.allowedAsObserveOnlyProposal,
    required this.boundaries,
    required this.blockerCodes,
    required this.nextAction,
  });

  final String toolName;
  final bool requiresUserApproval;
  final bool requiresTargetApproval;
  final bool requiresExactTextApproval;
  final bool requiresSeparatePublicActionApproval;
  final bool allowedAsObserveOnlyProposal;
  final List<MacosComputerUseApprovalBoundary> boundaries;
  final List<String> blockerCodes;
  final String nextAction;

  Map<String, dynamic> toJson() {
    return {
      'toolName': toolName,
      'requiresUserApproval': requiresUserApproval,
      'requiresTargetApproval': requiresTargetApproval,
      'requiresExactTextApproval': requiresExactTextApproval,
      'requiresSeparatePublicActionApproval':
          requiresSeparatePublicActionApproval,
      'allowedAsObserveOnlyProposal': allowedAsObserveOnlyProposal,
      'boundaries': boundaries
          .map((boundary) => boundary.name)
          .toList(growable: false),
      'blockerCodes': blockerCodes,
      'nextAction': nextAction,
    };
  }
}

class MacosComputerUseToolPolicy {
  const MacosComputerUseToolPolicy._();

  static const allToolNames = {
    'computer_get_permissions',
    'computer_request_permissions',
    'computer_open_system_settings',
    'computer_vision_observe',
    'computer_list_windows',
    'computer_focus_window',
    'computer_screenshot',
    'computer_screenshot_window',
    'computer_move_mouse',
    'computer_click',
    'computer_drag',
    'computer_scroll',
    'computer_type_text',
    'computer_press_key',
    'computer_start_system_audio_recording',
    'computer_stop_system_audio_recording',
  };

  static const planningAllowedToolNames = {
    'computer_get_permissions',
    'computer_vision_observe',
    'computer_list_windows',
    'computer_screenshot',
    'computer_screenshot_window',
  };

  static const approvalRequiredToolNames = {
    'computer_focus_window',
    'computer_move_mouse',
    'computer_click',
    'computer_drag',
    'computer_scroll',
    'computer_type_text',
    'computer_press_key',
    'computer_start_system_audio_recording',
  };

  static const smokeArmingRequiredToolNames = {
    'computer_move_mouse',
    'computer_click',
    'computer_drag',
    'computer_scroll',
    'computer_type_text',
    'computer_press_key',
    'computer_start_system_audio_recording',
  };

  static const emergencyStopToolNames = {
    'computer_stop_system_audio_recording',
  };

  static const publicActionTargetTokens = {
    'post',
    'tweet',
    'submit',
    'send',
    'publish',
    'purchase',
    'buy',
    'checkout',
    'order',
  };

  static bool isComputerUseTool(String toolName) {
    return allToolNames.contains(toolName);
  }

  static bool isAllowedInPlanning(String toolName) {
    return planningAllowedToolNames.contains(toolName);
  }

  static bool requiresUserApproval(String toolName) {
    return approvalRequiredToolNames.contains(toolName);
  }

  static bool requiresSmokeArming(String toolName) {
    return smokeArmingRequiredToolNames.contains(toolName);
  }

  static bool isEmergencyStop(String toolName) {
    return emergencyStopToolNames.contains(toolName);
  }

  static bool isPublicActionTarget(Map<String, dynamic>? target) {
    if (target == null) {
      return false;
    }
    final risk = _normalized(target['risk']);
    if (risk == 'public_action') {
      return true;
    }
    final role = _normalized(target['role']);
    final label = _normalized(target['label']);
    final action = _normalized(target['action']);
    final targetText = '$role $label $action';
    return publicActionTargetTokens.any(targetText.contains);
  }

  static MacosComputerUseActionProposalPolicyDecision? actionProposalDecision({
    required String toolName,
    Map<String, dynamic>? target,
    String? exactText,
  }) {
    final toolDecision = decision(toolName);
    if (toolDecision == null) {
      return null;
    }

    final isObservation =
        toolDecision.riskCategory == MacosComputerUseRiskCategory.observe;
    final requiresTargetApproval = switch (toolName) {
      'computer_focus_window' ||
      'computer_move_mouse' ||
      'computer_click' ||
      'computer_drag' ||
      'computer_scroll' ||
      'computer_type_text' ||
      'computer_press_key' => true,
      _ => false,
    };
    final requiresExactTextApproval = toolName == 'computer_type_text';
    final requiresSeparatePublicActionApproval =
        isPublicActionTarget(target) &&
        switch (toolName) {
          'computer_click' || 'computer_press_key' => true,
          _ => false,
        };
    final requiresSystemAudioApproval =
        toolName == 'computer_start_system_audio_recording';

    final boundaries = <MacosComputerUseApprovalBoundary>[
      if (requiresTargetApproval) MacosComputerUseApprovalBoundary.target,
      if (requiresExactTextApproval) MacosComputerUseApprovalBoundary.exactText,
      if (requiresSeparatePublicActionApproval)
        MacosComputerUseApprovalBoundary.publicAction,
      if (requiresSystemAudioApproval)
        MacosComputerUseApprovalBoundary.systemAudio,
    ];
    final blockerCodes = <String>[
      if (requiresExactTextApproval && _normalized(exactText).isEmpty)
        'exact_text_missing',
      if (requiresTargetApproval && target == null) 'target_missing',
      if (requiresSeparatePublicActionApproval)
        'separate_public_action_approval_required',
    ];

    return MacosComputerUseActionProposalPolicyDecision(
      toolName: toolName,
      requiresUserApproval:
          toolDecision.requiresUserApproval || boundaries.isNotEmpty,
      requiresTargetApproval: requiresTargetApproval,
      requiresExactTextApproval: requiresExactTextApproval,
      requiresSeparatePublicActionApproval:
          requiresSeparatePublicActionApproval,
      allowedAsObserveOnlyProposal: isObservation,
      boundaries: List<MacosComputerUseApprovalBoundary>.unmodifiable(
        boundaries,
      ),
      blockerCodes: List<String>.unmodifiable(blockerCodes),
      nextAction: _actionProposalNextAction(
        isObservation: isObservation,
        requiresExactTextApproval: requiresExactTextApproval,
        requiresSeparatePublicActionApproval:
            requiresSeparatePublicActionApproval,
        requiresTargetApproval: requiresTargetApproval,
      ),
    );
  }

  static MacosComputerUseToolPolicyDecision? decision(String toolName) {
    if (!isComputerUseTool(toolName)) {
      return null;
    }

    final category = switch (toolName) {
      'computer_get_permissions' ||
      'computer_request_permissions' ||
      'computer_open_system_settings' => MacosComputerUseToolCategory.setup,
      'computer_vision_observe' ||
      'computer_list_windows' ||
      'computer_screenshot' ||
      'computer_screenshot_window' => MacosComputerUseToolCategory.observation,
      'computer_focus_window' => MacosComputerUseToolCategory.windowFocus,
      'computer_move_mouse' ||
      'computer_click' ||
      'computer_drag' ||
      'computer_scroll' => MacosComputerUseToolCategory.pointerInput,
      'computer_type_text' ||
      'computer_press_key' => MacosComputerUseToolCategory.keyboardInput,
      'computer_start_system_audio_recording' ||
      'computer_stop_system_audio_recording' =>
        MacosComputerUseToolCategory.audio,
      _ => MacosComputerUseToolCategory.setup,
    };
    final riskCategory = switch (toolName) {
      'computer_get_permissions' ||
      'computer_request_permissions' ||
      'computer_open_system_settings' => MacosComputerUseRiskCategory.setup,
      'computer_vision_observe' ||
      'computer_list_windows' ||
      'computer_screenshot' ||
      'computer_screenshot_window' => MacosComputerUseRiskCategory.observe,
      'computer_focus_window' ||
      'computer_move_mouse' ||
      'computer_click' ||
      'computer_drag' ||
      'computer_scroll' ||
      'computer_type_text' ||
      'computer_press_key' => MacosComputerUseRiskCategory.input,
      'computer_start_system_audio_recording' =>
        MacosComputerUseRiskCategory.sensitive,
      'computer_stop_system_audio_recording' =>
        MacosComputerUseRiskCategory.recovery,
      _ => MacosComputerUseRiskCategory.setup,
    };

    return MacosComputerUseToolPolicyDecision(
      toolName: toolName,
      category: category,
      riskCategory: riskCategory,
      requiresUserApproval: requiresUserApproval(toolName),
      requiresSmokeArming: requiresSmokeArming(toolName),
      allowedInPlanning: isAllowedInPlanning(toolName),
      requiresPostActionObservation: switch (toolName) {
        'computer_focus_window' ||
        'computer_move_mouse' ||
        'computer_click' ||
        'computer_drag' ||
        'computer_scroll' ||
        'computer_type_text' ||
        'computer_press_key' ||
        'computer_start_system_audio_recording' ||
        'computer_stop_system_audio_recording' => true,
        _ => false,
      },
      emergencyStop: isEmergencyStop(toolName),
      policyLabel: switch (category) {
        MacosComputerUseToolCategory.setup => 'setup',
        MacosComputerUseToolCategory.observation => 'observation',
        MacosComputerUseToolCategory.windowFocus => 'window_focus',
        MacosComputerUseToolCategory.pointerInput => 'pointer_input',
        MacosComputerUseToolCategory.keyboardInput => 'keyboard_input',
        MacosComputerUseToolCategory.audio => 'system_audio',
      },
    );
  }

  static List<Map<String, dynamic>> coverage() {
    return allToolNames
        .map((toolName) => decision(toolName)!.toJson())
        .toList(growable: false);
  }

  static String _actionProposalNextAction({
    required bool isObservation,
    required bool requiresTargetApproval,
    required bool requiresExactTextApproval,
    required bool requiresSeparatePublicActionApproval,
  }) {
    if (isObservation) {
      return 'Observation can remain in the planning phase.';
    }
    if (requiresSeparatePublicActionApproval) {
      return 'Ask the user for separate explicit approval before any public action.';
    }
    if (requiresExactTextApproval) {
      return 'Ask the user to approve the exact text and target before typing.';
    }
    if (requiresTargetApproval) {
      return 'Ask the user to approve the exact target before acting.';
    }
    return 'Ask the user for explicit approval before running this computer-use action.';
  }

  static String _normalized(Object? value) {
    return value?.toString().trim().toLowerCase().replaceAll('-', '_') ?? '';
  }
}
