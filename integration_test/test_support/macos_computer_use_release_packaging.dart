import 'dart:convert';
import 'dart:io';

class MacosComputerUseReleasePackagingCheck {
  const MacosComputerUseReleasePackagingCheck({
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

class MacosComputerUseReleasePackagingReport {
  const MacosComputerUseReleasePackagingReport({
    required this.status,
    required this.ready,
    required this.projectRoot,
    required this.checks,
    required this.externalEvidence,
  });

  final String status;
  final bool ready;
  final String projectRoot;
  final List<MacosComputerUseReleasePackagingCheck> checks;
  final Map<String, Object?> externalEvidence;

  List<MacosComputerUseReleasePackagingCheck> get failedChecks =>
      checks.where((check) => !check.ok).toList(growable: false);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaName': 'macos_computer_use_m33_release_packaging',
      'schemaVersion': 1,
      'milestone': 'M33',
      'status': status,
      'ready': ready,
      'projectRoot': projectRoot,
      'checks': checks.map((check) => check.toJson()).toList(growable: false),
      'failedCheckIds': failedChecks
          .map((check) => check.id)
          .toList(growable: false),
      'externalEvidence': externalEvidence,
      'automationBoundary':
          'Static packaging checks only; signing identity, notarization, and TCC remain user-operated release steps.',
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# macOS Computer Use M33 Release Packaging')
      ..writeln()
      ..writeln('- Status: $status')
      ..writeln('- Ready: $ready')
      ..writeln('- Project root: `$projectRoot`')
      ..writeln(
        '- Automation boundary: static packaging checks only; signing identity, notarization, and TCC remain user-operated release steps.',
      )
      ..writeln()
      ..writeln('| Check | Ready | Next Action |')
      ..writeln('| --- | --- | --- |');
    for (final check in checks) {
      buffer.writeln(
        '| ${_markdownCell(check.label)} | ${check.ok} | ${_markdownCell(check.nextAction)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## External Release Evidence')
      ..writeln()
      ..writeln('- Signing identity: ${externalEvidence['signingIdentity']}')
      ..writeln('- Codesign verification: ${externalEvidence['codesign']}')
      ..writeln('- Notarization ticket: ${externalEvidence['notarization']}')
      ..writeln('- Stapler validation: ${externalEvidence['stapler']}');
    return buffer.toString();
  }
}

MacosComputerUseReleasePackagingReport buildMacosComputerUseReleasePackaging({
  Directory? projectRoot,
}) {
  final root = projectRoot ?? Directory.current;
  final pbxproj = _read(root, 'macos/Runner.xcodeproj/project.pbxproj');
  final signingConfig = _read(root, 'macos/Runner/Configs/Signing.xcconfig');
  final runnerReleaseEntitlements = _read(
    root,
    'macos/Runner/Release.entitlements',
  );
  final helperReleaseEntitlements = _read(
    root,
    'macos/ComputerUseHelper/Release.entitlements',
  );
  final helperInfoPlist = _read(root, 'macos/ComputerUseHelper/Info.plist');
  final launchAgent = _read(
    root,
    'macos/Runner/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist',
  );

  final checks = <MacosComputerUseReleasePackagingCheck>[
    _check(
      id: 'main_release_entitlements',
      label: 'Main app release entitlements',
      ok:
          runnerReleaseEntitlements != null &&
          pbxproj?.contains(
                'CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;',
              ) ==
              true,
      nextAction:
          'Keep Runner/Release.entitlements referenced by the Runner release configuration.',
      details: <String, Object?>{'path': 'macos/Runner/Release.entitlements'},
    ),
    _check(
      id: 'helper_release_entitlements',
      label: 'Helper release entitlements',
      ok:
          helperReleaseEntitlements != null &&
          pbxproj?.contains(
                'CODE_SIGN_ENTITLEMENTS = ComputerUseHelper/Release.entitlements;',
              ) ==
              true,
      nextAction:
          'Keep ComputerUseHelper/Release.entitlements referenced by release and profile helper builds.',
      details: <String, Object?>{
        'path': 'macos/ComputerUseHelper/Release.entitlements',
      },
    ),
    _check(
      id: 'hardened_runtime',
      label: 'Hardened runtime release settings',
      ok: _count(pbxproj, 'ENABLE_HARDENED_RUNTIME = YES;') >= 4,
      nextAction:
          'Enable hardened runtime for Runner and Caverno Computer Use release/profile configurations.',
    ),
    _check(
      id: 'helper_bundle_identity',
      label: 'Helper bundle identity',
      ok:
          pbxproj?.contains(
                'PRODUCT_BUNDLE_IDENTIFIER = "com.noguwo.apps.caverno.computer-use";',
              ) ==
              true &&
          helperInfoPlist?.contains('<key>LSUIElement</key>') == true &&
          helperInfoPlist?.contains(
                '<key>NSSystemAudioUsageDescription</key>',
              ) ==
              true,
      nextAction:
          'Keep Caverno Computer Use as a hidden agent bundle with system audio usage copy.',
    ),
    _check(
      id: 'launch_agent_mach_service',
      label: 'LaunchAgent Mach service',
      ok:
          launchAgent?.contains(
                '<string>com.noguwo.apps.caverno.computer-use</string>',
              ) ==
              true &&
          launchAgent?.contains(
                '<string>Contents/Helpers/Caverno Computer Use.app/Contents/MacOS/Caverno Computer Use</string>',
              ) ==
              true &&
          launchAgent?.contains(
                '<key>com.noguwo.apps.caverno.computer-use.xpc</key>',
              ) ==
              true &&
          launchAgent?.contains('<string>com.noguwo.apps.caverno</string>') ==
              true,
      nextAction:
          'Keep the bundled LaunchAgent label, BundleProgram, MachServices, and associated main bundle aligned.',
      details: <String, Object?>{
        'path':
            'macos/Runner/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist',
      },
    ),
    _check(
      id: 'embed_helper_phase',
      label: 'Embed helper build phase',
      ok:
          pbxproj?.contains('Embed Computer Use Helper') == true &&
          pbxproj?.contains(
                r'$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/Caverno Computer Use.app',
              ) ==
              true &&
          pbxproj?.contains(
                r'$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist',
              ) ==
              true &&
          pbxproj?.contains(r'ditto \"$HELPER_APP\"') == true &&
          pbxproj?.contains(r'ditto \"$LAUNCH_AGENT_SOURCE\"') == true,
      nextAction:
          'Keep the Runner build phase copying the helper and LaunchAgent into the release app bundle.',
    ),
    _check(
      id: 'identity_free_signing_defaults',
      label: 'Identity-free signing defaults',
      ok:
          signingConfig?.contains('CODE_SIGN_STYLE = Automatic') == true &&
          signingConfig?.contains('Signing.local.xcconfig') == true &&
          signingConfig?.contains('DEVELOPMENT_TEAM =') != true,
      nextAction:
          'Keep repository defaults identity-free and place local release signing overrides in Signing.local.xcconfig.',
    ),
  ];
  final ready = checks.every((check) => check.ok);
  return MacosComputerUseReleasePackagingReport(
    status: ready ? 'ready' : 'blocked',
    ready: ready,
    projectRoot: root.path,
    checks: List<MacosComputerUseReleasePackagingCheck>.unmodifiable(checks),
    externalEvidence: const <String, Object?>{
      'signingIdentity': 'user_operated_release_pipeline',
      'codesign': 'validated by M7 release artifact sign-off',
      'notarization': 'required before production distribution',
      'stapler': 'required after notarization',
    },
  );
}

MacosComputerUseReleasePackagingCheck _check({
  required String id,
  required String label,
  required bool ok,
  required String nextAction,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  return MacosComputerUseReleasePackagingCheck(
    id: id,
    label: label,
    ok: ok,
    nextAction: nextAction,
    details: details,
  );
}

String? _read(Directory root, String relativePath) {
  final file = File('${root.path}/$relativePath');
  if (!file.existsSync()) {
    return null;
  }
  return file.readAsStringSync();
}

int _count(String? text, String pattern) {
  if (text == null || pattern.isEmpty) {
    return 0;
  }
  var count = 0;
  var start = 0;
  while (true) {
    final index = text.indexOf(pattern, start);
    if (index < 0) {
      return count;
    }
    count += 1;
    start = index + pattern.length;
  }
}

String encodeReleasePackagingJson(
  MacosComputerUseReleasePackagingReport report,
) {
  return const JsonEncoder.withIndent('  ').convert(report.toJson());
}

String _markdownCell(Object? value) {
  return value.toString().replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
