import 'dart:convert';

import '../entities/tool_call_info.dart';

class AnalysisOptionsLintEditIssue {
  const AnalysisOptionsLintEditIssue({
    required this.path,
    required this.ungroundedRules,
    required this.observedDiagnosticCodes,
  });

  static const code = 'analysis_options_lint_evidence_required';

  final String path;
  final List<String> ungroundedRules;
  final List<String> observedDiagnosticCodes;

  String get summary =>
      'The analysis_options.yaml edit disables or relaxes diagnostics that '
      'are not present in the current turn diagnostics.';

  String get instruction =>
      'Fix the reported code instead of suppressing it, or run Dart analysis '
      'and retry with only an exact diagnostic code reported in this turn.';

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'path': path,
      'summary': summary,
      'ungrounded_rules': ungroundedRules,
      'observed_diagnostic_codes': observedDiagnosticCodes,
      'instruction': instruction,
    };
  }
}

/// Blocks invented lint suppressions while preserving ordinary YAML edits.
///
/// The model's explanation is intentionally not considered evidence. Only
/// structured Dart diagnostic feedback or diagnostic codes printed by an
/// executed Dart analyzer command in the current turn can ground a new rule.
class AnalysisOptionsLintEditGuard {
  const AnalysisOptionsLintEditGuard();

  AnalysisOptionsLintEditIssue? detectIssue({
    required ToolCallInfo toolCall,
    required List<ToolResultInfo> executedToolResults,
  }) {
    final toolName = toolCall.name.trim().toLowerCase();
    if (toolName != 'edit_file' && toolName != 'write_file') {
      return null;
    }

    final path = toolCall.arguments['path']?.toString().trim() ?? '';
    if (!_isAnalysisOptionsPath(path)) {
      return null;
    }

    final previousText = toolName == 'edit_file'
        ? toolCall.arguments['old_text']?.toString() ?? ''
        : '';
    final proposedText = toolName == 'edit_file'
        ? toolCall.arguments['new_text']?.toString() ?? ''
        : toolCall.arguments['content']?.toString() ?? '';
    final previousRules = _configuredDiagnosticSettings(previousText);
    final proposedRules = _configuredDiagnosticSettings(proposedText);
    final changedRules = {
      for (final entry in proposedRules.entries)
        if (_requiresDiagnosticEvidence(
          previousValue: previousRules[entry.key],
          proposedValue: entry.value,
        ))
          entry.key,
    };
    if (changedRules.isEmpty) {
      return null;
    }

    final observedCodes = _observedDiagnosticCodes(executedToolResults);
    final ungroundedRules = changedRules.difference(observedCodes).toList()
      ..sort();
    if (ungroundedRules.isEmpty) {
      return null;
    }

    final sortedObservedCodes = observedCodes.toList()..sort();
    return AnalysisOptionsLintEditIssue(
      path: path,
      ungroundedRules: ungroundedRules,
      observedDiagnosticCodes: sortedObservedCodes,
    );
  }

  bool _isAnalysisOptionsPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized == 'analysis_options.yaml' ||
        normalized.endsWith('/analysis_options.yaml');
  }

  bool _requiresDiagnosticEvidence({
    required String? previousValue,
    required String proposedValue,
  }) {
    if (previousValue == proposedValue) {
      return false;
    }
    if (proposedValue == 'false' ||
        proposedValue == 'ignore' ||
        proposedValue == 'info') {
      return true;
    }
    return previousValue == 'error' && proposedValue == 'warning';
  }

  Map<String, String> _configuredDiagnosticSettings(String yaml) {
    final settings = <String, String>{};
    final stack = <_YamlSection>[];
    for (final rawLine in const LineSplitter().convert(yaml)) {
      final line = _stripYamlComment(rawLine);
      if (line.trim().isEmpty) {
        continue;
      }
      final indent = line.length - line.trimLeft().length;
      while (stack.isNotEmpty && stack.last.indent >= indent) {
        stack.removeLast();
      }

      final listMatch = RegExp(
        r'''^\s*-\s*["']?([a-z][a-z0-9_]*)["']?\s*$''',
        caseSensitive: false,
      ).firstMatch(line);
      if (listMatch != null && _isLinterRulesPath(stack)) {
        settings[_normalizeCode(listMatch.group(1)!)] = 'true';
        continue;
      }

      final mappingMatch = RegExp(
        r'''^\s*["']?([a-z][a-z0-9_]*)["']?\s*:\s*(.*?)\s*$''',
        caseSensitive: false,
      ).firstMatch(line);
      if (mappingMatch == null) {
        continue;
      }
      final key = _normalizeCode(mappingMatch.group(1)!);
      final value = mappingMatch.group(2)!.trim();
      final path = [...stack.map((section) => section.key), key];
      if (_isConfiguredRulePath(path, value)) {
        settings[key] = _normalizeSettingValue(value);
      } else if (stack.isEmpty && _looksLikeStandaloneRuleEdit(key, value)) {
        // edit_file commonly receives only the exact rule line rather than
        // the surrounding linter.rules or analyzer.errors block.
        settings[key] = _normalizeSettingValue(value);
      }
      if (_isRulesContainerPath(path) &&
          value.startsWith('{') &&
          value.endsWith('}')) {
        settings.addAll(_inlineRuleSettings(value));
      }
      if (value.isEmpty) {
        stack.add(_YamlSection(indent: indent, key: key));
      }
    }
    return settings;
  }

  bool _isConfiguredRulePath(List<String> path, String value) {
    if (path.length == 3 && path[0] == 'linter' && path[1] == 'rules') {
      return value.isNotEmpty;
    }
    if (path.length == 3 && path[0] == 'analyzer' && path[1] == 'errors') {
      return const {
        'ignore',
        'info',
        'warning',
        'error',
      }.contains(value.toLowerCase());
    }
    return false;
  }

  bool _looksLikeStandaloneRuleEdit(String key, String value) {
    if (!key.contains('_')) {
      return false;
    }
    return const {
      'true',
      'false',
      'ignore',
      'info',
      'warning',
      'error',
    }.contains(_normalizeSettingValue(value));
  }

  bool _isRulesContainerPath(List<String> path) {
    return path.length == 2 &&
        ((path[0] == 'linter' && path[1] == 'rules') ||
            (path[0] == 'analyzer' && path[1] == 'errors'));
  }

  bool _isLinterRulesPath(List<_YamlSection> stack) {
    return stack.length == 2 &&
        stack[0].key == 'linter' &&
        stack[1].key == 'rules';
  }

  Map<String, String> _inlineRuleSettings(String value) {
    final settings = <String, String>{};
    final body = value.substring(1, value.length - 1);
    for (final entry in body.split(',')) {
      final match = RegExp(
        r'''^\s*["']?([a-z][a-z0-9_]*)["']?\s*:\s*(.*?)\s*$''',
        caseSensitive: false,
      ).firstMatch(entry);
      if (match != null) {
        settings[_normalizeCode(match.group(1)!)] = _normalizeSettingValue(
          match.group(2)!,
        );
      }
    }
    return settings;
  }

  String _stripYamlComment(String line) {
    var singleQuoted = false;
    var doubleQuoted = false;
    for (var index = 0; index < line.length; index += 1) {
      final character = line[index];
      if (character == "'" && !doubleQuoted) {
        singleQuoted = !singleQuoted;
      } else if (character == '"' && !singleQuoted) {
        doubleQuoted = !doubleQuoted;
      } else if (character == '#' && !singleQuoted && !doubleQuoted) {
        return line.substring(0, index);
      }
    }
    return line;
  }

  Set<String> _observedDiagnosticCodes(
    List<ToolResultInfo> executedToolResults,
  ) {
    final codes = <String>{};
    for (final result in executedToolResults) {
      if (result.name == 'dart_analyze_feedback') {
        _collectStructuredCodes(_tryDecodeMap(result.result), codes);
        continue;
      }
      if (!_isDartAnalyzeCommandResult(result)) {
        continue;
      }
      final decoded = _tryDecodeMap(result.result);
      _collectStructuredCodes(decoded, codes);
      final output = [
        decoded?['stdout'],
        decoded?['stderr'],
      ].whereType<String>().join('\n');
      _collectAnalyzerOutputCodes(output, codes);
    }
    return codes;
  }

  bool _isDartAnalyzeCommandResult(ToolResultInfo result) {
    if (result.name != 'local_execute_command' &&
        result.name != 'process_start' &&
        result.name != 'process_wait') {
      return false;
    }
    final decoded = _tryDecodeMap(result.result);
    final command =
        result.arguments['command']?.toString() ??
        decoded?['command']?.toString() ??
        '';
    return RegExp(
      r'(?:^|\s)(?:(?:fvm\s+)?dart|(?:fvm\s+)?flutter)\s+analyze(?:\s|$)',
      caseSensitive: false,
    ).hasMatch(command);
  }

  void _collectStructuredCodes(
    Map<String, dynamic>? payload,
    Set<String> codes,
  ) {
    final diagnostics = payload?['diagnostics'];
    if (diagnostics is! List) {
      return;
    }
    for (final diagnostic in diagnostics.whereType<Map>()) {
      final code = diagnostic['code']?.toString();
      if (code != null && _looksLikeDiagnosticCode(code)) {
        codes.add(_normalizeCode(code));
      }
    }
  }

  void _collectAnalyzerOutputCodes(String output, Set<String> codes) {
    for (final line in const LineSplitter().convert(output)) {
      final machineMatch = RegExp(
        r'^(?:INFO|WARNING|ERROR)\|[^|]+\|([A-Z][A-Z0-9_]*)\|',
      ).firstMatch(line.trim());
      if (machineMatch != null) {
        codes.add(_normalizeCode(machineMatch.group(1)!));
        continue;
      }
      final humanMatch = RegExp(
        r'(?:\s[-•]\s)([a-z][a-z0-9_]*)\s*$',
        caseSensitive: false,
      ).firstMatch(line.trim());
      if (humanMatch != null) {
        codes.add(_normalizeCode(humanMatch.group(1)!));
      }
    }
  }

  bool _looksLikeDiagnosticCode(String value) {
    return RegExp(
      r'^[a-z][a-z0-9_]*$',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  String _normalizeCode(String value) => value.trim().toLowerCase();

  String _normalizeSettingValue(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.length >= 2 &&
        ((normalized.startsWith('"') && normalized.endsWith('"')) ||
            (normalized.startsWith("'") && normalized.endsWith("'")))) {
      return normalized.substring(1, normalized.length - 1).trim();
    }
    return normalized;
  }

  Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class _YamlSection {
  const _YamlSection({required this.indent, required this.key});

  final int indent;
  final String key;
}
