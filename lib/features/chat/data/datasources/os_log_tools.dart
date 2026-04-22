import 'dart:convert';
import 'dart:io';

typedef OsLogProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class OsLogTools {
  OsLogTools._();

  static const Set<String> allToolNames = {'os_get_system_info', 'os_log_read'};
  static const Set<String> _supportedScopes = {
    'wifi',
    'network',
    'authentication',
    'system',
  };
  static const int _defaultSinceMinutes = 30;
  static const int _defaultMaxEntries = 50;
  static const int _maxSinceMinutes = 24 * 60;
  static const int _maxEntries = 200;
  static const List<String> _errorHints = [
    'error',
    'fail',
    'failed',
    'failure',
    'denied',
    'reject',
    'rejected',
    'timeout',
    'timed out',
    'deauth',
    'disconnect',
    'invalid',
    'unable',
  ];

  static bool get supportsSystemInfo =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  static bool get supportsLogRead => Platform.isMacOS || Platform.isLinux;
  static bool get isSupportedPlatform => supportsLogRead;

  static Map<String, dynamic> get systemInfoTool => {
    'type': 'function',
    'function': {
      'name': 'os_get_system_info',
      'description':
          'Get the current machine operating system name, version, build, '
          'kernel, and architecture. Use this before interpreting local OS '
          'logs when the platform or version is unclear.',
      'parameters': {'type': 'object', 'properties': {}},
    },
  };

  static Map<String, dynamic> get readTool => {
    'type': 'function',
    'function': {
      'name': 'os_log_read',
      'description':
          'Read recent local OS logs from this machine to investigate WiFi, '
          'network, or authentication problems. Best used to correlate local '
          'client-side failures with external AP/syslog findings. '
          'Available on macOS and Linux desktop environments.',
      'parameters': {
        'type': 'object',
        'properties': {
          'scope': {
            'type': 'string',
            'enum': ['wifi', 'network', 'authentication', 'system'],
            'description':
                'High-level filter preset. Use wifi or authentication for '
                'WiFi disconnect and login failures.',
          },
          'keywords': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional list of case-insensitive text snippets to match in '
                'log lines, such as ["auth", "802.1x", "eapol"].',
          },
          'process': {
            'type': 'string',
            'description':
                'Optional process name filter, such as "eapolclient" or '
                '"wifid".',
          },
          'subsystem': {
            'type': 'string',
            'description':
                'Optional macOS subsystem filter, such as "com.apple.wifi".',
          },
          'since_minutes': {
            'type': 'integer',
            'description':
                'How many recent minutes to inspect (default: 30, max: 1440).',
          },
          'max_entries': {
            'type': 'integer',
            'description':
                'Maximum number of matching log lines to return '
                '(default: 50, max: 200).',
          },
          'include_debug': {
            'type': 'boolean',
            'description':
                'Whether to include debug-level macOS unified log entries. '
                'Use this only when normal results are insufficient.',
          },
        },
        'required': <String>[],
      },
    },
  };

  static List<Map<String, dynamic>> get allTools {
    final tools = <Map<String, dynamic>>[];
    if (supportsSystemInfo) {
      tools.add(systemInfoTool);
    }
    if (supportsLogRead) {
      tools.add(readTool);
    }
    return tools;
  }

  static Future<String> getSystemInfo({
    OsLogProcessRunner? processRunner,
    String? linuxOsReleaseContents,
    Map<String, String>? environment,
  }) async {
    if (!supportsSystemInfo) {
      return jsonEncode({
        'error': true,
        'message':
            'System information inspection is only supported on desktop platforms.',
      });
    }

    final runner = processRunner ?? _defaultProcessRunner;
    final env = environment ?? Platform.environment;
    final info = <String, dynamic>{
      'os_family': Platform.operatingSystem,
      'raw_operating_system_version': Platform.operatingSystemVersion,
      'os_log_read_supported': supportsLogRead,
    };

    if (Platform.isMacOS) {
      final swVers = await _runCommandText(
        executable: '/usr/bin/sw_vers',
        arguments: const [],
        processRunner: runner,
      );
      final swVersMap = _parseKeyValueLines(swVers);
      final kernelVersion = await _runCommandText(
        executable: '/usr/bin/uname',
        arguments: const ['-r'],
        processRunner: runner,
      );
      final architecture = await _runCommandText(
        executable: '/usr/bin/uname',
        arguments: const ['-m'],
        processRunner: runner,
      );

      info.addAll({
        'name': swVersMap['ProductName'] ?? 'macOS',
        'version': swVersMap['ProductVersion'],
        'build': swVersMap['BuildVersion'],
        if (kernelVersion != null && kernelVersion.isNotEmpty)
          'kernel_version': kernelVersion,
        if (architecture != null && architecture.isNotEmpty)
          'architecture': architecture,
        'log_access_method': '/usr/bin/log show',
      });
      return jsonEncode(info);
    }

    if (Platform.isLinux) {
      final osReleaseContents =
          linuxOsReleaseContents ?? (await _readLinuxOsRelease()) ?? '';
      final osRelease = _parseOsRelease(osReleaseContents);
      final kernelVersion = await _runCommandText(
        executable: 'uname',
        arguments: const ['-r'],
        processRunner: runner,
      );
      final architecture = await _runCommandText(
        executable: 'uname',
        arguments: const ['-m'],
        processRunner: runner,
      );

      info.addAll({
        'name': osRelease['PRETTY_NAME'] ?? osRelease['NAME'] ?? 'Linux',
        'version':
            osRelease['VERSION_ID'] ??
            osRelease['VERSION'] ??
            Platform.operatingSystemVersion,
        if (kernelVersion != null && kernelVersion.isNotEmpty)
          'kernel_version': kernelVersion,
        if (architecture != null && architecture.isNotEmpty)
          'architecture': architecture,
        if (osRelease['ID'] != null) 'distribution_id': osRelease['ID'],
        'log_access_method': 'journalctl',
      });
      return jsonEncode(info);
    }

    if (Platform.isWindows) {
      info.addAll({
        'name': 'Windows',
        'version': Platform.operatingSystemVersion,
        if (env['PROCESSOR_ARCHITECTURE'] != null)
          'architecture': env['PROCESSOR_ARCHITECTURE'],
        if (env['PROCESSOR_IDENTIFIER'] != null)
          'processor_identifier': env['PROCESSOR_IDENTIFIER'],
      });
      return jsonEncode(info);
    }

    return jsonEncode(info);
  }

  static Future<String> read({
    String scope = 'wifi',
    List<String> keywords = const [],
    String? process,
    String? subsystem,
    int sinceMinutes = _defaultSinceMinutes,
    int maxEntries = _defaultMaxEntries,
    bool includeDebug = false,
    OsLogProcessRunner? processRunner,
  }) async {
    if (!supportsLogRead) {
      return jsonEncode({
        'error': true,
        'message': 'OS log inspection is only supported on macOS and Linux.',
      });
    }

    final normalizedScope = scope.trim().toLowerCase();
    if (!_supportedScopes.contains(normalizedScope)) {
      final supportedScopes = _supportedScopes.toList()..sort();
      return jsonEncode({
        'error': true,
        'message': 'scope must be one of: ${supportedScopes.join(', ')}',
      });
    }

    final windowMinutes = sinceMinutes.clamp(1, _maxSinceMinutes);
    final entryLimit = maxEntries.clamp(1, _maxEntries);
    final normalizedKeywords = keywords
        .map((keyword) => keyword.trim())
        .where((keyword) => keyword.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final normalizedProcess = process?.trim();
    final normalizedSubsystem = subsystem?.trim();
    final now = DateTime.now();
    final startTime = now.subtract(Duration(minutes: windowMinutes));
    final command = Platform.isMacOS
        ? _buildMacOsCommand(
            scope: normalizedScope,
            process: normalizedProcess,
            subsystem: normalizedSubsystem,
            sinceMinutes: windowMinutes,
            includeDebug: includeDebug,
          )
        : _buildLinuxCommand(scope: normalizedScope, startTime: startTime);
    final runner = processRunner ?? _defaultProcessRunner;

    try {
      final result = await runner(command.executable, command.arguments);
      final stdout = result.stdout.toString();
      final stderr = result.stderr.toString();

      if (result.exitCode != 0) {
        return jsonEncode({
          'error': true,
          'platform': Platform.isMacOS ? 'macos' : 'linux',
          'scope': normalizedScope,
          'command': command.displayCommand,
          'exit_code': result.exitCode,
          'message': 'The OS log command exited with a non-zero status.',
          if (stderr.trim().isNotEmpty) 'stderr': _truncate(stderr, 4000),
          if (stdout.trim().isNotEmpty) 'stdout': _truncate(stdout, 4000),
        });
      }

      final candidateLines = _extractCandidateLines(stdout);
      final matchingLines = candidateLines
          .where(
            (line) => _matchesLineFilters(
              line,
              keywords: normalizedKeywords,
              process: normalizedProcess,
              subsystem: normalizedSubsystem,
            ),
          )
          .toList(growable: false);
      final recentMatches = matchingLines.reversed
          .take(entryLimit)
          .map((line) => _buildEntry(line, keywords: normalizedKeywords))
          .toList(growable: false);

      return jsonEncode({
        'platform': Platform.isMacOS ? 'macos' : 'linux',
        'scope': normalizedScope,
        'command': command.displayCommand,
        'time_window_minutes': windowMinutes,
        'time_window_start': startTime.toIso8601String(),
        'time_window_end': now.toIso8601String(),
        'keywords': normalizedKeywords,
        if (normalizedProcess != null && normalizedProcess.isNotEmpty)
          'process': normalizedProcess,
        if (normalizedSubsystem != null && normalizedSubsystem.isNotEmpty)
          'subsystem': normalizedSubsystem,
        'entries_scanned': candidateLines.length,
        'matches_found': matchingLines.length,
        'entries_returned': recentMatches.length,
        'ordered_newest_first': true,
        if (matchingLines.length > entryLimit) 'truncated': true,
        if (stderr.trim().isNotEmpty) 'stderr': _truncate(stderr, 2000),
        'entries': recentMatches,
      });
    } on ProcessException catch (e) {
      return jsonEncode({
        'error': true,
        'platform': Platform.isMacOS ? 'macos' : 'linux',
        'scope': normalizedScope,
        'command': command.displayCommand,
        'message': e.message,
      });
    } catch (e) {
      return jsonEncode({
        'error': true,
        'platform': Platform.isMacOS ? 'macos' : 'linux',
        'scope': normalizedScope,
        'command': command.displayCommand,
        'message': e.toString(),
      });
    }
  }

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments);
  }

  static Future<String?> _runCommandText({
    required String executable,
    required List<String> arguments,
    required OsLogProcessRunner processRunner,
  }) async {
    try {
      final result = await processRunner(executable, arguments);
      if (result.exitCode != 0) {
        return null;
      }
      final stdout = result.stdout.toString().trim();
      return stdout.isEmpty ? null : stdout;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _readLinuxOsRelease() async {
    const paths = ['/etc/os-release', '/usr/lib/os-release'];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        return file.readAsString();
      }
    }
    return null;
  }

  static Map<String, String> _parseKeyValueLines(String? raw) {
    final map = <String, String>{};
    if (raw == null || raw.trim().isEmpty) {
      return map;
    }
    for (final line in const LineSplitter().convert(raw)) {
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        map[key] = value;
      }
    }
    return map;
  }

  static Map<String, String> _parseOsRelease(String raw) {
    final map = <String, String>{};
    if (raw.trim().isEmpty) {
      return map;
    }
    for (final line in const LineSplitter().convert(raw)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final separator = trimmed.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = trimmed.substring(0, separator).trim();
      var value = trimmed.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty && value.isNotEmpty) {
        map[key] = value;
      }
    }
    return map;
  }

  static _OsLogCommand _buildMacOsCommand({
    required String scope,
    required int sinceMinutes,
    required bool includeDebug,
    String? process,
    String? subsystem,
  }) {
    final args = <String>[
      'show',
      '--style',
      'compact',
      '--last',
      '${sinceMinutes}m',
      '--info',
    ];
    if (includeDebug) {
      args.add('--debug');
    }
    final predicate = _buildMacOsPredicate(
      scope: scope,
      process: process,
      subsystem: subsystem,
    );
    if (predicate != null && predicate.isNotEmpty) {
      args.addAll(['--predicate', predicate]);
    }
    return _OsLogCommand('/usr/bin/log', args);
  }

  static _OsLogCommand _buildLinuxCommand({
    required String scope,
    required DateTime startTime,
  }) {
    final args = <String>[
      '--since',
      _formatJournalctlDateTime(startTime),
      '--no-pager',
      '--output',
      'short-iso',
    ];
    for (final unit in _linuxUnitsForScope(scope)) {
      args.addAll(['-u', unit]);
    }
    return _OsLogCommand('journalctl', args);
  }

  static String? _buildMacOsPredicate({
    required String scope,
    String? process,
    String? subsystem,
  }) {
    final clauses = <String>[];
    final scopeClause = _macOsScopePredicate(scope);
    if (scopeClause != null) {
      clauses.add(scopeClause);
    }
    if (process != null && process.isNotEmpty) {
      clauses.add('process == "${_escapeMacPredicateValue(process)}"');
    }
    if (subsystem != null && subsystem.isNotEmpty) {
      clauses.add('subsystem == "${_escapeMacPredicateValue(subsystem)}"');
    }
    if (clauses.isEmpty) {
      return null;
    }
    return clauses.join(' AND ');
  }

  static String? _macOsScopePredicate(String scope) {
    return switch (scope) {
      'wifi' =>
        '(subsystem CONTAINS[c] "wifi" OR process == "airportd" OR process == "wifid" OR process == "eapolclient" OR eventMessage CONTAINS[c] "Wi-Fi" OR eventMessage CONTAINS[c] "wifi")',
      'network' =>
        '(subsystem CONTAINS[c] "network" OR process == "networkd" OR process == "configd" OR process == "mDNSResponder" OR eventMessage CONTAINS[c] "network" OR eventMessage CONTAINS[c] "dhcp" OR eventMessage CONTAINS[c] "dns")',
      'authentication' =>
        '(process == "eapolclient" OR eventMessage CONTAINS[c] "auth" OR eventMessage CONTAINS[c] "authentication" OR eventMessage CONTAINS[c] "802.1x" OR eventMessage CONTAINS[c] "eap" OR eventMessage CONTAINS[c] "handshake" OR eventMessage CONTAINS[c] "deny" OR eventMessage CONTAINS[c] "reject")',
      'system' => null,
      _ => null,
    };
  }

  static List<String> _linuxUnitsForScope(String scope) {
    return switch (scope) {
      'wifi' => const ['NetworkManager', 'wpa_supplicant', 'iwd'],
      'network' => const [
        'NetworkManager',
        'systemd-networkd',
        'systemd-resolved',
        'wpa_supplicant',
        'iwd',
      ],
      'authentication' => const ['wpa_supplicant', 'iwd', 'NetworkManager'],
      'system' => const [],
      _ => const [],
    };
  }

  static List<String> _extractCandidateLines(String stdout) {
    return const LineSplitter()
        .convert(stdout)
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .where((line) => !line.startsWith('Timestamp'))
        .toList(growable: false);
  }

  static bool _matchesLineFilters(
    String line, {
    required List<String> keywords,
    String? process,
    String? subsystem,
  }) {
    final lowerLine = line.toLowerCase();
    if (keywords.isNotEmpty &&
        !keywords.any((keyword) => lowerLine.contains(keyword.toLowerCase()))) {
      return false;
    }
    if (process != null &&
        process.isNotEmpty &&
        !lowerLine.contains(process.toLowerCase())) {
      return false;
    }
    if (Platform.isLinux &&
        subsystem != null &&
        subsystem.isNotEmpty &&
        !lowerLine.contains(subsystem.toLowerCase())) {
      return false;
    }
    return true;
  }

  static Map<String, dynamic> _buildEntry(
    String line, {
    required List<String> keywords,
  }) {
    final lowerLine = line.toLowerCase();
    final matchedKeywords = keywords
        .where((keyword) => lowerLine.contains(keyword.toLowerCase()))
        .toList(growable: false);
    final severityHints = _errorHints
        .where((keyword) => lowerLine.contains(keyword))
        .toList(growable: false);
    final timestamp = _extractLeadingTimestamp(line);

    final entry = <String, dynamic>{
      'line': _truncate(line, 1200),
      if (matchedKeywords.isNotEmpty) 'matched_keywords': matchedKeywords,
      if (severityHints.isNotEmpty) 'severity_hints': severityHints,
      'looks_like_error': severityHints.isNotEmpty,
    };
    if (timestamp != null) {
      entry['timestamp'] = timestamp;
    }
    return entry;
  }

  static String? _extractLeadingTimestamp(String line) {
    final compactMatch = RegExp(
      r'^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[+-]\d{4})?)',
    ).firstMatch(line);
    if (compactMatch != null) {
      return compactMatch.group(1);
    }

    final journalMatch = RegExp(
      r'^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})',
    ).firstMatch(line);
    return journalMatch?.group(1);
  }

  static String _formatJournalctlDateTime(DateTime value) {
    String twoDigits(int input) => input.toString().padLeft(2, '0');
    return '${value.year}-'
        '${twoDigits(value.month)}-'
        '${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:'
        '${twoDigits(value.minute)}:'
        '${twoDigits(value.second)}';
  }

  static String _escapeMacPredicateValue(String value) {
    return value.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength - 1)}...';
  }
}

class _OsLogCommand {
  const _OsLogCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;

  String get displayCommand => [executable, ...arguments].join(' ');
}
