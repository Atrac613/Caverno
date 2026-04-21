/// LAN scan tool definitions for the LLM in OpenAI function-call format.
class LanScanTools {
  LanScanTools._();

  static const Set<String> allToolNames = {'lan_scan', 'lan_get_scan_results'};

  static Map<String, dynamic> get scanTool => {
    'type': 'function',
    'function': {
      'name': 'lan_scan',
      'description':
          'Scan the local network (LAN) for active hosts using ping sweep, '
          'port probing, and neighbor discovery. Discovers devices on the '
          'same subnet, resolves hostnames via reverse DNS, ARP/NDP, and '
          'mDNS/Bonjour (in priority order), checks common ports, and '
          'retrieves MAC addresses from the local link-layer cache '
          '(macOS/Linux only). IPv4 uses subnet enumeration. IPv6 uses '
          'neighbor discovery by default and only performs direct CIDR '
          'enumeration for small ranges.',
      'parameters': {
        'type': 'object',
        'properties': {
          'subnet': {
            'type': 'string',
            'description':
                'Target subnet in CIDR notation (e.g. 192.168.1.0/24 or '
                'fd00::/120). When omitted, the tool auto-detects the local '
                'IPv4 subnet and/or local IPv6 neighbor context.',
          },
          'ip_version': {
            'type': 'string',
            'enum': ['auto', 'ipv4', 'ipv6'],
            'description':
                'Address family to scan. Use auto to combine IPv4 subnet '
                'enumeration with IPv6 neighbor discovery when available '
                '(default: auto).',
          },
          'timeout': {
            'type': 'integer',
            'description':
                'Per-host probe timeout in milliseconds (default: 1000, max: 5000).',
          },
          'ports': {
            'type': 'array',
            'items': {'type': 'integer'},
            'description':
                'TCP ports to probe on each host (default: [22, 80, 443, 8080]). '
                'Max 20 ports.',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get getScanResultsTool => {
    'type': 'function',
    'function': {
      'name': 'lan_get_scan_results',
      'description':
          'Get the cached results from the most recent LAN scan. '
          'Each entry includes IP address, hostname, response time, '
          'open ports, and MAC address (when available).',
      'parameters': {
        'type': 'object',
        'properties': {
          'sort_by': {
            'type': 'string',
            'enum': ['ip', 'response_time', 'hostname'],
            'description':
                'Sort results by IP address (numerically), response time '
                '(fastest first), or hostname alphabetically '
                '(default: ip).',
          },
        },
        'required': <String>[],
      },
    },
  };

  /// All tool definitions for registration.
  static List<Map<String, dynamic>> get allTools => [
    scanTool,
    getScanResultsTool,
  ];
}
