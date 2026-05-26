import 'dart:async';
import 'dart:io';

import '../domain/remote_coding_models.dart';

class RemoteCodingConnectionMessages {
  const RemoteCodingConnectionMessages._();

  static String missingHost() {
    return 'Pair with a desktop host first. Open Remote Coding Host on the desktop, then scan the pairing QR from this phone.';
  }

  static String missingSavedToken(RemoteCodingHost host) {
    return 'Saved credentials for ${host.name} are incomplete. Pair with the desktop again so this phone receives a fresh device token.';
  }

  static String invalidPairingCode() {
    return 'This QR code is not a Caverno Remote Coding pairing code. Open Remote Coding Host on the desktop and scan a fresh pairing QR.';
  }

  static String expiredPairingCode() {
    return 'Pairing code has expired. Generate a new Remote Coding QR on the desktop and scan it within 5 minutes.';
  }

  static String nonLanPairingCode() {
    return 'Pairing code host must be a LAN address. Make sure the desktop and phone are on the same local network, then generate a new QR.';
  }

  static String nonLanHost(RemoteCodingHost host) {
    return 'Saved remote coding host ${host.host}:${host.port} is not a LAN address. Pair again while both devices are on the same local network.';
  }

  static String connectionClosed(RemoteCodingHost? host) {
    final endpoint = host == null
        ? 'the desktop host'
        : '${host.host}:${host.port}';
    return 'Remote coding connection closed for $endpoint. If the desktop slept, changed Wi-Fi, or Remote Coding Host restarted, reconnect or scan a fresh pairing QR.';
  }

  static String connectionFailure(Object error, RemoteCodingHost host) {
    final endpoint = '${host.host}:${host.port}';
    if (error is TimeoutException) {
      return 'Timed out connecting to remote coding host at $endpoint. Make sure the desktop app is running, Remote Coding Host is enabled, and both devices are on the same LAN.';
    }
    if (error is SocketException) {
      return 'Could not reach remote coding host at $endpoint. Check that both devices are on the same LAN, the desktop IP has not changed, and the desktop firewall allows Caverno.';
    }
    if (error is WebSocketException) {
      return 'Remote coding host at $endpoint rejected the WebSocket connection. Pair again if the desktop host was restarted.';
    }
    return 'Failed to connect to remote coding host at $endpoint: $error';
  }

  static String unauthorizedToken() {
    return 'Remote coding token was rejected. Pair with the desktop again; the saved token may have expired, been revoked, or belonged to another desktop install.';
  }

  static String revokedDevice() {
    return 'This mobile device was revoked on the desktop. Pair again from Remote Coding Host to reconnect.';
  }

  static List<String> recoverySteps({
    required RemoteCodingHost? host,
    required String? error,
  }) {
    final steps = <String>[
      'Keep the phone and desktop on the same Wi-Fi or LAN.',
      'Open Settings > Tools > Remote Coding Host on the desktop and confirm it is enabled.',
      'If the desktop IP changed, scan a new pairing QR instead of reconnecting.',
    ];
    final lowerError = (error ?? '').toLowerCase();
    if (host != null) {
      steps.add('Current saved endpoint: ${host.host}:${host.port}.');
    }
    if (lowerError.contains('firewall') || lowerError.contains('reach')) {
      steps.add('Allow Caverno through the desktop firewall for LAN clients.');
    }
    if (lowerError.contains('reconnecting')) {
      steps.add('Leave this screen open; the app will retry automatically.');
    }
    if (lowerError.contains('token') || lowerError.contains('revoked')) {
      steps.add('Use Forget Host, then pair again from the desktop QR.');
    }
    if (lowerError.contains('expired') || lowerError.contains('qr')) {
      steps.add('Generate a new QR; pairing codes expire after 5 minutes.');
    }
    return steps;
  }
}
