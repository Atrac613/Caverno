import 'dart:convert';
import 'dart:io';

class MacosComputerUseReleaseSigningPreflightCheck {
  const MacosComputerUseReleaseSigningPreflightCheck({
    required this.id,
    required this.label,
    required this.ok,
    required this.nextAction,
    this.details = const <String, Object?>{},
  });

  final String id;
  final String label;
  final bool ok;
  final String nextAction;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'ok': ok,
      'nextAction': nextAction,
      if (details.isNotEmpty) 'details': details,
    };
  }
}

class MacosComputerUseReleaseSigningPreflightReport {
  const MacosComputerUseReleaseSigningPreflightReport({
    required this.status,
    required this.ready,
    required this.projectRoot,
    required this.checks,
    required this.operationBoundary,
  });

  final String status;
  final bool ready;
  final String projectRoot;
  final List<MacosComputerUseReleaseSigningPreflightCheck> checks;
  final String operationBoundary;

  List<MacosComputerUseReleaseSigningPreflightCheck> get failedChecks =>
      checks.where((check) => !check.ok).toList(growable: false);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_release_signing_preflight',
      'schemaVersion': 1,
      'status': status,
      'ready': ready,
      'projectRoot': projectRoot,
      'checks': checks.map((check) => check.toJson()).toList(growable: false),
      'failedCheckIds': failedChecks
          .map((check) => check.id)
          .toList(growable: false),
      'operationBoundary': operationBoundary,
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use Release Signing Preflight')
      ..writeln()
      ..writeln('- Status: $status')
      ..writeln('- Ready: $ready')
      ..writeln('- Project root: `$projectRoot`')
      ..writeln('- Operation boundary: $operationBoundary')
      ..writeln()
      ..writeln('| Check | Ready | Next Action |')
      ..writeln('| --- | --- | --- |');
    for (final check in checks) {
      buffer.writeln(
        '| ${_markdownCell(check.label)} | ${check.ok} | ${_markdownCell(check.nextAction)} |',
      );
    }
    return buffer.toString();
  }
}

MacosComputerUseReleaseSigningPreflightReport
buildMacosComputerUseReleaseSigningPreflight({
  Directory? projectRoot,
  List<String> codeSigningIdentities = const <String>[],
}) {
  final root = projectRoot ?? Directory.current;
  final signingLocal = File(
    '${root.path}/macos/Runner/Configs/Signing.local.xcconfig',
  );
  final signingLocalTemplate = File(
    '${root.path}/macos/Runner/Configs/Signing.local.xcconfig.example',
  );
  final gitignore = File('${root.path}/.gitignore');
  final gitignoreContent = gitignore.existsSync()
      ? gitignore.readAsStringSync()
      : null;
  final signingLocalContent = signingLocal.existsSync()
      ? signingLocal.readAsStringSync()
      : null;
  final ignoresSigningLocal =
      gitignoreContent != null &&
      RegExp(
        r'^\s*/?macos/Runner/Configs/Signing\.local\.xcconfig\s*$',
        multiLine: true,
      ).hasMatch(gitignoreContent);
  final hasDevelopmentTeam =
      signingLocalContent != null &&
      RegExp(
        r'^\s*DEVELOPMENT_TEAM\s*=',
        multiLine: true,
      ).hasMatch(signingLocalContent);
  final hasCodeSignIdentity =
      signingLocalContent != null &&
      RegExp(
        r'^\s*CODE_SIGN_IDENTITY\s*=',
        multiLine: true,
      ).hasMatch(signingLocalContent);
  final validIdentities = codeSigningIdentities
      .where((line) => line.trim().isNotEmpty && !line.contains('0 valid'))
      .toList(growable: false);
  final checks = <MacosComputerUseReleaseSigningPreflightCheck>[
    _check(
      id: 'signing_local_template',
      label: 'Local signing template',
      ok: signingLocalTemplate.existsSync(),
      nextAction:
          'Keep macos/Runner/Configs/Signing.local.xcconfig.example checked in as the local signing setup template.',
      details: <String, Object?>{'path': signingLocalTemplate.path},
    ),
    _check(
      id: 'signing_local_gitignore',
      label: 'Local signing gitignore guard',
      ok: ignoresSigningLocal,
      nextAction:
          'Add macos/Runner/Configs/Signing.local.xcconfig to .gitignore before creating local signing overrides.',
      details: <String, Object?>{'path': gitignore.path},
    ),
    _check(
      id: 'signing_local_config',
      label: 'Local signing override',
      ok: signingLocalContent != null,
      nextAction:
          'Create macos/Runner/Configs/Signing.local.xcconfig with local release signing overrides.',
      details: <String, Object?>{'path': signingLocal.path},
    ),
    _check(
      id: 'development_team',
      label: 'Development team',
      ok: hasDevelopmentTeam,
      nextAction:
          'Add DEVELOPMENT_TEAM to macos/Runner/Configs/Signing.local.xcconfig.',
    ),
    _check(
      id: 'code_sign_identity',
      label: 'Code sign identity override',
      ok: hasCodeSignIdentity,
      nextAction:
          'Add a non-ad-hoc CODE_SIGN_IDENTITY to macos/Runner/Configs/Signing.local.xcconfig.',
    ),
    _check(
      id: 'keychain_code_signing_identity',
      label: 'Keychain code signing identity',
      ok: validIdentities.isNotEmpty,
      nextAction:
          'Install or select a valid macOS code signing identity, then verify `security find-identity -v -p codesigning` lists it.',
      details: <String, Object?>{'identityCount': validIdentities.length},
    ),
  ];
  final ready = checks.every((check) => check.ok);
  return MacosComputerUseReleaseSigningPreflightReport(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    projectRoot: root.path,
    checks: List<MacosComputerUseReleaseSigningPreflightCheck>.unmodifiable(
      checks,
    ),
    operationBoundary:
        'report-only signing setup check; it does not sign, notarize, staple, grant TCC, or operate desktop apps.',
  );
}

String encodeReleaseSigningPreflightJson(
  MacosComputerUseReleaseSigningPreflightReport report,
) {
  return const JsonEncoder.withIndent('  ').convert(report.toJson());
}

MacosComputerUseReleaseSigningPreflightCheck _check({
  required String id,
  required String label,
  required bool ok,
  required String nextAction,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  return MacosComputerUseReleaseSigningPreflightCheck(
    id: id,
    label: label,
    ok: ok,
    nextAction: ok ? 'No action required.' : nextAction,
    details: details,
  );
}

String _markdownCell(Object? value) {
  return value.toString().replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
