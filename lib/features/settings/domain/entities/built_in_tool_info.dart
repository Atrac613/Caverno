import 'package:flutter/material.dart';

class BuiltInToolInfo {
  const BuiltInToolInfo({
    required this.name,
    required this.descriptionKey,
    required this.category,
  });

  final String name;
  final String descriptionKey;
  final String category;
}

class BuiltInToolRegistry {
  BuiltInToolRegistry._();

  static const String categoryDatetime = 'datetime';
  static const String categoryMemory = 'memory';
  static const String categoryNetwork = 'network';
  static const String categorySsh = 'ssh';
  static const String categoryGit = 'git';
  static const String categoryWebSearch = 'web_search';

  static const List<String> categories = [
    categoryDatetime,
    categoryMemory,
    categoryNetwork,
    categorySsh,
    categoryGit,
    categoryWebSearch,
  ];

  static const List<BuiltInToolInfo> tools = [
    // DateTime
    BuiltInToolInfo(
      name: 'get_current_datetime',
      descriptionKey: 'settings.tool_get_current_datetime',
      category: categoryDatetime,
    ),
    // Memory
    BuiltInToolInfo(
      name: 'search_past_conversations',
      descriptionKey: 'settings.tool_search_past_conversations',
      category: categoryMemory,
    ),
    BuiltInToolInfo(
      name: 'recall_memory',
      descriptionKey: 'settings.tool_recall_memory',
      category: categoryMemory,
    ),
    // Network
    BuiltInToolInfo(
      name: 'ping',
      descriptionKey: 'settings.tool_ping',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'whois_lookup',
      descriptionKey: 'settings.tool_whois_lookup',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'dns_lookup',
      descriptionKey: 'settings.tool_dns_lookup',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'port_check',
      descriptionKey: 'settings.tool_port_check',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'ssl_certificate',
      descriptionKey: 'settings.tool_ssl_certificate',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'http_status',
      descriptionKey: 'settings.tool_http_status',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'http_get',
      descriptionKey: 'settings.tool_http_get',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'http_head',
      descriptionKey: 'settings.tool_http_head',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'http_post',
      descriptionKey: 'settings.tool_http_post',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'http_put',
      descriptionKey: 'settings.tool_http_put',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'http_patch',
      descriptionKey: 'settings.tool_http_patch',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'http_delete',
      descriptionKey: 'settings.tool_http_delete',
      category: categoryNetwork,
    ),
    BuiltInToolInfo(
      name: 'traceroute',
      descriptionKey: 'settings.tool_traceroute',
      category: categoryNetwork,
    ),
    // SSH
    BuiltInToolInfo(
      name: 'ssh_connect',
      descriptionKey: 'settings.tool_ssh_connect',
      category: categorySsh,
    ),
    BuiltInToolInfo(
      name: 'ssh_execute_command',
      descriptionKey: 'settings.tool_ssh_execute_command',
      category: categorySsh,
    ),
    BuiltInToolInfo(
      name: 'ssh_disconnect',
      descriptionKey: 'settings.tool_ssh_disconnect',
      category: categorySsh,
    ),
    // Git
    BuiltInToolInfo(
      name: 'git_execute_command',
      descriptionKey: 'settings.tool_git_execute_command',
      category: categoryGit,
    ),
    // Web Search
    BuiltInToolInfo(
      name: 'web_search',
      descriptionKey: 'settings.tool_web_search',
      category: categoryWebSearch,
    ),
  ];

  static Map<String, List<BuiltInToolInfo>> get toolsByCategory {
    final map = <String, List<BuiltInToolInfo>>{};
    for (final tool in tools) {
      (map[tool.category] ??= []).add(tool);
    }
    return map;
  }

  static Set<String> toolNamesForCategory(String category) {
    return tools
        .where((t) => t.category == category)
        .map((t) => t.name)
        .toSet();
  }

  static IconData categoryIcon(String category) {
    return switch (category) {
      categoryDatetime => Icons.schedule,
      categoryMemory => Icons.memory,
      categoryNetwork => Icons.lan,
      categorySsh => Icons.terminal,
      categoryGit => Icons.merge_type,
      categoryWebSearch => Icons.search,
      _ => Icons.extension,
    };
  }
}
