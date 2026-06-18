import 'dart:io';

import 'package:caverno/features/settings/data/local_host_resource_probe.dart';
import 'package:caverno/features/settings/domain/entities/local_host_resources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads macOS memory and Apple Silicon status via sysctl', () async {
    final probe = LocalHostResourceProbe(
      platform: LocalHostPlatform.macOS,
      runProcess: (executable, arguments) async {
        expect(executable, '/usr/sbin/sysctl');
        return switch (arguments.last) {
          'hw.memsize' => ProcessResult(
            1,
            0,
            '${64 * localHostBytesPerGiB}\n',
            '',
          ),
          'hw.optional.arm64' => ProcessResult(1, 0, '1\n', ''),
          _ => ProcessResult(1, 1, '', 'unknown key'),
        };
      },
    );

    final profile = await probe.probe();

    expect(profile.totalMemoryBytes, 64 * localHostBytesPerGiB);
    expect(profile.appleSiliconUnifiedMemory, isTrue);
    expect(profile.detectionMethod, 'sysctl');
  });

  test('returns unknown when macOS memory sysctl fails', () async {
    final probe = LocalHostResourceProbe(
      platform: LocalHostPlatform.macOS,
      runProcess: (_, _) async => ProcessResult(1, 1, '', 'failed'),
    );

    final profile = await probe.probe();

    expect(profile.hasDetectedMemory, isFalse);
    expect(profile.message, contains('sysctl'));
  });

  test('returns unknown on unsupported platforms', () async {
    final probe = LocalHostResourceProbe(platform: LocalHostPlatform.linux);

    final profile = await probe.probe();

    expect(
      profile,
      const LocalHostResourceProfile.unknown(
        message: 'Host memory detection is currently available on macOS only.',
      ),
    );
  });
}
