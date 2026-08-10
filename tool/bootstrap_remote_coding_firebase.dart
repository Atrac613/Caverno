import 'dart:io';

import 'src/remote_coding_firebase_bootstrap.dart';

Future<void> main(List<String> args) async {
  try {
    final options = _BootstrapOptions.parse(args);
    final cli = _FirebaseCli(options.firebaseExecutable);
    var plan = buildRemoteCodingFirebaseBootstrapPlan(
      await cli.listApps(options.projectId),
    );

    stdout.writeln('Firebase project: ${options.projectId}');
    if (plan.requiresMutation && !options.apply) {
      stdout.writeln(
        'Dry run: create ${plan.missingPlatforms.join(' and ')} app(s) for '
        '$remoteCodingFirebaseNamespace.',
      );
      stdout.writeln('Re-run with --apply after confirming the project.');
      exitCode = 2;
      return;
    }

    if (plan.iosApp == null) {
      await cli.createApp(
        projectId: options.projectId,
        platform: 'IOS',
        displayName: 'Caverno iOS',
        namespace: remoteCodingFirebaseNamespace,
      );
    }
    if (plan.androidApp == null) {
      await cli.createApp(
        projectId: options.projectId,
        platform: 'ANDROID',
        displayName: 'Caverno Android',
        namespace: remoteCodingFirebaseNamespace,
      );
    }
    if (plan.requiresMutation) {
      plan = buildRemoteCodingFirebaseBootstrapPlan(
        await cli.listApps(options.projectId),
      );
    }
    if (plan.requiresMutation) {
      throw StateError('Firebase apps remain incomplete after registration.');
    }

    if (!options.apply) {
      stdout.writeln('Dry run: both Firebase apps already exist.');
      stdout.writeln('Re-run with --apply to download their configuration.');
      return;
    }

    await cli.downloadSdkConfig(
      projectId: options.projectId,
      platform: 'IOS',
      appId: plan.iosApp!.appId,
      outputPath: 'ios/Runner/GoogleService-Info.plist',
    );
    await cli.downloadSdkConfig(
      projectId: options.projectId,
      platform: 'ANDROID',
      appId: plan.androidApp!.appId,
      outputPath: 'android/app/google-services.json',
    );
    _verifyConfigurationFiles();
    stdout.writeln('Firebase mobile application configuration is ready.');
    stdout.writeln(
      'Next: firebase deploy --project ${options.projectId} '
      '--only functions:notification-relay,firestore,hosting',
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

final class _BootstrapOptions {
  const _BootstrapOptions({
    required this.projectId,
    required this.apply,
    required this.firebaseExecutable,
  });

  final String projectId;
  final bool apply;
  final String firebaseExecutable;

  static _BootstrapOptions parse(List<String> args) {
    String? projectId;
    var apply = false;
    var firebaseExecutable = 'firebase';
    for (var index = 0; index < args.length; index++) {
      switch (args[index]) {
        case '--project':
          projectId = _valueAfter(args, ++index, '--project');
        case '--firebase-bin':
          firebaseExecutable = _valueAfter(args, ++index, '--firebase-bin');
        case '--apply':
          apply = true;
        default:
          throw FormatException('Unknown argument: ${args[index]}');
      }
    }
    if (projectId == null || !isValidFirebaseProjectId(projectId)) {
      throw const FormatException(
        'Pass a valid Firebase project ID with --project.',
      );
    }
    return _BootstrapOptions(
      projectId: projectId,
      apply: apply,
      firebaseExecutable: firebaseExecutable,
    );
  }

  static String _valueAfter(List<String> args, int index, String option) {
    if (index >= args.length || args[index].startsWith('--')) {
      throw FormatException('$option requires a value.');
    }
    return args[index];
  }
}

final class _FirebaseCli {
  const _FirebaseCli(this.executable);

  final String executable;

  Future<List<RemoteCodingFirebaseApp>> listApps(String projectId) async {
    final result = await _run(['apps:list', '--project', projectId, '--json']);
    return parseFirebaseAppsList(result.stdout as String);
  }

  Future<void> createApp({
    required String projectId,
    required String platform,
    required String displayName,
    required String namespace,
  }) async {
    final namespaceOption = platform == 'IOS'
        ? '--bundle-id'
        : '--package-name';
    await _run([
      'apps:create',
      platform,
      displayName,
      namespaceOption,
      namespace,
      '--project',
      projectId,
      '--json',
    ]);
  }

  Future<void> downloadSdkConfig({
    required String projectId,
    required String platform,
    required String appId,
    required String outputPath,
  }) async {
    await File(outputPath).parent.create(recursive: true);
    await _run([
      'apps:sdkconfig',
      platform,
      appId,
      '--project',
      projectId,
      '--out',
      outputPath,
    ]);
  }

  Future<ProcessResult> _run(List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      final message = (result.stderr as String).trim();
      throw StateError(
        message.isEmpty ? 'Firebase CLI command failed.' : message,
      );
    }
    return result;
  }
}

void _verifyConfigurationFiles() {
  final ios = File('ios/Runner/GoogleService-Info.plist');
  final android = File('android/app/google-services.json');
  if (!ios.existsSync() ||
      !ios.readAsStringSync().contains(remoteCodingFirebaseNamespace) ||
      !android.existsSync() ||
      !android.readAsStringSync().contains(remoteCodingFirebaseNamespace)) {
    throw StateError(
      'Downloaded Firebase configuration does not match '
      '$remoteCodingFirebaseNamespace.',
    );
  }
}
