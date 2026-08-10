import 'dart:convert';
import 'dart:io';

final class RemoteCodingFcmReleaseGate {
  const RemoteCodingFcmReleaseGate({
    required this.id,
    required this.status,
    required this.evidence,
    required this.nextAction,
    this.userOperated = false,
  });

  final String id;
  final String status;
  final String evidence;
  final String nextAction;
  final bool userOperated;

  bool get isReady => status == 'ready';

  Map<String, Object> toJson() => {
    'id': id,
    'status': status,
    'evidence': evidence,
    'nextAction': nextAction,
    'userOperated': userOperated,
  };
}

final class RemoteCodingFcmReleaseGateResult {
  const RemoteCodingFcmReleaseGateResult({
    required this.generatedAt,
    required this.gates,
  });

  final DateTime generatedAt;
  final List<RemoteCodingFcmReleaseGate> gates;

  List<String> get blockedGateIds => [
    for (final gate in gates)
      if (!gate.isReady) gate.id,
  ];

  String get status => blockedGateIds.isEmpty
      ? 'ready_for_remote_coding_fcm_release'
      : 'blocked';

  Map<String, Object> toJson() => {
    'schemaName': 'remote_coding_fcm_release_gate',
    'schemaVersion': 1,
    'generatedAt': generatedAt.toIso8601String(),
    'status': status,
    'blockedGateIds': blockedGateIds,
    'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Remote Coding FCM Release Gate')
      ..writeln()
      ..writeln('- Status: `$status`')
      ..writeln('- Generated at: `${generatedAt.toIso8601String()}`');
    for (final gate in gates) {
      buffer
        ..writeln()
        ..writeln('## `${gate.id}`: `${gate.status}`')
        ..writeln()
        ..writeln('- Evidence: ${gate.evidence}')
        ..writeln('- Next action: ${gate.nextAction}');
    }
    return buffer.toString();
  }
}

RemoteCodingFcmReleaseGateResult buildRemoteCodingFcmReleaseGate({
  required Directory repoRoot,
  File? manualChecklistFile,
  DateTime? generatedAt,
}) {
  final checklist = _readChecklist(manualChecklistFile);
  final gates = <RemoteCodingFcmReleaseGate>[
    _platformCapabilityGate(repoRoot),
    _firebaseAppConfigurationGate(repoRoot),
    _relayImplementationGate(repoRoot),
    _manualGate(
      id: 'firebase_deployment',
      checklist: checklist,
      requiredPaths: const [
        'firebaseDeployment.projectSelected',
        'firebaseDeployment.firestoreEnabled',
        'firebaseDeployment.appCheckEnforcedIos',
        'firebaseDeployment.appCheckEnforcedAndroid',
        'firebaseDeployment.apnsAuthenticationKeyUploaded',
        'firebaseDeployment.relayDeployed',
        'firebaseDeployment.replayTtlEnabled',
        'firebaseDeployment.relayHealthVerified',
        'firebaseDeployment.releaseRelayOriginConfigured',
      ],
      nextAction:
          'Deploy and verify the Firebase relay, App Check, APNs, TTL, and release relay origin.',
    ),
    _manualGate(
      id: 'physical_device_delivery_matrix',
      checklist: checklist,
      requiredPaths: const [
        'physicalDeviceMatrix.iosForeground',
        'physicalDeviceMatrix.iosBackground',
        'physicalDeviceMatrix.iosLocked',
        'physicalDeviceMatrix.iosTerminated',
        'physicalDeviceMatrix.androidForeground',
        'physicalDeviceMatrix.androidBackground',
        'physicalDeviceMatrix.androidLocked',
        'physicalDeviceMatrix.androidTerminated',
        'physicalDeviceMatrix.tapOpensMatchingThread',
        'physicalDeviceMatrix.tokenRotation',
        'physicalDeviceMatrix.permissionDenied',
        'physicalDeviceMatrix.registrationRevocation',
        'physicalDeviceMatrix.relayOutageDoesNotAffectCoding',
      ],
      nextAction:
          'Run the FCM completion-notification matrix on signed iOS and Android physical devices.',
    ),
    _manualGate(
      id: 'release_signing_push_entitlements',
      checklist: checklist,
      requiredPaths: const [
        'releaseSigning.iosDistributionPushEntitlementVerified',
        'releaseSigning.androidReleaseFirebaseResourcesVerified',
        'releaseSigning.lockScreenContentIsGeneric',
      ],
      nextAction:
          'Inspect signed release artifacts and verify generic lock-screen content.',
    ),
  ];
  return RemoteCodingFcmReleaseGateResult(
    generatedAt: generatedAt ?? DateTime.now().toUtc(),
    gates: gates,
  );
}

Map<String, Object> remoteCodingFcmManualChecklistTemplate({
  DateTime? generatedAt,
}) => {
  'schemaName': 'remote_coding_fcm_manual_checklist',
  'schemaVersion': 1,
  'generatedAt': (generatedAt ?? DateTime.now().toUtc()).toIso8601String(),
  'firebaseDeployment': {
    'projectSelected': false,
    'firestoreEnabled': false,
    'appCheckEnforcedIos': false,
    'appCheckEnforcedAndroid': false,
    'apnsAuthenticationKeyUploaded': false,
    'relayDeployed': false,
    'replayTtlEnabled': false,
    'relayHealthVerified': false,
    'releaseRelayOriginConfigured': false,
  },
  'physicalDeviceMatrix': {
    'iosForeground': false,
    'iosBackground': false,
    'iosLocked': false,
    'iosTerminated': false,
    'androidForeground': false,
    'androidBackground': false,
    'androidLocked': false,
    'androidTerminated': false,
    'tapOpensMatchingThread': false,
    'tokenRotation': false,
    'permissionDenied': false,
    'registrationRevocation': false,
    'relayOutageDoesNotAffectCoding': false,
  },
  'releaseSigning': {
    'iosDistributionPushEntitlementVerified': false,
    'androidReleaseFirebaseResourcesVerified': false,
    'lockScreenContentIsGeneric': false,
  },
};

RemoteCodingFcmReleaseGate _platformCapabilityGate(Directory root) {
  final iosInfo = _read(root, 'ios/Runner/Info.plist');
  final iosEntitlements = _read(root, 'ios/Runner/Runner.entitlements');
  final iosPodfile = _read(root, 'ios/Podfile');
  final xcodeProject = _read(root, 'ios/Runner.xcodeproj/project.pbxproj');
  final androidManifest = _read(
    root,
    'android/app/src/main/AndroidManifest.xml',
  );
  final androidSettings = _read(root, 'android/settings.gradle.kts');
  final androidApp = _read(root, 'android/app/build.gradle.kts');
  final ready =
      iosInfo.contains('remote-notification') &&
      iosInfo.contains('FirebaseMessagingAutoInitEnabled') &&
      iosEntitlements.contains('aps-environment') &&
      iosPodfile.contains("platform :ios, '15.0'") &&
      iosPodfile.contains("IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'") &&
      xcodeProject.contains('com.apple.Push') &&
      xcodeProject.contains('com.apple.BackgroundModes') &&
      // Firebase reads GoogleService-Info.plist from the app bundle, and the
      // file itself is environment-owned, so the Runner target must copy it
      // conditionally instead of referencing it as a required resource.
      xcodeProject.contains('Copy Firebase Configuration') &&
      androidManifest.contains('POST_NOTIFICATIONS') &&
      androidManifest.contains('firebase_messaging_auto_init_enabled') &&
      androidManifest.contains(
        'com.google.firebase.messaging.default_notification_channel_id',
      ) &&
      androidManifest.contains('remote_coding_completion') &&
      androidSettings.contains('com.google.gms.google-services') &&
      androidApp.contains('google-services.json');
  return _staticGate(
    id: 'platform_capabilities',
    ready: ready,
    evidence:
        'iOS 15 push/background capabilities and Android notification/Google Services wiring are present.',
    nextAction:
        'Restore iOS push/background capabilities and Android Google Services wiring.',
  );
}

RemoteCodingFcmReleaseGate _firebaseAppConfigurationGate(Directory root) {
  final iosFile = File('${root.path}/ios/Runner/GoogleService-Info.plist');
  final androidFile = File('${root.path}/android/app/google-services.json');
  final bootstrapTool = File(
    '${root.path}/tool/bootstrap_remote_coding_firebase.dart',
  );
  final ready =
      bootstrapTool.existsSync() &&
      iosFile.existsSync() &&
      androidFile.existsSync() &&
      iosFile.readAsStringSync().contains('com.noguwo.apps.caverno') &&
      androidFile.readAsStringSync().contains('com.noguwo.apps.caverno');
  return _staticGate(
    id: 'firebase_app_configuration',
    ready: ready,
    evidence:
        'Firebase Apple and Android application files must match com.noguwo.apps.caverno.',
    nextAction:
        'Run tool/bootstrap_remote_coding_firebase.dart for the selected Firebase project.',
  );
}

RemoteCodingFcmReleaseGate _relayImplementationGate(Directory root) {
  final firebaseConfig = _read(root, 'firebase.json');
  final relay = _read(root, 'services/notification_relay/src/relay_service.js');
  final gateway = _read(
    root,
    'lib/features/remote_coding/data/remote_coding_mobile_notification_gateway.dart',
  );
  final firebaseStatus = _read(root, 'tool/remote_coding_firebase_status.dart');
  return _staticGate(
    id: 'relay_and_mobile_implementation',
    ready:
        firebaseConfig.contains('notification-relay') &&
        relay.contains('deliver') &&
        gateway.contains('getLimitedUseToken') &&
        gateway.contains('setAutoInitEnabled') &&
        firebaseStatus.contains('functions:list'),
    evidence:
        'The relay deployment config and limited-use App Check mobile lifecycle are present.',
    nextAction:
        'Restore the relay implementation and limited-use App Check mobile lifecycle.',
  );
}

RemoteCodingFcmReleaseGate _staticGate({
  required String id,
  required bool ready,
  required String evidence,
  required String nextAction,
}) => RemoteCodingFcmReleaseGate(
  id: id,
  status: ready ? 'ready' : 'blocked',
  evidence: evidence,
  nextAction: ready ? 'No action required.' : nextAction,
);

RemoteCodingFcmReleaseGate _manualGate({
  required String id,
  required Map<String, dynamic>? checklist,
  required List<String> requiredPaths,
  required String nextAction,
}) {
  final missing = checklist == null
      ? requiredPaths
      : requiredPaths
            .where((path) => _boolAt(checklist, path) != true)
            .toList(growable: false);
  return RemoteCodingFcmReleaseGate(
    id: id,
    status: missing.isEmpty ? 'ready' : 'blocked',
    evidence: missing.isEmpty
        ? 'All required user-operated evidence is recorded.'
        : 'Missing or false fields: ${missing.join(', ')}',
    nextAction: missing.isEmpty ? 'No action required.' : nextAction,
    userOperated: true,
  );
}

Map<String, dynamic>? _readChecklist(File? file) {
  if (file == null || !file.existsSync()) {
    return null;
  }
  final value = jsonDecode(file.readAsStringSync());
  if (value is! Map<String, dynamic> ||
      value['schemaName'] != 'remote_coding_fcm_manual_checklist' ||
      value['schemaVersion'] != 1) {
    throw const FormatException('FCM checklist schema is invalid.');
  }
  return value;
}

bool? _boolAt(Map<String, dynamic> source, String path) {
  Object? value = source;
  for (final segment in path.split('.')) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    value = value[segment];
  }
  return value is bool ? value : null;
}

String _read(Directory root, String path) {
  final file = File('${root.path}/$path');
  return file.existsSync() ? file.readAsStringSync() : '';
}
