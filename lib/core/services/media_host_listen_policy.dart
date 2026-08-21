import 'dart:io';

import '../../features/remote_coding/data/remote_coding_security.dart';

/// Where [MediaHostService] should listen, and what host to put in the URL.
class MediaHostBinding {
  const MediaHostBinding({
    required this.bindAddress,
    required this.advertiseHost,
  });

  /// Address passed to `HttpServer.bind`.
  final InternetAddress bindAddress;

  /// Host written into the URL handed to the model endpoint.
  final String advertiseHost;

  bool get isLoopbackOnly => bindAddress.isLoopback;
}

/// Decides the listen address for the short-lived media host.
///
/// Remote Coding refuses to bind a non-loopback plaintext listener in a release
/// build ([RemoteCodingListenPolicy]); this policy deliberately does not, and
/// the difference is the threat model rather than an oversight. Remote Coding
/// exposes a control channel that can drive a coding agent. This server exposes
/// one read-only file behind a 256-bit unguessable path, for at most a couple
/// of minutes and a couple of fetches, and stops as soon as the request that
/// needed it is done. Without a LAN bind the whole URL delivery mode is
/// unavailable on a real device, which is the mode this feature is built around.
class MediaHostListenPolicy {
  const MediaHostListenPolicy({List<NetworkInterface> Function()? interfaces})
    : _interfaces = interfaces;

  final List<NetworkInterface> Function()? _interfaces;

  /// Resolves how to serve media so that [endpoint] can fetch it.
  ///
  /// Returns null when the endpoint is off-box and this device has no usable
  /// LAN address, in which case the caller must inline the payload instead.
  Future<MediaHostBinding?> resolve({required Uri endpoint}) async {
    if (_endpointIsOnThisHost(endpoint)) {
      return MediaHostBinding(
        bindAddress: InternetAddress.loopbackIPv4,
        advertiseHost: '127.0.0.1',
      );
    }
    final lanAddress = await _resolveLanAddress();
    if (lanAddress == null) {
      return null;
    }
    return MediaHostBinding(
      bindAddress: InternetAddress.anyIPv4,
      advertiseHost: lanAddress.address,
    );
  }

  static bool _endpointIsOnThisHost(Uri endpoint) {
    final host = endpoint.host.trim().toLowerCase();
    if (host.isEmpty || host == 'localhost') {
      return true;
    }
    final address = InternetAddress.tryParse(host);
    return address != null && address.isLoopback;
  }

  Future<InternetAddress?> _resolveLanAddress() async {
    final interfaces =
        _interfaces?.call() ??
        await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
    InternetAddress? linkLocalFallback;
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback ||
            !RemoteCodingNetworkPolicy.isLanAddress(address)) {
          continue;
        }
        // 169.254.x.x only routes when both peers auto-configured; keep it as
        // a last resort so a real 192.168/10.x address always wins.
        if (address.isLinkLocal) {
          linkLocalFallback ??= address;
          continue;
        }
        return address;
      }
    }
    return linkLocalFallback;
  }
}
