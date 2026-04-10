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
  static const String categoryBle = 'ble';
  static const String categoryWifi = 'wifi';
  static const String categoryLanScan = 'lan_scan';

  static const List<String> categories = [
    categoryDatetime,
    categoryMemory,
    categoryNetwork,
    categorySsh,
    categoryGit,
    categoryWebSearch,
    categoryBle,
    categoryWifi,
    categoryLanScan,
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
    // BLE
    BuiltInToolInfo(
      name: 'ble_start_scan',
      descriptionKey: 'settings.tool_ble_start_scan',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_stop_scan',
      descriptionKey: 'settings.tool_ble_stop_scan',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_get_scan_results',
      descriptionKey: 'settings.tool_ble_get_scan_results',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_connect',
      descriptionKey: 'settings.tool_ble_connect',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_disconnect',
      descriptionKey: 'settings.tool_ble_disconnect',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_discover_services',
      descriptionKey: 'settings.tool_ble_discover_services',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_read_characteristic',
      descriptionKey: 'settings.tool_ble_read_characteristic',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_write_characteristic',
      descriptionKey: 'settings.tool_ble_write_characteristic',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_subscribe_characteristic',
      descriptionKey: 'settings.tool_ble_subscribe_characteristic',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_unsubscribe_characteristic',
      descriptionKey: 'settings.tool_ble_unsubscribe_characteristic',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_get_connection_state',
      descriptionKey: 'settings.tool_ble_get_connection_state',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_start_advertising',
      descriptionKey: 'settings.tool_ble_start_advertising',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_stop_advertising',
      descriptionKey: 'settings.tool_ble_stop_advertising',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_add_service',
      descriptionKey: 'settings.tool_ble_add_service',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_update_characteristic',
      descriptionKey: 'settings.tool_ble_update_characteristic',
      category: categoryBle,
    ),
    BuiltInToolInfo(
      name: 'ble_get_peripheral_state',
      descriptionKey: 'settings.tool_ble_get_peripheral_state',
      category: categoryBle,
    ),
    // WiFi
    BuiltInToolInfo(
      name: 'wifi_scan',
      descriptionKey: 'settings.tool_wifi_scan',
      category: categoryWifi,
    ),
    BuiltInToolInfo(
      name: 'wifi_get_scan_results',
      descriptionKey: 'settings.tool_wifi_get_scan_results',
      category: categoryWifi,
    ),
    BuiltInToolInfo(
      name: 'wifi_get_connection_info',
      descriptionKey: 'settings.tool_wifi_get_connection_info',
      category: categoryWifi,
    ),
    // LAN Scan
    BuiltInToolInfo(
      name: 'lan_scan',
      descriptionKey: 'settings.tool_lan_scan',
      category: categoryLanScan,
    ),
    BuiltInToolInfo(
      name: 'lan_get_scan_results',
      descriptionKey: 'settings.tool_lan_get_scan_results',
      category: categoryLanScan,
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
      categoryBle => Icons.bluetooth,
      categoryWifi => Icons.wifi,
      categoryLanScan => Icons.device_hub,
      _ => Icons.extension,
    };
  }
}
