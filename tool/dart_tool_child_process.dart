import 'dart:convert';
import 'dart:io';

const sqlite3NativeAssetId = 'package:sqlite3/src/ffi/libsqlite3.g.dart';

/// Starts a tool script on dartvm after injecting the sqlite3 native library.
///
/// Crash-child tests must SIGKILL the process that holds an uncommitted
/// SQLite write, so this keeps `--disable-dart-dev` (dartdev would be an extra
/// process). Linux CI cannot resolve `sqlite3_initialize` that way unless the
/// library is already in the process; Flutter's test native-assets build
/// already produced it, so preload that file instead of racing `dart run`.
Future<Process> startDartToolChild({
  required String scriptPath,
  List<String> arguments = const [],
  String? workingDirectory,
}) {
  final directory = workingDirectory ?? Directory.current.path;
  final libraryPath = resolveSqlite3NativeLibraryPath(
    workingDirectory: directory,
  );
  if (libraryPath == null) {
    throw StateError(
      'sqlite3 native library was not found under build/native_assets '
      'or .dart_tool/lib; crash children cannot resolve sqlite3_initialize.',
    );
  }
  return Process.start(
    resolveDartExecutable(workingDirectory: directory),
    dartToolChildArguments(scriptPath, arguments),
    workingDirectory: directory,
    environment: nativeLibraryPreloadEnvironment(libraryPath),
  );
}

List<String> dartToolChildArguments(String scriptPath, List<String> arguments) {
  return <String>['--disable-dart-dev', scriptPath, ...arguments];
}

String resolveDartExecutable({String? workingDirectory}) {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final root = workingDirectory ?? Directory.current.path;
  final flutterRoots = <String>[
    Directory(root).uri.resolve('.fvm/flutter_sdk/').toFilePath(),
    if ((Platform.environment['FLUTTER_ROOT'] ?? '').trim().isNotEmpty)
      Platform.environment['FLUTTER_ROOT']!.trim(),
  ];
  for (final flutterRoot in flutterRoots) {
    final candidate = File.fromUri(
      Directory(
        flutterRoot,
      ).uri.resolve('bin/cache/dart-sdk/bin/$executableName'),
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  final which = Process.runSync('which', [executableName]);
  if (which.exitCode == 0) {
    final path = (which.stdout as String).trim();
    if (path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
  }
  return executableName;
}

String? resolveSqlite3NativeLibraryPath({String? workingDirectory}) {
  final root = workingDirectory ?? Directory.current.path;
  final osName = Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : Platform.operatingSystem;
  final libraryName = Platform.isWindows
      ? 'sqlite3.dll'
      : Platform.isMacOS
      ? 'libsqlite3.dylib'
      : 'libsqlite3.so';
  final candidates = <File>[
    File.fromUri(
      Directory(root).uri.resolve('build/native_assets/$osName/$libraryName'),
    ),
    File.fromUri(Directory(root).uri.resolve('.dart_tool/lib/$libraryName')),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }

  final manifests = <File>[
    File.fromUri(
      Directory(
        root,
      ).uri.resolve('build/native_assets/$osName/native_assets.json'),
    ),
    File.fromUri(Directory(root).uri.resolve('.dart_tool/native_assets.yaml')),
  ];
  for (final manifest in manifests) {
    final path = sqlite3PathFromNativeAssetsManifest(manifest);
    if (path != null) {
      return path;
    }
  }
  return null;
}

String? sqlite3PathFromNativeAssetsManifest(File manifest) {
  if (!manifest.existsSync()) {
    return null;
  }
  final source = manifest.readAsStringSync();
  final jsonStart = source.indexOf('{');
  if (jsonStart < 0) {
    return null;
  }
  final decoded = jsonDecode(source.substring(jsonStart));
  if (decoded is! Map) {
    return null;
  }
  final nativeAssets = decoded['native-assets'];
  if (nativeAssets is! Map) {
    return null;
  }
  for (final osEntry in nativeAssets.values) {
    if (osEntry is! Map) {
      continue;
    }
    final listing = osEntry[sqlite3NativeAssetId];
    if (listing is! List || listing.length < 2 || listing[1] is! String) {
      continue;
    }
    final rawPath = listing[1] as String;
    final file = File(rawPath).isAbsolute
        ? File(rawPath)
        : File.fromUri(manifest.parent.uri.resolve(rawPath));
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  return null;
}

Map<String, String> nativeLibraryPreloadEnvironment(String libraryPath) {
  final environment = Map<String, String>.from(Platform.environment);
  if (Platform.isLinux) {
    environment['LD_PRELOAD'] = _prependSearchPath(
      environment['LD_PRELOAD'],
      libraryPath,
    );
  } else if (Platform.isMacOS) {
    environment['DYLD_INSERT_LIBRARIES'] = _prependSearchPath(
      environment['DYLD_INSERT_LIBRARIES'],
      libraryPath,
    );
  } else if (Platform.isWindows) {
    final directory = File(libraryPath).parent.path;
    environment['PATH'] = _prependSearchPath(
      environment['PATH'],
      directory,
      separator: ';',
    );
  }
  return environment;
}

String _prependSearchPath(
  String? current,
  String value, {
  String separator = ':',
}) {
  if (current == null || current.trim().isEmpty) {
    return value;
  }
  return '$value$separator$current';
}
