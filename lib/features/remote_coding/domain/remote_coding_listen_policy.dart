import 'dart:io';

/// Thrown when a release build would bind a plaintext non-loopback listener.
class RemoteCodingPlaintextLanForbiddenException implements Exception {
  const RemoteCodingPlaintextLanForbiddenException();

  @override
  String toString() =>
      'Remote Coding cannot bind a plaintext non-loopback listener in a release build.';
}

/// Decides which address a plaintext Remote Coding HTTP/WS server may bind.
///
/// Debug and profile builds may listen on all interfaces for LAN pairing.
/// Product/release builds fail closed before [HttpServer.bind] unless the
/// requested address is loopback.
class RemoteCodingListenPolicy {
  const RemoteCodingListenPolicy({required this.isRelease});

  /// Uses the same product flag Flutter exposes as `kReleaseMode`.
  factory RemoteCodingListenPolicy.current() {
    return const RemoteCodingListenPolicy(
      isRelease: bool.fromEnvironment('dart.vm.product'),
    );
  }

  final bool isRelease;

  /// Address that may be passed to [HttpServer.bind].
  ///
  /// Throws [RemoteCodingPlaintextLanForbiddenException] instead of returning
  /// a non-loopback address in a product build.
  InternetAddress bindAddress({InternetAddress? requested}) {
    final address = requested ?? InternetAddress.anyIPv4;
    if (isRelease && !address.isLoopback) {
      throw const RemoteCodingPlaintextLanForbiddenException();
    }
    return address;
  }
}
