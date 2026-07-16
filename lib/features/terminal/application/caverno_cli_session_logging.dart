import 'dart:io';

import '../../chat/data/datasources/llm_session_log_store.dart';

/// Resolves a terminal-specific log root when composition must override the
/// GUI-compatible application default.
Directory? resolveCavernoCliSessionLogRoot({
  required Directory? dataDirectory,
  required Map<String, String> environment,
}) {
  final dedicatedOverride = environment['CAVERNO_SESSION_LOG_DIR']?.trim();
  if (dedicatedOverride != null && dedicatedOverride.isNotEmpty) {
    return _normalizedDirectory(Directory(dedicatedOverride));
  }
  if (dataDirectory == null) {
    return null;
  }
  final normalizedDataRoot = _normalizedDirectory(dataDirectory);
  return _normalizedDirectory(
    Directory(
      '${normalizedDataRoot.path}${Platform.pathSeparator}session_logs',
    ),
  );
}

Directory _normalizedDirectory(Directory directory) {
  var path = Directory.fromUri(directory.absolute.uri.normalizePath()).path;
  while (path.length > 1 && path.endsWith(Platform.pathSeparator)) {
    if (Platform.isWindows && RegExp(r'^[A-Za-z]:\\$').hasMatch(path)) {
      break;
    }
    path = path.substring(0, path.length - 1);
  }
  return Directory(path);
}

LlmSessionLogStore createCavernoCliSessionLogStore({
  required Directory? dataDirectory,
  required Map<String, String> environment,
}) {
  final root = resolveCavernoCliSessionLogRoot(
    dataDirectory: dataDirectory,
    environment: environment,
  );
  return LlmSessionLogStore(
    rootDirectoryProvider: root == null ? null : () async => root,
    retentionPolicy: LlmSessionLogRetentionPolicy.fromEnvironment(environment),
  );
}
