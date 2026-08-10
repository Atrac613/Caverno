import 'dart:convert';
import 'dart:io';

import 'src/remote_coding_firebase_bootstrap.dart';
import 'src/remote_coding_firebase_status.dart';

Future<void> main(List<String> args) async {
  try {
    final options = _StatusOptions.parse(args);
    final cli = _FirebaseCli(options.firebaseExecutable, options.projectId);
    final results = await Future.wait([
      cli.runJson(['apps:list']),
      cli.runJson(['firestore:databases:list']),
      cli.runJson(['hosting:sites:list']),
      cli.runJson(['functions:list']),
    ]);
    final appsEnvelope = results[0];
    final firestoreEnvelope = results[1];
    final hostingEnvelope = results[2];
    final functionsEnvelope = results[3];
    final apps = appsEnvelope.success
        ? parseFirebaseAppsList(
            jsonEncode({'status': 'success', 'result': appsEnvelope.result}),
          )
        : const <RemoteCodingFirebaseApp>[];
    final appPlan = buildRemoteCodingFirebaseBootstrapPlan(apps);
    final localConfigReady = _localConfigurationReady();
    final firestoreReady = hasDefaultFirestoreDatabase(firestoreEnvelope);
    final hostingUrl = defaultHostingUrl(hostingEnvelope);
    final relayReady = hasActiveNotificationRelay(functionsEnvelope);
    final prerequisiteGates = <String, bool>{
      'mobile_apps': !appPlan.requiresMutation,
      'local_app_configuration': localConfigReady,
      'default_firestore': firestoreReady,
      'default_hosting_site': hostingUrl != null,
    };
    final blocked = [
      for (final entry in prerequisiteGates.entries)
        if (!entry.value) entry.key,
    ];
    final phase = blocked.isNotEmpty
        ? 'blocked'
        : relayReady
        ? 'deployed'
        : 'ready_to_deploy';
    final report = <String, Object?>{
      'schemaName': 'remote_coding_firebase_status',
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'projectId': options.projectId,
      'phase': phase,
      'blockedPrerequisites': blocked,
      'gates': {
        ...prerequisiteGates,
        'notification_relay_deployed': relayReady,
      },
      'firestoreLocation': defaultFirestoreLocation(firestoreEnvelope),
      'hostingUrl': hostingUrl,
      'relayOrigin': relayReady ? hostingUrl : null,
      'firebaseErrors': {
        if (appsEnvelope.error != null) 'apps': appsEnvelope.error,
        if (firestoreEnvelope.error != null)
          'firestore': firestoreEnvelope.error,
        if (hostingEnvelope.error != null) 'hosting': hostingEnvelope.error,
        if (functionsEnvelope.error != null)
          'functions': functionsEnvelope.error,
      },
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    exitCode = switch (phase) {
      'deployed' => 0,
      'ready_to_deploy' => 2,
      _ => 1,
    };
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

final class _StatusOptions {
  const _StatusOptions({
    required this.projectId,
    required this.firebaseExecutable,
  });

  final String projectId;
  final String firebaseExecutable;

  static _StatusOptions parse(List<String> args) {
    String? projectId;
    var firebaseExecutable = 'firebase';
    for (var index = 0; index < args.length; index++) {
      final option = args[index];
      if (option != '--project' && option != '--firebase-bin') {
        throw FormatException('Unknown argument: $option');
      }
      if (++index >= args.length || args[index].startsWith('--')) {
        throw FormatException('$option requires a value.');
      }
      if (option == '--project') {
        projectId = args[index];
      } else {
        firebaseExecutable = args[index];
      }
    }
    if (projectId == null || !isValidFirebaseProjectId(projectId)) {
      throw const FormatException(
        'Pass a valid Firebase project ID with --project.',
      );
    }
    return _StatusOptions(
      projectId: projectId,
      firebaseExecutable: firebaseExecutable,
    );
  }
}

final class _FirebaseCli {
  const _FirebaseCli(this.executable, this.projectId);

  final String executable;
  final String projectId;

  Future<FirebaseCliEnvelope> runJson(List<String> command) async {
    final result = await Process.run(executable, [
      ...command,
      '--project',
      projectId,
      '--json',
    ]);
    final output = (result.stdout as String).trim();
    if (output.isEmpty) {
      final error = (result.stderr as String).trim();
      throw StateError(error.isEmpty ? 'Firebase CLI failed.' : error);
    }
    return FirebaseCliEnvelope.parse(output);
  }
}

bool _localConfigurationReady() {
  final ios = File('ios/Runner/GoogleService-Info.plist');
  final android = File('android/app/google-services.json');
  return ios.existsSync() &&
      ios.readAsStringSync().contains(remoteCodingFirebaseNamespace) &&
      android.existsSync() &&
      android.readAsStringSync().contains(remoteCodingFirebaseNamespace);
}
