import 'dart:convert';

const remoteCodingFirebaseNamespace = 'com.noguwo.apps.caverno';

final class RemoteCodingFirebaseApp {
  const RemoteCodingFirebaseApp({
    required this.platform,
    required this.appId,
    required this.namespace,
  });

  final String platform;
  final String appId;
  final String namespace;

  factory RemoteCodingFirebaseApp.fromJson(Map<String, Object?> json) {
    final platform = json['platform'];
    final appId = json['appId'];
    final namespace = json['namespace'];
    if (platform is! String ||
        appId is! String ||
        namespace is! String ||
        platform.isEmpty ||
        appId.isEmpty ||
        namespace.isEmpty) {
      throw const FormatException('Firebase app entry is incomplete.');
    }
    return RemoteCodingFirebaseApp(
      platform: platform.toUpperCase(),
      appId: appId,
      namespace: namespace,
    );
  }
}

final class RemoteCodingFirebaseBootstrapPlan {
  const RemoteCodingFirebaseBootstrapPlan({
    required this.iosApp,
    required this.androidApp,
  });

  final RemoteCodingFirebaseApp? iosApp;
  final RemoteCodingFirebaseApp? androidApp;

  bool get requiresMutation => iosApp == null || androidApp == null;

  List<String> get missingPlatforms => [
    if (iosApp == null) 'IOS',
    if (androidApp == null) 'ANDROID',
  ];
}

List<RemoteCodingFirebaseApp> parseFirebaseAppsList(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map<String, Object?> || decoded['status'] != 'success') {
    throw const FormatException('Firebase CLI did not return success.');
  }
  final result = decoded['result'];
  if (result is! List<Object?>) {
    throw const FormatException('Firebase CLI app list is missing.');
  }
  return result
      .map((entry) {
        if (entry is! Map<String, Object?>) {
          throw const FormatException('Firebase app entry must be an object.');
        }
        return RemoteCodingFirebaseApp.fromJson(entry);
      })
      .toList(growable: false);
}

RemoteCodingFirebaseBootstrapPlan buildRemoteCodingFirebaseBootstrapPlan(
  List<RemoteCodingFirebaseApp> apps, {
  String namespace = remoteCodingFirebaseNamespace,
}) {
  RemoteCodingFirebaseApp? findUnique(String platform) {
    final matches = apps
        .where((app) => app.platform == platform && app.namespace == namespace)
        .toList(growable: false);
    if (matches.length > 1) {
      throw StateError(
        'Multiple $platform Firebase apps use namespace $namespace.',
      );
    }
    return matches.singleOrNull;
  }

  return RemoteCodingFirebaseBootstrapPlan(
    iosApp: findUnique('IOS'),
    androidApp: findUnique('ANDROID'),
  );
}

bool isValidFirebaseProjectId(String value) =>
    RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(value);
