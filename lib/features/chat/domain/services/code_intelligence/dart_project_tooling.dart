import 'dart:io';

class DartToolCommand {
  const DartToolCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

class DartChangedFile {
  const DartChangedFile({
    required this.absolutePath,
    required this.relativePath,
  });

  final String absolutePath;
  final String relativePath;
}

final class DartProjectTooling {
  const DartProjectTooling._();

  static List<DartChangedFile> changedDartFiles({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) {
    final root = Directory(projectRoot).absolute.path;
    final seen = <String>{};
    final files = <DartChangedFile>[];
    for (final rawPath in changedPaths) {
      final absolutePath = DartProjectPath.resolvePath(
        rawPath,
        projectRoot: root,
      );
      if (absolutePath == null) {
        continue;
      }
      if (!DartProjectPath.isInsideRoot(absolutePath, root)) {
        continue;
      }
      if (!absolutePath.toLowerCase().endsWith('.dart')) {
        continue;
      }
      if (!File(absolutePath).existsSync()) {
        continue;
      }
      if (!seen.add(DartProjectPath.pathKey(absolutePath))) {
        continue;
      }
      files.add(
        DartChangedFile(
          absolutePath: absolutePath,
          relativePath: DartProjectPath.relativePath(absolutePath, root),
        ),
      );
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return files;
  }

  static String rootForFiles(
    String projectRoot,
    List<DartChangedFile> changedDartFiles,
  ) {
    final roots = changedDartFiles
        .map((file) => nearestPackageRoot(file.absolutePath, projectRoot))
        .toSet();
    return roots.length == 1
        ? roots.single
        : Directory(projectRoot).absolute.path;
  }

  static String nearestPackageRoot(String filePath, String projectRoot) {
    var directory = File(filePath).parent.absolute;
    final root = Directory(projectRoot).absolute;
    while (DartProjectPath.isInsideRoot(directory.path, root.path)) {
      if (File.fromUri(directory.uri.resolve('pubspec.yaml')).existsSync()) {
        return directory.path;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }
    return root.path;
  }

  static String? inferPackageRootForTestPath({
    required String projectRoot,
    required String workingDirectory,
    required String testPath,
  }) {
    final root = Directory(projectRoot).absolute.path;
    final workingRoot = Directory(workingDirectory).absolute.path;
    final trimmedTestPath = testPath.trim();
    if (trimmedTestPath.isEmpty) {
      return null;
    }

    final directTestPath = DartProjectPath.resolvePath(
      trimmedTestPath,
      projectRoot: workingRoot,
    );
    if (directTestPath != null &&
        DartProjectPath.isInsideRoot(directTestPath, root) &&
        File(directTestPath).existsSync()) {
      final packageRoot = nearestPackageRoot(directTestPath, root);
      return _hasPubspec(packageRoot) ? packageRoot : null;
    }

    if (DartProjectPath.isAbsolutePath(trimmedTestPath)) {
      return null;
    }

    final normalizedTestPath = trimmedTestPath.replaceAll('\\', '/');
    final matches = <String>[];
    for (final packageRoot in _discoverPackageRoots(root)) {
      final candidate = File.fromUri(
        Directory(packageRoot).uri.resolve(normalizedTestPath),
      );
      if (candidate.existsSync()) {
        matches.add(packageRoot);
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  static bool hasFvmMetadata({
    required String packageRoot,
    required String projectRoot,
  }) {
    return File('$packageRoot/.fvm/fvm_config.json').existsSync() ||
        File('$packageRoot/.fvmrc').existsSync() ||
        File('$projectRoot/.fvm/fvm_config.json').existsSync() ||
        File('$projectRoot/.fvmrc').existsSync();
  }

  static bool isFlutterPackage(String packageRoot) {
    final pubspec = File.fromUri(
      Directory(packageRoot).uri.resolve('pubspec.yaml'),
    );
    if (!pubspec.existsSync()) {
      return false;
    }
    try {
      final content = pubspec.readAsStringSync();
      return RegExp(
            r'(^|\n)\s*flutter\s*:',
            multiLine: true,
          ).hasMatch(content) ||
          RegExp(
            r'(^|\n)\s*sdk\s*:\s*flutter\s*($|\n)',
            multiLine: true,
          ).hasMatch(content);
    } on FileSystemException {
      return false;
    }
  }

  static bool _hasPubspec(String packageRoot) {
    return File.fromUri(
      Directory(packageRoot).uri.resolve('pubspec.yaml'),
    ).existsSync();
  }

  static List<String> _discoverPackageRoots(
    String projectRoot, {
    int maxDepth = 4,
  }) {
    final roots = <String>[];
    void visit(Directory directory, int depth) {
      if (depth > maxDepth || _shouldSkipDirectory(directory)) {
        return;
      }
      if (_hasPubspec(directory.path)) {
        roots.add(directory.absolute.path);
      }
      if (depth == maxDepth) {
        return;
      }
      List<FileSystemEntity> children;
      try {
        children = directory.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      for (final child in children) {
        if (child is Directory) {
          visit(child, depth + 1);
        }
      }
    }

    visit(Directory(projectRoot).absolute, 0);
    return roots;
  }

  static bool _shouldSkipDirectory(Directory directory) {
    final segments = directory.path
        .split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty);
    final name = segments.isEmpty ? null : segments.last;
    return switch (name) {
      null => false,
      '.git' || '.dart_tool' || '.fvm' || 'build' => true,
      _ => false,
    };
  }
}

final class DartProjectPath {
  const DartProjectPath._();

  static final RegExp _windowsDriveLetterPath = RegExp(r'^[A-Za-z]:[\\/]');

  static String? resolvePath(String? rawPath, {required String projectRoot}) {
    final trimmed = rawPath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (isAbsolutePath(trimmed)) {
      return File(trimmed).absolute.path;
    }
    return File.fromUri(Directory(projectRoot).uri.resolve(trimmed)).path;
  }

  static bool isAbsolutePath(String path) {
    return path.startsWith('/') ||
        path.startsWith(r'\\') ||
        _windowsDriveLetterPath.hasMatch(path);
  }

  static bool isInsideRoot(String candidatePath, String projectRoot) {
    final rootKey = pathKey(projectRoot);
    final candidateKey = pathKey(candidatePath);
    final separator = Platform.pathSeparator;
    return candidateKey == rootKey ||
        candidateKey.startsWith('$rootKey$separator');
  }

  static String relativePath(String absolutePath, String projectRoot) {
    final root = Directory(projectRoot).absolute.path;
    final path = File(absolutePath).absolute.path;
    if (path == root) {
      return '.';
    }
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (!path.startsWith(prefix)) {
      return path;
    }
    return path.substring(prefix.length);
  }

  static String pathKey(String path) {
    final normalized = File(path).absolute.path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }
}
