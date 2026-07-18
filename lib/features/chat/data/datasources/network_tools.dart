import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_ping/dart_ping.dart';
import 'package:multicast_dns/multicast_dns.dart';

export 'network_tool_dependencies.dart'
    show NetworkAddressLookup, NetworkProcessRunner;

import 'network_address_utils.dart';
import 'network_http_tools.dart';
import 'network_neighbor_tools.dart';
import 'network_route_tools.dart';
import 'network_socket_tools.dart';
import 'network_tool_dependencies.dart';

typedef NetworkPingRunner =
    Future<String> Function({
      required String requestedHost,
      required String pingTarget,
      required int count,
      required int timeoutSeconds,
      String? resolvedIp,
      String? requestedIpVersion,
    });
typedef NetworkReverseLookup =
    Future<InternetAddress> Function(InternetAddress address);
typedef NetworkMdnsBrowseRunner =
    Future<Map<String, dynamic>> Function({
      required String serviceType,
      required int timeoutMs,
      required int maxResults,
      required String ipVersion,
    });

/// Network diagnostic utilities for built-in MCP tools.
///
/// All methods run locally without external API dependencies.
class NetworkTools {
  static final NetworkHttpTools _httpTools = NetworkHttpTools();
  static final NetworkNeighborTools _neighborTools = NetworkNeighborTools();
  static final NetworkRouteTools _routeTools = NetworkRouteTools();
  static final NetworkSocketTools _socketTools = NetworkSocketTools();

  static const Set<String> _supportedArpVersions = {'all', 'ipv4', 'ipv6'};
  static const Set<String> _supportedDnsRecordTypes = {
    'A',
    'AAAA',
    'PTR',
    'CNAME',
  };
  static const String _mdnsServiceCatalog = '_services._dns-sd._udp.local';

  // ---------------------------------------------------------------------------
  // DNS Lookup
  // ---------------------------------------------------------------------------

  /// Resolves [host] to IP addresses and returns a JSON-formatted result.
  static Future<String> dnsLookup({required String host}) async {
    final results = await InternetAddress.lookup(host);
    if (results.isEmpty) {
      return jsonEncode({'host': host, 'error': 'No records found'});
    }

    final records = results
        .map(
          (r) => {
            'address': r.address,
            'type': r.type == InternetAddressType.IPv4 ? 'A' : 'AAAA',
            'host': r.host,
          },
        )
        .toList();

    return jsonEncode({'host': host, 'records': records});
  }

  // ---------------------------------------------------------------------------
  // Route Lookup
  // ---------------------------------------------------------------------------

  /// Shows which route, interface, gateway, and source IP would be selected
  /// for a destination from the current machine.
  static Future<String> routeLookup({
    required String host,
    String ipVersion = 'auto',
    NetworkProcessRunner? processRunner,
    NetworkAddressLookup? addressLookup,
  }) {
    return _routeTools.routeLookup(
      host: host,
      ipVersion: ipVersion,
      processRunner: processRunner,
      addressLookup: addressLookup,
    );
  }

  // ---------------------------------------------------------------------------
  // Interface Info
  // ---------------------------------------------------------------------------

  /// Returns local interface addresses, MTU, flags, and default gateways.
  static Future<String> interfaceInfo({
    String? interfaceName,
    String ipVersion = 'all',
    NetworkProcessRunner? processRunner,
  }) {
    return _routeTools.interfaceInfo(
      interfaceName: interfaceName,
      ipVersion: ipVersion,
      processRunner: processRunner,
    );
  }

  // ---------------------------------------------------------------------------
  // DNS Query
  // ---------------------------------------------------------------------------

  /// Resolves a specific DNS record type for [target].
  static Future<String> dnsQuery({
    required String target,
    String recordType = 'A',
    NetworkAddressLookup? addressLookup,
    NetworkReverseLookup? reverseLookup,
    NetworkProcessRunner? processRunner,
  }) async {
    final normalizedType = recordType.trim().toUpperCase();
    if (!_supportedDnsRecordTypes.contains(normalizedType)) {
      return jsonEncode({
        'error': true,
        'message':
            'record_type must be one of: ${_supportedDnsRecordTypes.join(', ')}',
      });
    }

    final records = <Map<String, dynamic>>[];
    switch (normalizedType) {
      case 'A':
      case 'AAAA':
        final lookup = addressLookup ?? InternetAddress.lookup;
        final type = normalizedType == 'A'
            ? InternetAddressType.IPv4
            : InternetAddressType.IPv6;
        final addresses = await lookup(target, type: type);
        final seen = <String>{};
        for (final address in addresses) {
          if (seen.add(address.address)) {
            records.add({
              'type': normalizedType,
              'value': address.address,
              'host': address.host,
            });
          }
        }
        break;
      case 'PTR':
        final literal = InternetAddress.tryParse(
          normalizeNetworkIpForComparison(target),
        );
        if (literal == null) {
          return jsonEncode({
            'error': true,
            'message': 'PTR queries require an IPv4 or IPv6 literal address.',
          });
        }
        final reverse = reverseLookup ?? ((address) => address.reverse());
        final resolved = await reverse(literal);
        records.add({
          'type': normalizedType,
          'value': resolved.host,
          'address': literal.address,
        });
        break;
      case 'CNAME':
        final result = await _runProcess('nslookup', [
          '-type=cname',
          target,
        ], processRunner: processRunner);
        if (result.exitCode == 0) {
          final matches = RegExp(
            r'canonical name\s*=\s*(\S+)',
            caseSensitive: false,
          ).allMatches(result.stdout as String);
          final seen = <String>{};
          for (final match in matches) {
            final value = match.group(1);
            if (value != null && seen.add(value)) {
              records.add({'type': normalizedType, 'value': value});
            }
          }
        }
        break;
    }

    return jsonEncode({
      'target': target,
      'record_type': normalizedType,
      'records_found': records.length,
      'records': records,
    });
  }

  // ---------------------------------------------------------------------------
  // Path MTU
  // ---------------------------------------------------------------------------

  /// Attempts to discover the current path MTU for [host].
  static Future<String> pathMtu({
    required String host,
    String ipVersion = 'auto',
    NetworkProcessRunner? processRunner,
    NetworkAddressLookup? addressLookup,
  }) {
    return _routeTools.pathMtu(
      host: host,
      ipVersion: ipVersion,
      processRunner: processRunner,
      addressLookup: addressLookup,
    );
  }

  // ---------------------------------------------------------------------------
  // mDNS Browse
  // ---------------------------------------------------------------------------

  /// Browses the local multicast DNS service catalog or a specific service.
  static Future<String> mdnsBrowse({
    String serviceType = _mdnsServiceCatalog,
    String ipVersion = 'all',
    int timeoutMs = 2000,
    int maxResults = 50,
    NetworkMdnsBrowseRunner? browseRunner,
  }) async {
    final normalizedVersion = ipVersion.trim().toLowerCase();
    if (!_supportedArpVersions.contains(normalizedVersion)) {
      return jsonEncode({
        'error': true,
        'message':
            'ip_version must be one of: ${_supportedArpVersions.join(', ')}',
      });
    }

    final normalizedServiceType = _normalizeMdnsServiceType(serviceType);
    final effectiveTimeoutMs = timeoutMs.clamp(200, 10000).toInt();
    final effectiveMaxResults = maxResults.clamp(1, 100).toInt();

    final payload = browseRunner != null
        ? await browseRunner(
            serviceType: normalizedServiceType,
            timeoutMs: effectiveTimeoutMs,
            maxResults: effectiveMaxResults,
            ipVersion: normalizedVersion,
          )
        : await _browseMdnsPayload(
            serviceType: normalizedServiceType,
            timeoutMs: effectiveTimeoutMs,
            maxResults: effectiveMaxResults,
            ipVersion: normalizedVersion,
          );

    return jsonEncode(payload);
  }

  // ---------------------------------------------------------------------------
  // ARP / NDP Cache Inspection
  // ---------------------------------------------------------------------------

  static Future<String> arp({
    String? host,
    String ipVersion = 'all',
    NetworkProcessRunner? processRunner,
  }) {
    return _neighborTools.arp(
      host: host,
      ipVersion: ipVersion,
      processRunner: processRunner,
    );
  }

  static Future<String> ndp({
    String? host,
    NetworkProcessRunner? processRunner,
  }) {
    return _neighborTools.ndp(host: host, processRunner: processRunner);
  }

  // ---------------------------------------------------------------------------
  // Port Check
  // ---------------------------------------------------------------------------

  static Future<String> portCheck({
    required String host,
    required int port,
    int timeoutSeconds = 5,
  }) {
    return _socketTools.portCheck(
      host: host,
      port: port,
      timeoutSeconds: timeoutSeconds,
    );
  }

  // ---------------------------------------------------------------------------
  // SSL Certificate
  // ---------------------------------------------------------------------------

  static Future<String> sslCertificate({
    required String host,
    int port = 443,
    int timeoutSeconds = 10,
  }) {
    return _socketTools.sslCertificate(
      host: host,
      port: port,
      timeoutSeconds: timeoutSeconds,
    );
  }

  // ---------------------------------------------------------------------------
  // HTTP Status And Methods
  // ---------------------------------------------------------------------------

  static Future<String> httpStatus({
    required String url,
    int timeoutSeconds = 10,
  }) {
    return _httpTools.httpStatus(url: url, timeoutSeconds: timeoutSeconds);
  }

  static Future<String> httpGet({
    required String url,
    Map<String, String>? headers,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpTools.httpGet(
      url: url,
      headers: headers,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
    );
  }

  static Future<String> httpHead({
    required String url,
    Map<String, String>? headers,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpTools.httpHead(
      url: url,
      headers: headers,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
    );
  }

  static Future<String> httpDelete({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpTools.httpDelete(
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
    );
  }

  static Future<String> httpPost({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpTools.httpPost(
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
    );
  }

  static Future<String> httpPut({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpTools.httpPut(
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
    );
  }

  static Future<String> httpPatch({
    required String url,
    Map<String, String>? headers,
    String? body,
    String? contentType,
    int timeoutSeconds = 10,
    bool followRedirects = true,
    int maxRedirects = 5,
  }) {
    return _httpTools.httpPatch(
      url: url,
      headers: headers,
      body: body,
      contentType: contentType,
      timeoutSeconds: timeoutSeconds,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
    );
  }

  // ---------------------------------------------------------------------------
  // Traceroute
  // ---------------------------------------------------------------------------

  /// Traces the network path to [host] by incrementing TTL.
  static Future<String> traceroute({
    required String host,
    int maxHops = 20,
    int timeoutSeconds = 3,
  }) async {
    final hops = <Map<String, dynamic>>[];

    for (var ttl = 1; ttl <= maxHops; ttl++) {
      final ping = Ping(host, count: 1, timeout: timeoutSeconds, ttl: ttl);
      PingResponse? response;
      PingError? error;
      await for (final event in ping.stream) {
        switch (event) {
          case PingResponse():
            response = event;
          case PingError():
            error = event;
          case PingSummary():
        }
        if (response != null || error != null) break;
      }

      if (response == null && error == null) {
        hops.add({'hop': ttl, 'status': 'timeout'});
        continue;
      }

      if (error != null) {
        // TTL exceeded responses often come back as errors with the
        // intermediate router IP embedded in the message.
        hops.add({
          'hop': ttl,
          'status': 'ttl_exceeded',
          'message': _pingErrorMessage(error),
        });
        continue;
      }

      final resp = response!;
      final ms = resp.time?.inMicroseconds != null
          ? resp.time!.inMicroseconds / 1000.0
          : null;
      hops.add({
        'hop': ttl,
        'ip': resp.ip,
        if (ms != null) 'time_ms': double.parse(ms.toStringAsFixed(2)),
        'ttl': resp.ttl,
      });

      // Reached the destination.
      if (resp.ip != null) {
        try {
          final resolved = await InternetAddress.lookup(host);
          if (resolved.any((r) => r.address == resp.ip)) {
            break;
          }
        } catch (_) {
          // Ignore resolution failures; continue tracing.
        }
      }
    }

    return jsonEncode({'host': host, 'max_hops': maxHops, 'hops': hops});
  }

  // ---------------------------------------------------------------------------
  // Ping
  // ---------------------------------------------------------------------------
  /// Pings a [host] and returns a JSON-formatted result string.
  static Future<String> ping({
    required String host,
    int count = 4,
    int timeoutSeconds = 5,
    NetworkPingRunner? pingRunner,
  }) {
    return _runPing(
      requestedHost: host,
      pingTarget: host,
      count: count,
      timeoutSeconds: timeoutSeconds,
      pingRunner: pingRunner,
    );
  }

  /// Resolves [host] to IPv6 and pings the resulting IPv6 address.
  static Future<String> ping6({
    required String host,
    int count = 4,
    int timeoutSeconds = 5,
    NetworkAddressLookup? addressLookup,
    NetworkPingRunner? pingRunner,
  }) async {
    final ipv6Target = await _resolveIpv6Target(
      host,
      addressLookup: addressLookup,
    );
    return _runPing(
      requestedHost: host,
      pingTarget: ipv6Target.pingTarget,
      count: count,
      timeoutSeconds: timeoutSeconds,
      resolvedIp: ipv6Target.resolvedIp,
      requestedIpVersion: 'ipv6',
      pingRunner: pingRunner,
    );
  }

  static Future<String> _runPing({
    required String requestedHost,
    required String pingTarget,
    required int count,
    required int timeoutSeconds,
    String? resolvedIp,
    String? requestedIpVersion,
    NetworkPingRunner? pingRunner,
  }) async {
    final runner = pingRunner;
    if (runner != null) {
      return runner(
        requestedHost: requestedHost,
        pingTarget: pingTarget,
        count: count,
        timeoutSeconds: timeoutSeconds,
        resolvedIp: resolvedIp,
        requestedIpVersion: requestedIpVersion,
      );
    }

    final ping = Ping(pingTarget, count: count, timeout: timeoutSeconds);

    final results = <Map<String, dynamic>>[];
    var effectiveResolvedIp = resolvedIp;
    int transmitted = 0;
    int received = 0;
    final times = <double>[];

    await for (final event in ping.stream) {
      switch (event) {
        case PingResponse():
          effectiveResolvedIp ??= event.ip;
          transmitted++;
          if (event.time != null) {
            received++;
            final ms = event.time!.inMicroseconds / 1000.0;
            times.add(ms);
            results.add({
              'seq': event.seq,
              'ttl': event.ttl,
              'time_ms': double.parse(ms.toStringAsFixed(2)),
            });
          } else {
            results.add({'seq': event.seq, 'status': 'timeout'});
          }
        case PingError():
          transmitted++;
          results.add({
            'seq': event.seq ?? transmitted,
            'status': 'error',
            'message': _pingErrorMessage(event),
          });
        case PingSummary():
          // Use summary data if available.
          transmitted = event.transmitted;
          received = event.received;
      }
    }

    final lossPercent = transmitted > 0
        ? ((transmitted - received) / transmitted * 100).toStringAsFixed(1)
        : '0.0';

    final payload = <String, dynamic>{
      'host': requestedHost,
      ...?requestedIpVersion == null
          ? null
          : <String, dynamic>{'ip_version': requestedIpVersion},
      ...?effectiveResolvedIp == null
          ? null
          : <String, dynamic>{'resolved_ip': effectiveResolvedIp},
      'results': results,
      'summary': {
        'transmitted': transmitted,
        'received': received,
        'loss_percent': double.parse(lossPercent),
        if (times.isNotEmpty) ...{
          'min_ms': double.parse(
            times.reduce((a, b) => a < b ? a : b).toStringAsFixed(2),
          ),
          'avg_ms': double.parse(
            (times.reduce((a, b) => a + b) / times.length).toStringAsFixed(2),
          ),
          'max_ms': double.parse(
            times.reduce((a, b) => a > b ? a : b).toStringAsFixed(2),
          ),
        },
      },
    };

    return jsonEncode(payload);
  }

  static String _pingErrorMessage(PingError error) {
    return error.message ?? error.error.message;
  }

  static Future<({String pingTarget, String resolvedIp})> _resolveIpv6Target(
    String host, {
    NetworkAddressLookup? addressLookup,
  }) async {
    final literal = InternetAddress.tryParse(
      normalizeNetworkIpForComparison(host),
    );
    if (literal != null) {
      if (literal.type != InternetAddressType.IPv6) {
        throw SocketException('Host is not an IPv6 address');
      }
      return (pingTarget: host, resolvedIp: literal.address);
    }

    final lookup = addressLookup ?? InternetAddress.lookup;
    final addresses = await lookup(host, type: InternetAddressType.IPv6);
    if (addresses.isEmpty) {
      throw SocketException('No IPv6 address found for host "$host"');
    }

    return (
      pingTarget: addresses.first.address,
      resolvedIp: addresses.first.address,
    );
  }

  static Future<String> whoisLookup({required String domain}) {
    return _socketTools.whoisLookup(domain: domain);
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    NetworkProcessRunner? processRunner,
  }) {
    final runner = processRunner;
    return runner != null
        ? runner(executable, arguments)
        : Process.run(executable, arguments);
  }

  static Future<Map<String, dynamic>> _browseMdnsPayload({
    required String serviceType,
    required int timeoutMs,
    required int maxResults,
    required String ipVersion,
  }) async {
    final listenAddresses = ipVersion == 'ipv4'
        ? [InternetAddress.anyIPv4]
        : ipVersion == 'ipv6'
        ? [InternetAddress.anyIPv6]
        : [InternetAddress.anyIPv4, InternetAddress.anyIPv6];

    final serviceEntries = <String, _MdnsServiceEntry>{};
    final serviceTypes = <String>{};

    for (final listenAddress in listenAddresses) {
      MDnsClient? client;
      try {
        client = MDnsClient();
        await client.start(listenAddress: listenAddress);
        final pointers = await _collectStreamWithinTimeout<PtrResourceRecord>(
          client.lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
          ),
          timeout: Duration(milliseconds: timeoutMs),
          maxResults: maxResults,
        );

        if (serviceType == _mdnsServiceCatalog) {
          for (final pointer in pointers) {
            serviceTypes.add(pointer.domainName);
          }
          continue;
        }

        for (final pointer in pointers) {
          final instanceName = pointer.domainName;
          final targets = <_MdnsServiceTarget>[];
          final txtRecords = <String>{};

          final services = await _collectStreamWithinTimeout<SrvResourceRecord>(
            client.lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(instanceName),
            ),
            timeout: Duration(milliseconds: timeoutMs),
            maxResults: maxResults,
          );
          final texts = await _collectStreamWithinTimeout<TxtResourceRecord>(
            client.lookup<TxtResourceRecord>(
              ResourceRecordQuery.text(instanceName),
            ),
            timeout: Duration(milliseconds: timeoutMs),
            maxResults: maxResults,
          );
          for (final text in texts) {
            txtRecords.add(text.text);
          }

          for (final service in services) {
            final addresses = <String>{};
            if (ipVersion != 'ipv6') {
              final ipv4Addresses =
                  await _collectStreamWithinTimeout<IPAddressResourceRecord>(
                    client.lookup<IPAddressResourceRecord>(
                      ResourceRecordQuery.addressIPv4(service.target),
                    ),
                    timeout: Duration(milliseconds: timeoutMs),
                    maxResults: maxResults,
                  );
              addresses.addAll(
                ipv4Addresses.map((record) => record.address.address),
              );
            }
            if (ipVersion != 'ipv4') {
              final ipv6Addresses =
                  await _collectStreamWithinTimeout<IPAddressResourceRecord>(
                    client.lookup<IPAddressResourceRecord>(
                      ResourceRecordQuery.addressIPv6(service.target),
                    ),
                    timeout: Duration(milliseconds: timeoutMs),
                    maxResults: maxResults,
                  );
              addresses.addAll(
                ipv6Addresses.map((record) => record.address.address),
              );
            }

            targets.add(
              _MdnsServiceTarget(
                host: service.target,
                port: service.port,
                priority: service.priority,
                weight: service.weight,
                addresses: addresses.toList()..sort(compareNetworkIpAddresses),
              ),
            );
          }

          serviceEntries
              .putIfAbsent(
                instanceName,
                () => _MdnsServiceEntry(
                  instanceName: instanceName,
                  serviceType: serviceType,
                ),
              )
              .merge(
                _MdnsServiceEntry(
                  instanceName: instanceName,
                  serviceType: serviceType,
                  txtRecords: txtRecords.toList(growable: false),
                  targets: targets,
                ),
              );
        }
      } catch (_) {
        // Ignore transport-specific mDNS failures so the remaining family
        // still has a chance to return useful results.
      } finally {
        client?.stop();
      }
    }

    if (serviceType == _mdnsServiceCatalog) {
      final services = serviceTypes.toList()..sort();
      return {
        'service_type': serviceType,
        'ip_version': ipVersion,
        'services_found': services.length,
        'services': services.map((type) => {'service_type': type}).toList(),
      };
    }

    final services = serviceEntries.values.toList()
      ..sort((a, b) => a.instanceName.compareTo(b.instanceName));
    return {
      'service_type': serviceType,
      'ip_version': ipVersion,
      'services_found': services.length,
      'services': services.map((entry) => entry.toJson()).toList(),
    };
  }

  static Future<List<T>> _collectStreamWithinTimeout<T>(
    Stream<T> stream, {
    required Duration timeout,
    int? maxResults,
  }) async {
    final results = <T>[];
    final completer = Completer<List<T>>();
    late final StreamSubscription<T> subscription;

    void finish() {
      if (completer.isCompleted) {
        return;
      }
      subscription.cancel();
      completer.complete(results);
    }

    subscription = stream.listen(
      (event) {
        results.add(event);
        if (maxResults != null && results.length >= maxResults) {
          finish();
        }
      },
      onError: (error, stackTrace) => finish(),
      onDone: finish,
      cancelOnError: false,
    );

    Timer(timeout, finish);
    return completer.future;
  }

  static String _normalizeMdnsServiceType(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _mdnsServiceCatalog;
    }
    if (trimmed.endsWith('.local')) {
      return trimmed;
    }
    return '$trimmed.local';
  }

  static T? _firstWhereOrNull<T>(
    Iterable<T> values,
    bool Function(T value) predicate,
  ) {
    for (final value in values) {
      if (predicate(value)) {
        return value;
      }
    }
    return null;
  }
}

class _MdnsServiceEntry {
  _MdnsServiceEntry({
    required this.instanceName,
    required this.serviceType,
    List<String>? txtRecords,
    List<_MdnsServiceTarget>? targets,
  }) : txtRecords = txtRecords ?? <String>[],
       targets = targets ?? <_MdnsServiceTarget>[];

  final String instanceName;
  final String serviceType;
  final List<String> txtRecords;
  final List<_MdnsServiceTarget> targets;

  void merge(_MdnsServiceEntry other) {
    for (final record in other.txtRecords) {
      if (!txtRecords.contains(record)) {
        txtRecords.add(record);
      }
    }
    for (final target in other.targets) {
      final existing = NetworkTools._firstWhereOrNull<_MdnsServiceTarget>(
        targets,
        (entry) => entry.host == target.host && entry.port == target.port,
      );
      if (existing == null) {
        targets.add(target);
      } else {
        existing.merge(target);
      }
    }
    targets.sort((a, b) => a.host.compareTo(b.host));
  }

  Map<String, dynamic> toJson() => {
    'service_instance': instanceName,
    'service_type': serviceType,
    if (txtRecords.isNotEmpty) 'txt_records': txtRecords,
    if (targets.isNotEmpty)
      'targets': targets.map((entry) => entry.toJson()).toList(),
  };
}

class _MdnsServiceTarget {
  _MdnsServiceTarget({
    required this.host,
    required this.port,
    required this.priority,
    required this.weight,
    required this.addresses,
  });

  final String host;
  final int port;
  final int priority;
  final int weight;
  final List<String> addresses;

  void merge(_MdnsServiceTarget other) {
    for (final address in other.addresses) {
      if (!addresses.contains(address)) {
        addresses.add(address);
      }
    }
    addresses.sort(compareNetworkIpAddresses);
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'priority': priority,
    'weight': weight,
    if (addresses.isNotEmpty) 'addresses': addresses,
  };
}
