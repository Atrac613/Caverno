import 'dart:convert';

import '../entities/tool_call_info.dart';

typedef ToolResponseTextPredicate = bool Function(String value);
typedef ToolResultPredicate = bool Function(ToolResultInfo value);
typedef ToolResultPayloadPathResolver = String? Function(String result);
typedef CodeUnitSequencePredicate =
    bool Function(String value, List<List<int>> sequences);

class ToolTerminalResponsePolicy {
  const ToolTerminalResponsePolicy({
    required ToolResponseTextPredicate looksLikeUnexecutedToolRequest,
    required ToolResponseTextPredicate looksLikePlanOnlyFinalToolAnswer,
    required ToolResponseTextPredicate looksLikePendingToolActionResponse,
    required ToolResponseTextPredicate looksLikeStructuredToolRequest,
    required ToolResponseTextPredicate isFileMutationToolName,
    required ToolResultPredicate isSuccessfulFileMutationToolResult,
    required ToolResultPayloadPathResolver toolResultPayloadPath,
    required CodeUnitSequencePredicate containsAnyCodeUnitSequence,
    required ToolResponseTextPredicate containsCjkBlockerMarker,
    required ToolResponseTextPredicate containsCjkMissingEvidenceMarker,
  }) : _looksLikeUnexecutedToolRequest = looksLikeUnexecutedToolRequest,
       _looksLikePlanOnlyFinalToolAnswer = looksLikePlanOnlyFinalToolAnswer,
       _looksLikePendingToolActionResponse = looksLikePendingToolActionResponse,
       _looksLikeStructuredToolRequest = looksLikeStructuredToolRequest,
       _isFileMutationToolName = isFileMutationToolName,
       _isSuccessfulFileMutationToolResult = isSuccessfulFileMutationToolResult,
       _toolResultPayloadPath = toolResultPayloadPath,
       _containsAnyCodeUnitSequence = containsAnyCodeUnitSequence,
       _containsCjkBlockerMarker = containsCjkBlockerMarker,
       _containsCjkMissingEvidenceMarker = containsCjkMissingEvidenceMarker;

  final ToolResponseTextPredicate _looksLikeUnexecutedToolRequest;
  final ToolResponseTextPredicate _looksLikePlanOnlyFinalToolAnswer;
  final ToolResponseTextPredicate _looksLikePendingToolActionResponse;
  final ToolResponseTextPredicate _looksLikeStructuredToolRequest;
  final ToolResponseTextPredicate _isFileMutationToolName;
  final ToolResultPredicate _isSuccessfulFileMutationToolResult;
  final ToolResultPayloadPathResolver _toolResultPayloadPath;
  final CodeUnitSequencePredicate _containsAnyCodeUnitSequence;
  final ToolResponseTextPredicate _containsCjkBlockerMarker;
  final ToolResponseTextPredicate _containsCjkMissingEvidenceMarker;

  int hiddenAssistantEvidenceScore(String response) {
    return _hiddenAssistantEvidenceScore(response);
  }

  bool shouldAcceptRecoveryFinalTextResponse(String response) {
    return _shouldAcceptRecoveryFinalTextResponse(response);
  }

  bool shouldAcceptTerminalToolRoleFinalTextResponse(String response) {
    return _shouldAcceptTerminalToolRoleFinalTextResponse(response);
  }

  bool shouldAcceptTerminalFileMutationFinalTextResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _shouldAcceptTerminalFileMutationFinalTextResponse(
      response,
      toolResults,
    );
  }

  bool shouldAcceptTerminalBrowserSaveDataResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _shouldAcceptTerminalBrowserSaveDataResponse(response, toolResults);
  }

  String normalizeTerminalBrowserSaveDataResponse(String response) {
    return _normalizeTerminalBrowserSaveDataResponse(response);
  }

  List<String> successfulBrowserSaveDataPaths(
    List<ToolResultInfo> toolResults,
  ) {
    return _successfulBrowserSaveDataPaths(toolResults);
  }

  bool containsFileMutationCompletionMarker(String response) {
    return _containsFileMutationCompletionMarker(response);
  }

  bool containsOptionalFollowUpOffer(String normalizedResponse) {
    return _containsOptionalFollowUpOffer(normalizedResponse);
  }

  bool shouldAcceptTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _shouldAcceptTerminalSkillToolRoleResponse(response, toolResults);
  }

  bool shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
    String response,
    List<ToolResultInfo> toolResults,
    List<ToolCallInfo> followUpToolCalls,
  ) {
    return _shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
      response,
      toolResults,
      followUpToolCalls,
    );
  }

  bool looksLikeSkillContinuationWorkIntent(String response) {
    return _looksLikeSkillContinuationWorkIntent(response);
  }

  String normalizeTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _normalizeTerminalSkillToolRoleResponse(response, toolResults);
  }

  bool hasSuccessfulLoadSkillResult(List<ToolResultInfo> toolResults) {
    return _hasSuccessfulLoadSkillResult(toolResults);
  }

  bool toolResultLooksSuccessfulForFinalAnswer(String result) {
    return _toolResultLooksSuccessfulForFinalAnswer(result);
  }

  bool matchesLoadedSkillExplicitMarker({
    required String response,
    required List<ToolResultInfo> toolResults,
  }) {
    return _matchesLoadedSkillExplicitMarker(
      response: response,
      toolResults: toolResults,
    );
  }

  bool shouldAcceptTerminalToolRoleBlockerResponse(String response) {
    return _shouldAcceptTerminalToolRoleBlockerResponse(response);
  }

  bool isSavedWorkflowContinuationQuestion(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }
    final hasQuestion =
        candidate.contains('?') ||
        candidate.contains(String.fromCharCode(0xff1f));
    if (!hasQuestion) {
      return false;
    }
    return RegExp(
      r'\b(?:shall|should|can|may) i (?:continue|proceed)\b|'
      r'\b(?:continue|proceed) (?:to|with) the next (?:saved )?task\b|'
      r'\b(?:do you want|would you like) me to (?:continue|proceed)\b|'
      '\u6b21\u306e\u30bf\u30b9\u30af|'
      '\u9032\u307f\u307e\u3059\u304b',
      caseSensitive: false,
    ).hasMatch(candidate);
  }

  bool _containsAny(String value, List<String> markers) {
    return markers.any(value.contains);
  }

  int _hiddenAssistantEvidenceScore(String response) {
    final normalized = response.toLowerCase();
    var score = 0;
    if (normalized.contains('complete') || normalized.contains('completed')) {
      score += 2;
    }
    if (normalized.contains('validation passed') ||
        normalized.contains('tests passed') ||
        normalized.contains('was successful')) {
      score += 2;
    }
    if (normalized.contains('next task') ||
        normalized.contains('saved task') ||
        normalized.contains('in the plan')) {
      score += 1;
    }
    return score;
  }

  bool _shouldAcceptRecoveryFinalTextResponse(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }
    return _hiddenAssistantEvidenceScore(candidate) >= 2;
  }

  bool _shouldAcceptTerminalToolRoleFinalTextResponse(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }

    final normalized = candidate.toLowerCase();
    if (_hiddenAssistantEvidenceScore(candidate) < 2) {
      return false;
    }
    if (!normalized.contains('complete')) {
      return false;
    }
    final mentionsTaskReference =
        normalized.contains('task "') ||
        normalized.contains('task `') ||
        RegExp(r'task [0-9a-f-]{8,}').hasMatch(normalized);
    if (!mentionsTaskReference) {
      return false;
    }
    if (_containsOptionalFollowUpOffer(normalized)) {
      return false;
    }
    return true;
  }

  bool _shouldAcceptTerminalFileMutationFinalTextResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    final candidate = response.trim();
    if (candidate.isEmpty || candidate.length > 3000) {
      return false;
    }
    if (_containsOptionalFollowUpOffer(candidate.toLowerCase()) ||
        _looksLikeUnexecutedToolRequest(candidate) ||
        _looksLikePlanOnlyFinalToolAnswer(candidate)) {
      return false;
    }

    final successfulMutationResults = toolResults
        .where((toolResult) {
          return _isFileMutationToolName(toolResult.name) &&
              _isSuccessfulFileMutationToolResult(toolResult);
        })
        .toList(growable: false);
    if (successfulMutationResults.isEmpty) {
      return false;
    }

    final hasCompletionMarker =
        _containsFileMutationCompletionMarker(candidate) ||
        successfulMutationResults.any((toolResult) {
          final path = _toolResultPayloadPath(toolResult.result);
          return path != null && candidate.contains(path);
        });
    if (!hasCompletionMarker) {
      return false;
    }

    return successfulMutationResults.any((toolResult) {
      final path = _toolResultPayloadPath(toolResult.result);
      if (path == null) {
        return true;
      }
      final basename = path.split(RegExp(r'[/\\]+')).last;
      return candidate.contains(path) ||
          (basename.isNotEmpty && candidate.contains(basename));
    });
  }

  bool _shouldAcceptTerminalBrowserSaveDataResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    final candidate = response.trim();
    if (candidate.isEmpty || candidate.length > 3000) {
      return false;
    }
    if (_looksLikeUnexecutedToolRequest(candidate) ||
        _looksLikePlanOnlyFinalToolAnswer(candidate)) {
      return false;
    }

    final savedPaths = _successfulBrowserSaveDataPaths(toolResults);
    if (savedPaths.isEmpty) {
      return false;
    }
    return savedPaths.any(candidate.contains);
  }

  String _normalizeTerminalBrowserSaveDataResponse(String response) {
    return _stripTrailingOptionalFollowUpOffer(response.trim()).trim();
  }

  List<String> _successfulBrowserSaveDataPaths(
    List<ToolResultInfo> toolResults,
  ) {
    return toolResults
        .where((toolResult) {
          return toolResult.name.trim().toLowerCase() == 'browser_save_data' &&
              _toolResultLooksSuccessfulForFinalAnswer(toolResult.result);
        })
        .map((toolResult) => _toolResultPayloadPath(toolResult.result))
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);
  }

  bool _containsFileMutationCompletionMarker(String response) {
    final normalized = response.toLowerCase();
    return _containsAny(normalized, const [
      'saved',
      'wrote',
      'created',
      'updated',
      'overwrote',
      'modified',
      'file:',
      'file path',
      'bytes_written',
    ]);
  }

  bool _containsOptionalFollowUpOffer(String normalizedResponse) {
    return RegExp(
      r'\b(next task|shall i proceed|should i|would you like|do you want|'
      r'want me|let me know|anything else|need anything|i will |'
      r'i can continue|i can also|i can help)\b|'
      r'\b(other|another|different)\s+'
      r'(format|output|file|task|city|date|report|check)\b|'
      '\u4ed6\u306b|\u4ed6\u306e|\u5225\u306e|'
      '\u8ffd\u52a0\u3057\u305f\u3044|'
      '\u5fc5\u8981\u304c\u3042\u308a\u307e\u3059\u304b|'
      '\u304a\u77e5\u3089\u305b\u304f\u3060\u3055\u3044|'
      '\u8abf\u3079\u307e\u3059\u304b',
    ).hasMatch(normalizedResponse);
  }

  String _stripTrailingOptionalFollowUpOffer(String content) {
    final paragraphs = content.split(RegExp(r'\n\s*\n'));
    if (paragraphs.length < 2) {
      return content;
    }
    final trailing = paragraphs.last.trim();
    if (trailing.isEmpty) {
      return content;
    }
    if (!_containsOptionalFollowUpOffer(trailing.toLowerCase())) {
      return content;
    }
    final prefix = content.substring(0, content.lastIndexOf(paragraphs.last));
    return prefix.trimRight();
  }

  bool _shouldAcceptTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    final candidate = response.trim();
    if (candidate.isEmpty || candidate.length > 3000) {
      return false;
    }
    if (!_hasSuccessfulLoadSkillResult(toolResults)) {
      return false;
    }
    if (_looksLikeStructuredToolRequest(candidate)) {
      return false;
    }
    if (_looksLikePlanOnlyFinalToolAnswer(candidate) &&
        !_matchesLoadedSkillExplicitMarker(
          response: candidate,
          toolResults: toolResults,
        )) {
      return false;
    }
    return true;
  }

  bool _shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
    String response,
    List<ToolResultInfo> toolResults,
    List<ToolCallInfo> followUpToolCalls,
  ) {
    if (!_shouldAcceptTerminalSkillToolRoleResponse(response, toolResults) ||
        !_matchesLoadedSkillExplicitMarker(
          response: response,
          toolResults: toolResults,
        )) {
      return false;
    }
    if (followUpToolCalls.isEmpty) {
      return true;
    }
    return !_looksLikeSkillContinuationWorkIntent(response);
  }

  bool _looksLikeSkillContinuationWorkIntent(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }
    if (_looksLikePendingToolActionResponse(candidate) ||
        _looksLikeSkillContinuationIntent(candidate)) {
      return true;
    }
    return _stripTrailingSkillContinuationIntent(candidate).trim() != candidate;
  }

  String _normalizeTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    var candidate = response.trim();
    if (!_hasSuccessfulLoadSkillResult(toolResults)) {
      return candidate;
    }
    candidate = _stripTrailingOptionalSkillFollowUp(candidate);
    candidate = _stripTrailingSkillContinuationIntent(candidate);
    return candidate.trim();
  }

  String _stripTrailingOptionalSkillFollowUp(String content) {
    final dividerMatches = RegExp(
      r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$',
      multiLine: true,
    ).allMatches(content).toList(growable: false);
    if (dividerMatches.isNotEmpty) {
      final lastDivider = dividerMatches.last;
      final trailing = content.substring(lastDivider.end).trim();
      if (_looksLikeOptionalSkillFollowUp(trailing)) {
        return content.substring(0, lastDivider.start).trimRight();
      }
    }

    final paragraphs = content.split(RegExp(r'\n\s*\n'));
    if (paragraphs.length < 2) {
      return content;
    }
    final trailing = paragraphs.last.trim();
    if (!_looksLikeOptionalSkillFollowUp(trailing)) {
      return content;
    }
    final prefix = content.substring(0, content.lastIndexOf(paragraphs.last));
    return prefix.trimRight();
  }

  bool _looksLikeOptionalSkillFollowUp(String content) {
    final candidate = content.trim();
    if (candidate.isEmpty || candidate.length > 500) {
      return false;
    }
    if (candidate.split(RegExp(r'\n\s*\n')).length > 1) {
      return false;
    }

    final normalized = candidate.toLowerCase();
    final hasQuestion =
        normalized.contains('?') ||
        candidate.contains(String.fromCharCode(0xff1f));
    if (!hasQuestion) {
      return false;
    }

    if (_containsAny(normalized, const [
      'would you like me',
      'do you want me',
      'should i',
      'shall i',
      'can i proceed',
      'i can proceed',
      'proceed with',
      'execute these',
      'run these',
      'run the checks',
      'continue with',
      'current project',
      'project directory',
      'repository',
    ])) {
      return true;
    }

    return _containsCjkOptionalSkillFollowUpMarker(candidate);
  }

  String _stripTrailingSkillContinuationIntent(String content) {
    final dividerMatches = RegExp(
      r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$',
      multiLine: true,
    ).allMatches(content).toList(growable: false);
    if (dividerMatches.isNotEmpty) {
      final lastDivider = dividerMatches.last;
      final trailing = content.substring(lastDivider.end).trim();
      if (_looksLikeSkillContinuationIntent(trailing)) {
        return content.substring(0, lastDivider.start).trimRight();
      }
    }

    final paragraphs = content.split(RegExp(r'\n\s*\n'));
    if (paragraphs.length < 2) {
      return content;
    }
    final trailing = paragraphs.last.trim();
    if (!_looksLikeSkillContinuationIntent(trailing)) {
      return content;
    }
    final prefix = content.substring(0, content.lastIndexOf(paragraphs.last));
    return prefix.trimRight();
  }

  bool _looksLikeSkillContinuationIntent(String content) {
    final candidate = content.trim();
    if (candidate.isEmpty || candidate.length > 500) {
      return false;
    }
    if (candidate.split(RegExp(r'\n\s*\n')).length > 1) {
      return false;
    }

    final normalized = candidate.toLowerCase();
    if (_containsAny(normalized, const [
      'first, i will',
      'first i will',
      'next, i will',
      'now i will',
      'i will now',
      'i will inspect',
      'i will check',
      'i will run',
      'i will execute',
      'i will retrieve',
      'i will get',
      "i'll inspect",
      "i'll check",
      "i'll run",
      'let me inspect',
      'let me check',
      'let me run',
      'let me verify',
      'i am going to',
      "i'm going to",
      'start by checking',
      'begin by checking',
    ])) {
      return true;
    }

    return _containsCjkSkillContinuationIntentMarker(candidate);
  }

  bool _containsCjkSkillContinuationIntentMarker(String value) {
    if (_containsCjkDirectContinuationActionMarker(value)) {
      return true;
    }

    final startMarkers = [
      String.fromCharCodes([0x307e, 0x305a]),
      String.fromCharCodes([0x6b21, 0x306b]),
      String.fromCharCodes([0x3053, 0x308c, 0x304b, 0x3089]),
      String.fromCharCodes([0x5b9f, 0x969b, 0x306b]),
      String.fromCharCodes([0x73fe, 0x5728, 0x306e]),
      String.fromCharCodes([0x958b, 0x59cb]),
    ];
    final actionMarkers = [
      String.fromCharCodes([0x898b, 0x3066]),
      String.fromCharCodes([0x898b, 0x307e, 0x3059]),
      String.fromCharCodes([0x898b, 0x307e, 0x3057, 0x3087, 0x3046]),
      String.fromCharCodes([0x9032, 0x3081]),
      String.fromCharCodes([0x78ba, 0x8a8d]),
      String.fromCharCodes([0x53d6, 0x5f97]),
      String.fromCharCodes([0x5b9f, 0x884c]),
      String.fromCharCodes([0x691c, 0x8a3c]),
    ];
    return startMarkers.any(value.contains) &&
        actionMarkers.any(value.contains);
  }

  bool _containsCjkDirectContinuationActionMarker(String value) {
    final directActionMarkers = [
      String.fromCharCodes([0x63a2, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x691c, 0x7d22, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x8abf, 0x3079, 0x307e, 0x3059]),
    ];
    return directActionMarkers.any(value.contains);
  }

  bool _containsCjkOptionalSkillFollowUpMarker(String value) {
    final executionMarkers = [
      String.fromCharCodes([0x5b9f, 0x884c]),
      String.fromCharCodes([0x9032, 0x3081]),
    ];
    final permissionMarkers = [
      String.fromCharCodes([0x3088, 0x308d, 0x3057, 0x3044]),
      String.fromCharCodes([0x3067, 0x3057, 0x3087, 0x3046, 0x304b]),
      String.fromCharCodes([0x3057, 0x307e, 0x3059, 0x304b]),
      String.fromCharCodes([0x304f, 0x3060, 0x3055, 0x3044]),
    ];
    return executionMarkers.any(value.contains) &&
        permissionMarkers.any(value.contains);
  }

  bool _hasSuccessfulLoadSkillResult(List<ToolResultInfo> toolResults) {
    return toolResults.any(
      (toolResult) =>
          toolResult.name.trim().toLowerCase() == 'load_skill' &&
          _toolResultLooksSuccessfulForFinalAnswer(toolResult.result),
    );
  }

  bool _toolResultLooksSuccessfulForFinalAnswer(String result) {
    final trimmed = result.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('error:')) {
      return false;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<Object?, Object?>) {
        final keys = decoded.keys
            .whereType<String>()
            .map((key) => key.toLowerCase())
            .toSet();
        if (keys.contains('error')) {
          return false;
        }
        Object? codeValue;
        for (final entry in decoded.entries) {
          final key = entry.key;
          if (key is String && key.toLowerCase() == 'code') {
            codeValue = entry.value;
            break;
          }
        }
        final code = codeValue?.toString().toLowerCase();
        if (code != null &&
            (code.contains('denied') ||
                code.contains('failure') ||
                code.contains('failed') ||
                code.contains('not_executed'))) {
          return false;
        }
      }
    } on FormatException {
      return true;
    }
    return true;
  }

  bool _matchesLoadedSkillExplicitMarker({
    required String response,
    required List<ToolResultInfo> toolResults,
  }) {
    final responseMarkers = RegExp(
      r'\b[A-Z][A-Z0-9_]{5,}\b',
    ).allMatches(response).map((match) => match.group(0)).nonNulls.toSet();
    if (responseMarkers.isEmpty) {
      return false;
    }
    for (final toolResult in toolResults) {
      if (toolResult.name.trim().toLowerCase() != 'load_skill') {
        continue;
      }
      for (final marker in responseMarkers) {
        if (toolResult.result.contains(marker)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _shouldAcceptTerminalToolRoleBlockerResponse(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty || candidate.length > 3000) {
      return false;
    }
    if (_looksLikeUnexecutedToolRequest(candidate) ||
        _looksLikePlanOnlyFinalToolAnswer(candidate)) {
      return false;
    }

    final normalized = candidate.toLowerCase();
    final hasBlockerMarker = _containsAny(normalized, const [
      'blocked',
      'blocker',
      'cannot continue',
      "can't continue",
      'unable to continue',
      'required before',
      'is required',
      'are required',
      'not available',
      'not present',
      'missing',
      'does not exist',
      'permission denied',
      'access denied',
      'need access',
      'need the source',
      'need the repository',
      'need the path',
      'need the file',
      'need the logs',
      'please provide',
    ]);
    final hasMissingEvidenceMarker = _containsAny(normalized, const [
      'source code',
      'repository',
      'repo',
      'path',
      'file',
      'logs',
      'runtime data',
      'permission',
      'access',
      'credentials',
      'external dependency',
      'external package',
      'implementation',
    ]);
    final hasFailureReportMarker = _containsAny(normalized, const [
      'failed',
      'failure',
      'exited with',
      'exit code',
      'non-zero',
      'nonzero',
      'error:',
    ]);
    final hasCjkBlockerMarker = _containsCjkBlockerMarker(candidate);
    final hasCjkMissingEvidenceMarker = _containsCjkMissingEvidenceMarker(
      candidate,
    );
    final hasCjkFailureReportMarker = _containsAnyCodeUnitSequence(
      candidate,
      const [
        [0x5931, 0x6557],
        [0x30a8, 0x30e9, 0x30fc],
        [0x7570, 0x5e38, 0x7d42, 0x4e86],
      ],
    );
    return (hasBlockerMarker && hasMissingEvidenceMarker) ||
        hasFailureReportMarker ||
        (hasCjkBlockerMarker && hasCjkMissingEvidenceMarker) ||
        hasCjkFailureReportMarker;
  }
}
