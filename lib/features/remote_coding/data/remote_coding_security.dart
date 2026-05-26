import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

class RemoteCodingSecurity {
  RemoteCodingSecurity._();

  static final Random _random = Random.secure();

  static String randomToken({int byteLength = 32}) {
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String hashToken(String token) {
    return sha256.convert(utf8.encode(token.trim())).toString();
  }

  static bool constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    var diff = leftBytes.length ^ rightBytes.length;
    final maxLength = max(leftBytes.length, rightBytes.length);
    for (var index = 0; index < maxLength; index += 1) {
      final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
      final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
      diff |= leftByte ^ rightByte;
    }
    return diff == 0;
  }
}

class RemoteCodingNetworkPolicy {
  RemoteCodingNetworkPolicy._();

  static bool isLanHost(String host) {
    final normalizedHost = host.trim().toLowerCase();
    if (normalizedHost == 'localhost') {
      return true;
    }
    final address = InternetAddress.tryParse(normalizedHost);
    return address != null && isLanAddress(address);
  }

  static bool isLanAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) {
      return true;
    }
    if (address.type == InternetAddressType.IPv4) {
      final bytes = address.rawAddress;
      if (bytes.length != 4) return false;
      final first = bytes[0];
      final second = bytes[1];
      return first == 10 ||
          (first == 172 && second >= 16 && second <= 31) ||
          (first == 192 && second == 168) ||
          (first == 169 && second == 254);
    }
    if (address.type == InternetAddressType.IPv6) {
      final bytes = address.rawAddress;
      if (bytes.isEmpty) return false;
      final first = bytes[0];
      return (first & 0xfe) == 0xfc || first == 0xfe;
    }
    return false;
  }
}
