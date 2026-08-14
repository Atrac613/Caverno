import 'dart:io';

/// A destination that passed URI validation and an all-answer DNS decision.
class ApprovedEgressDestination {
  const ApprovedEgressDestination({required this.uri, required this.addresses});

  final Uri uri;
  final List<InternetAddress> addresses;

  /// The address selected for a pinned connection.
  InternetAddress get address => addresses.first;
}

/// A stable, non-sensitive reason for rejecting an outbound destination.
class EgressPolicyException implements Exception {
  const EgressPolicyException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'EgressPolicyException($code): $message';
}

/// Fail-closed policy for model-triggered HTTP and browser destinations.
///
/// URI validation is deliberately separate from DNS validation so transports
/// can resolve once and pin an approved answer to the actual connection.
class EgressDestinationPolicy {
  const EgressDestinationPolicy();

  static const Set<String> _allowedSchemes = {'http', 'https'};
  static const Set<String> _sensitiveRedirectHeaders = {
    'authorization',
    'cookie',
    'cookie2',
    'proxy-authorization',
  };

  Uri validateUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (!uri.isAbsolute || scheme.isEmpty) {
      throw const EgressPolicyException(
        'missing_host',
        'The destination must contain an absolute host.',
      );
    }
    if (!_allowedSchemes.contains(scheme)) {
      throw const EgressPolicyException(
        'unsafe_scheme',
        'Only HTTP and HTTPS destinations are allowed.',
      );
    }
    if (uri.host.isEmpty) {
      throw const EgressPolicyException(
        'missing_host',
        'The destination must contain an absolute host.',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      throw const EgressPolicyException(
        'embedded_credentials',
        'Credentials must not be embedded in a destination URI.',
      );
    }
    if (uri.host.contains('%')) {
      throw const EgressPolicyException(
        'unsafe_host',
        'Scoped or zone-qualified destination hosts are not allowed.',
      );
    }
    if (uri.hasPort && (uri.port <= 0 || uri.port > 65535)) {
      throw const EgressPolicyException(
        'unsafe_port',
        'The destination port is outside the allowed range.',
      );
    }
    return uri;
  }

  ApprovedEgressDestination approveResolvedAddresses(
    Uri uri,
    Iterable<InternetAddress> addresses,
  ) {
    final validatedUri = validateUri(uri);
    final resolved = List<InternetAddress>.unmodifiable(addresses);
    if (resolved.isEmpty) {
      throw const EgressPolicyException(
        'empty_dns_answer',
        'The destination did not resolve to an address.',
      );
    }
    for (final address in resolved) {
      if (!isSafeAddress(address)) {
        throw const EgressPolicyException(
          'unsafe_address',
          'The destination resolved to a non-public address.',
        );
      }
    }
    return ApprovedEgressDestination(uri: validatedUri, addresses: resolved);
  }

  void verifyPeer(ApprovedEgressDestination destination, InternetAddress peer) {
    final peerBytes = _canonicalAddressBytes(peer);
    final matches = destination.addresses.any(
      (address) => _bytesEqual(_canonicalAddressBytes(address), peerBytes),
    );
    if (!matches) {
      throw const EgressPolicyException(
        'peer_mismatch',
        'The connected peer did not match an approved DNS answer.',
      );
    }
  }

  bool isSafeAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length == 4) {
      return _isSafeIpv4(bytes);
    }
    if (bytes.length != 16) {
      return false;
    }

    if (_matchesPrefix(bytes, _ipv4MappedPrefix, 96)) {
      return _isSafeIpv4(bytes.sublist(12));
    }
    if (_matchesPrefix(bytes, _nat64WellKnownPrefix, 96)) {
      return _isSafeIpv4(bytes.sublist(12));
    }
    if (_matchesPrefix(bytes, const [0x20, 0x02], 16)) {
      return _isSafeIpv4(bytes.sublist(2, 6));
    }

    // Native public IPv6 is global unicast (2000::/3), minus IANA special-use
    // ranges that are not safe model-controlled destinations.
    if (!_matchesPrefix(bytes, const [0x20], 3)) {
      return false;
    }
    for (final range in _unsafeIpv6Ranges) {
      if (_matchesPrefix(bytes, range.bytes, range.prefixLength)) {
        return false;
      }
    }
    return true;
  }

  bool isSameOrigin(Uri first, Uri second) {
    return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
        first.host.toLowerCase() == second.host.toLowerCase() &&
        _effectivePort(first) == _effectivePort(second);
  }

  Map<String, String> headersForRedirect(
    Map<String, String> headers, {
    required Uri from,
    required Uri to,
  }) {
    if (isSameOrigin(from, to)) {
      return Map<String, String>.from(headers);
    }
    return Map<String, String>.fromEntries(
      headers.entries.where(
        (entry) => !_sensitiveRedirectHeaders.contains(entry.key.toLowerCase()),
      ),
    );
  }

  bool _isSafeIpv4(List<int> bytes) {
    if (bytes.length != 4) return false;
    for (final range in _unsafeIpv4Ranges) {
      if (_matchesPrefix(bytes, range.bytes, range.prefixLength)) {
        return false;
      }
    }
    return true;
  }

  List<int> _canonicalAddressBytes(InternetAddress address) {
    final bytes = address.rawAddress;
    if (bytes.length == 16 && _matchesPrefix(bytes, _ipv4MappedPrefix, 96)) {
      return bytes.sublist(12);
    }
    return bytes;
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
  }

  bool _bytesEqual(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  bool _matchesPrefix(List<int> value, List<int> prefix, int prefixLength) {
    final wholeBytes = prefixLength ~/ 8;
    final remainingBits = prefixLength % 8;
    if (value.length < wholeBytes || prefix.length < wholeBytes) return false;
    for (var index = 0; index < wholeBytes; index++) {
      if (value[index] != prefix[index]) return false;
    }
    if (remainingBits == 0) return true;
    if (value.length <= wholeBytes || prefix.length <= wholeBytes) return false;
    final mask = (0xff << (8 - remainingBits)) & 0xff;
    return value[wholeBytes] & mask == prefix[wholeBytes] & mask;
  }

  static const List<int> _ipv4MappedPrefix = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0xff,
    0xff,
  ];
  static const List<int> _nat64WellKnownPrefix = [
    0x00,
    0x64,
    0xff,
    0x9b,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

  static const List<_AddressRange> _unsafeIpv4Ranges = [
    _AddressRange([0], 8),
    _AddressRange([10], 8),
    _AddressRange([100, 64], 10),
    _AddressRange([127], 8),
    _AddressRange([169, 254], 16),
    _AddressRange([172, 16], 12),
    _AddressRange([192, 0, 0], 24),
    _AddressRange([192, 0, 2], 24),
    _AddressRange([192, 88, 99], 24),
    _AddressRange([192, 168], 16),
    _AddressRange([198, 18], 15),
    _AddressRange([198, 51, 100], 24),
    _AddressRange([203, 0, 113], 24),
    _AddressRange([224], 4),
    _AddressRange([240], 4),
  ];

  static const List<_AddressRange> _unsafeIpv6Ranges = [
    _AddressRange([0x20, 0x01, 0x00], 23),
    _AddressRange([0x20, 0x01, 0x0d, 0xb8], 32),
    _AddressRange([0x3f, 0xff], 20),
  ];
}

class _AddressRange {
  const _AddressRange(this.bytes, this.prefixLength);

  final List<int> bytes;
  final int prefixLength;
}
