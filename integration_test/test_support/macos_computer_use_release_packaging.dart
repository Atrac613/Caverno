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
  final appInfoConfig = _read(root, 'macos/Runner/Configs/AppInfo.xcconfig');
  final signingLocalExample = _read(
    root,
    'macos/Runner/Configs/Signing.local.xcconfig.example',
  );
  final podfile = _read(root, 'macos/Podfile');
  final runnerReleaseEntitlements = _read(
    root,
    'macos/Runner/Release.entitlements',
  );
  final helperReleaseEntitlements = _read(
    root,
    'macos/ComputerUseHelper/Release.entitlements',
  );
  final runnerInfoPlist = _read(root, 'macos/Runner/Info.plist');
  final helperInfoPlist = _read(root, 'macos/ComputerUseHelper/Info.plist');
  final sparkleBuildScript = _read(root, 'tool/build_macos_sparkle_release.sh');
  final sparkleStagingRehearsalScript = _read(
    root,
    'tool/run_macos_sparkle_staging_rehearsal.sh',
  );
  final sparkleStagingReleaseNotes = _read(
    root,
    'docs/releases/caverno-staging.md',
  );
  final sparklePublishScript = _read(
    root,
    'tool/publish_macos_sparkle_release.sh',
  );
  final sparkleS3PreflightScript = _read(
    root,
    'tool/run_macos_sparkle_s3_preflight.sh',
  );
  final sparkleS3PublicReadScript = _read(
    root,
    'tool/configure_macos_sparkle_s3_public_read.sh',
  );
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
          runnerInfoPlist?.contains(
                '<key>NSAudioCaptureUsageDescription</key>',
              ) ==
              true &&
          helperInfoPlist?.contains('<key>LSUIElement</key>') == true &&
          helperInfoPlist?.contains(
                '<key>NSAudioCaptureUsageDescription</key>',
              ) ==
              true,
      nextAction:
          'Keep Caverno.app as the Screen & System Audio Recording owner and Caverno Computer Use as a hidden agent bundle.',
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
          signingConfig?.contains('CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO') ==
              true &&
          signingConfig?.contains('Signing.local.xcconfig') == true &&
          signingConfig?.contains('DEVELOPMENT_TEAM =') != true,
      nextAction:
          'Keep repository defaults identity-free and place local release signing overrides in Signing.local.xcconfig.',
    ),
    _check(
      id: 'release_signing_delegates_to_local_config',
      label: 'Release signing delegates to local config',
      ok:
          !_namedBuildConfigsContain(
            pbxproj,
            'Release',
            'CODE_SIGN_IDENTITY = "Apple Development";',
          ) &&
          !_namedBuildConfigsContain(
            pbxproj,
            'Profile',
            'CODE_SIGN_IDENTITY = "Apple Development";',
          ) &&
          !_namedBuildConfigsContain(
            pbxproj,
            'Release',
            'DEVELOPMENT_TEAM = 89UG59TBNX;',
          ) &&
          !_namedBuildConfigsContain(
            pbxproj,
            'Profile',
            'DEVELOPMENT_TEAM = 89UG59TBNX;',
          ) &&
          !_namedBuildConfigsContain(
            pbxproj,
            'Release',
            'CODE_SIGN_STYLE = Automatic;',
          ) &&
          !_namedBuildConfigsContain(
            pbxproj,
            'Profile',
            'CODE_SIGN_STYLE = Automatic;',
          ),
      nextAction:
          'Keep Release and Profile signing identity, style, and team values out of the Xcode project so Signing.local.xcconfig controls Developer ID release signing.',
    ),
    _check(
      id: 'sparkle_dependency',
      label: 'Sparkle update dependency',
      ok: podfile?.contains("pod 'Sparkle', '~> 2.9'") == true,
      nextAction:
          'Keep Sparkle 2 available to the macOS Runner target through CocoaPods.',
      details: <String, Object?>{'path': 'macos/Podfile'},
    ),
    _check(
      id: 'sparkle_appcast_configuration',
      label: 'Sparkle appcast configuration',
      ok:
          runnerInfoPlist?.contains('<key>SUFeedURL</key>') == true &&
          runnerInfoPlist?.contains('<key>SUPublicEDKey</key>') == true &&
          runnerInfoPlist?.contains('<key>SUEnableAutomaticChecks</key>') ==
              true &&
          runnerInfoPlist?.contains('<key>SUScheduledCheckInterval</key>') ==
              true &&
          runnerInfoPlist?.contains('<integer>3600</integer>') == true &&
          appInfoConfig?.contains('SPARKLE_FEED_URL =') == true &&
          appInfoConfig?.contains('SPARKLE_PUBLIC_ED_KEY =') == true &&
          _appearsBefore(
            appInfoConfig,
            'SPARKLE_PUBLIC_ED_KEY =',
            '#include "Signing.xcconfig"',
          ) &&
          signingLocalExample?.contains('SPARKLE_FEED_URL') == true &&
          signingLocalExample?.contains('SPARKLE_PUBLIC_ED_KEY') == true,
      nextAction:
          'Keep release appcast URL and public EdDSA key injected through local signing configuration.',
      details: <String, Object?>{'path': 'macos/Runner/Info.plist'},
    ),
    _check(
      id: 'sparkle_publish_script',
      label: 'Sparkle S3 publish script',
      ok:
          sparklePublishScript?.contains('generate_appcast') == true &&
          sparklePublishScript?.contains('run_generate_appcast') == true &&
          sparklePublishScript?.contains('SUPublicEDKey.*does not match') ==
              true &&
          sparklePublishScript?.contains('lack of private EdDSA key') == true &&
          sparklePublishScript?.contains('--download-url-prefix') == true &&
          sparklePublishScript?.contains('aws') == true &&
          sparklePublishScript?.contains('s3 sync') == true &&
          sparklePublishScript?.contains('no-cache,max-age=0') == true,
      nextAction:
          'Use tool/publish_macos_sparkle_release.sh after signing, notarization, and stapling.',
      details: <String, Object?>{
        'path': 'tool/publish_macos_sparkle_release.sh',
      },
    ),
    _check(
      id: 'sparkle_s3_preflight',
      label: 'Sparkle S3 preflight',
      ok:
          sparkleS3PreflightScript?.contains(
                's3://caverno-macos-releases/caverno/macos',
              ) ==
              true &&
          sparkleS3PreflightScript?.contains('s3 ls') == true &&
          sparkleS3PreflightScript?.contains('head-bucket') == true &&
          sparkleS3PreflightScript?.contains('s3 cp') == true &&
          sparkleS3PreflightScript?.contains('--dryrun') == true &&
          sparkleS3PreflightScript?.contains('BlockPublicPolicy=false') ==
              true &&
          sparkleS3PreflightScript?.contains('get-public-access-block') == true,
      nextAction:
          'Use tool/run_macos_sparkle_s3_preflight.sh before the first real S3 publish.',
      details: <String, Object?>{
        'path': 'tool/run_macos_sparkle_s3_preflight.sh',
      },
    ),
    _check(
      id: 'sparkle_s3_public_read_config',
      label: 'Sparkle S3 public read config',
      ok:
          sparkleS3PublicReadScript?.contains(
                's3://caverno-macos-releases/caverno/macos',
              ) ==
              true &&
          sparkleS3PublicReadScript?.contains('--apply') == true &&
          sparkleS3PublicReadScript?.contains('put-public-access-block') ==
              true &&
          sparkleS3PublicReadScript?.contains('put-bucket-policy') == true &&
          sparkleS3PublicReadScript?.contains(
                'PublicReadCavernoMacosUpdates',
              ) ==
              true,
      nextAction:
          'Use tool/configure_macos_sparkle_s3_public_read.sh to review or apply direct-S3 public read settings.',
      details: <String, Object?>{
        'path': 'tool/configure_macos_sparkle_s3_public_read.sh',
      },
    ),
    _check(
      id: 'sparkle_release_driver',
      label: 'Sparkle release driver',
      ok:
          sparkleBuildScript?.contains('build macos --release') == true &&
          sparkleBuildScript?.contains('resign_sparkle_updater_components') ==
              true &&
          sparkleBuildScript?.contains('XPCServices/Downloader.xpc') == true &&
          sparkleBuildScript?.contains('XPCServices/Installer.xpc') == true &&
          sparkleBuildScript?.contains('Updater.app') == true &&
          sparkleBuildScript?.contains('Autoupdate') == true &&
          sparkleBuildScript?.contains(
                'Contents/Helpers/Caverno Computer Use.app',
              ) ==
              true &&
          sparkleBuildScript?.contains('CAVERNO_MACOS_CODESIGN_IDENTITY') ==
              true &&
          sparkleBuildScript?.contains('notarytool submit') == true &&
          sparkleBuildScript?.contains('stapler staple') == true &&
          sparkleBuildScript?.contains('stapler validate') == true &&
          sparkleBuildScript?.contains('codesign --verify --deep --strict') ==
              true &&
          sparkleBuildScript?.contains(
                'verify_sparkle_release_configuration',
              ) ==
              true &&
          sparkleBuildScript?.contains('SUFeedURL does not match') == true &&
          sparkleBuildScript?.contains('SUPublicEDKey') == true &&
          sparkleBuildScript?.contains('publish_macos_sparkle_release.sh') ==
              true &&
          sparkleBuildScript?.contains('--skip-notarization') == true &&
          sparkleBuildScript?.contains('--skip-publish') == true,
      nextAction:
          'Use tool/build_macos_sparkle_release.sh to build, notarize, package, and publish Sparkle release artifacts.',
      details: <String, Object?>{'path': 'tool/build_macos_sparkle_release.sh'},
    ),
    _check(
      id: 'sparkle_staging_rehearsal',
      label: 'Sparkle staging rehearsal',
      ok:
          sparkleStagingRehearsalScript?.contains(
                'build_macos_sparkle_release.sh',
              ) ==
              true &&
          sparkleStagingRehearsalScript?.contains('--dry-run') == true &&
          sparkleStagingRehearsalScript?.contains(
                'https://updates.example.invalid/caverno/macos/staging',
              ) ==
              true &&
          sparkleStagingRehearsalScript?.contains(
                's3://caverno-macos-releases/caverno/macos/staging',
              ) ==
              true &&
          sparkleStagingReleaseNotes?.contains(
                'Caverno macOS Staging Release Notes',
              ) ==
              true,
      nextAction:
          'Use tool/run_macos_sparkle_staging_rehearsal.sh for no-upload Sparkle publish path rehearsals.',
      details: <String, Object?>{
        'path': 'tool/run_macos_sparkle_staging_rehearsal.sh',
      },
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

bool _appearsBefore(String? text, String first, String second) {
  if (text == null) {
    return false;
  }
  final firstIndex = text.indexOf(first);
  final secondIndex = text.indexOf(second);
  return firstIndex >= 0 && secondIndex >= 0 && firstIndex < secondIndex;
}

bool _namedBuildConfigsContain(
  String? text,
  String configurationName,
  String pattern,
) {
  if (text == null || pattern.isEmpty) {
    return false;
  }
  return _nativeTargetBuildConfigBodies(
    text,
    configurationName,
  ).any((body) => body.contains(pattern));
}

Iterable<String> _nativeTargetBuildConfigBodies(
  String text,
  String configurationName,
) sync* {
  final configurationIds = _nativeTargetBuildConfigurationIds(
    text,
    configurationName,
  );
  for (final id in configurationIds) {
    final header = RegExp(
      RegExp.escape(id) +
          r' /\* ' +
          RegExp.escape(configurationName) +
          r' \*/ = \{',
    ).firstMatch(text);
    if (header == null) {
      continue;
    }
    final namePattern = RegExp(
      r'\n\s*name = ' + RegExp.escape(configurationName) + r';\n\s*\};',
    );
    final start = header.end;
    final endMatch = namePattern.firstMatch(text.substring(start));
    if (endMatch == null) {
      continue;
    }
    yield text.substring(start, start + endMatch.start);
  }
}

Set<String> _nativeTargetBuildConfigurationIds(
  String text,
  String configurationName,
) {
  const nativeTargets = <String>{'Runner', 'Caverno Computer Use'};
  final targetPattern = RegExp(
    r'/\* Build configuration list for PBXNativeTarget "([^"]+)" \*/ = \{'
    r'[\s\S]*?buildConfigurations = \(\n([\s\S]*?)\n\s*\);',
  );
  final entryPattern = RegExp(
    r'^\s*([A-F0-9]+) /\* ' + RegExp.escape(configurationName) + r' \*/,',
    multiLine: true,
  );
  return targetPattern
      .allMatches(text)
      .where((match) => nativeTargets.contains(match.group(1)))
      .expand((match) => entryPattern.allMatches(match.group(2) ?? ''))
      .map((match) => match.group(1))
      .whereType<String>()
      .toSet();
}

String encodeReleasePackagingJson(
  MacosComputerUseReleasePackagingReport report,
) {
  return const JsonEncoder.withIndent('  ').convert(report.toJson());
}

String _markdownCell(Object? value) {
  return value.toString().replaceAll('|', r'\|').replaceAll('\n', '<br>');
}
