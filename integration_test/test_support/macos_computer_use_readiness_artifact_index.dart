import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/macos_computer_use_setup.dart';

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
    required this.mvpFinalSignoffRehearsal,
  });

  final String reportRoot;
  final List<ReadinessArtifactEntry> entries;
  final ReadinessFinalSignoffRehearsal mvpFinalSignoffRehearsal;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_readiness_artifact_index',
      'schemaVersion': 1,
      'reportRoot': reportRoot,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'mvpFinalSignoffRehearsal': mvpFinalSignoffRehearsal.toJson(),
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
    buffer
      ..writeln()
      ..writeln('## MVP Final Sign-Off Rehearsal')
      ..writeln()
      ..writeln('- Ready: ${mvpFinalSignoffRehearsal.ready}')
      ..writeln(
        '- Missing required artifacts: ${mvpFinalSignoffRehearsal.missingArtifactIds.isEmpty ? 'none' : mvpFinalSignoffRehearsal.missingArtifactIds.join(', ')}',
      );
    buffer
      ..writeln()
      ..writeln('Operation boundary:')
      ..writeln()
      ..writeln(
        '- `tccGrants`: ${mvpFinalSignoffRehearsal.operationBoundary['tccGrants']}',
      )
      ..writeln(
        '- `desktopActions`: ${mvpFinalSignoffRehearsal.operationBoundary['desktopActions']}',
      )
      ..writeln(
        '- `inputSmokeRequiresArming`: ${mvpFinalSignoffRehearsal.operationBoundary['inputSmokeRequiresArming']}',
      )
      ..writeln(
        '- `systemAudioSmokeRequiresArming`: ${mvpFinalSignoffRehearsal.operationBoundary['systemAudioSmokeRequiresArming']}',
      );
    if (mvpFinalSignoffRehearsal.finalAggregationCommand != null) {
      buffer
        ..writeln()
        ..writeln('Final MVP aggregation command:')
        ..writeln()
        ..writeln('```bash')
        ..writeln(mvpFinalSignoffRehearsal.finalAggregationCommand)
        ..writeln('```');
    }
    buffer
      ..writeln()
      ..writeln('| Required Artifact | Present | Path |')
      ..writeln('| --- | --- | --- |');
    for (final artifact in mvpFinalSignoffRehearsal.requiredArtifacts) {
      buffer.writeln(
        '| ${_markdownCell(artifact.label)} | ${artifact.exists} | `${_escapeMarkdownCode(artifact.path)}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## MVP Rehearsal Next Actions')
      ..writeln();
    if (mvpFinalSignoffRehearsal.nextActions.isEmpty) {
      buffer.writeln(
        '- All required input evidence is present. Run final MVP sign-off aggregation.',
      );
    } else {
      for (final action in mvpFinalSignoffRehearsal.nextActions) {
        buffer.writeln('- $action');
      }
    }
    return buffer.toString();
  }
}

class ReadinessFinalSignoffRehearsal {
  const ReadinessFinalSignoffRehearsal({
    required this.ready,
    required this.requiredArtifacts,
    required this.missingArtifactIds,
    required this.nextActions,
    required this.finalAggregationCommand,
    this.operationBoundary = MacosComputerUseOperationBoundary.values,
  });

  final bool ready;
  final List<ReadinessArtifactEntry> requiredArtifacts;
  final List<String> missingArtifactIds;
  final List<String> nextActions;
  final String? finalAggregationCommand;
  final Map<String, Object?> operationBoundary;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'requiredArtifacts': requiredArtifacts
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'missingArtifactIds': missingArtifactIds,
      'nextActions': nextActions,
      'finalAggregationCommand': finalAggregationCommand,
      'operationBoundary': operationBoundary,
    };
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
    _latestEntry(
      'mvp_llm_readiness',
      'Latest MVP LLM readiness summary',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_mvp_llm_readiness_summary',
      parentPrefix: 'macos_computer_use_mvp_llm_readiness_',
      fileName: 'mvp_llm_readiness_summary.json',
    ),
    _latestEntry(
      'mvp_demo_readiness',
      'Latest MVP demo readiness summary',
      reportRoot,
      (json) =>
          json['schemaName'] == 'macos_computer_use_mvp_demo_readiness_summary',
      parentPrefix: 'macos_computer_use_mvp_demo_readiness_',
      fileName: 'mvp_demo_readiness_summary.json',
    ),
  ];
  return ReadinessArtifactIndex(
    reportRoot: reportRoot.path,
    entries: List<ReadinessArtifactEntry>.unmodifiable(entries),
    mvpFinalSignoffRehearsal: _mvpFinalSignoffRehearsal(reportRoot, entries),
  );
}

ReadinessFinalSignoffRehearsal _mvpFinalSignoffRehearsal(
  Directory reportRoot,
  List<ReadinessArtifactEntry> entries,
) {
  final byId = <String, ReadinessArtifactEntry>{
    for (final entry in entries) entry.id: entry,
  };
  final requiredIds = MacosComputerUseMvpGuidance.requiredEvidenceIds;
  final requiredArtifacts = requiredIds
      .map((id) => byId[id])
      .whereType<ReadinessArtifactEntry>()
      .toList(growable: false);
  final missingArtifactIds = requiredArtifacts
      .where((entry) => !entry.exists)
      .map((entry) => entry.id)
      .toList(growable: false);
  final nextActions = missingArtifactIds
      .map(_mvpMissingArtifactNextAction)
      .toList(growable: false);
  final finalAggregationCommand = missingArtifactIds.isEmpty
      ? _mvpFinalAggregationCommand(reportRoot, byId)
      : null;
  return ReadinessFinalSignoffRehearsal(
    ready: missingArtifactIds.isEmpty,
    requiredArtifacts: List<ReadinessArtifactEntry>.unmodifiable(
      requiredArtifacts,
    ),
    missingArtifactIds: List<String>.unmodifiable(missingArtifactIds),
    nextActions: List<String>.unmodifiable(nextActions),
    finalAggregationCommand: finalAggregationCommand,
  );
}

String _mvpFinalAggregationCommand(
  Directory reportRoot,
  Map<String, ReadinessArtifactEntry> entriesById,
) {
  return <String>[
    'bash',
    'tool/run_macos_computer_use_mvp_signoff.sh',
    '--final-signoff',
    '--root',
    reportRoot.path,
    '--manual-tcc-report',
    entriesById['manual_tcc']?.path ?? '',
    '--desktop-action-canary-summary',
    entriesById['desktop_action_canary']?.path ?? '',
    '--llm-canary-summary',
    entriesById['llm_canary']?.path ?? '',
  ].map(_shellQuote).join(' ');
}

String _mvpMissingArtifactNextAction(String artifactId) {
  switch (artifactId) {
    case 'release_artifact':
      return 'Refresh safe release inputs with `bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-safe-inputs`.';
    case 'canary_history':
      return 'Run the automation-safe Computer Use canary or safe readiness refresh to produce `macos_computer_use_canary_history.json`.';
    case 'manual_tcc':
      return MacosComputerUseMvpGuidance.manualTccNextAction;
    case 'desktop_action_canary':
      return MacosComputerUseMvpGuidance.desktopActionCanaryNextAction;
    case 'llm_canary':
      return MacosComputerUseMvpGuidance.llmCanaryNextAction;
    default:
      return 'Provide the missing `$artifactId` artifact before final sign-off aggregation.';
  }
}

Future<ReadinessArtifactIndex> writeReadinessArtifactIndex(
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
  return index;
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

String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (RegExp(r'^[A-Za-z0-9_./:=@%+-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}
