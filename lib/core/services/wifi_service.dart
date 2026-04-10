import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../utils/logger.dart';

/// Manages WiFi scanning and connection info queries.
class WifiService {
  final NetworkInfo _networkInfo = NetworkInfo();

  List<WiFiAccessPoint> _scanResults = [];

  /// Whether the wifi_scan plugin is available on this platform.
  static bool get _isScanSupported => Platform.isAndroid || Platform.isIOS;

  /// Trigger a WiFi scan and return the results.
  ///
  /// Returns a JSON-encoded list of discovered access points, or an error
  /// message if scanning is not supported on this platform.
  Future<String> startScan() async {
    if (!_isScanSupported) {
      return jsonEncode({
        'error': true,
        'message': 'WiFi scanning is not supported on ${Platform.operatingSystem}. '
            'Use wifi_get_connection_info instead for current network details.',
      });
    }

    final wifiScan = WiFiScan.instance;

    final canScan = await wifiScan.canStartScan(askPermissions: true);
    if (canScan != CanStartScan.yes) {
      return jsonEncode({
        'error': true,
        'message': 'WiFi scanning is not available '
            '(status: ${canScan.name}). '
            'Try wifi_get_connection_info instead for current network details.',
      });
    }

    final success = await wifiScan.startScan();
    if (!success) {
      return jsonEncode({
        'error': true,
        'message': 'Failed to start WiFi scan.',
      });
    }

    final canGet = await wifiScan.canGetScannedResults(askPermissions: true);
    if (canGet != CanGetScannedResults.yes) {
      return jsonEncode({
        'error': true,
        'message':
            'Cannot retrieve scan results (status: ${canGet.name}).',
      });
    }

    _scanResults = await wifiScan.getScannedResults();
    appLog('WiFi scan completed: ${_scanResults.length} networks found');

    return _formatScanResults();
  }

  /// Return cached scan results, optionally sorted.
  String getScanResults({String? sortBy}) {
    if (!_isScanSupported) {
      return jsonEncode({
        'error': true,
        'message': 'WiFi scanning is not supported on ${Platform.operatingSystem}. '
            'Use wifi_get_connection_info instead.',
      });
    }

    if (_scanResults.isEmpty) {
      return jsonEncode({
        'networks': <Map<String, dynamic>>[],
        'message': 'No cached scan results. Call wifi_scan first.',
      });
    }

    final sorted = List<WiFiAccessPoint>.from(_scanResults);
    if (sortBy == 'ssid') {
      sorted.sort((a, b) => a.ssid.compareTo(b.ssid));
    } else {
      // Default: sort by signal strength (strongest first).
      sorted.sort((a, b) => b.level.compareTo(a.level));
    }

    return _formatResults(sorted);
  }

  /// Get information about the currently connected WiFi network.
  Future<String> getConnectionInfo() async {
    try {
      final wifiName = await _networkInfo.getWifiName();
      final wifiBssid = await _networkInfo.getWifiBSSID();
      final wifiIp = await _networkInfo.getWifiIP();
      final wifiIpv6 = await _networkInfo.getWifiIPv6();
      final wifiSubmask = await _networkInfo.getWifiSubmask();
      final wifiBroadcast = await _networkInfo.getWifiBroadcast();
      final wifiGateway = await _networkInfo.getWifiGatewayIP();

      // Strip iOS quotes around SSID (e.g. "\"MyNetwork\"" → "MyNetwork").
      final ssid = wifiName?.replaceAll('"', '');

      if (ssid == null && wifiIp == null) {
        return jsonEncode({
          'connected': false,
          'message': 'Not connected to a WiFi network, or location permission '
              'is required to read the SSID.',
        });
      }

      return jsonEncode({
        'connected': true,
        'ssid': ssid,
        'bssid': wifiBssid,
        'ip': wifiIp,
        'ipv6': wifiIpv6,
        'subnet_mask': wifiSubmask,
        'broadcast': wifiBroadcast,
        'gateway': wifiGateway,
      });
    } catch (e) {
      appLog('WiFi connection info error: $e');
      return jsonEncode({
        'error': true,
        'message': 'Failed to get WiFi connection info: $e',
      });
    }
  }

  Future<void> dispose() async {
    _scanResults.clear();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  String _formatScanResults() {
    final sorted = List<WiFiAccessPoint>.from(_scanResults)
      ..sort((a, b) => b.level.compareTo(a.level));
    return _formatResults(sorted);
  }

  String _formatResults(List<WiFiAccessPoint> results) {
    final networks = results.map((ap) {
      return {
        'ssid': ap.ssid.isEmpty ? '<hidden>' : ap.ssid,
        'bssid': ap.bssid,
        'signal_dbm': ap.level,
        'frequency_mhz': ap.frequency,
        'capabilities': ap.capabilities,
      };
    }).toList();

    return jsonEncode({
      'count': networks.length,
      'networks': networks,
    });
  }
}

final wifiServiceProvider = Provider<WifiService>((ref) {
  final service = WifiService();
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
