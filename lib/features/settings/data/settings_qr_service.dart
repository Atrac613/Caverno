import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/app_settings.dart';
import 'settings_file_service.dart';

final settingsQrServiceProvider = Provider<SettingsQrService>((ref) {
  return SettingsQrService();
});

class SettingsQrService {
  /// Generates a QR-compatible string from [AppSettings].
  /// Uses minified JSON -> GZip -> Base64 for compact representation.
  String generateQrString(AppSettings settings) {
    final jsonString = jsonEncode(settings.toJson());
    final bytes = utf8.encode(jsonString);
    // Note: GZipCodec is available in dart:io (Mobile/Desktop)
    final compressed = GZipCodec().encode(bytes);
    return base64Encode(compressed);
  }

  /// Parses [AppSettings] from a QR data string.
  AppSettings parseQrString(String qrString) {
    try {
      final compressed = base64Decode(qrString.trim());
      final bytes = GZipCodec().decode(compressed);
      final jsonString = utf8.decode(bytes);
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final settings = AppSettings.fromJson(json);
      SettingsFileService.validateSettings(settings);
      return settings;
    } catch (e) {
      throw FormatException('Invalid or corrupt QR data: $e');
    }
  }
}
