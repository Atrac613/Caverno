import 'dart:io';

typedef NetworkProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

typedef NetworkAddressLookup =
    Future<List<InternetAddress>> Function(
      String host, {
      InternetAddressType type,
    });
