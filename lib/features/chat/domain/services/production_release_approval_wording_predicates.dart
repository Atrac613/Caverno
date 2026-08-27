import 'dart:convert';

import '../entities/mcp_tool_entity.dart';

/// Retired wording-based release verdict, kept only for shadow comparison.
///
/// Nothing here may grant a release. Every verdict below is bound to the
/// languages somebody enumerated: it reads "never release this" and "nao
/// execute o release" as approvals, and refuses genuine approvals in German
/// and Chinese. Approval is decided by the issued token instead -- see
/// `ProductionReleaseApprovalPolicy.answerApprovesToken`.
///
/// It lives apart from the policy so the live token verdict is not read
/// alongside 170 lines of vocabulary, and so deleting the shadow is a file
/// removal rather than a surgical edit.
final class ProductionReleaseApprovalWordingPredicates {
  const ProductionReleaseApprovalWordingPredicates();

  bool answerApproves(McpToolResult answerResult) {
    if (!answerResult.isSuccess) return false;
    final decoded = _decodeJsonObject(answerResult.result);
    if (decoded == null || decoded['status'] != 'answered') return false;

    var questionText = '';
    final answerEvidence = <String>[];
    void addEvidence(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        answerEvidence.add(value.trim());
      }
    }

    final questionValue = decoded['question'];
    if (questionValue is String && questionValue.trim().isNotEmpty) {
      questionText = questionValue.trim();
    }
    addEvidence(decoded['answer']);
    addEvidence(decoded['other']);
    final selected = decoded['selected'];
    if (selected is List) {
      for (final option in selected) {
        if (option is Map) {
          addEvidence(option['label']);
          addEvidence(option['description']);
          addEvidence(option['preview']);
        } else {
          addEvidence(option);
        }
      }
    }

    if (answerEvidence.isEmpty) return false;
    if (answerEvidence.any(looksLikeExplicitProductionReleaseApproval)) {
      return true;
    }
    if (!looksLikeExplicitProductionReleaseApproval(questionText)) {
      return false;
    }
    return answerEvidence.any(looksLikeAffirmativeReleaseApprovalAnswer);
  }

  bool looksLikeExplicitProductionReleaseApproval(String content) {
    final lowerContent = content.toLowerCase();
    if (RegExp(r'^\s*(release|ship)\b').hasMatch(lowerContent)) return true;
    if (!mentionsProductionRelease(content)) return false;
    return _containsAny(lowerContent, const [
          'run',
          'execute',
          'start',
          'publish',
          'upload',
          'ship',
          'production',
          'prod',
          'go ahead',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x5b9f, 0x884c],
          [0x9032, 0x3081],
          [0x516c, 0x958b],
          [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9],
          [0x672c, 0x756a],
          [0x3057, 0x3066],
          [0x304a, 0x9858, 0x3044],
          [0x3084, 0x3063, 0x3066],
        ]);
  }

  bool looksLikeProductionReleaseApprovalPrompt(String content) {
    if (!mentionsProductionRelease(content)) return false;
    final lowerContent = content.toLowerCase();
    final asksForApproval =
        _containsAny(lowerContent, const [
          'approve',
          'approval',
          'confirm',
          'permission',
          'authorize',
          'run',
          'execute',
          'proceed',
        ]) ||
        content.contains('?') ||
        content.contains(String.fromCharCode(0xff1f)) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x627f, 0x8a8d],
          [0x8a31, 0x53ef],
          [0x5b9f, 0x884c],
          [0x9032, 0x3081],
          [0x3057, 0x307e, 0x3059, 0x304b],
        ]);
    if (!asksForApproval) return false;
    return _containsAny(lowerContent, const [
          'production',
          'prod',
          'command',
          'release',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x672c, 0x756a],
          [0x30b3, 0x30de, 0x30f3, 0x30c9],
          [0x30ea, 0x30ea, 0x30fc, 0x30b9],
        ]);
  }

  bool mentionsProductionRelease(String content) {
    final lowerContent = content.toLowerCase();
    return _containsAny(lowerContent, const [
          'release',
          'publish',
          'upload',
          'app store connect',
          'sparkle',
          's3',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x30ea, 0x30ea, 0x30fc, 0x30b9],
          [0x672c, 0x756a],
          [0x516c, 0x958b],
          [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9],
        ]);
  }

  bool looksLikeAffirmativeReleaseApprovalAnswer(String content) {
    final lowerContent = content.toLowerCase();
    if (_containsAny(lowerContent, const [
      'do not',
      "don't",
      'dont',
      'no',
      'cancel',
      'decline',
      'deny',
      'reject',
      'skip',
      'stop',
      'block',
      'not release',
      'not now',
    ])) {
      return false;
    }
    return _containsAny(lowerContent, const [
          'approve',
          'approved',
          'yes',
          'go ahead',
          'proceed',
          'run',
          'execute',
          'release',
          'ship',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x627f, 0x8a8d],
          [0x306f, 0x3044],
          [0x9032, 0x3081],
          [0x5b9f, 0x884c],
          [0x516c, 0x958b],
          [0x672c, 0x756a],
          [0x304a, 0x9858, 0x3044],
          [0x3084, 0x3063, 0x3066],
        ]);
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) {
    return sequences.any(
      (sequence) => text.contains(String.fromCharCodes(sequence)),
    );
  }

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
