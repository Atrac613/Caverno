import 'dart:io';

import 'package:caverno/features/remote_coding/domain/remote_coding_listen_policy.dart';

/// Product-isolate smoke for SEC4.5b.
///
/// Compile with `--define=dart.vm.product=true`. A non-product isolate is not
/// containment evidence and exits 2. A product isolate that would bind a
/// plaintext non-loopback address exits 1. Success prints
/// `plaintext_non_loopback_listener_can_start=false` and never calls
/// [HttpServer.bind] for [InternetAddress.anyIPv4].
Future<void> main() async {
  const isRelease = bool.fromEnvironment('dart.vm.product');
  if (!isRelease) {
    stderr.writeln(
      'Refusing to treat a non-product isolate as containment evidence.',
    );
    exitCode = 2;
    return;
  }

  final policy = RemoteCodingListenPolicy.current();
  try {
    final address = policy.bindAddress(requested: InternetAddress.anyIPv4);
    final server = await HttpServer.bind(address, 0);
    await server.close(force: true);
    stderr.writeln(
      'FAIL: product isolate bound a plaintext non-loopback listener on '
      '${server.address.address}:${server.port}.',
    );
    stdout.writeln('plaintext_non_loopback_listener_can_start=true');
    exitCode = 1;
  } on RemoteCodingPlaintextLanForbiddenException {
    stdout.writeln('plaintext_non_loopback_listener_can_start=false');
    stdout.writeln('isRelease=$isRelease');
  }
}
