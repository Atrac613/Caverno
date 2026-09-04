import 'dart:convert';

import '../entities/tool_call_info.dart';

/// How a macOS computer-use action is described to the model, and what is
/// stripped before it gets there.
///
/// These were private methods on ChatNotifier's computer-use handler part and
/// so counted against the notifier library's ratchet aggregate, although every
/// one of them is a pure function of its arguments: a redaction, a summary, a
/// key spelling, a fixed error phrase. The redaction in particular is a rule
/// about what leaves the device, which is easier to review as its own unit
/// than as a helper halfway down a 789-line handler.
abstract final class ComputerUseActionPresentation {
  static Map<String, dynamic> redactActionResult(
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

  static Map<String, dynamic> postActionVisionArguments(
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

  static String blockedErrorMessage(String code) {
    return switch (code) {
      'arming_missing' =>
        'Computer Use action blocked because the unsafe arming confirmation was not enabled.',
      'action_policy_blocked' =>
        'Computer Use action blocked by the target safety policy.',
      'approval_denied' => 'User denied macOS computer use action.',
      _ => 'macOS computer use action was blocked.',
    };
  }

  static String summarizeText(Object? value, {int maxLength = 80}) {
    final text = (value as String?) ?? '';
    if (text.isEmpty) return '(empty text)';
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return jsonEncode(normalized);
    }
    return jsonEncode('${normalized.substring(0, maxLength - 1)}...');
  }

  static String formatKey(Object? key, Object? modifiers) {
    final modifierList = modifiers is List
        ? modifiers.map((value) => '$value').where((value) => value.isNotEmpty)
        : const Iterable<String>.empty();
    final parts = [
      ...modifierList,
      '${key ?? ''}',
    ].where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? '(unknown key)' : parts.join('+');
  }

  static String formatSpaceDirection(Object? direction) {
    final normalized = '${direction ?? ''}'.trim().toLowerCase();
    return switch (normalized) {
      'previous' || 'prev' || 'left' => 'previous',
      _ => 'next',
    };
  }

  /// A one-line description of [toolCall] for an approval sheet.
  ///
  /// The last of the computer-use description helpers to leave the notifier
  /// library: it reads no state either, and it calls three of the functions
  /// that moved here already.
  static String describeAction(ToolCallInfo toolCall) {
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
      'computer_type_text' => 'Type ${summarizeText(args['text'])}',
      'computer_switch_space' =>
        'Switch to ${formatSpaceDirection(args['direction'])} macOS Space',
      'computer_press_key' =>
        'Press ${formatKey(args['key'], args['modifiers'])}',
      'computer_start_system_audio_recording' =>
        'Start recording system audio to ${args['output_path'] ?? 'a temporary CAF file'}',
      _ => '${toolCall.name} ${jsonEncode(args)}',
    };
  }
}
