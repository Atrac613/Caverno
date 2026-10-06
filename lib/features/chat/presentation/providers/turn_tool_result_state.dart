import 'dart:convert';

import '../../domain/entities/tool_call_info.dart';

/// Mutable storage owned exclusively by [TurnToolResultLedger].
final class TurnToolResultState {
  DateTime? expiresAt;
  List<ToolResultInfo> completed = const <ToolResultInfo>[];
  final List<ToolResultInfo> content = <ToolResultInfo>[];
  final List<String> commands = <String>[];
  final List<String> commandExecutionIdentities = <String>[];
}

bool toolResultLooksFailed(String result) {
  final normalized = result.toLowerCase();
  if (normalized.contains('"error"') && normalized.contains('"code"')) {
    return true;
  }
  try {
    final decoded = jsonDecode(result);
    return decoded is Map && decoded.containsKey('error');
  } catch (_) {
    return false;
  }
}
