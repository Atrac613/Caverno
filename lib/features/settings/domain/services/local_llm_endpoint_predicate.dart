import 'dart:io';

/// Whether an endpoint is served from this machine or the local network.
///
/// "Local" here means reachable without leaving the user's own network, which
/// is what separates a server they can start, stop, and load models on from a
/// hosted API they can only talk to. Loopback, link-local, private IPv4/IPv6
/// ranges, `.local`/`.localhost` names and single-label hostnames all qualify;
/// a single-label name qualifies because only a local DNS or search domain can
/// resolve it.
class LocalLlmEndpointPredicate {
  const LocalLlmEndpointPredicate();

  /// True when [baseUrl] points at this machine or the local network.
  ///
  /// [discovered] short-circuits to true: an endpoint found by LAN discovery is
  /// local by construction, and its URL may use an address form this parser
  /// would otherwise have to guess about.
  bool isLocal(String baseUrl, {bool discovered = false}) {
    if (discovered) return true;
    final host = Uri.tryParse(baseUrl.trim())?.host.trim().toLowerCase() ?? '';
    if (host.isEmpty) return false;
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return true;
    }

    final address = InternetAddress.tryParse(host);
    if (address != null) return _isLocalAddress(address);

    // A single-label hostname is resolved by the local DNS/search domain.
    return !host.contains('.');
  }

  bool _isLocalAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return _isPrivateIpv4(bytes);
    }
    if ((bytes[0] & 0xfe) == 0xfc) return true;
    final isIpv4Mapped =
        bytes.length == 16 &&
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    return isIpv4Mapped && _isPrivateIpv4(bytes.sublist(12));
  }

  bool _isPrivateIpv4(List<int> bytes) =>
      bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168);
}
