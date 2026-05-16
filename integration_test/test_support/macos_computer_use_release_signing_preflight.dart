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
  final developmentTeam = _xcconfigValue(
    signingLocalContent,
    'DEVELOPMENT_TEAM',
  );
  final codeSignIdentity = _xcconfigValue(
    signingLocalContent,
    'CODE_SIGN_IDENTITY',
  );
  final developmentTeamReady = _validDevelopmentTeam(developmentTeam);
  final codeSignIdentityReady = _validCodeSignIdentity(codeSignIdentity);
  final validIdentities = codeSigningIdentities
      .where((line) => line.trim().isNotEmpty && !line.contains('0 valid'))
      .toList(growable: false);
  final matchingIdentityCount = codeSignIdentityReady
      ? _matchingIdentityCount(codeSignIdentity!, validIdentities)
      : 0;
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
          'Copy macos/Runner/Configs/Signing.local.xcconfig.example to the ignored macos/Runner/Configs/Signing.local.xcconfig, then set local release signing overrides.',
      details: <String, Object?>{
        'path': signingLocal.path,
        'templatePath': signingLocalTemplate.path,
      },
    ),
    _check(
      id: 'development_team',
      label: 'Development team',
      ok: developmentTeamReady,
      nextAction:
          'Add a concrete 10-character DEVELOPMENT_TEAM to macos/Runner/Configs/Signing.local.xcconfig.',
      details: <String, Object?>{
        'configured': developmentTeam != null,
        'valueStatus': _developmentTeamStatus(developmentTeam),
      },
    ),
    _check(
      id: 'code_sign_identity',
      label: 'Code sign identity override',
      ok: codeSignIdentityReady,
      nextAction:
          'Add a non-ad-hoc CODE_SIGN_IDENTITY to macos/Runner/Configs/Signing.local.xcconfig.',
      details: <String, Object?>{
        'configured': codeSignIdentity != null,
        'valueStatus': _codeSignIdentityStatus(codeSignIdentity),
      },
    ),
    _check(
      id: 'keychain_code_signing_identity',
      label: 'Keychain code signing identity',
      ok: validIdentities.isNotEmpty,
      nextAction:
          'Install or select a valid macOS code signing identity, then verify `security find-identity -v -p codesigning` lists it.',
      details: <String, Object?>{'identityCount': validIdentities.length},
    ),
    _check(
      id: 'code_sign_identity_keychain_match',
      label: 'Code sign identity keychain match',
      ok: matchingIdentityCount > 0,
      nextAction:
          'Set CODE_SIGN_IDENTITY to a non-ad-hoc identity that appears in `security find-identity -v -p codesigning`.',
      details: <String, Object?>{'matchCount': matchingIdentityCount},
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

String? _xcconfigValue(String? content, String key) {
  if (content == null) {
    return null;
  }
  final match = RegExp(
    '^\\s*${RegExp.escape(key)}\\s*=\\s*(.*?)\\s*\$',
    multiLine: true,
  ).firstMatch(content);
  final value = match?.group(1)?.trim();
  if (value == null || value.isEmpty) {
    return value;
  }
  return value;
}

bool _validDevelopmentTeam(String? value) {
  return _developmentTeamStatus(value) == 'valid';
}

String _developmentTeamStatus(String? value) {
  if (value == null) {
    return 'missing';
  }
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return 'empty';
  }
  if (normalized == 'YOURTEAMID') {
    return 'placeholder';
  }
  if (!RegExp(r'^[A-Z0-9]{10}$').hasMatch(normalized)) {
    return 'invalid_format';
  }
  return 'valid';
}

bool _validCodeSignIdentity(String? value) {
  return _codeSignIdentityStatus(value) == 'valid';
}

String _codeSignIdentityStatus(String? value) {
  if (value == null) {
    return 'missing';
  }
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return 'empty';
  }
  if (normalized == '-' ||
      normalized.toLowerCase() == 'ad hoc' ||
      normalized.toLowerCase() == 'sign to run locally') {
    return 'ad_hoc';
  }
  return 'valid';
}

int _matchingIdentityCount(String configuredIdentity, List<String> identities) {
  final normalizedIdentity = configuredIdentity.toLowerCase();
  return identities
      .where((identity) => identity.toLowerCase().contains(normalizedIdentity))
      .length;
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
