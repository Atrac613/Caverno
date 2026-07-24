import 'dart:io';

Directory resolvePlanModeTemporaryRoot({Map<String, String>? environment}) {
  final resolvedEnvironment = environment ?? Platform.environment;
  final configuredHome = resolvedEnvironment['CAVERNO_HOME']?.trim() ?? '';
  if (configuredHome.isNotEmpty) {
    return Directory('$configuredHome/tmp').absolute;
  }

  final userHome = resolvedEnvironment['HOME']?.trim() ?? '';
  if (userHome.isEmpty) {
    throw StateError('HOME must be set when CAVERNO_HOME is not configured.');
  }
  return Directory('$userHome/.caverno/tmp').absolute;
}

Future<Directory> createPlanModeTemporaryDirectory(
  String prefix, {
  Map<String, String>? environment,
}) async {
  final root = resolvePlanModeTemporaryRoot(environment: environment);
  await root.create(recursive: true);
  return root.createTemp(prefix);
}
