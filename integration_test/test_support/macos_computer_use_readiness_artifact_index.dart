import 'dart:convert';
import 'dart:io';

class ReadinessArtifactEntry {
  const ReadinessArtifactEntry({
    required this.id,
    required this.label,
    required this.path,
    required this.exists,
  });

  final String id;
  final String label;
  final String path;
  final bool exists;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'path': path,
      'exists': exists,
    };
  }
}

class ReadinessArtifactIndex {
  const ReadinessArtifactIndex({
    required this.reportRoot,
    required this.entries,
  });

  final String reportRoot;
  final List<ReadinessArtifactEntry> entries;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_readiness_artifact_index',
      'schemaVersion': 1,
      'reportRoot': reportRoot,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use Readiness Artifact Index')
      ..writeln()
      ..writeln('- Report root: `$reportRoot`')
      ..writeln()
      ..writeln('| Artifact | Exists | Path |')
      ..writeln('| --- | --- | --- |');
    for (final entry in entries) {
      buffer.writeln(
        '| ${_markdownCell(entry.label)} | ${entry.exists} | `${_escapeMarkdownCode(entry.path)}` |',
      );
    }
    return buffer.toString();
  }
}

ReadinessArtifactIndex buildReadinessArtifactIndex(Directory reportRoot) {
  final entries = <ReadinessArtifactEntry>[
    _entry(
      'release_artifact',
      'M7 release artifact report',
      '${reportRoot.path}/macos_computer_use_release_artifact_signoff.json',
    ),
    _entry(
      'canary_history',
      'Computer Use canary history',
      '${reportRoot.path}/macos_computer_use_canary_history.json',
    ),
    _entry(
      'readiness_ci_json',
      'CI readiness JSON',
      '${reportRoot.path}/macos_computer_use_release_readiness_ci.json',
    ),
    _entry(
      'readiness_ci_md',
      'CI readiness Markdown',
      '${reportRoot.path}/macos_computer_use_release_readiness_ci.md',
    ),
    _entry(
      'readiness_signoff_json',
      'Sign-off readiness JSON',
      '${reportRoot.path}/macos_computer_use_release_readiness_signoff.json',
    ),
    _entry(
      'readiness_signoff_md',
      'Sign-off readiness Markdown',
      '${reportRoot.path}/macos_computer_use_release_readiness_signoff.md',
    ),
    _latestEntry(
      'manual_tcc',
      'Latest manual TCC evidence',
      reportRoot,
      (json) =>
          json['schemaName'] ==
              'macos_computer_use_manual_tcc_report_summary' ||
          json.containsKey('releaseRuntimeSignoffGate'),
    ),
    _latestEntry(
      'desktop_action_canary',
      'Latest desktop action canary summary',
      reportRoot,
      (json) =>
          json['schemaName'] ==
          'macos_computer_use_desktop_action_canary_summary',
      parentPrefix: 'macos_computer_use_desktop_action_canary_',
      fileName: 'canary_summary.json',
    ),
    _latestLlmCanaryEntry(
      'llm_canary',
      'Latest LLM canary summary',
      reportRoot,
    ),
  ];
  return ReadinessArtifactIndex(
    reportRoot: reportRoot.path,
    entries: List<ReadinessArtifactEntry>.unmodifiable(entries),
  );
}

Future<void> writeReadinessArtifactIndex(
  Directory reportRoot, {
  String? outputJsonPath,
  String? outputMarkdownPath,
}) async {
  reportRoot.createSync(recursive: true);
  final index = buildReadinessArtifactIndex(reportRoot);
  final outputJson = File(
    outputJsonPath ??
        '${reportRoot.path}/macos_computer_use_readiness_artifact_index.json',
  );
  final outputMarkdown = File(
    outputMarkdownPath ??
        '${reportRoot.path}/macos_computer_use_readiness_artifact_index.md',
  );
  await outputJson.writeAsString(
    const JsonEncoder.withIndent('  ').convert(index.toJson()),
  );
  await outputMarkdown.writeAsString(index.toMarkdown());
}

ReadinessArtifactEntry _latestLlmCanaryEntry(
  String id,
  String label,
  Directory reportRoot,
) {
  final files = reportRoot.existsSync()
      ? reportRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => _basename(file.path) == 'canary_summary.json')
            .where((file) {
              final parent = _basename(file.parent.path);
              return parent.startsWith(
                    'macos_computer_use_llm_decision_canary_',
                  ) ||
                  parent.startsWith(
                    'macos_computer_use_mvp_fixture_llm_canary_',
                  ) ||
                  parent.startsWith(
                    'macos_computer_use_mvp_fixture_vision_llm_canary_',
                  ) ||
                  parent.startsWith('plan_mode_ping_cli_canary_');
            })
            .where((file) {
              final json = _readJsonObject(file);
              return json != null &&
                  json.containsKey('runCount') &&
                  (json.containsKey('passedCount') ||
                      json['schemaName'] ==
                          'macos_computer_use_mvp_fixture_llm_canary_summary' ||
                      json['schemaName'] ==
                          'macos_computer_use_mvp_fixture_vision_llm_canary_summary');
            })
            .toList(growable: false)
      : <File>[];
  files.sort((left, right) {
    final modifiedCompare = left.statSync().modified.compareTo(
      right.statSync().modified,
    );
    if (modifiedCompare != 0) {
      return modifiedCompare;
    }
    return left.path.compareTo(right.path);
  });

  final computerUseFiles = files
      .where((file) {
        return _basename(
              file.parent.path,
            ).startsWith('macos_computer_use_llm_decision_canary_') ||
            _basename(
              file.parent.path,
            ).startsWith('macos_computer_use_mvp_fixture_vision_llm_canary_') ||
            _basename(
              file.parent.path,
            ).startsWith('macos_computer_use_mvp_fixture_llm_canary_');
      })
      .toList(growable: false);
  final visionFiles = computerUseFiles
      .where((file) {
        return _basename(
          file.parent.path,
        ).startsWith('macos_computer_use_mvp_fixture_vision_llm_canary_');
      })
      .toList(growable: false);
  final aggregateFiles = computerUseFiles
      .where((file) {
        return _basename(
          file.parent.path,
        ).startsWith('macos_computer_use_mvp_fixture_llm_canary_');
      })
      .toList(growable: false);
  final mvpFixtureFiles = computerUseFiles
      .where((file) {
        final json = _readJsonObject(file);
        final scenario = json?['scenario'] as String?;
        return scenario != null && scenario.startsWith('mvp-fixture');
      })
      .toList(growable: false);
  final latest = visionFiles.isNotEmpty
      ? visionFiles.last
      : aggregateFiles.isNotEmpty
      ? aggregateFiles.last
      : mvpFixtureFiles.isNotEmpty
      ? mvpFixtureFiles.last
      : computerUseFiles.isNotEmpty
      ? computerUseFiles.last
      : files.isEmpty
      ? null
      : files.last;
  return ReadinessArtifactEntry(
    id: id,
    label: label,
    path: latest?.path ?? '',
    exists: latest != null,
  );
}

ReadinessArtifactEntry _entry(String id, String label, String path) {
  return ReadinessArtifactEntry(
    id: id,
    label: label,
    path: path,
    exists: File(path).existsSync(),
  );
}

ReadinessArtifactEntry _latestEntry(
  String id,
  String label,
  Directory reportRoot,
  bool Function(Map<String, dynamic> json) matches, {
  String? parentPrefix,
  String? fileName,
}) {
  final files = reportRoot.existsSync()
      ? reportRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .where((file) {
              if (fileName != null && _basename(file.path) != fileName) {
                return false;
              }
              if (parentPrefix != null &&
                  !_basename(file.parent.path).startsWith(parentPrefix)) {
                return false;
              }
              final json = _readJsonObject(file);
              return json != null && matches(json);
            })
            .toList(growable: false)
      : <File>[];
  files.sort((left, right) {
    final modifiedCompare = left.statSync().modified.compareTo(
      right.statSync().modified,
    );
    if (modifiedCompare != 0) {
      return modifiedCompare;
    }
    return left.path.compareTo(right.path);
  });
  final latest = files.isEmpty ? null : files.last;
  return ReadinessArtifactEntry(
    id: id,
    label: label,
    path: latest?.path ?? '',
    exists: latest != null,
  );
}

Map<String, dynamic>? _readJsonObject(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  } on FileSystemException {
    return null;
  }
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
