import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/app_settings.dart';

final settingsFileServiceProvider = Provider<SettingsFileService>((ref) {
  return SettingsFileService();
});

class SettingsFileService {
  static final _urlPattern = RegExp(r'^https?://.+');

  Future<AppSettings?> importSettings() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.first;
    String content;

    if (file.bytes != null) {
      content = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      content = await File.fromUri(Uri.file(file.path!)).readAsString();
    } else {
      return null;
    }

    final json = jsonDecode(content) as Map<String, dynamic>;
    final settings = AppSettings.fromJson(json);
    validateSettings(settings);
    return settings;
  }

  Future<String?> exportSettings(AppSettings settings) async {
    final jsonString = jsonEncode(settings.toJson());
    final bytes = utf8.encode(jsonString);

    final result = await FilePicker.saveFile(
      dialogTitle: 'Export Settings',
      fileName: 'caverno_settings.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(bytes),
    );

    return result;
  }

  /// Validates imported settings values.
  /// Throws [FormatException] if any value is out of acceptable range.
  static void validateSettings(AppSettings settings) {
    if (settings.baseUrl.isEmpty || !_urlPattern.hasMatch(settings.baseUrl)) {
      throw const FormatException('baseUrl must be a valid HTTP/HTTPS URL');
    }
    if (settings.model.isEmpty) {
      throw const FormatException('model must not be empty');
    }
    if (settings.apiKey.isEmpty) {
      throw const FormatException('apiKey must not be empty');
    }
    if (settings.temperature < 0.0 || settings.temperature > 2.0) {
      throw const FormatException('temperature must be between 0.0 and 2.0');
    }
    if (settings.maxTokens < 1 || settings.maxTokens > 1000000) {
      throw const FormatException('maxTokens must be between 1 and 1,000,000');
    }
    if (settings.speechRate < 0.0 || settings.speechRate > 1.0) {
      throw const FormatException('speechRate must be between 0.0 and 1.0');
    }
    if (settings.voicevoxSpeakerId < 0) {
      throw const FormatException('voicevoxSpeakerId must be non-negative');
    }
    for (final mcpServer in settings.effectiveMcpServers) {
      final mcpUrl = mcpServer.normalizedUrl;
      if (mcpUrl.isEmpty) {
        continue;
      }
      if (!_urlPattern.hasMatch(mcpUrl)) {
        throw const FormatException(
          'Each mcpUrl must be a valid HTTP/HTTPS URL',
        );
      }
    }
    if (settings.whisperUrl.isNotEmpty &&
        !_urlPattern.hasMatch(settings.whisperUrl)) {
      throw const FormatException('whisperUrl must be a valid HTTP/HTTPS URL');
    }
    if (settings.voicevoxUrl.isNotEmpty &&
        !_urlPattern.hasMatch(settings.voicevoxUrl)) {
      throw const FormatException('voicevoxUrl must be a valid HTTP/HTTPS URL');
    }
    if (settings.normalizedGoogleChatWebhookUrl.isNotEmpty &&
        !_urlPattern.hasMatch(settings.normalizedGoogleChatWebhookUrl)) {
      throw const FormatException(
        'googleChatWebhookUrl must be a valid HTTP/HTTPS URL',
      );
    }
  }
}
