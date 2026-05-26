import 'dart:convert';

import '../entities/message.dart';

enum CodingApprovalAutoReviewOutcome { allow, deny }

class CodingApprovalAutoReviewDecision {
  const CodingApprovalAutoReviewDecision({
    required this.outcome,
    required this.riskLevel,
    required this.userAuthorization,
    required this.rationale,
  });

  final CodingApprovalAutoReviewOutcome outcome;
  final String riskLevel;
  final String userAuthorization;
  final String rationale;

  bool get isAllowed => outcome == CodingApprovalAutoReviewOutcome.allow;
}

class CodingApprovalConversationEntry {
  const CodingApprovalConversationEntry({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class CodingApprovalAutoReviewRequest {
  const CodingApprovalAutoReviewRequest({
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
  final List<CodingApprovalConversationEntry> conversationTail;
  final String? path;
  final String? workingDirectory;
  final String? reason;
  final String? warningTitle;
  final String? warningMessage;
  final String? preview;
}

class CodingApprovalAutoReviewService {
  CodingApprovalAutoReviewService._();

  static const int _maxConversationEntries = 8;
  static const int _maxConversationContentChars = 900;
  static const int _maxPreviewChars = 12000;

  static List<CodingApprovalConversationEntry> buildConversationTail(
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
          (message) => CodingApprovalConversationEntry(
            role: message.role.name,
            content: _truncate(message.content, _maxConversationContentChars),
          ),
        )
        .toList(growable: false);
  }

  static List<Message> buildMessages(CodingApprovalAutoReviewRequest request) {
    final now = DateTime.now();
    return [
      Message(
        id: 'auto_review_policy',
        role: MessageRole.system,
        timestamp: now,
        content:
            'You are Caverno approval auto-review. Review whether the requested coding action may cross the local permission boundary. '
            'Do not execute tools. Do not propose alternatives. Return only strict JSON with keys outcome, riskLevel, userAuthorization, and rationale. '
            'Use outcome "allow" only when the action is clearly requested by the user, scoped to the selected project, and not destructive beyond that intent. '
            'Use outcome "deny" for destructive, credential, exfiltration, network side-effect, privilege escalation, or unrelated actions.',
      ),
      Message(
        id: 'auto_review_request',
        role: MessageRole.user,
        timestamp: now,
        content: jsonEncode(_packetForRequest(request)),
      ),
    ];
  }

  static CodingApprovalAutoReviewDecision? parseDecision(String content) {
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
      'allow' => CodingApprovalAutoReviewOutcome.allow,
      'deny' => CodingApprovalAutoReviewOutcome.deny,
      _ => null,
    };
    if (outcome == null) return null;

    final rationale = '${decoded['rationale'] ?? ''}'.trim();
    if (rationale.isEmpty) return null;

    return CodingApprovalAutoReviewDecision(
      outcome: outcome,
      riskLevel: '${decoded['riskLevel'] ?? 'unknown'}'.trim(),
      userAuthorization: '${decoded['userAuthorization'] ?? 'unknown'}'.trim(),
      rationale: rationale,
    );
  }

  static Map<String, dynamic> _packetForRequest(
    CodingApprovalAutoReviewRequest request,
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
