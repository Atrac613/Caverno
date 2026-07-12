import 'dart:convert';
import 'dart:io';

import '../entities/tool_call_info.dart';
import 'file_reference_extractor.dart';

class UnwrittenFileClaim {
  const UnwrittenFileClaim({
    required this.displayPath,
    required this.absolutePath,
    required this.exists,
  });

  final String displayPath;
  final String absolutePath;
  final bool exists;
}

class UnwrittenFileClaimAssessment {
  const UnwrittenFileClaimAssessment({required this.claims});

  final List<UnwrittenFileClaim> claims;

  bool get hasClaims => claims.isNotEmpty;

  String buildNotice() {
    final details = claims
        .map((claim) {
          final path = '`${claim.displayPath}`';
          if (!claim.exists) {
            return '$path was listed as created or updated but does not exist.';
          }
          return '$path was listed as created or updated but was not modified '
              'in this turn.';
        })
        .join(' ');
    return 'Deliverable claim check: $details';
  }
}

class UnwrittenFileClaimGuard {
  const UnwrittenFileClaimGuard();

  static final RegExp _completedEnglishMutation = RegExp(
    r'\b(?:created|added|updated|wrote|written)\b',
    caseSensitive: false,
  );
  static final RegExp _futureOrNegativeEnglishMutation = RegExp(
    r"\b(?:will|would|should|could|can|may|might|to|not|never|"
    r"didn['’]?t|wasn['’]?t|weren['’]?t|haven['’]?t|"
    r"hasn['’]?t)\s+(?:be\s+)?(?:create(?:d)?|add(?:ed)?|"
    r'update(?:d)?|write|written)\b',
    caseSensitive: false,
  );
  static final RegExp _planningEnglishMutation = RegExp(
    r'\b(?:plan|planning|intend|intending|going)\s+to\s+'
    r'(?:create|add|update|write)\b',
    caseSensitive: false,
  );
  static final RegExp _completedJapaneseMutation = RegExp(
    r'(?:\u65b0\u898f)?\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0',
    unicode: true,
  );
  static final RegExp _futureOrNegativeJapaneseMutation = RegExp(
    r'(?:\u672a\u4f5c\u6210|'
    r'(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)'
    r'(?:\u3057\u307e\u3059|\u3059\u308b|\u4e88\u5b9a|\u3057\u306a\u3044)|'
    r'(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)'
    r'(?:\u306f|\u304c|\u3092)?'
    r'(?:\u4e0d\u8981|\u5fc5\u8981(?:\u306f|\u304c)?\u306a\u3044))',
    unicode: true,
  );
  static final RegExp _completedEnglishMutationBeforePath = RegExp(
    r'\b(?:created|added|updated|wrote|written)\b'
    r'(?:\s+(?:(?:the|a|an)\s+)?(?:new\s+|existing\s+)?'
    r'files?(?:\s+at)?)?'
    r'\s*(?:[:\u2013\u2014-]\s*)?[`*_~\[(]*\s*$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _completedEnglishMutationAfterPath = RegExp(
    r'^(?::\d{1,7}(?::\d{1,7})?)?\s*[`*_~\]\}]*\s*'
    r'(?:'
    r'(?:(?:was|were)|(?:has|have)\s+been|(?:is|are)\s+now)\s+'
    r'(?:(?:successfully|newly)\s+)*(?:created|added|updated|written)\b|'
    r'[(:\u2013\u2014-]\s*(?:(?:successfully|newly)\s+)*'
    r'(?:created|added|updated|written)\b'
    r'(?=\s*(?:[\]),.;:]|$))'
    r')',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _completedJapaneseMutationBeforePath = RegExp(
    r'(?:\u65b0\u898f)?(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)'
    r'(?:\u6e08\u307f)?\s*[:\uff1a\u2013\u2014-]\s*'
    r'[`*_~\[(]*\s*$',
    unicode: true,
  );
  static final RegExp _completedJapaneseMutationAfterPath = RegExp(
    r'^(?::\d{1,7}(?::\d{1,7})?)?\s*[`*_~\]\}]*\s*'
    r'(?:'
    r'\u3092\s*(?:\u65b0\u898f)?'
    r'(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)'
    r'(?:\u3057\u307e\u3057\u305f|\u3057\u305f|\u6e08\u307f(?:\u3067\u3059)?)|'
    r'\u306f\s*(?:\u65b0\u898f)?'
    r'(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)'
    r'(?:\u3057\u307e\u3057\u305f|\u6e08\u307f(?:\u3067\u3059)?)|'
    r'[\uff08(:\uff1a\u2013\u2014-]\s*(?:\u65b0\u898f)?'
    r'(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)'
    r'(?:\u6e08\u307f)?(?=\s*(?:[\uff09\]),.;\u3002]|$))'
    r')',
    unicode: true,
  );
  static final RegExp _completedMutationListBeforePaths = RegExp(
    r'^\s*(?:(?:[-*+]|\d+[.)])\s+)?'
    r'(?:'
    r'(?:files?\s+)?(?:created|added|updated|wrote|written)'
    r'(?:\s+files?)?|'
    r'(?:\u65b0\u898f)?(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)'
    r'(?:\u6e08\u307f)?'
    r')\s*[:\uff1a\u2013\u2014-]\s*'
    r'[`*_~\[(]*<file-ref>(?::\d{1,7}(?::\d{1,7})?)?'
    r'[`*_~\]\)]*'
    r'(?:\s*(?:,|;|&|\band\b|\u3001|\u3068)\s*'
    r'[`*_~\[(]*<file-ref>(?::\d{1,7}(?::\d{1,7})?)?'
    r'[`*_~\]\)]*)+'
    r'\s*[.!;\u3002]?\s*$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _completedMutationListAfterPaths = RegExp(
    r'^\s*(?:(?:[-*+]|\d+[.)])\s+)?'
    r'[`*_~\[(]*<file-ref>(?::\d{1,7}(?::\d{1,7})?)?'
    r'[`*_~\]\)]*'
    r'(?:\s*(?:,|;|&|\band\b|\u3001|\u3068)\s*'
    r'[`*_~\[(]*<file-ref>(?::\d{1,7}(?::\d{1,7})?)?'
    r'[`*_~\]\)]*)+'
    r'\s*(?:'
    r'(?:(?:was|were)|(?:has|have)\s+been)\s+'
    r'(?:(?:successfully|newly)\s+)*(?:created|added|updated|written)\b|'
    r'(?:\u3092|\u306f)\s*(?:\u65b0\u898f)?'
    r'(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)'
    r'(?:\u3057\u307e\u3057\u305f|\u3057\u305f|\u6e08\u307f(?:\u3067\u3059)?)'
    r')\s*[.!\u3002]?\s*$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _completedMutationTableHeading = RegExp(
    r'(?:files?\s+(?:created|added|updated|written)|'
    r'(?:created|added|updated|written)\s+files?|'
    r'(?:\u4f5c\u6210|\u66f4\u65b0|\u8ffd\u52a0)(?:\u3057\u305f)?\u30d5\u30a1\u30a4\u30eb)',
    caseSensitive: false,
    unicode: true,
  );

  UnwrittenFileClaimAssessment assess({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required String projectRoot,
    bool Function(String path)? pathExists,
  }) {
    final normalizedRoot = _normalizeAbsolutePath(projectRoot);
    if (candidateResponse.trim().isEmpty || normalizedRoot == null) {
      return const UnwrittenFileClaimAssessment(claims: []);
    }

    final successfullyMutatedPaths = _successfulMutationPaths(
      toolResults,
      normalizedRoot,
    );
    final claimedPaths = <String, String>{};
    var insideFence = false;
    var insideMutationTable = false;
    var mutationTableStarted = false;
    for (final line in candidateResponse.split('\n')) {
      if (line.trimLeft().startsWith('```')) {
        insideFence = !insideFence;
        continue;
      }
      if (insideFence) {
        continue;
      }
      final trimmedLine = line.trim();
      if (_completedMutationTableHeading.hasMatch(trimmedLine)) {
        insideMutationTable = true;
        mutationTableStarted = false;
        continue;
      }
      final isTableRow = trimmedLine.startsWith('|');
      if (insideMutationTable) {
        if (isTableRow) {
          mutationTableStarted = true;
          for (final reference in FileReferenceExtractor.extract(line)) {
            final absolutePath = _resolveInsideRoot(
              reference.path,
              normalizedRoot,
            );
            if (absolutePath != null) {
              claimedPaths.putIfAbsent(absolutePath, () => reference.path);
            }
          }
          continue;
        }
        if (trimmedLine.isEmpty && !mutationTableStarted) {
          continue;
        }
        insideMutationTable = false;
      }
      if (!_looksLikeCompletedMutationClaim(line)) {
        continue;
      }
      final references = FileReferenceExtractor.extract(line);
      final hasMutationListClaim = _hasCompletedMutationListClaim(
        line,
        references,
      );
      for (final reference in references) {
        if (!hasMutationListClaim &&
            !_hasCompletedMutationClaimForPath(line, reference.path)) {
          continue;
        }
        final absolutePath = _resolveInsideRoot(reference.path, normalizedRoot);
        if (absolutePath != null) {
          claimedPaths.putIfAbsent(absolutePath, () => reference.path);
        }
      }
    }

    final exists = pathExists ?? (path) => File(path).existsSync();
    final claims = <UnwrittenFileClaim>[];
    for (final entry in claimedPaths.entries) {
      if (successfullyMutatedPaths.contains(entry.key)) {
        continue;
      }
      final pathExistsNow = exists(entry.key);
      if (pathExistsNow) {
        continue;
      }
      claims.add(
        UnwrittenFileClaim(
          displayPath: entry.value,
          absolutePath: entry.key,
          exists: pathExistsNow,
        ),
      );
    }
    return UnwrittenFileClaimAssessment(
      claims: List<UnwrittenFileClaim>.unmodifiable(claims),
    );
  }

  bool _looksLikeCompletedMutationClaim(String line) {
    if (_futureOrNegativeEnglishMutation.hasMatch(line) ||
        _planningEnglishMutation.hasMatch(line) ||
        _futureOrNegativeJapaneseMutation.hasMatch(line)) {
      return false;
    }
    return _completedEnglishMutation.hasMatch(line) ||
        _completedJapaneseMutation.hasMatch(line);
  }

  bool _hasCompletedMutationClaimForPath(String line, String path) {
    final normalizedLine = line.toLowerCase();
    final normalizedPath = path.toLowerCase();
    var searchStart = 0;
    while (searchStart < normalizedLine.length) {
      final pathStart = normalizedLine.indexOf(normalizedPath, searchStart);
      if (pathStart < 0) {
        return false;
      }
      final pathEnd = pathStart + path.length;
      final beforePath = line.substring(0, pathStart);
      final afterPath = line.substring(pathEnd);
      if (_completedEnglishMutationBeforePath.hasMatch(beforePath) ||
          _completedEnglishMutationAfterPath.hasMatch(afterPath) ||
          _completedJapaneseMutationBeforePath.hasMatch(beforePath) ||
          _completedJapaneseMutationAfterPath.hasMatch(afterPath)) {
        return true;
      }
      searchStart = pathEnd;
    }
    return false;
  }

  bool _hasCompletedMutationListClaim(
    String line,
    List<FileReference> references,
  ) {
    if (references.length < 2) {
      return false;
    }
    var maskedLine = line;
    final paths = references.map((reference) => reference.path).toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final path in paths) {
      maskedLine = maskedLine.replaceAll(
        RegExp(RegExp.escape(path), caseSensitive: false),
        '<file-ref>',
      );
    }
    return _completedMutationListBeforePaths.hasMatch(maskedLine) ||
        _completedMutationListAfterPaths.hasMatch(maskedLine);
  }

  Set<String> _successfulMutationPaths(
    List<ToolResultInfo> toolResults,
    String normalizedRoot,
  ) {
    final paths = <String>{};
    for (final toolResult in toolResults) {
      if (!_isMutationTool(toolResult.name) ||
          !_isSuccessfulResult(toolResult.result)) {
        continue;
      }
      try {
        final decoded = jsonDecode(toolResult.result);
        if (decoded is! Map<Object?, Object?>) {
          continue;
        }
        final rawPath = decoded['path']?.toString().trim();
        if (rawPath == null || rawPath.isEmpty) {
          continue;
        }
        final path = _resolveInsideRoot(rawPath, normalizedRoot);
        if (path != null) {
          paths.add(path);
        }
      } catch (_) {
        continue;
      }
    }
    return paths;
  }

  bool _isMutationTool(String name) {
    switch (name.trim().toLowerCase()) {
      case 'write_file':
      case 'edit_file':
      case 'delete_file':
      case 'rollback_last_file_change':
        return true;
    }
    return false;
  }

  bool _isSuccessfulResult(String result) {
    final normalized = result.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.startsWith('error:') ||
        normalized.startsWith('auto-review denied')) {
      return false;
    }
    try {
      final decoded = jsonDecode(result);
      if (decoded is! Map<Object?, Object?>) {
        return true;
      }
      if (decoded['error'] != null || decoded['ok'] == false) {
        return false;
      }
      final code = decoded['code']?.toString().trim().toLowerCase();
      return code != 'permission_denied' &&
          code != 'bookmark_restore_failed' &&
          code != 'tool_execution_failed';
    } catch (_) {
      return true;
    }
  }

  String? _resolveInsideRoot(String path, String normalizedRoot) {
    final candidate = _normalizeAbsolutePath(
      _isAbsolutePath(path) ? path : '$normalizedRoot/$path',
    );
    if (candidate == null ||
        (candidate != normalizedRoot &&
            !candidate.startsWith('$normalizedRoot/'))) {
      return null;
    }
    return candidate;
  }

  String? _normalizeAbsolutePath(String path) {
    final normalizedSeparators = path.trim().replaceAll('\\', '/');
    if (!_isAbsolutePath(normalizedSeparators)) {
      return null;
    }
    final prefix = normalizedSeparators.startsWith('/')
        ? '/'
        : normalizedSeparators.substring(0, 3);
    final remainder = normalizedSeparators.substring(prefix.length);
    final segments = <String>[];
    for (final segment in remainder.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isEmpty) {
          return null;
        }
        segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    final suffix = segments.join('/');
    return suffix.isEmpty ? prefix : '$prefix$suffix';
  }

  bool _isAbsolutePath(String path) {
    return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }
}
