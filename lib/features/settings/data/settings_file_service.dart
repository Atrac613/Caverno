import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../domain/entities/app_settings.dart';
import 'encrypted_settings_export_codec.dart';
import 'settings_export_sanitizer.dart';

typedef EncryptedSettingsPassphraseProvider = Future<String?> Function();

final settingsFileServiceProvider = Provider<SettingsFileService>((ref) {
  return SettingsFileService();
});

class SettingsFileService {
  static final _urlPattern = RegExp(r'^https?://.+');
  static const _exportSanitizer = SettingsExportSanitizer();

  Future<AppSettings?> importSettings() => _importSettings();

  Future<AppSettings?> importSettingsWithEncryptedPassphrase(
    EncryptedSettingsPassphraseProvider requestPassphrase,
  ) => _importSettings(requestPassphrase: requestPassphrase);

  Future<AppSettings?> _importSettings({
    EncryptedSettingsPassphraseProvider? requestPassphrase,
  }) async {
    try {
      appLog('[SettingsImport] Opening settings JSON picker');
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        appLog('[SettingsImport] Import cancelled');
        return null;
      }

      final file = result.files.first;
      appLog(
        '[SettingsImport] Selected ${file.name} '
        '(${file.bytes?.length ?? file.size} bytes)',
      );
      final selectedByteLength = file.bytes?.length ?? file.size;
      if (selectedByteLength >
          EncryptedSettingsExportCodec.maximumEnvelopeBytes) {
        throw const FormatException('Settings import is too large');
      }
      String content;

      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        content = await File.fromUri(Uri.file(file.path!)).readAsString();
      } else {
        appLog('[SettingsImport] Selected file has no bytes or readable path');
        return null;
      }
      String? passphrase;
      if (EncryptedSettingsExportCodec.isEncryptedEnvelope(content)) {
        if (requestPassphrase == null) {
          throw const FormatException(
            'Encrypted settings import requires a passphrase',
          );
        }
        passphrase = await requestPassphrase();
        if (passphrase == null) {
          appLog('[SettingsImport] Encrypted settings import cancelled');
          return null;
        }
      }

      final settings = await decodeSettingsImport(
        content,
        passphrase: passphrase,
      );
      appLog('[SettingsImport] Settings JSON validated successfully');
      return settings;
    } catch (error, stackTrace) {
      appLog('[SettingsImport] Failed to import settings: $error');
      appLog('[SettingsImport] $stackTrace');
      rethrow;
    }
  }

  Future<String?> exportSettings(AppSettings settings) async {
    final jsonString = encodeSettings(settings);
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

  Future<String?> exportSettingsWithSecrets(
    AppSettings settings,
    String passphrase,
  ) async {
    final encrypted = await encryptSettings(settings, passphrase);
    final bytes = utf8.encode(encrypted);

    return FilePicker.saveFile(
      dialogTitle: 'Export Encrypted Settings',
      fileName: 'caverno_settings_encrypted.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(bytes),
    );
  }

  static String encodeSettings(AppSettings settings) {
    return jsonEncode(_exportSanitizer.toExportJson(settings));
  }

  static Future<String> encryptSettings(
    AppSettings settings,
    String passphrase,
  ) {
    return compute(_encryptSettingsExport, <String, String>{
      'plaintext': jsonEncode(settings.toJson()),
      'passphrase': passphrase,
    });
  }

  static Future<String> decryptSettings(String envelope, String passphrase) {
    return compute(_decryptSettingsExport, <String, String>{
      'envelope': envelope,
      'passphrase': passphrase,
    });
  }

  static Future<AppSettings> decodeSettingsImport(
    String content, {
    String? passphrase,
  }) async {
    if (utf8.encode(content).length >
        EncryptedSettingsExportCodec.maximumEnvelopeBytes) {
      throw const FormatException('Settings import is too large');
    }
    if (EncryptedSettingsExportCodec.isEncryptedEnvelope(content)) {
      if (passphrase == null) {
        throw const FormatException(
          'Encrypted settings import requires a passphrase',
        );
      }
      content = await decryptSettings(content, passphrase);
    }
    final json = jsonDecode(content) as Map<String, dynamic>;
    final settings = AppSettings.fromJson(json);
    validateSettings(settings);
    return settings;
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

String _encryptSettingsExport(Map<String, String> request) {
  return EncryptedSettingsExportCodec().encrypt(
    plaintext: request['plaintext']!,
    passphrase: request['passphrase']!,
  );
}

String _decryptSettingsExport(Map<String, String> request) {
  return EncryptedSettingsExportCodec().decrypt(
    envelope: request['envelope']!,
    passphrase: request['passphrase']!,
  );
}
