import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import 'printed_tool_call_recovery.dart';

/// Extracts and partitions calls while the caller owns seen-call acceptance.
final class ContentToolCallPartition {
  const ContentToolCallPartition._({
    required this.fresh,
    required this.repeated,
  });

  final List<ToolCallData> fresh;
  final List<ToolCallData> repeated;

  static ContentToolCallPartition fromContent({
    required String content,
    required Set<String>? advertisedToolNames,
    required bool Function(ToolCallData call) acceptCall,
  }) {
    final calls = const PrintedToolCallRecovery().extract(
      content: content,
      advertisedToolNames: advertisedToolNames,
    );
    final fresh = <ToolCallData>[];
    final repeated = <ToolCallData>[];
    for (final call in calls) {
      if (acceptCall(call)) {
        fresh.add(call);
      } else {
        repeated.add(call);
      }
    }
    return ContentToolCallPartition._(fresh: fresh, repeated: repeated);
  }
}
