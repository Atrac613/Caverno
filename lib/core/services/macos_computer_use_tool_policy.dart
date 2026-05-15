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
  secureField,
  credential,
  payment,
  destructive,
}

class MacosComputerUseProductionActionPhase {
  const MacosComputerUseProductionActionPhase({
    required this.id,
    required this.label,
    required this.required,
    required this.reportOnly,
    required this.userOperated,
    required this.desktopActionAllowed,
    required this.nextArtifact,
    required this.description,
  });

  final String id;
  final String label;
  final bool required;
  final bool reportOnly;
  final bool userOperated;
  final bool desktopActionAllowed;
  final String nextArtifact;
  final String description;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'required': required,
      'reportOnly': reportOnly,
      'userOperated': userOperated,
      'desktopActionAllowed': desktopActionAllowed,
      'nextArtifact': nextArtifact,
      'description': description,
    };
  }
}

class MacosComputerUseProductionActionPolicySummary {
  const MacosComputerUseProductionActionPolicySummary({
    required this.schemaName,
    required this.schemaVersion,
    required this.status,
    required this.phaseOrder,
    required this.phases,
    required this.requiredApprovals,
    required this.publicActionSeparateApprovalRequired,
    required this.publicActionTokens,
    required this.emergencyStopRequired,
    required this.postActionReviewRequired,
    required this.hardBlocks,
    required this.nextAction,
  });

  final String schemaName;
  final int schemaVersion;
  final String status;
  final List<String> phaseOrder;
  final List<MacosComputerUseProductionActionPhase> phases;
  final List<String> requiredApprovals;
  final bool publicActionSeparateApprovalRequired;
  final List<String> publicActionTokens;
  final bool emergencyStopRequired;
  final bool postActionReviewRequired;
  final List<String> hardBlocks;
  final String nextAction;

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'status': status,
      'phaseOrder': phaseOrder,
      'phases': phases.map((phase) => phase.toJson()).toList(growable: false),
      'requiredApprovals': requiredApprovals,
      'publicActionSeparateApprovalRequired':
          publicActionSeparateApprovalRequired,
      'publicActionTokens': publicActionTokens,
      'emergencyStopRequired': emergencyStopRequired,
      'postActionReviewRequired': postActionReviewRequired,
      'hardBlocks': hardBlocks,
      'nextAction': nextAction,
    };
  }
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

class MacosComputerUseTargetSafetyDecision {
  const MacosComputerUseTargetSafetyDecision({
    required this.riskTags,
    required this.blockerCodes,
    required this.requiresSeparateApproval,
    required this.hardBlocked,
  });

  final List<String> riskTags;
  final List<String> blockerCodes;
  final bool requiresSeparateApproval;
  final bool hardBlocked;

  bool get hasRisk => riskTags.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'riskTags': riskTags,
      'blockerCodes': blockerCodes,
      'requiresSeparateApproval': requiresSeparateApproval,
      'hardBlocked': hardBlocked,
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
    required this.targetSafety,
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
  final MacosComputerUseTargetSafetyDecision targetSafety;
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
      'targetSafety': targetSafety.toJson(),
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
    'computer_accessibility_snapshot',
    'computer_list_displays',
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
    'computer_accessibility_snapshot',
    'computer_list_displays',
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

  static const secureFieldTargetTokens = {
    'secure',
    'secure_field',
    'secure_text',
    'secure_text_field',
    'password_field',
    'passcode_field',
  };

  static const credentialTargetTokens = {
    'credential',
    'credentials',
    'password',
    'passcode',
    'login',
    'sign_in',
    'signin',
    'api_key',
    'token',
    'secret',
    'ssh_key',
    'recovery_key',
  };

  static const paymentTargetTokens = {
    'payment',
    'pay',
    'purchase',
    'buy',
    'checkout',
    'order',
    'billing',
    'invoice',
    'credit_card',
    'card_number',
    'cart',
  };

  static const destructiveTargetTokens = {
    'delete',
    'remove',
    'destroy',
    'erase',
    'reset',
    'revoke',
    'disable',
    'format',
    'wipe',
    'cancel_subscription',
    'danger',
    'danger_zone',
    'uninstall',
  };

  static const productionActionPhaseOrder = [
    'observe',
    'approval_packet',
    'action_time_confirmation',
    'emergency_stop_available',
    'execution_result_intake',
    'post_action_review',
  ];

  static const productionRequiredApprovals = [
    'target_label',
    'exact_text_for_typing',
    'public_action_label_for_public_actions',
    'secure_field_target_refusal',
    'credential_target_refusal',
    'payment_target_refusal',
    'destructive_target_refusal',
    'system_audio_recording_for_audio',
    'post_action_observation',
  ];

  static const productionHardBlocks = [
    'fresh_observation_missing',
    'approval_packet_missing_or_unapproved',
    'action_time_confirmation_missing',
    'emergency_stop_unavailable',
    'execution_result_intake_missing',
    'post_action_review_missing',
    'public_action_missing_separate_approval',
    'secure_field_target_blocked',
    'credential_target_blocked',
    'payment_target_blocked',
    'destructive_target_blocked',
  ];

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
    if (risk == 'input' || risk == 'low') {
      return false;
    }
    final role = _normalized(target['role']);
    final label = _normalized(target['label']);
    final action = _normalized(target['action']);
    final targetText = '$role $label $action';
    return publicActionTargetTokens.any(targetText.contains);
  }

  static MacosComputerUseTargetSafetyDecision targetSafetyDecision(
    Map<String, dynamic>? target,
  ) {
    if (target == null) {
      return const MacosComputerUseTargetSafetyDecision(
        riskTags: [],
        blockerCodes: [],
        requiresSeparateApproval: false,
        hardBlocked: false,
      );
    }

    final risk = _normalized(target['risk']);
    final targetText = _targetText(target);
    final riskTags = <String>[
      if (risk == 'public_action' || isPublicActionTarget(target))
        'public_action',
      if (risk == 'secure_field' ||
          _containsAny(targetText, secureFieldTargetTokens))
        'secure_field',
      if (risk == 'credential' ||
          _containsAny(targetText, credentialTargetTokens))
        'credential',
      if (risk == 'payment' || _containsAny(targetText, paymentTargetTokens))
        'payment',
      if (risk == 'destructive' ||
          _containsAny(targetText, destructiveTargetTokens))
        'destructive',
    ];

    final hardBlockedTags = riskTags.where(
      (tag) =>
          tag == 'secure_field' ||
          tag == 'credential' ||
          tag == 'payment' ||
          tag == 'destructive',
    );
    final blockerCodes = <String>[
      if (riskTags.contains('public_action'))
        'separate_public_action_approval_required',
      for (final tag in hardBlockedTags) '${tag}_target_blocked',
    ];

    return MacosComputerUseTargetSafetyDecision(
      riskTags: List<String>.unmodifiable(riskTags),
      blockerCodes: List<String>.unmodifiable(blockerCodes),
      requiresSeparateApproval: riskTags.contains('public_action'),
      hardBlocked: hardBlockedTags.isNotEmpty,
    );
  }

  static MacosComputerUseProductionActionPolicySummary
  productionActionPolicy() {
    return MacosComputerUseProductionActionPolicySummary(
      schemaName: 'macos_computer_use_production_action_policy',
      schemaVersion: 1,
      status: 'defined',
      phaseOrder: productionActionPhaseOrder,
      phases: const [
        MacosComputerUseProductionActionPhase(
          id: 'observe',
          label: 'Fresh visual observation',
          required: true,
          reportOnly: false,
          userOperated: false,
          desktopActionAllowed: false,
          nextArtifact: 'M14 or M30 observe evidence',
          description:
              'Capture current visual state and classify targets before any action proposal.',
        ),
        MacosComputerUseProductionActionPhase(
          id: 'approval_packet',
          label: 'Explicit approval packet',
          required: true,
          reportOnly: true,
          userOperated: true,
          desktopActionAllowed: false,
          nextArtifact: 'M16 approval_packet.json',
          description:
              'Record target, exact text, public-action, and post-action observation approvals before execution.',
        ),
        MacosComputerUseProductionActionPhase(
          id: 'action_time_confirmation',
          label: 'Action-time confirmation',
          required: true,
          reportOnly: true,
          userOperated: true,
          desktopActionAllowed: false,
          nextArtifact: 'M18 execution_handoff.json',
          description:
              'Confirm fresh observation, exact target, exact text, and public action immediately before runtime.',
        ),
        MacosComputerUseProductionActionPhase(
          id: 'emergency_stop_available',
          label: 'Emergency stop available',
          required: true,
          reportOnly: false,
          userOperated: true,
          desktopActionAllowed: true,
          nextArtifact: 'computer_stop_system_audio_recording',
          description:
              'Keep a recovery path available while any input or recording action is pending or running.',
        ),
        MacosComputerUseProductionActionPhase(
          id: 'execution_result_intake',
          label: 'Execution result intake',
          required: true,
          reportOnly: true,
          userOperated: true,
          desktopActionAllowed: false,
          nextArtifact: 'M20 execution_result_intake.json',
          description:
              'Record user-reported runtime outcome and post-action observation after execution.',
        ),
        MacosComputerUseProductionActionPhase(
          id: 'post_action_review',
          label: 'Post-action review',
          required: true,
          reportOnly: true,
          userOperated: true,
          desktopActionAllowed: false,
          nextArtifact: 'M22 post_action_review.json',
          description:
              'Review the result, classify final state, and decide whether another observe/action cycle is needed.',
        ),
      ],
      requiredApprovals: productionRequiredApprovals,
      publicActionSeparateApprovalRequired: true,
      publicActionTokens: publicActionTargetTokens.toList(growable: false),
      emergencyStopRequired: true,
      postActionReviewRequired: true,
      hardBlocks: productionHardBlocks,
      nextAction:
          'Use the observe, approval packet, action-time confirmation, result intake, and post-action review artifacts before any production desktop action.',
    );
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
    final targetSafety = targetSafetyDecision(target);
    final requiresSystemAudioApproval =
        toolName == 'computer_start_system_audio_recording';

    final boundaries = <MacosComputerUseApprovalBoundary>[
      if (requiresTargetApproval) MacosComputerUseApprovalBoundary.target,
      if (requiresExactTextApproval) MacosComputerUseApprovalBoundary.exactText,
      if (requiresSeparatePublicActionApproval)
        MacosComputerUseApprovalBoundary.publicAction,
      if (targetSafety.riskTags.contains('secure_field'))
        MacosComputerUseApprovalBoundary.secureField,
      if (targetSafety.riskTags.contains('credential'))
        MacosComputerUseApprovalBoundary.credential,
      if (targetSafety.riskTags.contains('payment'))
        MacosComputerUseApprovalBoundary.payment,
      if (targetSafety.riskTags.contains('destructive'))
        MacosComputerUseApprovalBoundary.destructive,
      if (requiresSystemAudioApproval)
        MacosComputerUseApprovalBoundary.systemAudio,
    ];
    final blockerCodes = <String>[
      if (requiresExactTextApproval && _normalized(exactText).isEmpty)
        'exact_text_missing',
      if (requiresTargetApproval && target == null) 'target_missing',
      ...targetSafety.blockerCodes,
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
      targetSafety: targetSafety,
      nextAction: _actionProposalNextAction(
        isObservation: isObservation,
        requiresExactTextApproval: requiresExactTextApproval,
        requiresSeparatePublicActionApproval:
            requiresSeparatePublicActionApproval,
        targetSafety: targetSafety,
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
      'computer_accessibility_snapshot' ||
      'computer_list_displays' ||
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
      'computer_accessibility_snapshot' ||
      'computer_list_displays' ||
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
    required MacosComputerUseTargetSafetyDecision targetSafety,
  }) {
    if (isObservation) {
      return 'Observation can remain in the planning phase.';
    }
    if (targetSafety.hardBlocked) {
      return 'Do not execute this action. Choose a non-sensitive, non-payment, non-destructive target or ask the user to handle it manually.';
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
    return value?.toString().trim().toLowerCase().replaceAll(
          RegExp(r'[\s\-]+'),
          '_',
        ) ??
        '';
  }

  static String _targetText(Map<String, dynamic> target) {
    return [
      target['risk'],
      target['role'],
      target['label'],
      target['action'],
      target['subrole'],
      target['description'],
      target['help'],
    ].map(_normalized).where((value) => value.isNotEmpty).join(' ');
  }

  static bool _containsAny(String haystack, Iterable<String> needles) {
    return needles.any((needle) => haystack.contains(needle));
  }
}
