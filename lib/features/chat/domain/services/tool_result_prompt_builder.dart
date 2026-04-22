import 'dart:convert';

import '../../data/datasources/chat_remote_datasource.dart';

class ToolResultPromptBuilder {
  ToolResultPromptBuilder._();

  static List<Map<String, dynamic>> dedupeToolsByName(
    List<Map<String, dynamic>> tools,
  ) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final tool in tools) {
      final name = (tool['function'] as Map?)?['name'];
      if (name is! String || name.isEmpty) {
        continue;
      }
      if (seen.add(name)) {
        deduped.add(tool);
      }
    }
    return deduped;
  }

  static String buildAnswerPrompt(
    List<ToolResultInfo> toolResults, {
    Map<String, String> descriptionsByName = const {},
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'Please answer the user\'s question based on the following tool results.',
      )
      ..writeln()
      ..writeln(
        'Interpret each tool name, description, arguments, and result together.',
      )
      ..writeln(
        'Preserve the entity roles implied by the tool and the payload.',
      )
      ..writeln(
        'Do not guess that an opaque identifier is an end-user device. '
        'It may instead refer to infrastructure such as a router, gateway, '
        'access point, interface, or monitored node.',
      )
      ..writeln(
        'If the role of an identifier is not explicit in the payload, say it '
        'is ambiguous instead of guessing.',
      )
      ..writeln(
        'Prefer explicit fields such as role, type, kind, category, or '
        'interpretation_hint over heuristics based on how an identifier looks.',
      )
      ..writeln()
      ..write(
        formatToolResults(toolResults, descriptionsByName: descriptionsByName),
      );
    return buffer.toString().trimRight();
  }

  static String formatToolResults(
    List<ToolResultInfo> toolResults, {
    Map<String, String> descriptionsByName = const {},
  }) {
    final sections = toolResults.map((toolResult) {
      final buffer = StringBuffer()..writeln('[Tool: ${toolResult.name}]');
      final description = descriptionsByName[toolResult.name];
      if (description != null && description.isNotEmpty) {
        buffer.writeln('Description: $description');
      }
      final scopeNote = buildToolScopeNote(
        toolName: toolResult.name,
        description: description,
      );
      if (scopeNote != null) {
        buffer.writeln('Scope note: $scopeNote');
      }
      if (toolResult.arguments.isNotEmpty) {
        buffer.writeln('Arguments: ${jsonEncode(toolResult.arguments)}');
      }
      buffer
        ..writeln('Result:')
        ..write(toolResult.result);
      return buffer.toString().trimRight();
    });
    return sections.join('\n\n');
  }

  static Map<String, String> descriptionsByNameFromDefinitions(
    List<Map<String, dynamic>> definitions,
  ) {
    final descriptionsByName = <String, String>{};
    for (final tool in definitions) {
      final function = tool['function'];
      if (function is! Map) {
        continue;
      }
      final name = function['name'];
      final description = function['description'];
      if (name is String &&
          name.isNotEmpty &&
          description is String &&
          description.isNotEmpty) {
        descriptionsByName[name] = description;
      }
    }
    return descriptionsByName;
  }

  static String? buildToolScopeNote({
    required String toolName,
    String? description,
  }) {
    final combinedText = '$toolName ${description ?? ''}'.toLowerCase();
    if (combinedText.contains('router') || combinedText.contains('gateway')) {
      return 'This is infrastructure-side telemetry. Identifiers may refer '
          'to the router, gateway, interfaces, or other monitored '
          'infrastructure rather than a client device.';
    }
    if (combinedText.contains('wifi') ||
        combinedText.contains('wi-fi') ||
        combinedText.contains('access point') ||
        combinedText.contains('bssid') ||
        combinedText.contains('ssid')) {
      return 'This is wireless-side telemetry. Identifiers may refer to '
          'radios, access points, or BSSIDs rather than user devices.';
    }
    return null;
  }
}
