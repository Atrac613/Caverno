import 'dart:io';

String normalizeNetworkIpForComparison(String value) {
  final separatorIndex = value.indexOf('%');
  return separatorIndex >= 0 ? value.substring(0, separatorIndex) : value;
}

int compareNetworkIpAddresses(String a, String b) {
  final aAddress = InternetAddress.tryParse(normalizeNetworkIpForComparison(a));
  final bAddress = InternetAddress.tryParse(normalizeNetworkIpForComparison(b));

  if (aAddress == null || bAddress == null) {
    return a.compareTo(b);
  }

  if (aAddress.type != bAddress.type) {
    return aAddress.type == InternetAddressType.IPv4 ? -1 : 1;
  }

  final aBytes = aAddress.rawAddress;
  final bBytes = bAddress.rawAddress;
  final maxLength = aBytes.length < bBytes.length
      ? aBytes.length
      : bBytes.length;

  for (var index = 0; index < maxLength; index += 1) {
    final difference = aBytes[index] - bBytes[index];
    if (difference != 0) {
      return difference;
    }
  }

  return a.compareTo(b);
}
