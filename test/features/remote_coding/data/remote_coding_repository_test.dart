import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_security.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('invalid persisted server settings fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({
      'remote_coding_server_settings': '{not-json',
    });
    final prefs = await SharedPreferences.getInstance();

    final settings = RemoteCodingRepository(prefs).loadServerSettings();

    expect(settings.enabled, isFalse);
    expect(settings.port, 8767);
    expect(settings.pairedDevices, isEmpty);
  });

  test('invalid persisted mobile host is ignored on startup', () async {
    SharedPreferences.setMockInitialValues({
      'remote_coding_mobile_host': jsonEncode({
        'id': '',
        'name': 'Desktop',
        'host': '',
        'port': 8767,
      }),
    });
    final prefs = await SharedPreferences.getInstance();

    final host = RemoteCodingRepository(prefs).loadMobileHost();

    expect(host, isNull);
  });

  test('desktop paired device state stores token hashes only', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = RemoteCodingRepository(prefs);
    const rawToken = 'mobile-token';
    final settings = RemoteCodingServerSettings(
      enabled: true,
      pairedDevices: [
        RemoteCodingPairedDevice(
          id: 'device-1',
          name: 'Phone',
          tokenHash: RemoteCodingSecurity.hashToken(rawToken),
          createdAt: DateTime(2026, 5, 26, 12),
          lastSeenAt: DateTime(2026, 5, 26, 12),
        ),
      ],
    );

    await repository.saveServerSettings(settings);
    final stored = prefs.getString('remote_coding_server_settings')!;

    expect(stored, isNot(contains(rawToken)));
    expect(stored, contains(RemoteCodingSecurity.hashToken(rawToken)));
  });
}
