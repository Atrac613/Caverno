import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'network_tools.dart';

typedef BuiltInNetworkOperationRunner =
    Future<String> Function({
      required String name,
      required Map<String, dynamic> arguments,
    });

/// Owns the built-in network tool definitions and execution contract.
class BuiltInNetworkToolHandler {
  BuiltInNetworkToolHandler({BuiltInNetworkOperationRunner? operationRunner})
    : _operationRunner = operationRunner ?? _runNetworkOperation;

  static const List<String> toolNames = <String>[
    'ping',
    'ping6',
    'arp',
    'ndp',
    'route_lookup',
    'interface_info',
    'whois_lookup',
    'dns_lookup',
    'dns_query',
    'port_check',
    'ssl_certificate',
    'http_status',
    'http_get',
    'http_head',
    'http_post',
    'http_put',
    'http_patch',
    'http_delete',
    'traceroute',
    'path_mtu',
    'mdns_browse',
  ];

  static const Set<String> _toolNameSet = <String>{...toolNames};

  final BuiltInNetworkOperationRunner _operationRunner;

  List<Map<String, dynamic>> get definitions => <Map<String, dynamic>>[
    _pingTool,
    _ping6Tool,
    _arpTool,
    _ndpTool,
    _routeLookupTool,
    _interfaceInfoTool,
    _whoisLookupTool,
    _dnsLookupTool,
    _dnsQueryTool,
    _portCheckTool,
    _sslCertificateTool,
    _httpStatusTool,
    _httpGetTool,
    _httpHeadTool,
    _httpPostTool,
    _httpPutTool,
    _httpPatchTool,
    _httpDeleteTool,
    _tracerouteTool,
    _pathMtuTool,
    _mdnsBrowseTool,
  ];

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown network tool');
    }

    try {
      late final Map<String, dynamic> normalizedArguments;
      switch (name) {
        case 'ping':
        case 'ping6':
          final host = (arguments['host'] as String?)?.trim() ?? '';
          if (host.isEmpty) {
            return _validationFailure(name, 'Host is required');
          }
          normalizedArguments = <String, dynamic>{
            'host': host,
            'count': ((arguments['count'] as num?)?.toInt() ?? 4).clamp(1, 10),
            'timeout': ((arguments['timeout'] as num?)?.toInt() ?? 5).clamp(
              1,
              30,
            ),
          };
        case 'arp':
          final host = (arguments['host'] as String?)?.trim();
          normalizedArguments = <String, dynamic>{
            'host': host == null || host.isEmpty ? null : host,
            'ip_version': (arguments['ip_version'] as String?)?.trim() ?? 'all',
          };
        case 'ndp':
          final host = (arguments['host'] as String?)?.trim();
          normalizedArguments = <String, dynamic>{
            'host': host == null || host.isEmpty ? null : host,
          };
        case 'route_lookup':
          final host = (arguments['host'] as String?)?.trim() ?? '';
          if (host.isEmpty) {
            return _validationFailure(name, 'Host is required');
          }
          normalizedArguments = <String, dynamic>{
            'host': host,
            'ip_version':
                (arguments['ip_version'] as String?)?.trim().toLowerCase() ??
                'auto',
          };
        case 'interface_info':
          final interfaceName = (arguments['interface'] as String?)?.trim();
          normalizedArguments = <String, dynamic>{
            'interface': interfaceName == null || interfaceName.isEmpty
                ? null
                : interfaceName,
            'ip_version':
                (arguments['ip_version'] as String?)?.trim().toLowerCase() ??
                'all',
          };
        case 'whois_lookup':
          final domain = (arguments['domain'] as String?)?.trim() ?? '';
          if (domain.isEmpty) {
            return _validationFailure(name, 'Domain is required');
          }
          normalizedArguments = <String, dynamic>{'domain': domain};
        case 'dns_lookup':
          final host = (arguments['host'] as String?)?.trim() ?? '';
          if (host.isEmpty) {
            return _validationFailure(name, 'Host is required');
          }
          normalizedArguments = <String, dynamic>{'host': host};
        case 'dns_query':
          final target = (arguments['target'] as String?)?.trim() ?? '';
          if (target.isEmpty) {
            return _validationFailure(name, 'Target is required');
          }
          normalizedArguments = <String, dynamic>{
            'target': target,
            'record_type':
                (arguments['record_type'] as String?)?.trim().toUpperCase() ??
                'A',
          };
        case 'port_check':
          final host = (arguments['host'] as String?)?.trim() ?? '';
          final port = (arguments['port'] as num?)?.toInt();
          if (host.isEmpty || port == null) {
            return _validationFailure(name, 'Host and port are required');
          }
          normalizedArguments = <String, dynamic>{
            'host': host,
            'port': port,
            'timeout': ((arguments['timeout'] as num?)?.toInt() ?? 5).clamp(
              1,
              30,
            ),
          };
        case 'ssl_certificate':
          final host = (arguments['host'] as String?)?.trim() ?? '';
          if (host.isEmpty) {
            return _validationFailure(name, 'Host is required');
          }
          normalizedArguments = <String, dynamic>{
            'host': host,
            'port': ((arguments['port'] as num?)?.toInt() ?? 443).clamp(
              1,
              65535,
            ),
          };
        case 'http_status':
          final url = (arguments['url'] as String?)?.trim() ?? '';
          if (url.isEmpty) {
            return _validationFailure(name, 'URL is required');
          }
          normalizedArguments = <String, dynamic>{
            'url': url,
            'timeout': ((arguments['timeout'] as num?)?.toInt() ?? 10).clamp(
              1,
              30,
            ),
          };
        case 'http_get':
        case 'http_head':
        case 'http_post':
        case 'http_put':
        case 'http_patch':
        case 'http_delete':
          final url = (arguments['url'] as String?)?.trim() ?? '';
          if (url.isEmpty) {
            return _validationFailure(name, 'URL is required');
          }
          normalizedArguments = <String, dynamic>{
            'url': url,
            'headers': _parseHeaderMap(arguments['headers']),
            'body': arguments['body'] as String?,
            'content_type': (arguments['content_type'] as String?)?.trim(),
            'timeout': ((arguments['timeout'] as num?)?.toInt() ?? 10).clamp(
              1,
              30,
            ),
            'follow_redirects': arguments['follow_redirects'] as bool? ?? true,
            'max_redirects':
                ((arguments['max_redirects'] as num?)?.toInt() ?? 5).clamp(
                  0,
                  10,
                ),
          };
        case 'traceroute':
          final host = (arguments['host'] as String?)?.trim() ?? '';
          if (host.isEmpty) {
            return _validationFailure(name, 'Host is required');
          }
          normalizedArguments = <String, dynamic>{
            'host': host,
            'max_hops': ((arguments['max_hops'] as num?)?.toInt() ?? 20).clamp(
              1,
              30,
            ),
            'timeout': ((arguments['timeout'] as num?)?.toInt() ?? 3).clamp(
              1,
              10,
            ),
          };
        case 'path_mtu':
          final host = (arguments['host'] as String?)?.trim() ?? '';
          if (host.isEmpty) {
            return _validationFailure(name, 'Host is required');
          }
          normalizedArguments = <String, dynamic>{
            'host': host,
            'ip_version':
                (arguments['ip_version'] as String?)?.trim().toLowerCase() ??
                'auto',
          };
        case 'mdns_browse':
          normalizedArguments = <String, dynamic>{
            'service_type':
                (arguments['service_type'] as String?)?.trim().isNotEmpty ==
                    true
                ? (arguments['service_type'] as String).trim()
                : '_services._dns-sd._udp.local',
            'ip_version':
                (arguments['ip_version'] as String?)?.trim().toLowerCase() ??
                'all',
            'timeout_ms': ((arguments['timeout_ms'] as num?)?.toInt() ?? 2000)
                .clamp(200, 10000),
            'max_results': ((arguments['max_results'] as num?)?.toInt() ?? 50)
                .clamp(1, 100),
          };
      }

      final result = await _operationRunner(
        name: name,
        arguments: normalizedArguments,
      );
      appLog(_successLog(name));
      return McpToolResult(toolName: name, result: result, isSuccess: true);
    } catch (error) {
      appLog(_errorLog(name, error));
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: error.toString(),
      );
    }
  }

  static McpToolResult _validationFailure(String name, String message) {
    return McpToolResult(
      toolName: name,
      result: '',
      isSuccess: false,
      errorMessage: message,
    );
  }

  static String _successLog(String name) => switch (name) {
    'ping' => '[McpToolService] Ping tool executed successfully',
    'ping6' => '[McpToolService] Ping6 tool executed successfully',
    'arp' => '[McpToolService] ARP tool executed successfully',
    'ndp' => '[McpToolService] NDP tool executed successfully',
    'route_lookup' => '[McpToolService] Route lookup executed successfully',
    'interface_info' => '[McpToolService] Interface info executed successfully',
    'whois_lookup' => '[McpToolService] Whois tool executed successfully',
    'dns_lookup' => '[McpToolService] DNS lookup executed successfully',
    'dns_query' => '[McpToolService] DNS query executed successfully',
    'port_check' => '[McpToolService] Port check executed successfully',
    'ssl_certificate' =>
      '[McpToolService] SSL certificate check executed successfully',
    'http_status' => '[McpToolService] HTTP status check executed successfully',
    'http_get' ||
    'http_head' ||
    'http_post' ||
    'http_put' ||
    'http_patch' ||
    'http_delete' => '[McpToolService] $name executed successfully',
    'traceroute' => '[McpToolService] Traceroute executed successfully',
    'path_mtu' => '[McpToolService] Path MTU executed successfully',
    'mdns_browse' => '[McpToolService] mDNS browse executed successfully',
    _ => throw StateError('Unknown network tool: $name'),
  };

  static String _errorLog(String name, Object error) => switch (name) {
    'ping' => '[McpToolService] Ping tool error: $error',
    'ping6' => '[McpToolService] Ping6 tool error: $error',
    'arp' => '[McpToolService] ARP tool error: $error',
    'ndp' => '[McpToolService] NDP tool error: $error',
    'route_lookup' => '[McpToolService] Route lookup error: $error',
    'interface_info' => '[McpToolService] Interface info error: $error',
    'whois_lookup' => '[McpToolService] Whois tool error: $error',
    'dns_lookup' => '[McpToolService] DNS lookup error: $error',
    'dns_query' => '[McpToolService] DNS query error: $error',
    'port_check' => '[McpToolService] Port check error: $error',
    'ssl_certificate' => '[McpToolService] SSL certificate error: $error',
    'http_status' => '[McpToolService] HTTP status error: $error',
    'http_get' ||
    'http_head' ||
    'http_post' ||
    'http_put' ||
    'http_patch' ||
    'http_delete' => '[McpToolService] $name error: $error',
    'traceroute' => '[McpToolService] Traceroute error: $error',
    'path_mtu' => '[McpToolService] Path MTU error: $error',
    'mdns_browse' => '[McpToolService] mDNS browse error: $error',
    _ => throw StateError('Unknown network tool: $name'),
  };

  static Map<String, String>? _parseHeaderMap(dynamic raw) {
    if (raw is! Map) return null;
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (key == null || value == null) return;
      result[key.toString()] = value.toString();
    });
    return result.isEmpty ? null : result;
  }

  static Future<String> _runNetworkOperation({
    required String name,
    required Map<String, dynamic> arguments,
  }) => switch (name) {
    'ping' => NetworkTools.ping(
      host: arguments['host'] as String,
      count: arguments['count'] as int,
      timeoutSeconds: arguments['timeout'] as int,
    ),
    'ping6' => NetworkTools.ping6(
      host: arguments['host'] as String,
      count: arguments['count'] as int,
      timeoutSeconds: arguments['timeout'] as int,
    ),
    'arp' => NetworkTools.arp(
      host: arguments['host'] as String?,
      ipVersion: arguments['ip_version'] as String,
    ),
    'ndp' => NetworkTools.ndp(host: arguments['host'] as String?),
    'route_lookup' => NetworkTools.routeLookup(
      host: arguments['host'] as String,
      ipVersion: arguments['ip_version'] as String,
    ),
    'interface_info' => NetworkTools.interfaceInfo(
      interfaceName: arguments['interface'] as String?,
      ipVersion: arguments['ip_version'] as String,
    ),
    'whois_lookup' => NetworkTools.whoisLookup(
      domain: arguments['domain'] as String,
    ),
    'dns_lookup' => NetworkTools.dnsLookup(host: arguments['host'] as String),
    'dns_query' => NetworkTools.dnsQuery(
      target: arguments['target'] as String,
      recordType: arguments['record_type'] as String,
    ),
    'port_check' => NetworkTools.portCheck(
      host: arguments['host'] as String,
      port: arguments['port'] as int,
      timeoutSeconds: arguments['timeout'] as int,
    ),
    'ssl_certificate' => NetworkTools.sslCertificate(
      host: arguments['host'] as String,
      port: arguments['port'] as int,
    ),
    'http_status' => NetworkTools.httpStatus(
      url: arguments['url'] as String,
      timeoutSeconds: arguments['timeout'] as int,
    ),
    'http_get' => NetworkTools.httpGet(
      url: arguments['url'] as String,
      headers: arguments['headers'] as Map<String, String>?,
      timeoutSeconds: arguments['timeout'] as int,
      followRedirects: arguments['follow_redirects'] as bool,
      maxRedirects: arguments['max_redirects'] as int,
    ),
    'http_head' => NetworkTools.httpHead(
      url: arguments['url'] as String,
      headers: arguments['headers'] as Map<String, String>?,
      timeoutSeconds: arguments['timeout'] as int,
      followRedirects: arguments['follow_redirects'] as bool,
      maxRedirects: arguments['max_redirects'] as int,
    ),
    'http_post' => NetworkTools.httpPost(
      url: arguments['url'] as String,
      headers: arguments['headers'] as Map<String, String>?,
      body: arguments['body'] as String?,
      contentType: arguments['content_type'] as String?,
      timeoutSeconds: arguments['timeout'] as int,
      followRedirects: arguments['follow_redirects'] as bool,
      maxRedirects: arguments['max_redirects'] as int,
    ),
    'http_put' => NetworkTools.httpPut(
      url: arguments['url'] as String,
      headers: arguments['headers'] as Map<String, String>?,
      body: arguments['body'] as String?,
      contentType: arguments['content_type'] as String?,
      timeoutSeconds: arguments['timeout'] as int,
      followRedirects: arguments['follow_redirects'] as bool,
      maxRedirects: arguments['max_redirects'] as int,
    ),
    'http_patch' => NetworkTools.httpPatch(
      url: arguments['url'] as String,
      headers: arguments['headers'] as Map<String, String>?,
      body: arguments['body'] as String?,
      contentType: arguments['content_type'] as String?,
      timeoutSeconds: arguments['timeout'] as int,
      followRedirects: arguments['follow_redirects'] as bool,
      maxRedirects: arguments['max_redirects'] as int,
    ),
    'http_delete' => NetworkTools.httpDelete(
      url: arguments['url'] as String,
      headers: arguments['headers'] as Map<String, String>?,
      body: arguments['body'] as String?,
      contentType: arguments['content_type'] as String?,
      timeoutSeconds: arguments['timeout'] as int,
      followRedirects: arguments['follow_redirects'] as bool,
      maxRedirects: arguments['max_redirects'] as int,
    ),
    'traceroute' => NetworkTools.traceroute(
      host: arguments['host'] as String,
      maxHops: arguments['max_hops'] as int,
      timeoutSeconds: arguments['timeout'] as int,
    ),
    'path_mtu' => NetworkTools.pathMtu(
      host: arguments['host'] as String,
      ipVersion: arguments['ip_version'] as String,
    ),
    'mdns_browse' => NetworkTools.mdnsBrowse(
      serviceType: arguments['service_type'] as String,
      ipVersion: arguments['ip_version'] as String,
      timeoutMs: arguments['timeout_ms'] as int,
      maxResults: arguments['max_results'] as int,
    ),
    _ => throw ArgumentError.value(name, 'name', 'Unknown network tool'),
  };

  static Map<String, dynamic> get _pingTool => {
    'type': 'function',
    'function': {
      'name': 'ping',
      'description':
          'Ping a network host to check reachability and measure latency. '
          'Returns round-trip times, packet loss, and statistics.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description':
                'Hostname or IP address to ping (e.g., google.com, 8.8.8.8)',
          },
          'count': {
            'type': 'integer',
            'description':
                'Number of ping packets to send (default: 4, max: 10)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout per ping in seconds (default: 5)',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _ping6Tool => {
    'type': 'function',
    'function': {
      'name': 'ping6',
      'description':
          'Ping a host over IPv6. Resolves the host to an IPv6 address, then '
          'checks reachability and latency using ICMPv6.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description':
                'IPv6 hostname or literal address to ping (e.g., ipv6.google.com, 2001:4860:4860::8888)',
          },
          'count': {
            'type': 'integer',
            'description':
                'Number of ping packets to send (default: 4, max: 10)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout per ping in seconds (default: 5)',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _arpTool => {
    'type': 'function',
    'function': {
      'name': 'arp',
      'description':
          'Inspect the local ARP/NDP neighbor cache to see recently observed '
          'IP-to-MAC mappings on the current network. Supports both IPv4 '
          '(ARP) and IPv6 neighbor discovery entries when the platform '
          'exposes them.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description':
                'Optional hostname or IP address to filter for a specific '
                'neighbor entry.',
          },
          'ip_version': {
            'type': 'string',
            'enum': ['all', 'ipv4', 'ipv6'],
            'description':
                'Address family to inspect (default: all). IPv4 reads the '
                'ARP table and IPv6 reads the NDP/neighbor table.',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get _ndpTool => {
    'type': 'function',
    'function': {
      'name': 'ndp',
      'description':
          'Inspect the local IPv6 neighbor discovery cache to see recently '
          'observed IPv6-to-MAC mappings on the current network.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description':
                'Optional IPv6 address or hostname filter for a specific '
                'neighbor entry.',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get _routeLookupTool => {
    'type': 'function',
    'function': {
      'name': 'route_lookup',
      'description':
          'Show which interface, gateway, and source IP the local machine '
          'would use to reach a destination. Useful for IPv4/IPv6 route '
          'selection diagnostics.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname or IP address to evaluate',
          },
          'ip_version': {
            'type': 'string',
            'enum': ['auto', 'ipv4', 'ipv6'],
            'description':
                'Address family to inspect (default: auto). Auto returns the '
                'first reachable IPv4 and IPv6 route when available.',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _interfaceInfoTool => {
    'type': 'function',
    'function': {
      'name': 'interface_info',
      'description':
          'Inspect local network interfaces, addresses, MTU, flags, and '
          'default gateways.',
      'parameters': {
        'type': 'object',
        'properties': {
          'interface': {
            'type': 'string',
            'description':
                'Optional interface name to inspect (for example en0, eth0).',
          },
          'ip_version': {
            'type': 'string',
            'enum': ['all', 'ipv4', 'ipv6'],
            'description':
                'Address family filter for the returned addresses and '
                'gateways (default: all).',
          },
        },
        'required': <String>[],
      },
    },
  };

  static Map<String, dynamic> get _whoisLookupTool => {
    'type': 'function',
    'function': {
      'name': 'whois_lookup',
      'description':
          'Look up domain registration information (WHOIS). Returns registrar, '
          'creation/expiry dates, name servers, and registrant details.',
      'parameters': {
        'type': 'object',
        'properties': {
          'domain': {
            'type': 'string',
            'description': 'Domain name to look up (e.g., example.com)',
          },
        },
        'required': ['domain'],
      },
    },
  };

  static Map<String, dynamic> get _dnsLookupTool => {
    'type': 'function',
    'function': {
      'name': 'dns_lookup',
      'description':
          'Resolve a hostname to IP addresses (A/AAAA records). '
          'Returns all resolved addresses with their type.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname to resolve (e.g., google.com)',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _dnsQueryTool => {
    'type': 'function',
    'function': {
      'name': 'dns_query',
      'description':
          'Resolve a specific DNS record type. Supports A, AAAA, PTR, and '
          'CNAME queries for precise dual-stack troubleshooting.',
      'parameters': {
        'type': 'object',
        'properties': {
          'target': {
            'type': 'string',
            'description':
                'Hostname or IP address to query. PTR expects a literal IP.',
          },
          'record_type': {
            'type': 'string',
            'enum': ['A', 'AAAA', 'PTR', 'CNAME'],
            'description': 'DNS record type to query (default: A).',
          },
        },
        'required': ['target'],
      },
    },
  };

  static Map<String, dynamic> get _portCheckTool => {
    'type': 'function',
    'function': {
      'name': 'port_check',
      'description':
          'Test whether a specific TCP port is open on a host. '
          'Returns open/closed status and response time.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname or IP address to check',
          },
          'port': {
            'type': 'integer',
            'description': 'TCP port number to test (e.g., 80, 443, 8080)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout in seconds (default: 5)',
          },
        },
        'required': ['host', 'port'],
      },
    },
  };

  static Map<String, dynamic> get _sslCertificateTool => {
    'type': 'function',
    'function': {
      'name': 'ssl_certificate',
      'description':
          'Inspect the TLS/SSL certificate of a host. Returns subject, issuer, '
          'validity dates, and whether it is currently valid.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname to inspect (e.g., google.com)',
          },
          'port': {
            'type': 'integer',
            'description': 'Port number (default: 443)',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _httpStatusTool => {
    'type': 'function',
    'function': {
      'name': 'http_status',
      'description':
          'Check if a URL is reachable. Returns HTTP status code, response '
          'headers, response time, and redirect chain.',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'Full URL to check (e.g., https://example.com)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout in seconds (default: 10)',
          },
        },
        'required': ['url'],
      },
    },
  };

  static Map<String, dynamic> _httpMethodSchema({
    required String name,
    required String description,
    required bool acceptsBody,
  }) {
    final properties = <String, dynamic>{
      'url': {
        'type': 'string',
        'description': 'Full URL to request (e.g., https://example.com/api)',
      },
      'headers': {
        'type': 'object',
        'description':
            'Optional request headers as a JSON object of string values '
            '(e.g., {"Authorization": "Bearer ..."}).',
        'additionalProperties': {'type': 'string'},
      },
      'timeout': {
        'type': 'integer',
        'description': 'Timeout in seconds (default: 10, max: 30)',
      },
      'follow_redirects': {
        'type': 'boolean',
        'description': 'Whether to follow HTTP redirects (default: true)',
      },
      'max_redirects': {
        'type': 'integer',
        'description': 'Maximum redirects to follow (default: 5, max: 10)',
      },
    };

    if (acceptsBody) {
      properties['body'] = {
        'type': 'string',
        'description':
            'Raw request body as a string. For JSON, pass a stringified '
            'JSON document and set content_type accordingly.',
      };
      properties['content_type'] = {
        'type': 'string',
        'description':
            'Convenience for the Content-Type header (default: '
            'application/json when body is provided). Ignored if a '
            'Content-Type entry is also supplied via headers.',
      };
    }

    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': ['url'],
        },
      },
    };
  }

  static Map<String, dynamic> get _httpGetTool => _httpMethodSchema(
    name: 'http_get',
    description:
        'Perform an HTTP GET request and return status code, headers, '
        'and the response body (UTF-8 decoded, truncated to 4000 chars).',
    acceptsBody: false,
  );

  static Map<String, dynamic> get _httpHeadTool => _httpMethodSchema(
    name: 'http_head',
    description:
        'Perform an HTTP HEAD request. Returns status code and response '
        'headers without the body.',
    acceptsBody: false,
  );

  static Map<String, dynamic> get _httpPostTool => _httpMethodSchema(
    name: 'http_post',
    description:
        'Perform an HTTP POST request with an optional request body. '
        'Returns status code, headers, and response body (truncated to '
        '4000 chars).',
    acceptsBody: true,
  );

  static Map<String, dynamic> get _httpPutTool => _httpMethodSchema(
    name: 'http_put',
    description:
        'Perform an HTTP PUT request with an optional request body. '
        'Returns status code, headers, and response body (truncated to '
        '4000 chars).',
    acceptsBody: true,
  );

  static Map<String, dynamic> get _httpPatchTool => _httpMethodSchema(
    name: 'http_patch',
    description:
        'Perform an HTTP PATCH request with an optional request body. '
        'Returns status code, headers, and response body (truncated to '
        '4000 chars).',
    acceptsBody: true,
  );

  static Map<String, dynamic> get _httpDeleteTool => _httpMethodSchema(
    name: 'http_delete',
    description:
        'Perform an HTTP DELETE request. A request body is permitted '
        'but optional. Returns status code, headers, and response body '
        '(truncated to 4000 chars).',
    acceptsBody: true,
  );

  static Map<String, dynamic> get _tracerouteTool => {
    'type': 'function',
    'function': {
      'name': 'traceroute',
      'description':
          'Trace the network path to a host by incrementing TTL. '
          'Shows each hop with IP address and response time.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname or IP address to trace (e.g., google.com)',
          },
          'max_hops': {
            'type': 'integer',
            'description': 'Maximum number of hops (default: 20, max: 30)',
          },
          'timeout': {
            'type': 'integer',
            'description': 'Timeout per hop in seconds (default: 3)',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _pathMtuTool => {
    'type': 'function',
    'function': {
      'name': 'path_mtu',
      'description':
          'Attempt to discover the path MTU to a destination. Uses '
          'tracepath when available and otherwise falls back to the local '
          'egress interface MTU as an upper bound.',
      'parameters': {
        'type': 'object',
        'properties': {
          'host': {
            'type': 'string',
            'description': 'Hostname or IP address to evaluate',
          },
          'ip_version': {
            'type': 'string',
            'enum': ['auto', 'ipv4', 'ipv6'],
            'description': 'Address family to inspect (default: auto).',
          },
        },
        'required': ['host'],
      },
    },
  };

  static Map<String, dynamic> get _mdnsBrowseTool => {
    'type': 'function',
    'function': {
      'name': 'mdns_browse',
      'description':
          'Browse local multicast DNS services. By default it lists '
          'advertised service types, or it can inspect a specific service '
          'such as _ipp._tcp.local.',
      'parameters': {
        'type': 'object',
        'properties': {
          'service_type': {
            'type': 'string',
            'description':
                'mDNS service type to browse (default: _services._dns-sd._udp.local).',
          },
          'ip_version': {
            'type': 'string',
            'enum': ['all', 'ipv4', 'ipv6'],
            'description':
                'Transport and address family preference (default: all).',
          },
          'timeout_ms': {
            'type': 'integer',
            'description':
                'How long to wait for responses in milliseconds '
                '(default: 2000, max: 10000).',
          },
          'max_results': {
            'type': 'integer',
            'description':
                'Maximum number of services or PTR answers to collect '
                '(default: 50, max: 100).',
          },
        },
        'required': <String>[],
      },
    },
  };
}
