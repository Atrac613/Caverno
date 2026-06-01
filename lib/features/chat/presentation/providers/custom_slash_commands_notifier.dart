import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../settings/presentation/providers/settings_notifier.dart';
import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_prompt_template.dart';

final customSlashCommandsNotifierProvider =
    NotifierProvider<
      CustomSlashCommandsNotifier,
      List<SlashCommandPromptTemplate>
    >(CustomSlashCommandsNotifier.new);

class CustomSlashCommandsNotifier
    extends Notifier<List<SlashCommandPromptTemplate>> {
  static const storageKey = 'custom_slash_command_templates.v1';

  late final SharedPreferences _preferences;

  @override
  List<SlashCommandPromptTemplate> build() {
    _preferences = ref.read(sharedPreferencesProvider);
    return _load();
  }

  Future<void> upsert(SlashCommandPromptTemplate template) async {
    final normalized = _normalize(template);
    _validate(normalized);
    final templates = List<SlashCommandPromptTemplate>.from(state);
    final existingIndex = templates.indexWhere(
      (item) => item.id == normalized.id,
    );
    if (existingIndex == -1) {
      _ensureNameAvailable(normalized, templates);
      templates.add(normalized);
    } else {
      _ensureNameAvailable(normalized, [
        for (final item in templates)
          if (item.id != normalized.id) item,
      ]);
      templates[existingIndex] = normalized;
    }
    templates.sort((left, right) => left.name.compareTo(right.name));
    state = List<SlashCommandPromptTemplate>.unmodifiable(templates);
    await _save(state);
  }

  Future<void> remove(String id) async {
    state = [
      for (final template in state)
        if (template.id != id) template,
    ];
    await _save(state);
  }

  Future<void> clear() async {
    state = const <SlashCommandPromptTemplate>[];
    await _preferences.remove(storageKey);
  }

  List<SlashCommandPromptTemplate> _load() {
    final encoded = _preferences.getString(storageKey);
    if (encoded == null || encoded.isEmpty) {
      return const <SlashCommandPromptTemplate>[];
    }
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      final templates = decoded
          .whereType<Map<String, dynamic>>()
          .map(SlashCommandPromptTemplate.fromJson)
          .where((template) => template.id.isNotEmpty)
          .map(_normalize)
          .toList(growable: false);
      return List<SlashCommandPromptTemplate>.unmodifiable(templates);
    } catch (_) {
      return const <SlashCommandPromptTemplate>[];
    }
  }

  Future<void> _save(List<SlashCommandPromptTemplate> templates) async {
    await _preferences.setString(
      storageKey,
      jsonEncode([for (final template in templates) template.toJson()]),
    );
  }

  SlashCommandPromptTemplate _normalize(SlashCommandPromptTemplate template) {
    final normalizedAliases = <String>{
      for (final alias in template.aliases)
        if (_normalizeCommandToken(alias).isNotEmpty)
          _normalizeCommandToken(alias),
    }.where((alias) => alias != _normalizeCommandToken(template.name)).toList();
    return template.copyWith(
      id: template.id.trim().isEmpty
          ? DateTime.now().microsecondsSinceEpoch.toString()
          : template.id.trim(),
      name: _normalizeCommandToken(template.name),
      description: template.description.trim(),
      aliases: normalizedAliases,
      argumentHint:
          template.argumentRequirement == SlashCommandArgumentRequirement.none
          ? null
          : _normalizeArgumentHint(template.argumentHint),
      template: template.template.trim(),
    );
  }

  String _normalizeCommandToken(String value) {
    return value.trim().replaceFirst(RegExp(r'^/+'), '').toLowerCase();
  }

  String? _normalizeArgumentHint(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _validate(SlashCommandPromptTemplate template) {
    if (template.name.isEmpty || !looksLikeSlashCommandName(template.name)) {
      throw ArgumentError(
        'Slash command names must use letters, numbers, _, -, or :.',
      );
    }
    if (reservedSlashCommandNames.contains(template.name)) {
      throw ArgumentError(
        'Slash command names cannot override built-in commands.',
      );
    }
    for (final alias in template.aliases) {
      if (!looksLikeSlashCommandName(alias)) {
        throw ArgumentError(
          'Slash command aliases must use letters, numbers, _, -, or :.',
        );
      }
      if (reservedSlashCommandNames.contains(alias)) {
        throw ArgumentError(
          'Slash command aliases cannot override built-in commands.',
        );
      }
    }
    if (template.description.isEmpty) {
      throw ArgumentError('Slash command descriptions are required.');
    }
    if (template.template.isEmpty) {
      throw ArgumentError('Slash command templates are required.');
    }
  }

  void _ensureNameAvailable(
    SlashCommandPromptTemplate template,
    List<SlashCommandPromptTemplate> existingTemplates,
  ) {
    final newTokens = {template.name, ...template.aliases};
    for (final existing in existingTemplates) {
      final existingTokens = {existing.name, ...existing.aliases};
      if (newTokens.intersection(existingTokens).isNotEmpty) {
        throw ArgumentError('Slash command names and aliases must be unique.');
      }
    }
  }
}
