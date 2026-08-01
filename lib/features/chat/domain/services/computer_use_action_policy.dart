// ChatNotifier decomposition collaborator: computer-use-action-policy

import 'dart:convert';

import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../entities/mcp_tool_entity.dart';
import 'immutable_json_snapshot.dart';

/// Immutable Computer Use action captured before policy evaluation.
final class ComputerUseActionInput {
  ComputerUseActionInput({
    required this.toolName,
    required Map<String, dynamic> arguments,
  }) : arguments = freezeComputerUseArguments(arguments);

  final String toolName;
  final Map<String, dynamic> arguments;
}

/// Immutable action summary and details displayed during approval.
final class ComputerUseActionPresentation {
  ComputerUseActionPresentation({
    required this.summary,
    required List<String> details,
  }) : details = List<String>.unmodifiable(details);

  final String summary;
  final List<String> details;
}

/// Immutable vision-observation context displayed during approval.
final class ComputerUseContext {
  ComputerUseContext({required this.summary, required List<String> details})
    : details = List<String>.unmodifiable(details);

  final String? summary;
  final List<String> details;
}

/// Explicit observation result supplied after action execution.
final class ComputerUsePostActionObservation {
  const ComputerUsePostActionObservation({
    required this.toolName,
    required this.success,
    this.result,
    this.errorCode,
  });

  final String toolName;
  final bool success;
  final String? result;
  final String? errorCode;
}

/// Immutable inputs for composing an action and its observation.
final class ComputerUseResultCompositionInput {
  const ComputerUseResultCompositionInput({
    required this.actionResult,
    required this.policy,
    required this.observation,
  });

  final McpToolResult actionResult;
  final MacosComputerUseToolPolicyDecision? policy;
  final ComputerUsePostActionObservation? observation;
}

/// Immutable blocked-action mapping inputs.
final class ComputerUseBlockedInput {
  ComputerUseBlockedInput({
    required this.action,
    required this.policy,
    required this.code,
    List<String> approvalBlockerCodes = const [],
    this.actionProposalNextAction,
  }) : approvalBlockerCodes = List<String>.unmodifiable(approvalBlockerCodes);

  final ComputerUseActionInput action;
  final MacosComputerUseToolPolicyDecision? policy;
  final String code;
  final List<String> approvalBlockerCodes;
  final String? actionProposalNextAction;
}

/// Exact result and error text returned for a blocked action.
final class ComputerUseBlockedOutcome {
  const ComputerUseBlockedOutcome({
    required this.result,
    required this.errorMessage,
  });

  final String result;
  final String errorMessage;
}

/// Pure Computer Use presentation, redaction, and result policy.
final class ComputerUseActionPolicy {
  const ComputerUseActionPolicy();

  ComputerUseActionPresentation approvalPresentation(
    ComputerUseActionInput action,
  ) {
    final details = actionDetails(action);
    return ComputerUseActionPresentation(
      summary: describeAction(action),
      details: details,
    );
  }

  McpToolResult resultWithPostActionObservation(
    ComputerUseResultCompositionInput input,
  ) {
    final observation = input.observation;
    if (observation == null) {
      return input.actionResult;
    }
    final result = input.actionResult;
    final actionResult =
        _tryDecodeMap(result.result) ?? {'rawResult': result.result};
    final observationResult =
        _tryDecodeMap(observation.result ?? '') ??
        <String, dynamic>{
          'ok': observation.success,
          if (observation.errorCode != null) 'code': observation.errorCode,
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
        'policy': input.policy?.toJson(),
        'action': redactActionResult(actionResult),
        'postActionObservationRequired':
            input.policy?.requiresPostActionObservation == true,
        'postActionObservation': {
          'toolName': observation.toolName,
          'success': observation.success,
          'imageAttached': imageAttached,
          if (observation.errorCode != null) 'errorCode': observation.errorCode,
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

  Map<String, dynamic> redactActionResult(Map<String, dynamic> actionResult) {
    final redacted = Map<String, dynamic>.from(actionResult)
      ..remove('imageBase64')
      ..remove('text');
    if (actionResult['text'] is String) {
      redacted['textRedacted'] = true;
      redacted['textLength'] = (actionResult['text'] as String).length;
    }
    return redacted;
  }

  Map<String, dynamic> postActionVisionArguments(
    ComputerUseActionInput action,
  ) {
    final windowId = action.arguments['window_id'];
    final displayId = action.arguments['display_id'];
    return freezeComputerUseArguments({
      'target': windowId != null ? 'window' : 'front_window',
      'max_width': 800,
      'include_windows': true,
      'window_id': ?windowId,
      'display_id': ?displayId,
    });
  }

  ComputerUseBlockedOutcome blockedOutcome(ComputerUseBlockedInput input) {
    return ComputerUseBlockedOutcome(
      result: blockedResult(input),
      errorMessage: blockedErrorMessage(input.code),
    );
  }

  String blockedResult(ComputerUseBlockedInput input) {
    return jsonEncode({
      'ok': false,
      'toolName': input.action.toolName,
      'code': input.code,
      'error': blockedErrorMessage(input.code),
      'policy': input.policy?.toJson(),
      'requiresUserApproval': input.policy?.requiresUserApproval ?? false,
      'requiresSmokeArming': input.policy?.requiresSmokeArming ?? false,
      'emergencyStop': input.policy?.emergencyStop ?? false,
      if (input.approvalBlockerCodes.isNotEmpty)
        'approvalBlockers': input.approvalBlockerCodes,
      'nextAction': switch (input.code) {
        'action_policy_blocked' =>
          input.actionProposalNextAction ??
              'Resolve the Computer Use action policy blockers before retrying.',
        'arming_missing' =>
          'Ask the user to explicitly arm the pending Computer Use action before retrying.',
        'approval_denied' =>
          'Ask the user for explicit approval before retrying this Computer Use action.',
        _ => 'Inspect the Computer Use approval state before retrying.',
      },
    });
  }

  String blockedErrorMessage(String code) {
    return switch (code) {
      'arming_missing' =>
        'Computer Use action blocked because the unsafe arming confirmation was not enabled.',
      'action_policy_blocked' =>
        'Computer Use action blocked by the target safety policy.',
      'approval_denied' => 'User denied macOS computer use action.',
      _ => 'macOS computer use action was blocked.',
    };
  }

  String? metadataString(
    Map<String, dynamic>? target,
    Map<String, dynamic> arguments,
    List<String> keys,
  ) {
    for (final source in [target, arguments]) {
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

  ComputerUseContext visionObservationContext(ComputerUseActionInput action) {
    final args = action.arguments;
    final details = <String>[
      if (args['vision_observation_id'] != null)
        'Observation ID: ${args['vision_observation_id']}',
      if (args['coordinate_space'] != null)
        'Coordinate space: ${args['coordinate_space']}',
      if (args['source_width'] != null && args['source_height'] != null)
        'Source screenshot: ${args['source_width']} x ${args['source_height']} px',
      if (args['window_id'] != null) 'Target window ID: ${args['window_id']}',
      if (args['display_id'] != null)
        'Target display ID: ${args['display_id']}',
    ];
    return ComputerUseContext(
      summary:
          'Verify this action against the latest vision observation before approving.',
      details: details,
    );
  }

  Map<String, dynamic>? actionTarget(ComputerUseActionInput action) {
    final args = action.arguments;
    final target = args['target'];
    if (target is Map) {
      return freezeComputerUseArguments(Map<String, dynamic>.from(target));
    }
    final label = (args['target_label'] as String?)?.trim();
    final role = (args['target_role'] as String?)?.trim();
    final risk = (args['target_risk'] as String?)?.trim();
    final intendedAction = (args['target_action'] as String?)?.trim();
    if ([label, role, risk, intendedAction].any(_isNotEmpty)) {
      return freezeComputerUseArguments({
        if (_isNotEmpty(label)) 'label': label,
        if (_isNotEmpty(role)) 'role': role,
        if (_isNotEmpty(risk)) 'risk': risk,
        if (_isNotEmpty(intendedAction)) 'action': intendedAction,
      });
    }
    final derived = switch (action.toolName) {
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
        'label': 'macOS Space ${formatSpaceDirection(args['direction'])}',
        'role': 'macos_space',
        'action': 'switch_space',
      },
      'computer_press_key' => {
        'label': formatKey(args['key'], args['modifiers']),
        'role': 'keyboard_shortcut',
        'action': 'press_key',
      },
      _ => null,
    };
    return derived == null ? null : freezeComputerUseArguments(derived);
  }

  String? exactText(ComputerUseActionInput action) {
    if (action.toolName != 'computer_type_text') {
      return null;
    }
    return action.arguments['text'] as String?;
  }

  String describeAction(ComputerUseActionInput action) {
    final args = action.arguments;
    return switch (action.toolName) {
      'computer_focus_window' => 'Focus window ${args['window_id']}',
      'computer_move_mouse' => 'Move pointer to (${args['x']}, ${args['y']})',
      'computer_click' =>
        'Click ${args['button'] ?? 'left'} at (${args['x']}, ${args['y']})',
      'computer_drag' =>
        'Drag from (${args['from_x']}, ${args['from_y']}) to (${args['to_x']}, ${args['to_y']})',
      'computer_scroll' =>
        'Scroll by (${args['delta_x'] ?? 0}, ${args['delta_y'] ?? -5})',
      'computer_type_text' => 'Type ${summarizeText(args['text'])}',
      'computer_switch_space' =>
        'Switch to ${formatSpaceDirection(args['direction'])} macOS Space',
      'computer_press_key' =>
        'Press ${formatKey(args['key'], args['modifiers'])}',
      'computer_start_system_audio_recording' =>
        'Start recording system audio to ${args['output_path'] ?? 'a temporary CAF file'}',
      _ => '${action.toolName} ${jsonEncode(args)}',
    };
  }

  List<String> actionDetails(ComputerUseActionInput action) {
    final args = action.arguments;
    final details = <String>['Tool: ${action.toolName}'];
    final reason = args['reason'] as String?;
    switch (action.toolName) {
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
          'Text preview: ${summarizeText(args['text'], maxLength: 160)}',
        ]);
      case 'computer_switch_space':
        final direction = formatSpaceDirection(args['direction']);
        details.addAll([
          'Direction: $direction',
          'Shortcut: ${direction == 'previous' ? 'control+left' : 'control+right'}',
        ]);
      case 'computer_press_key':
        details.add('Key: ${formatKey(args['key'], args['modifiers'])}');
      case 'computer_start_system_audio_recording':
        details.addAll([
          'Output: ${args['output_path'] ?? 'temporary CAF file'}',
          'Exclude Caverno audio: ${args['exclude_current_process_audio'] ?? true}',
        ]);
    }
    if (reason != null && reason.trim().isNotEmpty) {
      details.add('Model reason: ${reason.trim()}');
    }
    return List<String>.unmodifiable(details);
  }

  String summarizeText(Object? value, {int maxLength = 80}) {
    final text = (value as String?) ?? '';
    if (text.isEmpty) return '(empty text)';
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return jsonEncode(
      normalized.length <= maxLength
          ? normalized
          : '${normalized.substring(0, maxLength - 1)}...',
    );
  }

  String formatKey(Object? key, Object? modifiers) {
    final modifierList = modifiers is List
        ? modifiers.map((value) => '$value').where((value) => value.isNotEmpty)
        : const Iterable<String>.empty();
    final parts = [
      ...modifierList,
      '${key ?? ''}',
    ].where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? '(unknown key)' : parts.join('+');
  }

  String formatSpaceDirection(Object? direction) {
    final normalized = '${direction ?? ''}'.trim().toLowerCase();
    return switch (normalized) {
      'previous' || 'prev' || 'left' => 'previous',
      _ => 'next',
    };
  }
}

bool _isNotEmpty(String? value) => value != null && value.isNotEmpty;

Map<String, dynamic>? _tryDecodeMap(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> freezeComputerUseArguments(Map<String, dynamic> value) {
  return ImmutableJsonSnapshot.freezeMap(value);
}
