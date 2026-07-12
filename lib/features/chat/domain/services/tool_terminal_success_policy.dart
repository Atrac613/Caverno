import 'dart:convert';

/// Recognizes an explicit, structured terminal-success contract from a tool.
class ToolTerminalSuccessPolicy {
  const ToolTerminalSuccessPolicy();

  String? terminalMessage(String rawResult) {
    final payload = _decodeObject(rawResult);
    if (payload == null || payload['terminal_success'] != true) {
      return null;
    }
    final message = payload['terminal_message']?.toString().trim();
    return message == null || message.isEmpty
        ? 'Verification succeeded. The requested work is complete.'
        : message;
  }

  Map<String, dynamic>? _decodeObject(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

/// Tracks terminal evidence in tool-call order within one execution batch.
class ToolTerminalSuccessBatchState {
  String? _message;

  String? get message => _message;

  bool observeSuccessfulResult({
    required String rawResult,
    required bool isMutationTool,
  }) {
    final explicitMessage = const ToolTerminalSuccessPolicy().terminalMessage(
      rawResult,
    );
    if (explicitMessage != null) {
      _message = explicitMessage;
      return true;
    } else if (isMutationTool) {
      _message = null;
    }
    return false;
  }
}
