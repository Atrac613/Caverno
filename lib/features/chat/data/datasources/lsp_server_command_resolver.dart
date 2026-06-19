import 'dart:io';

import '../../../../core/services/login_shell_environment.dart';
import '../../domain/services/dart_project_tooling.dart';

class LspServerCommand {
  const LspServerCommand({
    required this.languageId,
    required this.command,
    required this.workingDirectory,
  });

  final String languageId;
  final String command;
  final String workingDirectory;

  String get executable {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.split(RegExp(r'\s+')).first;
  }
}

abstract interface class LspServerExecutableProbe {
  Future<LspServerExecutableAvailability> check(LspServerCommand command);
}

class LspServerExecutableAvailability {
  const LspServerExecutableAvailability({
    required this.available,
    required this.executable,
    this.resolvedPath,
    this.code,
    this.error,
  });

  factory LspServerExecutableAvailability.available({
    required String executable,
    required String resolvedPath,
  }) {
    return LspServerExecutableAvailability(
      available: true,
      executable: executable,
      resolvedPath: resolvedPath,
    );
  }

  factory LspServerExecutableAvailability.unavailable({
    required String executable,
    String? code,
    String? error,
  }) {
    return LspServerExecutableAvailability(
      available: false,
      executable: executable,
      code: code ?? 'language_server_executable_not_found',
      error: error,
    );
  }

  final bool available;
  final String executable;
  final String? resolvedPath;
  final String? code;
  final String? error;

  Map<String, dynamic> toJson() {
    return {
      'available': available,
      'executable': executable,
      if (resolvedPath != null) 'resolved_path': resolvedPath,
      if (code != null) 'code': code,
      if (error != null) 'error': error,
    };
  }
}

class PathLspServerExecutableProbe implements LspServerExecutableProbe {
  const PathLspServerExecutableProbe({this.environmentResolver});

  final Future<Map<String, String>> Function()? environmentResolver;

  @override
  Future<LspServerExecutableAvailability> check(
    LspServerCommand command,
  ) async {
    final executable = command.executable;
    if (executable.isEmpty) {
      return LspServerExecutableAvailability.unavailable(
        executable: executable,
        code: 'language_server_executable_missing',
        error: 'Language server command did not include an executable.',
      );
    }

    final environment = environmentResolver == null
        ? await LoginShellEnvironment.instance.environment()
        : await environmentResolver!();
    final resolvedPath = _resolveExecutablePath(
      executable: executable,
      workingDirectory: command.workingDirectory,
      environment: environment,
    );
    if (resolvedPath != null) {
      return LspServerExecutableAvailability.available(
        executable: executable,
        resolvedPath: resolvedPath,
      );
    }

    return LspServerExecutableAvailability.unavailable(
      executable: executable,
      error:
          'Language server executable "$executable" was not found on PATH for '
          '${command.languageId}. Install it or update PATH before running '
          '"${command.command}".',
    );
  }

  String? _resolveExecutablePath({
    required String executable,
    required String workingDirectory,
    required Map<String, String> environment,
  }) {
    if (executable.contains('/') || executable.contains(r'\')) {
      final file = File(executable);
      final candidate = file.isAbsolute
          ? file
          : File.fromUri(
              Directory(workingDirectory).absolute.uri.resolve(executable),
            );
      return _isRunnableFile(candidate.path) ? candidate.absolute.path : null;
    }

    final path = environment['PATH'] ?? Platform.environment['PATH'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';
    for (final directory in path.split(separator)) {
      if (directory.trim().isEmpty) {
        continue;
      }
      for (final candidateName in _candidateNames(executable, environment)) {
        final candidatePath = File.fromUri(
          Directory(directory).absolute.uri.resolve(candidateName),
        ).path;
        if (_isRunnableFile(candidatePath)) {
          return File(candidatePath).absolute.path;
        }
      }
    }
    return null;
  }

  Iterable<String> _candidateNames(
    String executable,
    Map<String, String> environment,
  ) {
    if (!Platform.isWindows || executable.contains('.')) {
      return [executable];
    }
    final extensions = (environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD')
        .split(';')
        .where((extension) => extension.trim().isNotEmpty)
        .map(
          (extension) => extension.startsWith('.') ? extension : '.$extension',
        );
    return [
      executable,
      for (final extension in extensions) '$executable$extension',
    ];
  }

  bool _isRunnableFile(String path) {
    if (!File(path).existsSync()) {
      return false;
    }
    if (Platform.isWindows) {
      return true;
    }
    final mode = FileStat.statSync(path).mode;
    return mode & 0x49 != 0;
  }
}

class LspServerCommandResolver {
  const LspServerCommandResolver();

  LspServerCommand? resolve({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) {
    final root = Directory(projectRoot).absolute.path;
    final dartFiles = DartProjectTooling.changedDartFiles(
      projectRoot: root,
      changedPaths: changedPaths,
    );
    if (dartFiles.isNotEmpty) {
      final packageRoot = DartProjectTooling.rootForFiles(root, dartFiles);
      final usesFvm = DartProjectTooling.hasFvmMetadata(
        packageRoot: packageRoot,
        projectRoot: root,
      );
      return LspServerCommand(
        languageId: 'dart',
        command: usesFvm
            ? 'fvm dart language-server --protocol=lsp'
            : 'dart language-server --protocol=lsp',
        workingDirectory: packageRoot,
      );
    }

    final changedFiles = _changedFiles(
      projectRoot: root,
      changedPaths: changedPaths,
    );
    for (final file in changedFiles) {
      final lowerPath = file.toLowerCase();
      if (_isTypeScriptPath(lowerPath)) {
        return LspServerCommand(
          languageId: 'typescript',
          command: 'typescript-language-server --stdio',
          workingDirectory: root,
        );
      }
      if (lowerPath.endsWith('.py')) {
        return LspServerCommand(
          languageId: 'python',
          command: 'pyright-langserver --stdio',
          workingDirectory: root,
        );
      }
      if (lowerPath.endsWith('.swift')) {
        return LspServerCommand(
          languageId: 'swift',
          command: 'sourcekit-lsp',
          workingDirectory: root,
        );
      }
    }
    return null;
  }

  List<String> _changedFiles({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) {
    final files = <String>[];
    final seen = <String>{};
    for (final rawPath in changedPaths) {
      final absolutePath = DartProjectPath.resolvePath(
        rawPath,
        projectRoot: projectRoot,
      );
      if (absolutePath == null ||
          !DartProjectPath.isInsideRoot(absolutePath, projectRoot) ||
          !File(absolutePath).existsSync()) {
        continue;
      }
      if (seen.add(DartProjectPath.pathKey(absolutePath))) {
        files.add(absolutePath);
      }
    }
    files.sort();
    return files;
  }

  bool _isTypeScriptPath(String lowerPath) {
    return lowerPath.endsWith('.ts') ||
        lowerPath.endsWith('.tsx') ||
        lowerPath.endsWith('.js') ||
        lowerPath.endsWith('.jsx') ||
        lowerPath.endsWith('.mjs') ||
        lowerPath.endsWith('.cjs');
  }
}
