import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

/// Retention bounds for the approval audit trail. Because entries are
/// partitioned into one file per day, pruning works at day-file granularity:
/// files older than [maxAge] are deleted, and only the [maxFiles] most recent
/// day-files are kept.
class ToolApprovalAuditRetentionPolicy {
  const ToolApprovalAuditRetentionPolicy({
    this.maxAge = defaultMaxAge,
    this.maxFiles = defaultMaxFiles,
  });

  static const Duration defaultMaxAge = Duration(days: 30);
  static const int defaultMaxFiles = 60;

  /// Delete day-files older than this. Null disables age-based pruning.
  final Duration? maxAge;

  /// Keep at most this many day-files. Null disables count-based pruning.
  final int? maxFiles;

  factory ToolApprovalAuditRetentionPolicy.fromEnvironment([
    Map<String, String>? environment,
  ]) {
    final env = environment ?? Platform.environment;
    return ToolApprovalAuditRetentionPolicy(
      maxAge: _parseMaxAge(
        env['CAVERNO_APPROVAL_AUDIT_MAX_AGE_DAYS'],
        fallback: defaultMaxAge,
      ),
      maxFiles: _parsePositiveInt(
        env['CAVERNO_APPROVAL_AUDIT_MAX_FILES'],
        fallback: defaultMaxFiles,
      ),
    );
  }

  static int? _parsePositiveInt(String? value, {required int fallback}) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null) return fallback;
    return parsed <= 0 ? null : parsed;
  }

  static Duration? _parseMaxAge(String? value, {required Duration fallback}) {
    final days = _parsePositiveInt(value, fallback: fallback.inDays);
    return days == null ? null : Duration(days: days);
  }
}

/// Append-only, local-only audit trail for **automated** high-risk tool
/// approvals (full access auto-runs and LLM auto-review verdicts).
///
/// Unlike [LlmSessionLogStore] (opt-in, captures full prompts/responses), this
/// is always on, lightweight (one JSON line per automated decision), and
/// records the *verdict* so you can later answer "which request was allowed or
/// denied, and why". Manual approvals are intentionally not recorded here — the
/// user made those decisions interactively.
///
/// Entries are written as JSON Lines to date-partitioned files under
/// `~/.caverno/approval_audit/<YYYY-MM-DD>.jsonl`, so they are trivially
/// greppable. Secret-bearing argument fields are dropped before writing.
/// Old day-files are pruned per [ToolApprovalAuditRetentionPolicy].
class ToolApprovalAuditLog {
  ToolApprovalAuditLog({
    Future<Directory> Function()? rootDirectoryProvider,
    ToolApprovalAuditRetentionPolicy? retentionPolicy,
  }) : _rootDirectoryProvider =
           rootDirectoryProvider ?? _defaultRootDirectoryProvider,
       _retentionPolicy =
           retentionPolicy ?? ToolApprovalAuditRetentionPolicy.fromEnvironment(),
       // Default to a no-op under `flutter test` so unrelated tests never touch
       // the developer's home directory. Tests that assert on output inject an
       // explicit [rootDirectoryProvider], which re-enables writing.
       _enabled = rootDirectoryProvider != null || !_isFlutterTest;

  final Future<Directory> Function() _rootDirectoryProvider;
  final ToolApprovalAuditRetentionPolicy _retentionPolicy;
  final bool _enabled;

  static const schemaName = 'caverno_tool_approval_audit_entry';
  static const schemaVersion = 1;
  static const directoryEnvironmentKey = 'CAVERNO_APPROVAL_AUDIT_DIR';
  static final RegExp _dayFilePattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})\.jsonl$',
  );

  /// Argument keys whose values are bulk content or secrets: never written
  /// verbatim. A length marker is kept so you know a value was present.
  static const _redactedArgumentKeys = {
    'value',
    'script',
    'data',
    'content',
    'new_text',
    'old_text',
    'password',
    'passwd',
    'pwd',
    'secret',
    'token',
    'image_base64',
    'imagebase64',
  };

  static const int _maxStringLength = 240;

  static bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> record({
    required String tool,
    required String actionKind,
    required String domain,
    required String mode,
    required String outcome,
    String? decisionSource,
    String? rationale,
    String? riskLevel,
    Map<String, dynamic>? arguments,
    String? workspaceMode,
    String? sessionId,
    String? conversationId,
    DateTime? timestamp,
  }) async {
    if (!_enabled) return;
    final now = timestamp ?? DateTime.now();
    final entry = <String, dynamic>{
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'timestamp': now.toIso8601String(),
      'tool': tool,
      'actionKind': actionKind,
      'domain': domain,
      'mode': mode,
      'outcome': outcome,
      'decisionSource': ?decisionSource,
      if (rationale != null && rationale.trim().isNotEmpty)
        'rationale': rationale.trim(),
      if (riskLevel != null && riskLevel.trim().isNotEmpty)
        'riskLevel': riskLevel.trim(),
      if (arguments != null) 'arguments': _summarizeArguments(arguments),
      if (workspaceMode != null && workspaceMode.trim().isNotEmpty)
        'workspaceMode': workspaceMode.trim(),
      if (sessionId != null && sessionId.trim().isNotEmpty)
        'sessionId': sessionId.trim(),
      if (conversationId != null && conversationId.trim().isNotEmpty)
        'conversationId': conversationId.trim(),
    };
    try {
      final file = await _fileFor(now);
      await file.parent.create(recursive: true);
      // Prune only when a new day-file is about to be created — this throttles
      // directory scans to roughly once per day instead of once per decision.
      final isNewDayFile = !await file.exists();
      await file.writeAsString(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
        flush: true,
      );
      if (isNewDayFile) {
        await _pruneOldLogs(file.parent, now);
      }
    } catch (error) {
      appLog('[ApprovalAudit] Failed to write approval audit entry: $error');
    }
  }

  Future<File> _fileFor(DateTime now) async {
    final root = await _rootDirectoryProvider();
    return File('${root.path}/approval_audit/${_dayStamp(now)}.jsonl');
  }

  String _dayStamp(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Deletes day-files older than [ToolApprovalAuditRetentionPolicy.maxAge] and
  /// trims the directory to the newest [ToolApprovalAuditRetentionPolicy.maxFiles].
  /// Best effort: failures are swallowed so logging never throws.
  Future<void> _pruneOldLogs(Directory directory, DateTime now) async {
    try {
      if (!await directory.exists()) return;
      final dayFiles = <({File file, DateTime date})>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final match = _dayFilePattern.firstMatch(name);
        if (match == null) continue;
        final date = DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        );
        dayFiles.add((file: entity, date: date));
      }

      final maxAge = _retentionPolicy.maxAge;
      final survivors = <({File file, DateTime date})>[];
      if (maxAge != null) {
        final cutoff = now.subtract(maxAge);
        for (final entry in dayFiles) {
          // Compare against end-of-day so a file is kept for its full last day.
          final expiresAt = entry.date.add(const Duration(days: 1));
          if (expiresAt.isBefore(cutoff)) {
            await entry.file.delete();
          } else {
            survivors.add(entry);
          }
        }
      } else {
        survivors.addAll(dayFiles);
      }

      final maxFiles = _retentionPolicy.maxFiles;
      if (maxFiles != null && survivors.length > maxFiles) {
        survivors.sort((a, b) => a.date.compareTo(b.date));
        final excess = survivors.length - maxFiles;
        for (final entry in survivors.take(excess)) {
          await entry.file.delete();
        }
      }
    } catch (error) {
      appLog('[ApprovalAudit] Failed to prune approval audit logs: $error');
    }
  }

  Map<String, dynamic> _summarizeArguments(Map<String, dynamic> arguments) {
    final summary = <String, dynamic>{};
    for (final entry in arguments.entries) {
      final key = entry.key;
      if (_redactedArgumentKeys.contains(key.toLowerCase())) {
        final value = entry.value;
        summary[key] = value is String
            ? '[redacted len=${value.length}]'
            : '[redacted]';
        continue;
      }
      summary[key] = _truncate(entry.value);
    }
    return summary;
  }

  dynamic _truncate(dynamic value) {
    if (value is String && value.length > _maxStringLength) {
      return '${value.substring(0, _maxStringLength)}…';
    }
    return value;
  }

  static Future<Directory> _defaultRootDirectoryProvider() async {
    final override = Platform.environment[directoryEnvironmentKey]?.trim();
    if (override != null && override.isNotEmpty) {
      return Directory(override);
    }
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      return Directory('$home/.caverno');
    }
    return Directory('${Directory.systemTemp.path}/caverno');
  }
}

final toolApprovalAuditLogProvider = Provider<ToolApprovalAuditLog>((ref) {
  return ToolApprovalAuditLog();
});
