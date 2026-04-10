/// WiFi tool definitions for the LLM in OpenAI function-call format.
class WifiTools {
  WifiTools._();

  static const Set<String> allToolNames = {
    'wifi_scan',
    'wifi_get_scan_results',
    'wifi_get_connection_info',
  };

  static Map<String, dynamic> get scanTool => {
    'type': 'function',
    'function': {
      'name': 'wifi_scan',
      'description':
          'Scan for nearby WiFi access points and return the results. '
          'Results are also cached and can be retrieved later with '
          'wifi_get_scan_results. Requires location permission on most platforms.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  };

  static Map<String, dynamic> get getScanResultsTool => {
    'type': 'function',
    'function': {
      'name': 'wifi_get_scan_results',
      'description':
          'Get the cached results from the most recent WiFi scan. '
          'Each entry includes SSID, BSSID, signal level (dBm), frequency, '
          'and security capabilities.',
      'parameters': {
        'type': 'object',
        'properties': {
          'sort_by': {
            'type': 'string',
            'enum': ['signal', 'ssid'],
            'description':
                'Sort results by signal strength (strongest first) or '
                'SSID name alphabetically (default: signal).',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get getConnectionInfoTool => {
    'type': 'function',
    'function': {
      'name': 'wifi_get_connection_info',
      'description':
          'Get information about the currently connected WiFi network '
          'including SSID, BSSID, and IP address. '
          'Returns an error if not connected to WiFi.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  };

  /// All tool definitions for registration.
  static List<Map<String, dynamic>> get allTools => [
    scanTool,
    getScanResultsTool,
    getConnectionInfoTool,
  ];
}
