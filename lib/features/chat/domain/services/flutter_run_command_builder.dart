import 'dart:convert';

import '../entities/flutter_run_device.dart';
import 'dart_project_tooling.dart';

/// A command to spawn, kept as executable plus arguments so nothing is ever
/// handed to a shell for re-parsing.
class FlutterRunCommand {
  const FlutterRunCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  /// What to show the user, matching what they would type themselves.
  String get displayCommand => [executable, ...arguments].join(' ');

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FlutterRunCommand &&
            executable == other.executable &&
            workingDirectory == other.workingDirectory &&
            _sameArguments(arguments, other.arguments);
  }

  @override
  int get hashCode =>
      Object.hash(executable, workingDirectory, Object.hashAll(arguments));

  static bool _sameArguments(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

/// Decides how to invoke Flutter for a project and reads back what it says.
///
/// FVM is not a preference here: a project pinned to a Flutter version fails or
/// silently builds against the wrong SDK when invoked with a bare `flutter`, so
/// the pin is detected from the project itself rather than configured.
class FlutterRunCommandBuilder {
  const FlutterRunCommandBuilder({
    bool Function(String projectRoot)? usesFvm,
    bool Function(String projectRoot)? isFlutterProject,
  }) : _usesFvm = usesFvm,
       _isFlutterProject = isFlutterProject;

  final bool Function(String projectRoot)? _usesFvm;
  final bool Function(String projectRoot)? _isFlutterProject;

  bool usesFvm(String projectRoot) =>
      _usesFvm?.call(projectRoot) ??
      DartProjectTooling.hasFvmMetadata(
        packageRoot: projectRoot,
        projectRoot: projectRoot,
      );

  bool isFlutterProject(String projectRoot) =>
      _isFlutterProject?.call(projectRoot) ??
      DartProjectTooling.isFlutterPackage(projectRoot);

  /// `flutter devices --machine`, which prints a JSON array this class parses.
  FlutterRunCommand devices({required String projectRoot}) =>
      _command(projectRoot, const ['devices', '--machine']);

  /// `flutter run -d <device>`.
  FlutterRunCommand run({
    required String projectRoot,
    required String deviceId,
    List<String> extraArguments = const [],
  }) => _command(projectRoot, ['run', '-d', deviceId, ...extraArguments]);

  FlutterRunCommand _command(
    String projectRoot,
    List<String> flutterArguments,
  ) {
    final fvm = usesFvm(projectRoot);
    return FlutterRunCommand(
      executable: fvm ? 'fvm' : 'flutter',
      arguments: [if (fvm) 'flutter', ...flutterArguments],
      workingDirectory: projectRoot,
    );
  }

  /// Parses `flutter devices --machine` output.
  ///
  /// Tolerates leading noise: the tool prints version-check banners and
  /// analytics notices before the JSON on a first run, and a strict decode of
  /// the whole stream would report "no devices" for a machine that has them.
  static List<FlutterRunDevice> parseDevices(String output) {
    final start = output.indexOf('[');
    final end = output.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(output.substring(start, end + 1));
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];

    final devices = <FlutterRunDevice>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final id = _string(map['id']);
      if (id.isEmpty) continue;
      devices.add(
        FlutterRunDevice(
          id: id,
          name: _string(map['name'], fallback: id),
          targetPlatform: _string(map['targetPlatform']),
          isEmulator: map['emulator'] == true,
          isSupported: map['isSupported'] != false,
          sdk: map['sdk'] is String ? map['sdk'] as String : null,
        ),
      );
    }
    return List.unmodifiable(devices);
  }

  static String _string(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return fallback;
  }
}
