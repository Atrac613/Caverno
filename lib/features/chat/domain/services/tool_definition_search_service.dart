import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'tool_result_prompt_builder.dart';

class ToolDefinitionSearchSelection {
  const ToolDefinitionSearchSelection({
    required this.toolSearchEnabled,
    required this.toolDefinitions,
    required this.selectedToolNames,
  });

  final bool toolSearchEnabled;
  final List<Map<String, dynamic>> toolDefinitions;
  final Set<String> selectedToolNames;
}

class ToolDefinitionSearchService {
  ToolDefinitionSearchService._();

  static const toolName = 'tool_search';
  static const autoEnableToolCountThreshold = 24;
  static const defaultMaxResults = 8;
  static const maxResultsLimit = 20;

  /// A query term appearing in more than this many searchable tools' text is
  /// treated as generic (e.g. "device", "data", "get"): it no longer earns
  /// description/parameter points, so a tool is not matched just because a
  /// common word happens to recur in its docs. Name-level matches always count.
  static const genericDescriptionTermToolThreshold = 4;

  static const Set<String> _searchToolNames = {
    'search_web',
    'search_news',
    'search_images',
    'searxng_web_search',
    'web_search',
  };

  static const Set<String> _alwaysLoadedToolNames = {
    toolName,
    'get_current_datetime',
    'search_past_conversations',
    'recall_memory',
    'ask_user_question',
    'spawn_subagent',
    'get_subagent_result',
    'load_skill',
    // Keep save_skill in the initial set so in-chat skill authoring is
    // discoverable without the model first calling tool_search; the system
    // prompt only injects save_skill guidance when the tool is selected.
    'save_skill',
    'search_web',
    'search_news',
    'search_images',
    'searxng_web_search',
    'web_search',
    'ping',
    'whois_lookup',
    'dns_lookup',
    'port_check',
    'ssl_certificate',
    'http_status',
    'traceroute',
    'list_directory',
    'read_file',
    'write_file',
    'edit_file',
    'rollback_last_file_change',
    'process_start',
    'process_status',
    'process_tail',
    'process_wait',
    'process_list',
    'process_cancel',
    'find_files',
    'search_files',
    'local_execute_command',
    'run_tests',
    'git_execute_command',
    // Keep dependency grounding in the initial set so coding answers can be
    // grounded in the project's installed sources without first calling
    // tool_search (LL10). Covered by the F6 classification guard.
    'resolve_installed_dependency',
    'ping6',
    'arp',
    'ndp',
    'route_lookup',
    'interface_info',
    'dns_query',
    'http_get',
    'http_head',
    'path_mtu',
    'mdns_browse',
    'wifi_scan',
    'wifi_get_scan_results',
    'wifi_get_connection_info',
    'lan_scan',
    'lan_get_scan_results',
    'get_wifi_health',
    'get_wan_status',
    'get_dns_health',
    'get_conn_overview',
    'get_capture_health',
    'get_weird_events',
    'get_notice_events',
    'explain_network_slowdown_context',
  };

  static Map<String, dynamic> get toolDefinition => const {
    'type': 'function',
    'function': {
      'name': toolName,
      'description':
          'Search the available tool catalog by task, capability, or tool name. '
          'Use this when the needed tool is not currently available in the tool list.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Capability or tool name to search for, such as "read a MCP resource" or "database query".',
          },
          'max_results': {
            'type': 'integer',
            'description': 'Maximum number of matching tools to return.',
            'minimum': 1,
            'maximum': maxResultsLimit,
          },
        },
        'required': ['query'],
      },
    },
  };

  static List<Map<String, dynamic>> appendSearchToolIfUseful(
    List<Map<String, dynamic>> definitions,
  ) {
    final deduped = ToolResultPromptBuilder.dedupeToolsByName(definitions);
    if (!shouldEnableToolSearch(deduped) || _containsTool(deduped, toolName)) {
      return deduped;
    }
    return ToolResultPromptBuilder.dedupeToolsByName([
      toolDefinition,
      ...deduped,
    ]);
  }

  static bool shouldEnableToolSearch(List<Map<String, dynamic>> definitions) {
    final searchable = _searchableDefinitions(
      definitions,
    ).toList(growable: false);
    return searchable.length > autoEnableToolCountThreshold ||
        _hasSearchAndBrowserTools(searchable);
  }

  static ToolDefinitionSearchSelection buildInitialSelection(
    List<Map<String, dynamic>> definitions,
  ) {
    final deduped = ToolResultPromptBuilder.dedupeToolsByName(definitions);
    final enabled = shouldEnableToolSearch(deduped);
    final selectedNames = enabled
        ? _defaultInitialToolNames(deduped)
        : _legacyInitialToolNames(deduped);
    return ToolDefinitionSearchSelection(
      toolSearchEnabled: enabled,
      toolDefinitions: enabled
          ? definitionsForSelectedTools(
              deduped,
              selectedToolNames: selectedNames,
              toolSearchEnabled: enabled,
            )
          : _definitionsMatchingNames(deduped, selectedNames),
      selectedToolNames: selectedNames,
    );
  }

  static List<Map<String, dynamic>> definitionsForSelectedTools(
    List<Map<String, dynamic>> definitions, {
    required Set<String> selectedToolNames,
    required bool toolSearchEnabled,
  }) {
    final deduped = ToolResultPromptBuilder.dedupeToolsByName(definitions);
    if (!toolSearchEnabled) {
      return deduped;
    }

    final selected = <Map<String, dynamic>>[toolDefinition];
    for (final definition in deduped) {
      final name = toolNameFromDefinition(definition);
      if (name == null || name == toolName) continue;
      if (selectedToolNames.contains(name)) {
        selected.add(definition);
      }
    }
    return ToolResultPromptBuilder.dedupeToolsByName(selected);
  }

  static String searchToolDefinitions({
    required List<Map<String, dynamic>> definitions,
    required String query,
    int maxResults = defaultMaxResults,
  }) {
    final trimmedQuery = query.trim();
    final normalizedQuery = _normalize(trimmedQuery);
    final limit = maxResults.clamp(1, maxResultsLimit).toInt();
    if (normalizedQuery.isEmpty) {
      return jsonEncode({
        'query': trimmedQuery,
        'matched_tool_count': 0,
        'matched_tools': const <Map<String, dynamic>>[],
        'message': 'Provide a non-empty query to search the tool catalog.',
      });
    }

    final terms = _tokenize(normalizedQuery);
    final searchable = _searchableDefinitions(
      definitions,
    ).toList(growable: false);
    final genericTerms = _genericQueryTerms(searchable, terms);
    final scored = <_ScoredToolDefinition>[];
    for (final definition in searchable) {
      final score = _scoreDefinition(
        definition,
        normalizedQuery,
        terms,
        genericTerms,
      );
      if (score <= 0) continue;
      scored.add(_ScoredToolDefinition(definition: definition, score: score));
    }
    scored.sort((a, b) {
      final scoreComparison = b.score.compareTo(a.score);
      if (scoreComparison != 0) return scoreComparison;
      return (toolNameFromDefinition(a.definition) ?? '').compareTo(
        toolNameFromDefinition(b.definition) ?? '',
      );
    });

    final matches = scored
        .take(limit)
        .map((match) {
          final function = match.definition['function'] as Map;
          return {
            'name': function['name'],
            if (function['description'] is String)
              'description': function['description'],
            if (function['parameters'] is Map)
              'parameters': function['parameters'],
            'score': match.score,
          };
        })
        .toList(growable: false);

    return jsonEncode({
      'query': trimmedQuery,
      'matched_tool_count': matches.length,
      'matched_tools': matches,
      'message': matches.isEmpty
          ? 'No matching tools were found. Try a broader capability query.'
          : 'These tools will be available in the next tool-call request. Call the best matching tool next.',
    });
  }

  static Set<String> discoveredToolNamesFromResults(
    Iterable<ToolResultInfo> toolResults,
  ) {
    final discovered = <String>{};
    for (final toolResult in toolResults) {
      if (toolResult.name != toolName) continue;
      final decoded = _tryDecodeJsonMap(toolResult.result);
      final matches = decoded?['matched_tools'];
      if (matches is! List) continue;
      for (final match in matches) {
        if (match is! Map) continue;
        final name = match['name'];
        if (name is String && name.isNotEmpty && name != toolName) {
          discovered.add(name);
        }
      }
    }
    return discovered;
  }

  static String? toolNameFromDefinition(Map<String, dynamic> definition) {
    final function = definition['function'];
    if (function is! Map) return null;
    final name = function['name'];
    return name is String && name.isNotEmpty ? name : null;
  }

  static Set<String> toolNamesFromDefinitions(
    Iterable<Map<String, dynamic>> definitions,
  ) {
    return definitions.map(toolNameFromDefinition).whereType<String>().toSet();
  }

  static Set<String> _legacyInitialToolNames(
    List<Map<String, dynamic>> definitions,
  ) {
    final names = toolNamesFromDefinitions(definitions);
    if (names.any(_searchToolNames.contains)) {
      return names.intersection(_alwaysLoadedToolNames);
    }
    return names;
  }

  static Set<String> _defaultInitialToolNames(
    List<Map<String, dynamic>> definitions,
  ) {
    final names = toolNamesFromDefinitions(definitions);
    return names.where(shouldLoadInitially).toSet()..add(toolName);
  }

  /// Whether [toolName] is part of the initial tool-search selection (sent on
  /// the first request) rather than deferred behind `tool_search`. Public so
  /// the F6 classification guard can assert every built-in tool is either
  /// initial-loaded or intentionally deferred.
  static bool shouldLoadInitially(String toolName) {
    final normalized = toolName.trim().toLowerCase();
    return _alwaysLoadedToolNames.contains(normalized) ||
        normalized.startsWith('wifi_') ||
        normalized.startsWith('get_wifi_') ||
        normalized.startsWith('wan_') ||
        normalized.startsWith('get_wan_') ||
        normalized.startsWith('lan_') ||
        normalized.startsWith('get_lan_');
  }

  static bool _hasSearchAndBrowserTools(
    Iterable<Map<String, dynamic>> definitions,
  ) {
    final names = toolNamesFromDefinitions(
      definitions,
    ).map((name) => name.trim().toLowerCase());
    return names.any(_searchToolNames.contains) && names.any(_isBrowserTool);
  }

  static bool _isBrowserTool(String toolName) {
    return toolName.trim().toLowerCase().startsWith('browser_');
  }

  static List<Map<String, dynamic>> _definitionsMatchingNames(
    List<Map<String, dynamic>> definitions,
    Set<String> selectedNames,
  ) {
    return definitions
        .where((definition) {
          final name = toolNameFromDefinition(definition);
          return name != null && selectedNames.contains(name);
        })
        .toList(growable: false);
  }

  static bool _containsTool(
    List<Map<String, dynamic>> definitions,
    String name,
  ) {
    return definitions.any(
      (definition) => toolNameFromDefinition(definition) == name,
    );
  }

  static Iterable<Map<String, dynamic>> _searchableDefinitions(
    Iterable<Map<String, dynamic>> definitions,
  ) {
    return ToolResultPromptBuilder.dedupeToolsByName(
      definitions.toList(),
    ).where((definition) => toolNameFromDefinition(definition) != toolName);
  }

  static int _scoreDefinition(
    Map<String, dynamic> definition,
    String normalizedQuery,
    List<String> terms,
    Set<String> genericTerms,
  ) {
    final function = definition['function'];
    if (function is! Map) return 0;
    final name = _normalize(function['name']?.toString() ?? '');
    final description = _normalize(function['description']?.toString() ?? '');
    final parameters = _normalize(
      jsonEncode(function['parameters'] ?? const {}),
    );
    var score = 0;

    if (name == normalizedQuery) score += 200;
    if (name.contains(normalizedQuery)) score += 90;
    if (description.contains(normalizedQuery)) score += 35;
    if (parameters.contains(normalizedQuery)) score += 12;

    final nameParts = name.split(RegExp(r'[_\-\s]+')).toSet();
    for (final term in terms) {
      if (term.length <= 1) continue;
      // Name-level matches always count: a term in the tool name is a strong
      // signal regardless of how common the word is across the catalog.
      if (nameParts.contains(term)) {
        score += 50;
      } else if (name.contains(term)) {
        score += 30;
      }
      // Description/parameter matches only count for discriminating terms, so a
      // generic word recurring in many tools' docs cannot alone match a tool
      // whose name and topical terms are unrelated to the query.
      if (genericTerms.contains(term)) continue;
      if (description.contains(term)) score += 12;
      if (parameters.contains(term)) score += 4;
    }
    return score;
  }

  /// Query terms that appear in more than [genericDescriptionTermToolThreshold]
  /// of the [searchable] tools' text — too common to discriminate, so their
  /// description/parameter matches are ignored in [_scoreDefinition].
  static Set<String> _genericQueryTerms(
    List<Map<String, dynamic>> searchable,
    List<String> terms,
  ) {
    if (searchable.length <= genericDescriptionTermToolThreshold) {
      return const <String>{};
    }
    final texts = <String>[
      for (final definition in searchable)
        if (definition['function'] is Map)
          _normalize(
            '${(definition['function'] as Map)['name']} '
            '${(definition['function'] as Map)['description']} '
            '${jsonEncode((definition['function'] as Map)['parameters'] ?? const {})}',
          ),
    ];
    final generic = <String>{};
    for (final term in terms) {
      if (term.length <= 1 || generic.contains(term)) continue;
      var count = 0;
      for (final text in texts) {
        if (text.contains(term)) count += 1;
        if (count > genericDescriptionTermToolThreshold) {
          generic.add(term);
          break;
        }
      }
    }
    return generic;
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _tokenize(String value) {
    return value
        .split(RegExp(r'[^a-z0-9_]+'))
        .map((term) => term.trim())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class _ScoredToolDefinition {
  const _ScoredToolDefinition({required this.definition, required this.score});

  final Map<String, dynamic> definition;
  final int score;
}
