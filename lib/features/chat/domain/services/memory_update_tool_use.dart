import 'dart:convert';

import 'session_memory_service.dart';

/// Renders a memory-update result as the display-only tool_use tag the
/// transcript shows after extraction. No notifier state.
abstract final class MemoryUpdateToolUse {
  static String build(MemoryUpdateResult result) {
    final payload = <String, dynamic>{
      'name': 'memory_update',
      'arguments': <String, dynamic>{
        'summaryUpdated': result.summaryUpdated,
        'added': result.addedMemoryCount,
        'updated': result.updatedMemoryCount,
        'queuedReview': result.queuedReviewCount,
        'suppressed': result.suppressedCandidateCount,
        'profileUpdated': result.profileUpdated,
        'method': result.generationMethod.name,
      },
    };
    return '<tool_use>${jsonEncode(payload)}</tool_use>';
  }
}
