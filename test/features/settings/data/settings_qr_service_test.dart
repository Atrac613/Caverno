import 'package:caverno/features/settings/data/settings_qr_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsQrService', () {
    final service = SettingsQrService();

    test('should encode and decode settings correctly', () {
      final settings = AppSettings.defaults().copyWith(
        baseUrl: 'https://example.com/api',
        model: 'test-model',
        apiKey: 'test-key',
        temperature: 1.5,
        maxTokens: 2048,
        showMemoryUpdates: true,
      );

      final qrString = service.generateQrString(settings);
      expect(qrString, isNotEmpty);

      final decodedSettings = service.parseQrString(qrString);
      expect(decodedSettings, equals(settings));
    });

    test('should throw FormatException for invalid data', () {
      expect(
        () => service.parseQrString('invalid-base64'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
