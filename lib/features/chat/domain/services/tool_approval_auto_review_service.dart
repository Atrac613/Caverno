import 'dart:convert';

import '../entities/message.dart';

enum ToolApprovalAutoReviewOutcome { allow, deny }

/// Which permission boundary the auto-reviewer is judging. Swaps the system
/// prompt so the same JSON contract serves coding writes, browser actions, and
/// device/remote connections.
enum ToolApprovalAutoReviewDomain { coding, browser, connection }

class ToolApprovalAutoReviewDecision {
  const ToolApprovalAutoReviewDecision({
    required this.outcome,
    required this.riskLevel,
    required this.userAuthorization,
    required this.rationale,
  });

  final ToolApprovalAutoReviewOutcome outcome;
  final String riskLevel;
  final String userAuthorization;
  final String rationale;

  bool get isAllowed => outcome == ToolApprovalAutoReviewOutcome.allow;
}

class ToolApprovalConversationEntry {
  const ToolApprovalConversationEntry({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class ToolApprovalAutoReviewRequest {
  const ToolApprovalAutoReviewRequest({
    required this.actionKind,
    required this.toolName,
    required this.arguments,
    required this.conversationTail,
    this.path,
    this.workingDirectory,
    this.reason,
    this.warningTitle,
    this.warningMessage,
    this.preview,
  });

  final String actionKind;
  final String toolName;
  final Map<String, dynamic> arguments;
  final List<ToolApprovalConversationEntry> conversationTail;
  final String? path;
  final String? workingDirectory;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;
  final String? preview;
}

class ToolApprovalAutoReviewService {
  ToolApprovalAutoReviewService._();

  static const int _maxConversationEntries = 8;
  static const int _maxConversationContentChars = 900;
  static const int _maxPreviewChars = 12000;

  static List<ToolApprovalConversationEntry> buildConversationTail(
    List<Message> messages,
  ) {
    return messages
        .where(
          (message) =>
              message.role == MessageRole.user ||
              message.role == MessageRole.assistant,
        )
        .takeLast(_maxConversationEntries)
        .map(
          (message) => ToolApprovalConversationEntry(
            role: message.role.name,
            content: _truncate(message.content, _maxConversationContentChars),
          ),
        )
        .toList(growable: false);
  }

  static List<Message> buildMessages(
    ToolApprovalAutoReviewRequest request, {
    ToolApprovalAutoReviewDomain domain =
        ToolApprovalAutoReviewDomain.coding,
  }) {
    final now = DateTime.now();
    return [
      Message(
        id: 'auto_review_policy',
        role: MessageRole.system,
        timestamp: now,
        content: switch (domain) {
          ToolApprovalAutoReviewDomain.coding =>
            'You are Caverno approval auto-review. Review whether the requested coding action may cross the local permission boundary. '
                'Do not execute tools. Do not propose alternatives. Return only strict JSON with keys outcome, riskLevel, userAuthorization, and rationale. '
                'Use outcome "allow" only when the action is clearly requested by the user, scoped to the selected project, and not destructive beyond that intent. '
                'Use outcome "deny" for destructive, credential, exfiltration, network side-effect, privilege escalation, or unrelated actions.',
          ToolApprovalAutoReviewDomain.browser =>
            'You are Caverno approval auto-review for the built-in browser. Review whether the requested browser action may cross a safety boundary. '
                'Do not execute tools. Do not propose alternatives. Return only strict JSON with keys outcome, riskLevel, userAuthorization, and rationale. '
                'Use outcome "allow" only when the action clearly advances the user request and does not submit credentials, make a purchase, send a message, post publicly, or otherwise cause an irreversible side effect. '
                'Use outcome "deny" for credential entry, payments, destructive or irreversible submissions, data exfiltration, or actions unrelated to the user request.',
          ToolApprovalAutoReviewDomain.connection =>
            'You are Caverno approval auto-review for device and remote connections (SSH, Bluetooth LE, serial). Review whether the requested action may cross a safety boundary. '
                'Do not execute tools. Do not propose alternatives. Return only strict JSON with keys outcome, riskLevel, userAuthorization, and rationale. '
                'Use outcome "allow" only when the action clearly advances the user request and targets a host/device the user asked to use, and is not a destructive, irreversible, or system-altering command. '
                'Use outcome "deny" for destructive or irreversible commands, privilege escalation, credential exposure, or actions on hosts/devices unrelated to the user request.',
        },
      ),
      Message(
        id: 'auto_review_request',
        role: MessageRole.user,
        timestamp: now,
        content: jsonEncode(_packetForRequest(request)),
      ),
    ];
  }

  static ToolApprovalAutoReviewDecision? parseDecision(String content) {
    final jsonText = _extractJsonObject(content);
    if (jsonText == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final outcomeText = '${decoded['outcome'] ?? ''}'.trim().toLowerCase();
    final outcome = switch (outcomeText) {
      'allow' => ToolApprovalAutoReviewOutcome.allow,
      'deny' => ToolApprovalAutoReviewOutcome.deny,
      _ => null,
    };
    if (outcome == null) return null;

    final rationale = '${decoded['rationale'] ?? ''}'.trim();
    if (rationale.isEmpty) return null;

    return ToolApprovalAutoReviewDecision(
      outcome: outcome,
      riskLevel: '${decoded['riskLevel'] ?? 'unknown'}'.trim(),
      userAuthorization: '${decoded['userAuthorization'] ?? 'unknown'}'.trim(),
      rationale: rationale,
    );
  }

  static Map<String, dynamic> _packetForRequest(
    ToolApprovalAutoReviewRequest request,
  ) {
    return {
      'schemaName': 'caverno_coding_approval_auto_review_request',
      'instructions':
          'Return only {"outcome":"allow|deny","riskLevel":"low|medium|high|critical","userAuthorization":"unknown|low|medium|high","rationale":"one concise sentence"}.',
      'action': {
        'kind': request.actionKind,
        'toolName': request.toolName,
        'arguments': request.arguments,
        if (_hasText(request.path)) 'path': request.path,
        if (_hasText(request.workingDirectory))
          'workingDirectory': request.workingDirectory,
        if (_hasText(request.reason)) 'reason': request.reason,
        if (_hasText(request.warningTitle))
          'warningTitle': request.warningTitle,
        if (_hasText(request.warningMessage))
          'warningMessage': request.warningMessage,
        if (_hasText(request.preview))
          'preview': _truncate(request.preview!, _maxPreviewChars),
      },
      'conversationTail': request.conversationTail
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }

  static String? _extractJsonObject(String content) {
    var candidate = content.trim();
    final fenced = RegExp(
      r'^```(?:json)?\s*(.*?)\s*```$',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(candidate);
    if (fenced != null) {
      candidate = fenced.group(1)!.trim();
    }

    if (candidate.startsWith('{') && candidate.endsWith('}')) {
      return candidate;
    }

    final start = candidate.indexOf('{');
    final end = candidate.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    return candidate.substring(start, end + 1);
  }

  static bool _hasText(String? value) => value?.trim().isNotEmpty == true;

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }
}

extension _TakeLastExtension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList(growable: false);
    if (values.length <= count) return values;
    return values.skip(values.length - count);
  }
}
