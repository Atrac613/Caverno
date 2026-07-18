import 'dart:io';
import 'dart:typed_data';

/// Represents an IPv4 or IPv6 CIDR network.
class LanIpNetwork {
  LanIpNetwork._({
    required this.networkAddress,
    required this.prefixLength,
    required this.addressType,
    required BigInt firstValue,
    required BigInt lastValue,
  }) : _firstValue = firstValue,
       _lastValue = lastValue;

  static const int maxEnumeratedHosts = 1024;

  final String networkAddress;
  final int prefixLength;
  final InternetAddressType addressType;
  final BigInt _firstValue;
  final BigInt _lastValue;

  bool get isIpv4 => addressType == InternetAddressType.IPv4;
  bool get isIpv6 => addressType == InternetAddressType.IPv6;
  int get _bitLength => isIpv4 ? 32 : 128;

  String get cidr => '$networkAddress/$prefixLength';

  int get hostCount {
    final usable = _usableHostCount;
    final capped = usable > BigInt.from(maxEnumeratedHosts)
        ? BigInt.from(maxEnumeratedHosts)
        : usable;
    return capped.toInt();
  }

  List<String> enumerableHostIps() {
    final usable = _usableHostCount;
    if (usable <= BigInt.zero) {
      return const [];
    }
    if (isIpv6 && usable > BigInt.from(maxEnumeratedHosts)) {
      return const [];
    }

    final start = _enumerationStart;
    final limit = hostCount;
    final results = <String>[];
    for (var index = 0; index < limit; index += 1) {
      final current = start + BigInt.from(index);
      if (current > _lastValue) {
        break;
      }
      results.add(_bigIntToAddressString(current, addressType));
    }
    return results;
  }

  bool contains(String ip) {
    final address = _tryParseLiteral(ip);
    if (address == null || address.type != addressType) {
      return false;
    }
    final value = _addressToBigInt(address);
    return value >= _firstValue && value <= _lastValue;
  }

  static LanIpNetwork? parse(String cidr) {
    final parts = cidr.trim().split('/');
    if (parts.length != 2) {
      return null;
    }

    final prefix = int.tryParse(parts[1]);
    if (prefix == null) {
      return null;
    }

    return fromIpAndPrefix(parts[0], prefix);
  }

  static LanIpNetwork? fromIpAndPrefix(String ip, int prefix) {
    final address = _tryParseLiteral(ip);
    if (address == null) {
      return null;
    }

    final bitLength = address.type == InternetAddressType.IPv4 ? 32 : 128;
    if (prefix < 0 || prefix > bitLength) {
      return null;
    }

    final allOnes = (BigInt.one << bitLength) - BigInt.one;
    final hostBits = bitLength - prefix;
    final hostMask = hostBits == 0
        ? BigInt.zero
        : (BigInt.one << hostBits) - BigInt.one;
    final networkMask = allOnes ^ hostMask;
    final addressValue = _addressToBigInt(address);
    final firstValue = addressValue & networkMask;
    final lastValue = firstValue | hostMask;

    return LanIpNetwork._(
      networkAddress: _bigIntToAddressString(firstValue, address.type),
      prefixLength: prefix,
      addressType: address.type,
      firstValue: firstValue,
      lastValue: lastValue,
    );
  }

  static int compareAddresses(String a, String b) {
    final aAddress = _tryParseLiteral(a);
    final bAddress = _tryParseLiteral(b);

    if (aAddress == null || bAddress == null) {
      return a.compareTo(b);
    }
    if (aAddress.type != bAddress.type) {
      return aAddress.type == InternetAddressType.IPv4 ? -1 : 1;
    }

    final aBytes = aAddress.rawAddress;
    final bBytes = bAddress.rawAddress;
    final length = aBytes.length < bBytes.length
        ? aBytes.length
        : bBytes.length;

    for (var index = 0; index < length; index += 1) {
      final diff = aBytes[index] - bBytes[index];
      if (diff != 0) {
        return diff;
      }
    }

    return a.compareTo(b);
  }

  static String stripScopeId(String value) {
    final trimmed = value.trim();
    final separatorIndex = trimmed.indexOf('%');
    return separatorIndex >= 0 ? trimmed.substring(0, separatorIndex) : trimmed;
  }

  static bool looksLikeIpv6(String value) => stripScopeId(value).contains(':');

  BigInt get _usableHostCount {
    final total = _lastValue - _firstValue + BigInt.one;
    if (isIpv4 && prefixLength <= 30) {
      return total - BigInt.from(2);
    }
    if (isIpv6 && prefixLength < _bitLength) {
      return total - BigInt.one;
    }
    return total;
  }

  BigInt get _enumerationStart {
    if (isIpv4 && prefixLength <= 30) {
      return _firstValue + BigInt.one;
    }
    if (isIpv6 && prefixLength < _bitLength) {
      return _firstValue + BigInt.one;
    }
    return _firstValue;
  }

  static InternetAddress? _tryParseLiteral(String value) {
    final stripped = stripScopeId(value);
    if (stripped.isEmpty) {
      return null;
    }
    return InternetAddress.tryParse(stripped);
  }

  static BigInt _addressToBigInt(InternetAddress address) {
    var result = BigInt.zero;
    for (final byte in address.rawAddress) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  static String _bigIntToAddressString(
    BigInt value,
    InternetAddressType addressType,
  ) {
    final byteCount = addressType == InternetAddressType.IPv4 ? 4 : 16;
    final bytes = Uint8List(byteCount);
    var remaining = value;

    for (var index = byteCount - 1; index >= 0; index -= 1) {
      bytes[index] = (remaining & BigInt.from(0xFF)).toInt();
      remaining = remaining >> 8;
    }

    return InternetAddress.fromRawAddress(bytes).address;
  }
}
