import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';

/// What the running turn is doing right now, derived from the streamed content.
///
/// Content is the only per-turn signal that survives a thread switch and the
/// bubble being destroyed by the ListView when it scrolls out of view, so the
/// phase is read from the message rather than written into `ChatState` by the
/// tool loop. It is also self-clearing: the tool loop appends the `<tool_use>`
/// marker for every call in a batch before the batch executes, so the tail
/// holds for the whole batch and stops matching the moment the next request
/// streams a token.
enum AssistantTurnPhase { thinking, runningTools, responding }

/// Classifies [content] into the phase its tail describes.
AssistantTurnPhase assistantTurnPhaseFor(String content) {
  final end = _lastNonWhitespaceIndex(content);
  if (end == 0) return AssistantTurnPhase.thinking;
  if (_endsAt(content, end, '</tool_use>') ||
      _endsAt(content, end, '</tool_call>')) {
    return AssistantTurnPhase.runningTools;
  }
  if (_hasOpenReasoningTag(content)) return AssistantTurnPhase.thinking;
  return AssistantTurnPhase.responding;
}

/// The status line's phase text.
///
/// [runningToolNames] is ground truth from the tool-execution lifecycle and
/// wins whenever it has entries: the content tail keeps its `</tool_use>`
/// marker until the next request streams a token, so deriving from content
/// alone claims tools are running while the model is already thinking.
String assistantTurnStatusLabel({
  required String content,
  required List<String> runningToolNames,
}) {
  if (runningToolNames.length == 1) {
    return 'content.turn_status_running_tool'.tr(
      namedArgs: {'tool': runningToolNames.single},
    );
  }
  if (runningToolNames.length > 1) {
    return 'content.turn_status_running_tools_count'.tr(
      namedArgs: {'count': '${runningToolNames.length}'},
    );
  }
  return assistantTurnPhaseFor(content).label;
}

extension AssistantTurnPhaseLabel on AssistantTurnPhase {
  String get label => switch (this) {
    AssistantTurnPhase.thinking => 'content.turn_status_thinking'.tr(),
    AssistantTurnPhase.runningTools => 'content.turn_status_running_tools'.tr(),
    AssistantTurnPhase.responding => 'content.turn_status_responding'.tr(),
  };
}

/// Trailing whitespace boundary, found by index so no substring is allocated
/// on a string that grows with every streamed token.
int _lastNonWhitespaceIndex(String content) {
  var end = content.length;
  while (end > 0) {
    final unit = content.codeUnitAt(end - 1);
    if (unit == 0x20 || unit == 0x0A || unit == 0x0D || unit == 0x09) {
      end--;
      continue;
    }
    break;
  }
  return end;
}

bool _endsAt(String content, int end, String marker) =>
    end >= marker.length && content.startsWith(marker, end - marker.length);

/// True when a reasoning block was opened and never closed.
///
/// `<think` cannot match inside `</think>`, so the open and close probes never
/// collide and a bare `</think>` reads as closed.
bool _hasOpenReasoningTag(String content) {
  final open = math.max(
    content.lastIndexOf('<think'),
    content.lastIndexOf('<thought'),
  );
  if (open < 0) return false;
  final close = math.max(
    content.lastIndexOf('</think'),
    content.lastIndexOf('</thought'),
  );
  return open > close;
}
