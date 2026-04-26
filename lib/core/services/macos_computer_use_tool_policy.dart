enum MacosComputerUseToolCategory {
  setup,
  observation,
  windowFocus,
  pointerInput,
  keyboardInput,
  audio,
}

enum MacosComputerUseRiskCategory { setup, observe, input, sensitive, recovery }

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

class MacosComputerUseToolPolicy {
  const MacosComputerUseToolPolicy._();

  static const allToolNames = {
    'computer_get_permissions',
    'computer_request_permissions',
    'computer_open_system_settings',
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

  static MacosComputerUseToolPolicyDecision? decision(String toolName) {
    if (!isComputerUseTool(toolName)) {
      return null;
    }

    final category = switch (toolName) {
      'computer_get_permissions' ||
      'computer_request_permissions' ||
      'computer_open_system_settings' => MacosComputerUseToolCategory.setup,
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
}
