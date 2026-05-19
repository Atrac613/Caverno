// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierComputerUseHandlers on ChatNotifier {
  Future<McpToolResult> _handleComputerUseAction(ToolCallInfo toolCall) async {
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      toolCall.arguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final policy = MacosComputerUseToolPolicy.decision(toolCall.name);
    final actionProposalPolicy =
        MacosComputerUseToolPolicy.actionProposalDecision(
          toolName: toolCall.name,
          target: _computerUseActionTarget(toolCall),
          exactText: _computerUseExactText(toolCall),
        );
    final approvalCopy = MacosComputerUseApprovalCopy.from(
      toolName: toolCall.name,
      policy: policy,
    );
    final targetContext = _computerUseApprovalTargetContext(toolCall);
    final exactTextContext = _computerUseApprovalExactTextContext(toolCall);
    final visionObservationContext = _computerUseVisionObservationContext(
      toolCall,
    );
    final details = [
      if (policy != null) ...[
        'Policy: ${policy.policyLabel}',
        'Risk category: ${policy.riskCategory.name}',
        'Requires approval: ${policy.requiresUserApproval}',
        'Requires smoke arming: ${policy.requiresSmokeArming}',
        'Requires post-action observation: ${policy.requiresPostActionObservation}',
        if (policy.emergencyStop) 'Emergency stop: true',
      ],
      if (actionProposalPolicy != null) ...[
        'Approval boundaries: ${actionProposalPolicy.boundaries.map((boundary) => boundary.name).join(', ')}',
        'Action proposal next action: ${actionProposalPolicy.nextAction}',
        if (actionProposalPolicy.blockerCodes.isNotEmpty)
          'Action proposal blockers: ${actionProposalPolicy.blockerCodes.join(', ')}',
      ],
      ..._computerUseActionDetails(toolCall),
    ];

    final decision = await requestComputerUseAction(
      toolName: toolCall.name,
      title: approvalCopy.title,
      riskCategory: policy?.riskCategory.name ?? 'unknown',
      riskLabel: approvalCopy.riskLabel,
      warningMessage: approvalCopy.warningMessage,
      approveLabel: approvalCopy.approveLabel,
      requiresUserApproval: policy?.requiresUserApproval ?? false,
      requiresSmokeArming: policy?.requiresSmokeArming ?? false,
      emergencyStop: policy?.emergencyStop ?? false,
      approvalBoundaries:
          actionProposalPolicy?.boundaries
              .map((boundary) => boundary.name)
              .toList(growable: false) ??
          const [],
      approvalBlockerCodes: actionProposalPolicy?.blockerCodes ?? const [],
      actionProposalNextAction: actionProposalPolicy?.nextAction,
      summary: _describeComputerUseAction(toolCall),
      details: details,
      targetSummary: targetContext.summary,
      targetDetails: targetContext.details,
      exactTextPreview: exactTextContext.preview,
      exactTextLength: exactTextContext.length,
      visionObservationSummary: visionObservationContext.summary,
      visionObservationDetails: visionObservationContext.details,
      reason: toolCall.arguments['reason'] as String?,
    );
    if (!decision.approved) {
      final blockerCode = decision.blockerCode ?? 'approval_denied';
      MacosComputerUseAuditLog.instance.record(
        toolName: toolCall.name,
        policy: policy,
        approvalResult: blockerCode == 'arming_missing'
            ? 'arming_missing'
            : 'denied',
        success: false,
        errorCode: blockerCode,
      );
      final blockedResult = _computerUseBlockedResult(
        toolCall: toolCall,
        policy: policy,
        code: blockerCode,
      );
      return _rememberToolApprovalResult(
        toolCall.name,
        toolCall.arguments,
        McpToolResult(
          toolName: toolCall.name,
          result: blockedResult,
          isSuccess: false,
          errorMessage: _computerUseBlockedErrorMessage(blockerCode),
        ),
      );
    }

    if (actionProposalPolicy?.blockerCodes.isNotEmpty == true) {
      const blockerCode = 'action_policy_blocked';
      MacosComputerUseAuditLog.instance.record(
        toolName: toolCall.name,
        policy: policy,
        approvalResult: 'blocked',
        success: false,
        errorCode: blockerCode,
      );
      final blockedResult = _computerUseBlockedResult(
        toolCall: toolCall,
        policy: policy,
        code: blockerCode,
        approvalBlockerCodes: actionProposalPolicy!.blockerCodes,
        actionProposalNextAction: actionProposalPolicy.nextAction,
      );
      return _rememberToolApprovalResult(
        toolCall.name,
        toolCall.arguments,
        McpToolResult(
          toolName: toolCall.name,
          result: blockedResult,
          isSuccess: false,
          errorMessage: _computerUseBlockedErrorMessage(blockerCode),
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
    final postActionObservation = result.isSuccess
        ? await _runComputerUsePostActionObservation(policy, toolCall)
        : null;
    MacosComputerUseAuditLog.instance.record(
      toolName: toolCall.name,
      policy: policy,
      approvalResult: 'approved',
      success: result.isSuccess,
      result: result.result,
      errorCode: result.errorMessage,
      postActionObservation: postActionObservation,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      toolCall.arguments,
      _computerUseResultWithPostActionObservation(
        result: result,
        policy: policy,
        postActionObservation: postActionObservation,
      ),
    );
  }

  Future<McpToolResult> _handleComputerUseActionWithoutApproval(
    ToolCallInfo toolCall,
  ) async {
    final policy = MacosComputerUseToolPolicy.decision(toolCall.name);
    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
    MacosComputerUseAuditLog.instance.record(
      toolName: toolCall.name,
      policy: policy,
      approvalResult: 'not_required',
      success: result.isSuccess,
      result: result.result,
      errorCode: result.errorMessage,
    );
    return result;
  }

  Future<MacosComputerUsePostActionObservation?>
  _runComputerUsePostActionObservation(
    MacosComputerUseToolPolicyDecision? policy,
    ToolCallInfo toolCall,
  ) async {
    if (policy?.requiresPostActionObservation != true) {
      return null;
    }

    final observationToolName = switch (policy!.riskCategory) {
      MacosComputerUseRiskCategory.input ||
      MacosComputerUseRiskCategory.sensitive => 'computer_vision_observe',
      MacosComputerUseRiskCategory.recovery => 'computer_get_permissions',
      _ => null,
    };
    if (observationToolName == null) {
      return null;
    }

    final observationArguments = switch (observationToolName) {
      'computer_vision_observe' => _computerUsePostActionVisionArguments(
        toolCall.arguments,
      ),
      _ => <String, dynamic>{},
    };
    try {
      final result = await _mcpToolService!.executeTool(
        name: observationToolName,
        arguments: observationArguments,
      );
      return MacosComputerUsePostActionObservation(
        toolName: observationToolName,
        success: result.isSuccess,
        result: result.result,
        errorCode: result.errorMessage,
      );
    } catch (error) {
      return MacosComputerUsePostActionObservation(
        toolName: observationToolName,
        success: false,
        errorCode: error.toString(),
      );
    }
  }

  McpToolResult _computerUseResultWithPostActionObservation({
    required McpToolResult result,
    required MacosComputerUseToolPolicyDecision? policy,
    required MacosComputerUsePostActionObservation? postActionObservation,
  }) {
    if (postActionObservation == null) {
      return result;
    }

    final actionResult =
        _tryDecodeMap(result.result) ??
        <String, dynamic>{'rawResult': result.result};
    final observationResult =
        _tryDecodeMap(postActionObservation.result ?? '') ??
        <String, dynamic>{
          'ok': postActionObservation.success,
          if (postActionObservation.errorCode != null)
            'code': postActionObservation.errorCode,
        };
    final observationMetadata = Map<String, dynamic>.from(observationResult);
    final imageBase64 = observationMetadata.remove('imageBase64');
    final imageMimeType = observationMetadata['imageMimeType'] as String?;
    final imageAttached = imageBase64 is String && imageBase64.isNotEmpty;

    return McpToolResult(
      toolName: result.toolName,
      isSuccess: result.isSuccess,
      errorMessage: result.errorMessage,
      result: jsonEncode({
        'ok': result.isSuccess,
        'schemaName': 'macos_computer_use_action_result',
        'schemaVersion': 1,
        'toolName': result.toolName,
        'policy': policy?.toJson(),
        'action': _redactComputerUseActionResult(actionResult),
        'postActionObservationRequired':
            policy?.requiresPostActionObservation == true,
        'postActionObservation': {
          'toolName': postActionObservation.toolName,
          'success': postActionObservation.success,
          'imageAttached': imageAttached,
          if (postActionObservation.errorCode != null)
            'errorCode': postActionObservation.errorCode,
          ...observationMetadata,
        },
        if (imageAttached) 'imageBase64': imageBase64,
        if (imageAttached) 'imageMimeType': imageMimeType ?? 'image/png',
        'nextAction': imageAttached
            ? 'Inspect the attached post-action observation before proposing another desktop action.'
            : 'Run computer_vision_observe before proposing another desktop action.',
      }),
    );
  }

  Map<String, dynamic> _redactComputerUseActionResult(
    Map<String, dynamic> actionResult,
  ) {
    final redacted = Map<String, dynamic>.from(actionResult)
      ..remove('imageBase64')
      ..remove('text');
    if (actionResult['text'] is String) {
      redacted['textRedacted'] = true;
      redacted['textLength'] = (actionResult['text'] as String).length;
    }
    return redacted;
  }

  Map<String, dynamic> _computerUsePostActionVisionArguments(
    Map<String, dynamic> actionArguments,
  ) {
    final windowId = actionArguments['window_id'];
    final displayId = actionArguments['display_id'];
    final arguments = <String, dynamic>{
      'target': windowId != null ? 'window' : 'front_window',
      'max_width': 800,
      'include_windows': true,
    };
    if (windowId != null) {
      arguments['window_id'] = windowId;
    }
    if (displayId != null) {
      arguments['display_id'] = displayId;
    }
    return arguments;
  }

  String _computerUseBlockedResult({
    required ToolCallInfo toolCall,
    required MacosComputerUseToolPolicyDecision? policy,
    required String code,
    List<String> approvalBlockerCodes = const [],
    String? actionProposalNextAction,
  }) {
    return jsonEncode({
      'ok': false,
      'toolName': toolCall.name,
      'code': code,
      'error': _computerUseBlockedErrorMessage(code),
      'policy': policy?.toJson(),
      'requiresUserApproval': policy?.requiresUserApproval ?? false,
      'requiresSmokeArming': policy?.requiresSmokeArming ?? false,
      'emergencyStop': policy?.emergencyStop ?? false,
      if (approvalBlockerCodes.isNotEmpty)
        'approvalBlockers': approvalBlockerCodes,
      'nextAction': switch (code) {
        'action_policy_blocked' =>
          actionProposalNextAction ??
              'Resolve the Computer Use action policy blockers before retrying.',
        'arming_missing' =>
          'Ask the user to explicitly arm the pending Computer Use action before retrying.',
        'approval_denied' =>
          'Ask the user for explicit approval before retrying this Computer Use action.',
        _ => 'Inspect the Computer Use approval state before retrying.',
      },
    });
  }

  String _computerUseBlockedErrorMessage(String code) {
    return switch (code) {
      'arming_missing' =>
        'Computer Use action blocked because the unsafe arming confirmation was not enabled.',
      'action_policy_blocked' =>
        'Computer Use action blocked by the target safety policy.',
      'approval_denied' => 'User denied macOS computer use action.',
      _ => 'macOS computer use action was blocked.',
    };
  }

  Future<ComputerUseActionApprovalDecision> requestComputerUseAction({
    required String toolName,
    required String title,
    required String riskCategory,
    required String riskLabel,
    required String warningMessage,
    required String approveLabel,
    required bool requiresUserApproval,
    required bool requiresSmokeArming,
    required bool emergencyStop,
    required List<String> approvalBoundaries,
    required List<String> approvalBlockerCodes,
    String? actionProposalNextAction,
    required String summary,
    required List<String> details,
    String? targetSummary,
    List<String> targetDetails = const [],
    String? exactTextPreview,
    int? exactTextLength,
    String? visionObservationSummary,
    List<String> visionObservationDetails = const [],
    String? reason,
  }) {
    final completer = Completer<ComputerUseActionApprovalDecision>();
    state = state.copyWith(
      pendingComputerUseAction: PendingComputerUseAction(
        id: const Uuid().v4(),
        toolName: toolName,
        title: title,
        riskCategory: riskCategory,
        riskLabel: riskLabel,
        warningMessage: warningMessage,
        approveLabel: approveLabel,
        requiresUserApproval: requiresUserApproval,
        requiresSmokeArming: requiresSmokeArming,
        emergencyStop: emergencyStop,
        summary: summary,
        details: details,
        targetSummary: targetSummary,
        targetDetails: targetDetails,
        exactTextPreview: exactTextPreview,
        exactTextLength: exactTextLength,
        approvalBoundaries: approvalBoundaries,
        approvalBlockerCodes: approvalBlockerCodes,
        actionProposalNextAction: actionProposalNextAction,
        visionObservationSummary: visionObservationSummary,
        visionObservationDetails: visionObservationDetails,
        reason: reason,
        completer: completer,
      ),
    );
    return completer.future;
  }

  void resolveComputerUseAction({
    required String id,
    required bool approved,
    bool armed = false,
  }) {
    final pending = state.pendingComputerUseAction;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(
        ComputerUseActionApprovalDecision(
          approved: approved && (!pending.requiresSmokeArming || armed),
          armed: armed,
          blockerCode: approved && pending.requiresSmokeArming && !armed
              ? 'arming_missing'
              : approved
              ? null
              : 'approval_denied',
        ),
      );
    }
    state = state.copyWith(pendingComputerUseAction: null);
  }

  ({String? summary, List<String> details}) _computerUseApprovalTargetContext(
    ToolCallInfo toolCall,
  ) {
    final args = toolCall.arguments;
    final target = _computerUseActionTarget(toolCall);
    final appName = _computerUseMetadataString(target, args, const [
      'appName',
      'applicationName',
      'app_name',
      'application',
    ]);
    final bundleId = _computerUseMetadataString(target, args, const [
      'bundleIdentifier',
      'appBundleId',
      'app_bundle_id',
      'bundle_id',
    ]);
    final windowTitle = _computerUseMetadataString(target, args, const [
      'windowTitle',
      'window_title',
      'title',
    ]);
    final windowId = _computerUseMetadataString(target, args, const [
      'windowId',
      'window_id',
    ]);
    final elementId = _computerUseMetadataString(target, args, const [
      'elementId',
      'element_id',
    ]);
    final role = _computerUseMetadataString(target, args, const [
      'role',
      'target_role',
    ]);
    final label = _computerUseMetadataString(target, args, const [
      'label',
      'target_label',
    ]);
    final action = _computerUseMetadataString(target, args, const [
      'action',
      'target_action',
    ]);
    final risk = _computerUseMetadataString(target, args, const [
      'risk',
      'target_risk',
    ]);

    final details = <String>[
      if (appName != null) 'App: $appName',
      if (bundleId != null) 'Bundle ID: $bundleId',
      if (windowTitle != null && windowId != null)
        'Window: $windowTitle (id $windowId)'
      else if (windowTitle != null)
        'Window: $windowTitle'
      else if (windowId != null)
        'Window ID: $windowId',
      if (elementId != null) 'Element ID: $elementId',
      if (role != null) 'Role: $role',
      if (label != null) 'Label: $label',
      if (action != null) 'Intended action: $action',
      if (risk != null) 'Target risk: $risk',
      if (args['x'] != null && args['y'] != null)
        'Coordinate fallback: x=${args['x']}, y=${args['y']}',
    ];

    if (details.isEmpty) {
      return (summary: null, details: const []);
    }

    final summary = label != null && role != null
        ? 'Review the $role target "$label" before approving.'
        : label != null
        ? 'Review target "$label" before approving.'
        : elementId != null
        ? 'Review target element $elementId before approving.'
        : 'Review the desktop target before approving.';
    return (summary: summary, details: details);
  }

  ({String? preview, int? length}) _computerUseApprovalExactTextContext(
    ToolCallInfo toolCall,
  ) {
    if (toolCall.name != 'computer_type_text') {
      return (preview: null, length: null);
    }
    final text = toolCall.arguments['text'];
    if (text is! String) {
      return (preview: null, length: null);
    }
    return (preview: text, length: text.length);
  }

  String? _computerUseMetadataString(
    Map<String, dynamic>? target,
    Map<String, dynamic> args,
    List<String> keys,
  ) {
    for (final source in [target, args]) {
      if (source == null) continue;
      for (final key in keys) {
        final value = source[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
        if (value is num || value is bool) {
          return '$value';
        }
      }
    }
    return null;
  }

  ({String? summary, List<String> details})
  _computerUseVisionObservationContext(ToolCallInfo toolCall) {
    final args = toolCall.arguments;
    final details = <String>[];
    final observationId = args['vision_observation_id'];
    final coordinateSpace = args['coordinate_space'];
    final sourceWidth = args['source_width'];
    final sourceHeight = args['source_height'];
    final windowId = args['window_id'];
    final displayId = args['display_id'];

    if (observationId != null) {
      details.add('Observation ID: $observationId');
    }
    if (coordinateSpace != null) {
      details.add('Coordinate space: $coordinateSpace');
    }
    if (sourceWidth != null && sourceHeight != null) {
      details.add('Source screenshot: $sourceWidth x $sourceHeight px');
    }
    if (windowId != null) {
      details.add('Target window ID: $windowId');
    }
    if (displayId != null) {
      details.add('Target display ID: $displayId');
    }

    return (
      summary:
          'Verify this action against the latest vision observation before approving.',
      details: details,
    );
  }

  Map<String, dynamic>? _computerUseActionTarget(ToolCallInfo toolCall) {
    final args = toolCall.arguments;
    final target = args['target'];
    if (target is Map) {
      return Map<String, dynamic>.from(target);
    }

    final explicitLabel = (args['target_label'] as String?)?.trim();
    final explicitRole = (args['target_role'] as String?)?.trim();
    final explicitRisk = (args['target_risk'] as String?)?.trim();
    final explicitAction = (args['target_action'] as String?)?.trim();
    if ([
      explicitLabel,
      explicitRole,
      explicitRisk,
      explicitAction,
    ].any((value) => value != null && value.isNotEmpty)) {
      return {
        if (explicitLabel != null && explicitLabel.isNotEmpty)
          'label': explicitLabel,
        if (explicitRole != null && explicitRole.isNotEmpty)
          'role': explicitRole,
        if (explicitRisk != null && explicitRisk.isNotEmpty)
          'risk': explicitRisk,
        if (explicitAction != null && explicitAction.isNotEmpty)
          'action': explicitAction,
      };
    }

    return switch (toolCall.name) {
      'computer_focus_window' => {
        'label': 'Window ${args['window_id']}',
        'role': 'window',
        'action': 'focus',
      },
      'computer_move_mouse' => {
        'label': 'Pointer target (${args['x']}, ${args['y']})',
        'role': 'coordinate',
        'action': 'move',
      },
      'computer_click' => {
        'label': 'Click target (${args['x']}, ${args['y']})',
        'role': 'coordinate',
        'action': 'click',
      },
      'computer_drag' => {
        'label':
            'Drag target (${args['from_x']}, ${args['from_y']}) to (${args['to_x']}, ${args['to_y']})',
        'role': 'coordinate_range',
        'action': 'drag',
      },
      'computer_scroll' => {
        'label':
            'Scroll target (${args['x'] ?? 'current'}, ${args['y'] ?? 'current'})',
        'role': 'scroll_target',
        'action': 'scroll',
      },
      'computer_type_text' => {
        'label': 'Focused text input',
        'role': 'text_input',
        'action': 'type_text',
      },
      'computer_switch_space' => {
        'label':
            'macOS Space ${_formatComputerUseSpaceDirection(args['direction'])}',
        'role': 'macos_space',
        'action': 'switch_space',
      },
      'computer_press_key' => {
        'label': _formatComputerUseKey(args['key'], args['modifiers']),
        'role': 'keyboard_shortcut',
        'action': 'press_key',
      },
      _ => null,
    };
  }

  String? _computerUseExactText(ToolCallInfo toolCall) {
    if (toolCall.name != 'computer_type_text') {
      return null;
    }
    return toolCall.arguments['text'] as String?;
  }

  String _describeComputerUseAction(ToolCallInfo toolCall) {
    final args = toolCall.arguments;
    return switch (toolCall.name) {
      'computer_focus_window' => 'Focus window ${args['window_id']}',
      'computer_move_mouse' => 'Move pointer to (${args['x']}, ${args['y']})',
      'computer_click' =>
        'Click ${args['button'] ?? 'left'} at (${args['x']}, ${args['y']})',
      'computer_drag' =>
        'Drag from (${args['from_x']}, ${args['from_y']}) to (${args['to_x']}, ${args['to_y']})',
      'computer_scroll' =>
        'Scroll by (${args['delta_x'] ?? 0}, ${args['delta_y'] ?? -5})',
      'computer_type_text' => 'Type ${_summarizeComputerUseText(args['text'])}',
      'computer_switch_space' =>
        'Switch to ${_formatComputerUseSpaceDirection(args['direction'])} macOS Space',
      'computer_press_key' =>
        'Press ${_formatComputerUseKey(args['key'], args['modifiers'])}',
      'computer_start_system_audio_recording' =>
        'Start recording system audio to ${args['output_path'] ?? 'a temporary CAF file'}',
      _ => '${toolCall.name} ${jsonEncode(args)}',
    };
  }

  List<String> _computerUseActionDetails(ToolCallInfo toolCall) {
    final args = toolCall.arguments;
    final details = <String>['Tool: ${toolCall.name}'];
    final reason = args['reason'] as String?;
    switch (toolCall.name) {
      case 'computer_focus_window':
        details.add('Window ID: ${args['window_id']}');
      case 'computer_move_mouse':
        details.addAll([
          'Coordinates: x=${args['x']}, y=${args['y']}',
          if (args['window_id'] != null) 'Window ID: ${args['window_id']}',
          if (args['source_width'] != null && args['source_height'] != null)
            'Source screenshot: ${args['source_width']} x ${args['source_height']} px',
          if (args['display_id'] != null) 'Display ID: ${args['display_id']}',
        ]);
      case 'computer_click':
        details.addAll([
          'Coordinates: x=${args['x']}, y=${args['y']}',
          'Button: ${args['button'] ?? 'left'}',
          'Click count: ${args['click_count'] ?? 1}',
          if (args['window_id'] != null) 'Window ID: ${args['window_id']}',
          if (args['source_width'] != null && args['source_height'] != null)
            'Source screenshot: ${args['source_width']} x ${args['source_height']} px',
          if (args['display_id'] != null) 'Display ID: ${args['display_id']}',
        ]);
      case 'computer_drag':
        details.addAll([
          'From: x=${args['from_x']}, y=${args['from_y']}',
          'To: x=${args['to_x']}, y=${args['to_y']}',
          'Duration: ${args['duration_ms'] ?? 300} ms',
          if (args['window_id'] != null) 'Window ID: ${args['window_id']}',
          if (args['source_width'] != null && args['source_height'] != null)
            'Source screenshot: ${args['source_width']} x ${args['source_height']} px',
          if (args['display_id'] != null) 'Display ID: ${args['display_id']}',
        ]);
      case 'computer_scroll':
        details.addAll([
          'Delta X: ${args['delta_x'] ?? 0}',
          'Delta Y: ${args['delta_y'] ?? -5}',
          if (args['window_id'] != null) 'Window ID: ${args['window_id']}',
          if (args['x'] != null && args['y'] != null)
            'Pointer target: x=${args['x']}, y=${args['y']}',
        ]);
      case 'computer_type_text':
        details.addAll([
          'Text length: ${('${args['text'] ?? ''}').length} characters',
          'Text preview: ${_summarizeComputerUseText(args['text'], maxLength: 160)}',
        ]);
      case 'computer_switch_space':
        final direction = _formatComputerUseSpaceDirection(args['direction']);
        final shortcut = direction == 'previous'
            ? 'control+left'
            : 'control+right';
        details.addAll(['Direction: $direction', 'Shortcut: $shortcut']);
      case 'computer_press_key':
        details.add(
          'Key: ${_formatComputerUseKey(args['key'], args['modifiers'])}',
        );
      case 'computer_start_system_audio_recording':
        details.addAll([
          'Output: ${args['output_path'] ?? 'temporary CAF file'}',
          'Exclude Caverno audio: ${args['exclude_current_process_audio'] ?? true}',
        ]);
    }
    if (reason != null && reason.trim().isNotEmpty) {
      details.add('Model reason: ${reason.trim()}');
    }
    return details;
  }

  String _summarizeComputerUseText(Object? value, {int maxLength = 80}) {
    final text = (value as String?) ?? '';
    if (text.isEmpty) return '(empty text)';
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return jsonEncode(normalized);
    }
    return jsonEncode('${normalized.substring(0, maxLength - 1)}...');
  }

  String _formatComputerUseKey(Object? key, Object? modifiers) {
    final modifierList = modifiers is List
        ? modifiers.map((value) => '$value').where((value) => value.isNotEmpty)
        : const Iterable<String>.empty();
    final parts = [
      ...modifierList,
      '${key ?? ''}',
    ].where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? '(unknown key)' : parts.join('+');
  }

  String _formatComputerUseSpaceDirection(Object? direction) {
    final normalized = '${direction ?? ''}'.trim().toLowerCase();
    return switch (normalized) {
      'previous' || 'prev' || 'left' => 'previous',
      _ => 'next',
    };
  }
}
