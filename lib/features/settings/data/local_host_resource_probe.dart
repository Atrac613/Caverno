import 'dart:io';

import '../domain/entities/local_host_resources.dart';

enum LocalHostPlatform { macOS, linux, windows, other }

typedef LocalProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

LocalHostPlatform detectLocalHostPlatform() {
  if (Platform.isMacOS) return LocalHostPlatform.macOS;
  if (Platform.isLinux) return LocalHostPlatform.linux;
  if (Platform.isWindows) return LocalHostPlatform.windows;
  return LocalHostPlatform.other;
}

class LocalHostResourceProbe {
  LocalHostResourceProbe({
    LocalHostPlatform? platform,
    LocalProcessRunner? runProcess,
  }) : _platform = platform,
       _runProcess = runProcess;

  final LocalHostPlatform? _platform;
  final LocalProcessRunner? _runProcess;

  Future<LocalHostResourceProfile> probe() async {
    final platform = _platform ?? detectLocalHostPlatform();
    return switch (platform) {
      LocalHostPlatform.macOS => _probeMacOS(),
      LocalHostPlatform.linux ||
      LocalHostPlatform.windows ||
      LocalHostPlatform.other => const LocalHostResourceProfile.unknown(
        message: 'Host memory detection is currently available on macOS only.',
      ),
    };
  }

  Future<LocalHostResourceProfile> _probeMacOS() async {
    final totalMemoryBytes = await _readSysctlInt('hw.memsize');
    if (totalMemoryBytes == null) {
      return const LocalHostResourceProfile.unknown(
        message: 'Could not read host memory from sysctl.',
      );
    }

    final arm64Flag = await _readSysctlInt('hw.optional.arm64');
    return LocalHostResourceProfile.detected(
      totalMemoryBytes: totalMemoryBytes,
      appleSiliconUnifiedMemory: arm64Flag == 1,
      detectionMethod: 'sysctl',
      message: arm64Flag == 1
          ? 'Apple Silicon unified memory detected.'
          : 'Host memory detected.',
    );
  }

  Future<int?> _readSysctlInt(String key) async {
    try {
      final runner = _runProcess ?? Process.run;
      final result = await runner('/usr/sbin/sysctl', ['-n', key]);
      if (result.exitCode != 0) return null;
      final value = int.tryParse('${result.stdout}'.trim());
      if (value == null || value <= 0) return null;
      return value;
    } catch (_) {
      return null;
    }
  }
}
