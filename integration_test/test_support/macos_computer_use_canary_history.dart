import 'dart:convert';
import 'dart:io';

class ComputerUseCanaryHistoryEntry {
  const ComputerUseCanaryHistoryEntry({
    required this.name,
    required this.directory,
    required this.summaryPath,
    required this.preset,
    required this.tccBoundary,
    required this.stabilityMode,
    required this.stable,
    required this.runCount,
    required this.passed,
    required this.failed,
    required this.passRate,
    required this.failureClasses,
    required this.modifiedAt,
  });

  final String name;
  final String directory;
  final String summaryPath;
  final String preset;
  final String tccBoundary;
  final bool stabilityMode;
  final bool stable;
  final int runCount;
  final int passed;
  final int failed;
  final double passRate;
  final Map<String, int> failureClasses;
  final DateTime modifiedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'directory': directory,
      'summaryPath': summaryPath,
      'preset': preset,
      'tccBoundary': tccBoundary,
      'stabilityMode': stabilityMode,
      'stable': stable,
      'runCount': runCount,
      'passed': passed,
      'failed': failed,
      'passRate': passRate,
      'failureClasses': failureClasses,
      'modifiedAt': modifiedAt.toIso8601String(),
    };
  }
}

class ComputerUseCanaryHistory {
  const ComputerUseCanaryHistory({required this.entries, required this.limit});

  final List<ComputerUseCanaryHistoryEntry> entries;
  final int limit;

  ComputerUseCanaryHistoryEntry? get latest =>
      entries.isEmpty ? null : entries.last;

  ComputerUseCanaryHistoryEntry? get previous =>
      entries.length < 2 ? null : entries[entries.length - 2];

  double? get latestPassRateDelta {
    final current = latest;
    final baseline = previous;
    if (current == null || baseline == null) {
      return null;
    }
    return current.passRate - baseline.passRate;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_canary_history',
      'schemaVersion': 1,
      'limit': limit,
      'entryCount': entries.length,
      'latestStatus': latest == null
          ? 'missing'
          : (latest!.stable ? 'stable' : 'unstable'),
      'latestPassRateDelta': latestPassRateDelta,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use Canary History')
      ..writeln()
      ..writeln('- Entry count: ${entries.length}')
      ..writeln(
        '- Latest status: ${latest == null ? 'missing' : (latest!.stable ? 'stable' : 'unstable')}',
      )
      ..writeln(
        '- Latest pass-rate delta: ${_formatDelta(latestPassRateDelta)}',
      )
      ..writeln()
      ..writeln(
        '| Run | Preset | Stability | Stable | Pass Rate | Passed | Failed | Failure Classes | Summary |',
      )
      ..writeln('| --- | --- | --- | --- | ---: | ---: | ---: | --- | --- |');

    for (final entry in entries.reversed) {
      buffer.writeln(
        '| ${_markdownCell(entry.name)} | ${_markdownCell(entry.preset)} | ${entry.stabilityMode} | ${entry.stable} | ${(entry.passRate * 100).toStringAsFixed(1)}% | ${entry.passed} | ${entry.failed} | ${_failureClassesCell(entry.failureClasses)} | `${_escapeMarkdownCode(entry.summaryPath)}` |',
      );
    }
    return buffer.toString();
  }
}

ComputerUseCanaryHistory buildComputerUseCanaryHistory(
  Directory reportRoot, {
  int limit = 10,
}) {
  if (!reportRoot.existsSync()) {
    return ComputerUseCanaryHistory(entries: const [], limit: limit);
  }

  final summaries =
      reportRoot
          .listSync()
          .whereType<Directory>()
          .where(
            (directory) => _basename(
              directory.path,
            ).startsWith('macos_computer_use_live_canary_'),
          )
          .map((directory) => File('${directory.path}/canary_summary.json'))
          .where((file) => file.existsSync())
          .toList(growable: false)
        ..sort((left, right) => left.parent.path.compareTo(right.parent.path));

  final selected = summaries.length <= limit
      ? summaries
      : summaries.sublist(summaries.length - limit);
  final entries = selected
      .map(_readHistoryEntry)
      .whereType<ComputerUseCanaryHistoryEntry>()
      .toList(growable: false);

  return ComputerUseCanaryHistory(
    entries: List<ComputerUseCanaryHistoryEntry>.unmodifiable(entries),
    limit: limit,
  );
}

ComputerUseCanaryHistoryEntry? _readHistoryEntry(File summaryFile) {
  try {
    final decoded = jsonDecode(summaryFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final failureClasses = <String, int>{};
    final rawFailureClasses = decoded['failureClasses'];
    if (rawFailureClasses is Map<String, dynamic>) {
      for (final entry in rawFailureClasses.entries) {
        final value = entry.value;
        if (value is int) {
          failureClasses[entry.key] = value;
        } else if (value is num) {
          failureClasses[entry.key] = value.toInt();
        }
      }
    }

    final passed = _intValue(decoded['passed']);
    final failed = _intValue(decoded['failed']);
    final runCount = _intValue(decoded['runCount']);
    final passRate = _doubleValue(decoded['passRate']);
    return ComputerUseCanaryHistoryEntry(
      name: _basename(summaryFile.parent.path),
      directory: summaryFile.parent.path,
      summaryPath: summaryFile.path,
      preset: decoded['preset'] as String? ?? 'unknown',
      tccBoundary: decoded['tccBoundary'] as String? ?? 'unknown',
      stabilityMode: decoded['stabilityMode'] == true,
      stable: decoded['stable'] == true || (runCount > 0 && failed == 0),
      runCount: runCount,
      passed: passed,
      failed: failed,
      passRate: passRate,
      failureClasses: Map<String, int>.unmodifiable(failureClasses),
      modifiedAt: summaryFile.statSync().modified,
    );
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

double _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return 0;
}

String _failureClassesCell(Map<String, int> failureClasses) {
  if (failureClasses.isEmpty) {
    return '-';
  }
  return failureClasses.entries
      .map((entry) => '${_markdownCell(entry.key)}: ${entry.value}')
      .join('<br>');
}

String _formatDelta(double? delta) {
  if (delta == null) {
    return '-';
  }
  final sign = delta > 0 ? '+' : '';
  return '$sign${(delta * 100).toStringAsFixed(1)}%';
}

String _markdownCell(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return '-';
  }
  return text.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}

String _escapeMarkdownCode(String value) {
  return value.replaceAll('`', r'\`');
}

String _basename(String path) {
  final segments = path.split(Platform.pathSeparator);
  for (final segment in segments.reversed) {
    if (segment.isNotEmpty) {
      return segment;
    }
  }
  return path;
}
