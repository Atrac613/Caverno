import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_verification_evidence_contract.dart';

class CodingVerificationClaimMismatch {
  const CodingVerificationClaimMismatch({
    required this.claimedPassedCount,
    required this.actualPassedCount,
    required this.actualFailedCount,
    required this.actualSkippedCount,
    this.claimedTotalCount,
    this.command,
  });

  final int claimedPassedCount;
  final int? claimedTotalCount;
  final int actualPassedCount;
  final int actualFailedCount;
  final int actualSkippedCount;
  final String? command;

  int get actualTotalCount =>
      actualPassedCount + actualFailedCount + actualSkippedCount;
}

class CodingVerificationClaimAssessment {
  const CodingVerificationClaimAssessment({this.mismatch});

  final CodingVerificationClaimMismatch? mismatch;

  bool get hasMismatch => mismatch != null;

  String buildNotice() {
    final value = mismatch;
    if (value == null) {
      return '';
    }
    final claimed = value.claimedTotalCount == null
        ? '${value.claimedPassedCount} passing tests'
        : '${value.claimedPassedCount}/${value.claimedTotalCount} passing tests';
    final commandSuffix = value.command == null
        ? ''
        : ' The recorded command was `${value.command}`.';
    return 'Verification claim check: The response reports $claimed, but '
        'the recorded verification observed ${value.actualPassedCount} passed, '
        '${value.actualFailedCount} failed, and ${value.actualSkippedCount} '
        'skipped test(s).$commandSuffix';
  }
}

class CodingVerificationClaimGuard {
  const CodingVerificationClaimGuard();

  static final RegExp _fractionClaim = RegExp(
    r'(?<!\d)(\d{1,7})\s*/\s*(\d{1,7})(?!\d)',
    unicode: true,
  );
  static final RegExp _passedCountBeforeStatus = RegExp(
    r'(?<!\d)(\d{1,7})\s*'
    r'(?:(?:tests?|test cases?|cases?|\u4ef6)\s*)?'
    r'(?:(?:all|every|\u5168\u3066|\u3059\u3079\u3066|'
    r'\u5168\u90e8)\s*)?'
    r'(?:passed|passing|successful|succeeded|success|'
    r'\u6210\u529f|\u5408\u683c|\u30d1\u30b9(?!\u30ef\u30fc\u30c9))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _passedCountAfterStatus = RegExp(
    r'(?:passed|passing|successful|succeeded|success|'
    r'\u6210\u529f|\u5408\u683c|\u30d1\u30b9(?!\u30ef\u30fc\u30c9))'
    r'\s*(?:tests?|test cases?|cases?|\u4ef6)?\s*[:=\uff1a]?\s*'
    r'(?<!\d)(\d{1,7})(?!\d)',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _verificationContext = RegExp(
    r'(?:tests?|test cases?|dart\s+test|flutter\s+test|'
    r'passed|passing|successful|succeeded|success|'
    r'\u30c6\u30b9\u30c8|\u6210\u529f|\u5408\u683c|'
    r'\u30d1\u30b9(?!\u30ef\u30fc\u30c9))',
    caseSensitive: false,
    unicode: true,
  );

  CodingVerificationClaimAssessment assess({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final evidence = _latestEvidence(toolResults);
    if (evidence == null || candidateResponse.trim().isEmpty) {
      return const CodingVerificationClaimAssessment();
    }
    final claim = _firstCountClaim(candidateResponse);
    if (claim == null) {
      return const CodingVerificationClaimAssessment();
    }
    final actualTotal =
        evidence.passedCount + evidence.failedCount + evidence.skippedCount;
    final countMatches = claim.passedCount == evidence.passedCount;
    final totalMatches =
        claim.totalCount == null || claim.totalCount == actualTotal;
    if (countMatches && totalMatches) {
      return const CodingVerificationClaimAssessment();
    }
    return CodingVerificationClaimAssessment(
      mismatch: CodingVerificationClaimMismatch(
        claimedPassedCount: claim.passedCount,
        claimedTotalCount: claim.totalCount,
        actualPassedCount: evidence.passedCount,
        actualFailedCount: evidence.failedCount,
        actualSkippedCount: evidence.skippedCount,
        command: evidence.command,
      ),
    );
  }

  _VerificationCountClaim? _firstCountClaim(String response) {
    var insideFence = false;
    for (final line in response.split('\n')) {
      if (line.trimLeft().startsWith('```')) {
        insideFence = !insideFence;
        continue;
      }
      if (insideFence) {
        continue;
      }
      for (final match in _fractionClaim.allMatches(line)) {
        final contextStart = match.start > 80 ? match.start - 80 : 0;
        final contextEnd = match.end + 80 < line.length
            ? match.end + 80
            : line.length;
        if (!_verificationContext.hasMatch(
          line.substring(contextStart, contextEnd),
        )) {
          continue;
        }
        return _VerificationCountClaim(
          passedCount: int.parse(match.group(1)!),
          totalCount: int.parse(match.group(2)!),
        );
      }
      final before = _passedCountBeforeStatus.firstMatch(line);
      if (before != null) {
        return _VerificationCountClaim(
          passedCount: int.parse(before.group(1)!),
        );
      }
      final after = _passedCountAfterStatus.firstMatch(line);
      if (after != null) {
        return _VerificationCountClaim(passedCount: int.parse(after.group(1)!));
      }
    }
    return null;
  }

  _VerificationEvidence? _latestEvidence(List<ToolResultInfo> toolResults) {
    for (final toolResult in toolResults.reversed) {
      if (toolResult.name !=
          CodingVerificationEvidenceContract.toolName) {
        continue;
      }
      try {
        final payload = jsonDecode(toolResult.result);
        if (payload is! Map<Object?, Object?> ||
            payload['schema'] !=
                CodingVerificationEvidenceContract.schemaName) {
          continue;
        }
        final counts = payload['counts'];
        if (counts is! Map<Object?, Object?>) {
          continue;
        }
        final passed = _nonNegativeInt(counts['passed']);
        final failed = _nonNegativeInt(counts['failed']);
        final skipped = _nonNegativeInt(counts['skipped']);
        if (passed == null || failed == null || skipped == null) {
          continue;
        }
        return _VerificationEvidence(
          passedCount: passed,
          failedCount: failed,
          skippedCount: skipped,
          command: _commandFromPayload(payload),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  int? _nonNegativeInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    return parsed == null || parsed < 0 ? null : parsed;
  }

  String? _commandFromPayload(Map<Object?, Object?> payload) {
    final verification = payload['verification'];
    if (verification is! Map<Object?, Object?>) {
      return null;
    }
    final executable = verification['executable']?.toString().trim();
    if (executable == null || executable.isEmpty) {
      return null;
    }
    final arguments = verification['arguments'];
    if (arguments is! List<Object?> || arguments.isEmpty) {
      return executable;
    }
    return '$executable ${arguments.map((value) => value.toString()).join(' ')}';
  }
}

class _VerificationCountClaim {
  const _VerificationCountClaim({required this.passedCount, this.totalCount});

  final int passedCount;
  final int? totalCount;
}

class _VerificationEvidence {
  const _VerificationEvidence({
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    this.command,
  });

  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final String? command;
}
