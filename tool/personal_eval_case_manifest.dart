import 'dart:convert';
import 'dart:io';

import 'caverno_session_log_summary.dart';

const _schemaName = 'caverno_personal_eval_case_manifest';
const _schemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = PersonalEvalCaseManifestOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_case_manifest.dart '
      '--log PATH --case-id ID --title TITLE '
      '--prompt TEXT|--prompt-file PATH --repo-state-ref REF '
      '--verification-result passed|failed|inconclusive --consent '
      '[--verification-command COMMAND] [--workspace-mode MODE] [--out PATH]',
    );
    exitCode = 64;
    return;
  }

  if (!options.consent) {
    stderr.writeln(
      'Explicit --consent is required before recording a personal eval case.',
    );
    exitCode = 64;
    return;
  }

  final logFile = File(options.logPath);
  if (!logFile.existsSync()) {
    stderr.writeln('Session log file not found: ${logFile.path}');
    exitCode = 66;
    return;
  }

  final prompt = await options.resolvePrompt();
  final manifest = await buildPersonalEvalCaseManifest(
    logFile: logFile,
    caseId: options.caseId,
    title: options.title,
    prompt: prompt,
    repoStateRef: options.repoStateRef,
    verificationCommand: options.verificationCommand,
    verificationResult: options.verificationResult,
    workspaceMode: options.workspaceMode,
    consent: options.consent,
  );
  final output = const JsonEncoder.withIndent('  ').convert(manifest.toJson());
  final outPath = options.outPath;
  if (outPath == null) {
    stdout.writeln(output);
    return;
  }
  final outFile = File(outPath);
  await outFile.parent.create(recursive: true);
  await outFile.writeAsString('$output\n');
  stdout.writeln('Personal eval case manifest written to ${outFile.path}');
}

Future<PersonalEvalCaseManifest> buildPersonalEvalCaseManifest({
  required File logFile,
  required String caseId,
  required String title,
  required String prompt,
  required String repoStateRef,
  required PersonalEvalVerificationResult verificationResult,
  required bool consent,
  String? verificationCommand,
  String? workspaceMode,
  DateTime? generatedAt,
}) async {
  final normalizedCaseId = caseId.trim();
  final normalizedTitle = title.trim();
  final normalizedPrompt = prompt.trim();
  final normalizedRepoStateRef = repoStateRef.trim();
  if (normalizedCaseId.isEmpty || !_safeIdPattern.hasMatch(normalizedCaseId)) {
    throw ArgumentError.value(
      caseId,
      'caseId',
      'Use only letters, numbers, dots, underscores, and hyphens.',
    );
  }
  if (normalizedTitle.isEmpty) {
    throw ArgumentError.value(title, 'title', 'Title must not be empty.');
  }
  if (normalizedPrompt.isEmpty) {
    throw ArgumentError.value(prompt, 'prompt', 'Prompt must not be empty.');
  }
  if (normalizedRepoStateRef.isEmpty) {
    throw ArgumentError.value(
      repoStateRef,
      'repoStateRef',
      'Repository state reference must not be empty.',
    );
  }
  if (!consent) {
    throw ArgumentError(
      'Explicit user consent is required before recording an eval case.',
    );
  }

  final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
  final readiness = _readinessForSummary(summary);
  if (readiness == PersonalEvalCaseReadiness.blocked) {
    throw StateError(
      'Only completed session logs can seed a personal eval case. '
      'Summary result was `${summary.result}`.',
    );
  }

  return PersonalEvalCaseManifest(
    schemaName: _schemaName,
    schemaVersion: _schemaVersion,
    generatedAt: generatedAt ?? DateTime.now(),
    caseId: normalizedCaseId,
    title: normalizedTitle,
    readiness: readiness,
    task: PersonalEvalTaskSnapshot(
      prompt: normalizedPrompt,
      repoStateRef: normalizedRepoStateRef,
      verificationCommand: _trimToNull(verificationCommand),
      verificationResult: verificationResult,
      workspaceMode: _trimToNull(workspaceMode),
    ),
    source: PersonalEvalSourceSnapshot.fromSummary(summary),
    consent: const PersonalEvalConsentSnapshot(explicitUserConsent: true),
    privacy: const PersonalEvalPrivacySnapshot(),
  );
}

PersonalEvalCaseReadiness _readinessForSummary(
  CavernoLlmSessionLogSummary summary,
) {
  if (summary.hasFatalError || summary.finalAnswer == null) {
    return PersonalEvalCaseReadiness.blocked;
  }
  if (summary.hasWarnings || summary.malformedLineCount > 0) {
    return PersonalEvalCaseReadiness.reviewRecommended;
  }
  return PersonalEvalCaseReadiness.ready;
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final _safeIdPattern = RegExp(r'^[A-Za-z0-9._-]+$');

enum PersonalEvalVerificationResult {
  passed,
  failed,
  inconclusive;

  static PersonalEvalVerificationResult? parse(String value) {
    return switch (value.trim()) {
      'passed' => PersonalEvalVerificationResult.passed,
      'failed' => PersonalEvalVerificationResult.failed,
      'inconclusive' => PersonalEvalVerificationResult.inconclusive,
      _ => null,
    };
  }
}

enum PersonalEvalCaseReadiness {
  ready('ready'),
  reviewRecommended('review_recommended'),
  blocked('blocked');

  const PersonalEvalCaseReadiness(this.jsonValue);

  final String jsonValue;
}

final class PersonalEvalCaseManifestOptions {
  const PersonalEvalCaseManifestOptions({
    required this.logPath,
    required this.caseId,
    required this.title,
    required this.repoStateRef,
    required this.verificationResult,
    required this.consent,
    this.prompt,
    this.promptFilePath,
    this.verificationCommand,
    this.workspaceMode,
    this.outPath,
  });

  final String logPath;
  final String caseId;
  final String title;
  final String? prompt;
  final String? promptFilePath;
  final String repoStateRef;
  final String? verificationCommand;
  final PersonalEvalVerificationResult verificationResult;
  final String? workspaceMode;
  final String? outPath;
  final bool consent;

  Future<String> resolvePrompt() async {
    final inlinePrompt = prompt;
    if (inlinePrompt != null) {
      return inlinePrompt;
    }
    final path = promptFilePath;
    if (path == null) {
      return '';
    }
    return File(path).readAsString();
  }

  static PersonalEvalCaseManifestOptions? parse(List<String> args) {
    String? logPath;
    String? caseId;
    String? title;
    String? prompt;
    String? promptFilePath;
    String? repoStateRef;
    String? verificationCommand;
    PersonalEvalVerificationResult? verificationResult;
    String? workspaceMode;
    String? outPath;
    var consent = false;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--log':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          logPath = value;
        case '--case-id':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          caseId = value;
        case '--title':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          title = value;
        case '--prompt':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          prompt = value;
        case '--prompt-file':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          promptFilePath = value;
        case '--repo-state-ref':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          repoStateRef = value;
        case '--verification-command':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          verificationCommand = value;
        case '--verification-result':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          verificationResult = PersonalEvalVerificationResult.parse(value);
          if (verificationResult == null) return null;
        case '--workspace-mode':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          workspaceMode = value;
        case '--out':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          outPath = value;
        case '--consent':
          consent = true;
        default:
          return null;
      }
    }

    final promptSourceCount =
        (prompt == null ? 0 : 1) + (promptFilePath == null ? 0 : 1);
    if (logPath == null ||
        caseId == null ||
        title == null ||
        promptSourceCount != 1 ||
        repoStateRef == null ||
        verificationResult == null) {
      return null;
    }

    return PersonalEvalCaseManifestOptions(
      logPath: logPath,
      caseId: caseId,
      title: title,
      prompt: prompt,
      promptFilePath: promptFilePath,
      repoStateRef: repoStateRef,
      verificationCommand: verificationCommand,
      verificationResult: verificationResult,
      workspaceMode: workspaceMode,
      outPath: outPath,
      consent: consent,
    );
  }

  static String? _nextValue(List<String> args, int index) {
    if (index >= args.length) {
      return null;
    }
    final value = args[index];
    return value.startsWith('--') ? null : value;
  }
}

final class PersonalEvalCaseManifest {
  const PersonalEvalCaseManifest({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.caseId,
    required this.title,
    required this.readiness,
    required this.task,
    required this.source,
    required this.consent,
    required this.privacy,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String caseId;
  final String title;
  final PersonalEvalCaseReadiness readiness;
  final PersonalEvalTaskSnapshot task;
  final PersonalEvalSourceSnapshot source;
  final PersonalEvalConsentSnapshot consent;
  final PersonalEvalPrivacySnapshot privacy;

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'caseId': caseId,
      'title': title,
      'readiness': readiness.jsonValue,
      'task': task.toJson(),
      'source': source.toJson(),
      'consent': consent.toJson(generatedAt),
      'privacy': privacy.toJson(),
    };
  }
}

final class PersonalEvalTaskSnapshot {
  const PersonalEvalTaskSnapshot({
    required this.prompt,
    required this.repoStateRef,
    required this.verificationCommand,
    required this.verificationResult,
    required this.workspaceMode,
  });

  final String prompt;
  final String repoStateRef;
  final String? verificationCommand;
  final PersonalEvalVerificationResult verificationResult;
  final String? workspaceMode;

  Map<String, dynamic> toJson() {
    return {
      'prompt': prompt,
      'repoStateRef': repoStateRef,
      if (verificationCommand != null)
        'verificationCommand': verificationCommand,
      'verificationResult': verificationResult.name,
      if (workspaceMode != null) 'workspaceMode': workspaceMode,
    };
  }
}

final class PersonalEvalSourceSnapshot {
  const PersonalEvalSourceSnapshot({
    required this.sessionLogPath,
    required this.sessionLogSummary,
  });

  final String sessionLogPath;
  final PersonalEvalSessionLogSummarySnapshot sessionLogSummary;

  factory PersonalEvalSourceSnapshot.fromSummary(
    CavernoLlmSessionLogSummary summary,
  ) {
    return PersonalEvalSourceSnapshot(
      sessionLogPath: summary.logPath,
      sessionLogSummary: PersonalEvalSessionLogSummarySnapshot.fromSummary(
        summary,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionLogPath': sessionLogPath,
      'sessionLogSummary': sessionLogSummary.toJson(),
    };
  }
}

final class PersonalEvalSessionLogSummarySnapshot {
  const PersonalEvalSessionLogSummarySnapshot({
    required this.result,
    required this.entryCount,
    required this.malformedLineCount,
    required this.toolCallCount,
    required this.totalDurationMs,
    required this.operationCounts,
    required this.finishReasonCounts,
    required this.warningCodes,
    required this.finalAnswerLineNumber,
  });

  final String result;
  final int entryCount;
  final int malformedLineCount;
  final int toolCallCount;
  final int totalDurationMs;
  final Map<String, int> operationCounts;
  final Map<String, int> finishReasonCounts;
  final List<String> warningCodes;
  final int? finalAnswerLineNumber;

  factory PersonalEvalSessionLogSummarySnapshot.fromSummary(
    CavernoLlmSessionLogSummary summary,
  ) {
    return PersonalEvalSessionLogSummarySnapshot(
      result: summary.result,
      entryCount: summary.entryCount,
      malformedLineCount: summary.malformedLineCount,
      toolCallCount: summary.toolCallCount,
      totalDurationMs: summary.entries.fold(
        0,
        (total, entry) => total + (entry.durationMs ?? 0),
      ),
      operationCounts: Map.unmodifiable(summary.operationCounts),
      finishReasonCounts: Map.unmodifiable(summary.finishReasonCounts),
      warningCodes: List.unmodifiable(
        summary.warnings.map((warning) => warning.code),
      ),
      finalAnswerLineNumber: summary.finalAnswer?.lineNumber,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'result': result,
      'entryCount': entryCount,
      'malformedLineCount': malformedLineCount,
      'toolCallCount': toolCallCount,
      'totalDurationMs': totalDurationMs,
      'operationCounts': operationCounts,
      'finishReasonCounts': finishReasonCounts,
      'warningCodes': warningCodes,
      if (finalAnswerLineNumber != null)
        'finalAnswerLineNumber': finalAnswerLineNumber,
    };
  }
}

final class PersonalEvalConsentSnapshot {
  const PersonalEvalConsentSnapshot({required this.explicitUserConsent});

  final bool explicitUserConsent;

  Map<String, dynamic> toJson(DateTime recordedAt) {
    return {
      'explicitUserConsent': explicitUserConsent,
      'recordedAt': recordedAt.toIso8601String(),
      'scope': 'personal_eval_case_recording',
    };
  }
}

final class PersonalEvalPrivacySnapshot {
  const PersonalEvalPrivacySnapshot();

  Map<String, dynamic> toJson() {
    return {
      'localOnly': true,
      'anonymization': 'none',
      'exportPolicy': 'excluded_by_default',
    };
  }
}
