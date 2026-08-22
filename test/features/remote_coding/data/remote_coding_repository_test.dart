import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_repository.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_secure_store.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_security.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_tls_identity.dart';
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

  test('corrupt persisted TLS identity is replaced', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secureStore = _MemorySecureStore();
    final repository = RemoteCodingRepository(prefs, secureStore: secureStore);
    final replacement = RemoteCodingTlsIdentity.generate();
    secureStore.values['caverno.remote_coding.tls.identity'] = jsonEncode({
      ...replacement.toJson(),
      'certificatePin': 'deadbeef',
    });
    var generationCount = 0;

    final loaded = await repository.loadOrCreateTlsIdentity(() {
      generationCount += 1;
      return replacement;
    });

    expect(generationCount, 1);
    expect(loaded.certificatePin, replacement.certificatePin);
    expect(
      secureStore.values['caverno.remote_coding.tls.identity'],
      jsonEncode(replacement.toJson()),
    );
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

  test(
    'mobile management secret is separated from persisted metadata',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = _MemorySecureStore();
      final repository = RemoteCodingRepository(
        prefs,
        secureStore: secureStore,
      );
      final registration = RemoteCodingRelayRegistrationResponse(
        deliveryHandle: 'delivery_handle_1',
        managementKeyId: 'management-key-1',
        managementSecret: 'management-secret',
        expiresAt: DateTime.utc(2026, 9, 10),
      );

      await repository.saveMobileRelayRegistration(registration);
      final stored = prefs.getString(
        'remote_coding_mobile_notification_relay',
      )!;
      final loaded = await repository.loadMobileRelayRegistration();

      expect(stored, contains('delivery_handle_1'));
      expect(stored, contains('management-key-1'));
      expect(stored, isNot(contains('management-secret')));
      expect(stored, isNot(contains('deliveryKeyId')));
      expect(loaded?.toJson(), registration.toJson());
    },
  );

  test('mobile relay loading fails closed when a secret is missing', () async {
    SharedPreferences.setMockInitialValues({
      'remote_coding_mobile_notification_relay': jsonEncode({
        'schemaVersion': 2,
        'deliveryHandle': 'delivery_handle_1',
        'managementKeyId': 'management-key-1',
        'expiresAt': DateTime.utc(2026, 9, 10).toIso8601String(),
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final repository = RemoteCodingRepository(
      prefs,
      secureStore: _MemorySecureStore(),
    );

    expect(await repository.loadMobileRelayRegistration(), isNull);
  });

  test('mobile relay clear removes metadata and management secret', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secureStore = _MemorySecureStore();
    final repository = RemoteCodingRepository(prefs, secureStore: secureStore);
    final registration = RemoteCodingRelayRegistrationResponse(
      deliveryHandle: 'delivery_handle_1',
      managementKeyId: 'management-key-1',
      managementSecret: 'management-secret',
      expiresAt: DateTime.utc(2026, 9, 10),
    );
    await repository.saveMobileRelayRegistration(registration);

    await repository.clearMobileRelayRegistration();

    expect(await repository.loadMobileRelayRegistration(), isNull);
    expect(secureStore.values, isEmpty);
    expect(prefs.getString('remote_coding_mobile_notification_relay'), isNull);
  });

  test('mobile relay installation ID is stable and non-secret', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = RemoteCodingRepository(
      prefs,
      secureStore: _MemorySecureStore(),
    );
    var generatedCount = 0;

    final first = await repository.loadOrCreateMobileRelayInstallationId(() {
      generatedCount += 1;
      return 'installation_123';
    });
    final second = await repository.loadOrCreateMobileRelayInstallationId(() {
      generatedCount += 1;
      return 'installation_456';
    });

    expect(first, 'installation_123');
    expect(second, first);
    expect(generatedCount, 1);
    expect(
      prefs.getString('remote_coding_mobile_notification_installation_id'),
      first,
    );
  });

  test('invalid mobile relay installation IDs fail closed', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = RemoteCodingRepository(
      prefs,
      secureStore: _MemorySecureStore(),
    );

    await expectLater(
      repository.loadOrCreateMobileRelayInstallationId(
        () => 'installation with spaces',
      ),
      throwsFormatException,
    );
  });

  test('desktop relay delivery secrets are isolated per device', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secureStore = _MemorySecureStore();
    final repository = RemoteCodingRepository(prefs, secureStore: secureStore);

    await repository.saveDesktopRelayDeliverySecret(
      deviceId: 'device-1',
      deliverySecret: 'delivery-secret-1',
    );
    await repository.saveDesktopRelayDeliverySecret(
      deviceId: 'device-2',
      deliverySecret: 'delivery-secret-2',
    );
    await repository.deleteDesktopRelayDeliverySecret('device-1');

    expect(await repository.loadDesktopRelayDeliverySecret('device-1'), isNull);
    expect(
      await repository.loadDesktopRelayDeliverySecret('device-2'),
      'delivery-secret-2',
    );
  });

  test('paired-device relay metadata remains backward compatible', () async {
    final legacy = RemoteCodingPairedDevice.fromJson({
      'id': 'device-1',
      'name': 'Phone',
      'tokenHash': 'token-hash',
      'createdAt': DateTime.utc(2026, 8, 10).toIso8601String(),
      'lastSeenAt': DateTime.utc(2026, 8, 10).toIso8601String(),
    });
    final configured = RemoteCodingPairedDevice(
      id: 'device-2',
      name: 'Tablet',
      tokenHash: 'token-hash-2',
      createdAt: DateTime.utc(2026, 8, 10),
      lastSeenAt: DateTime.utc(2026, 8, 10),
      relayDeliveryHandle: 'delivery_handle_2',
      relayDeliveryKeyId: 'delivery-key-2',
      relayCredentialExpiresAt: DateTime.utc(2026, 9, 10),
    );
    final roundTripped = RemoteCodingPairedDevice.fromJson(configured.toJson());

    expect(legacy.hasNotificationRelay, isFalse);
    expect(legacy.toJson(), isNot(contains('relayDeliveryHandle')));
    expect(roundTripped.hasNotificationRelay, isTrue);
    expect(roundTripped.relayDeliveryHandle, 'delivery_handle_2');
    expect(roundTripped.relayDeliveryKeyId, 'delivery-key-2');
    expect(roundTripped.relayCredentialExpiresAt, DateTime.utc(2026, 9, 10));
    expect(
      roundTripped.relayCredentialState,
      RemoteCodingRelayCredentialState.active,
    );
  });

  test(
    'desktop credential stays unusable until activation and retains revoke state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = _MemorySecureStore();
      final repository = RemoteCodingRepository(
        prefs,
        secureStore: secureStore,
      );
      final device = RemoteCodingPairedDevice(
        id: 'device-1',
        name: 'Phone',
        tokenHash: 'token-hash',
        createdAt: DateTime.utc(2026, 8, 10),
        lastSeenAt: DateTime.utc(2026, 8, 10),
      );
      await repository.saveServerSettings(
        RemoteCodingServerSettings(enabled: true, pairedDevices: [device]),
      );

      final pending = await repository.installPendingDesktopRelayCredential(
        deviceId: device.id,
        credential: RemoteCodingRelayDelegationRedemptionResponse(
          delegationId: 'delegation_123',
          deliveryHandle: 'delivery_handle_1',
          deliveryKeyId: 'delivery-key-123',
          deliverySecret: 'desktop-delivery-secret',
          expiresAt: DateTime.utc(2026, 9, 10),
        ),
      );

      expect(
        pending.relayCredentialState,
        RemoteCodingRelayCredentialState.pendingActivation,
      );
      expect(pending.relayDelegationId, 'delegation_123');
      expect(
        pending.hasUsableNotificationRelayAt(DateTime.utc(2026, 8, 11)),
        isFalse,
      );
      expect(
        await repository.loadDesktopRelayDeliverySecret(device.id),
        'desktop-delivery-secret',
      );

      final active = await repository.markDesktopRelayCredentialActive(
        deviceId: device.id,
        deliveryKeyId: 'delivery-key-123',
      );
      expect(
        active.hasUsableNotificationRelayAt(DateTime.utc(2026, 8, 11)),
        isTrue,
      );
      expect(
        active.hasUsableNotificationRelayAt(DateTime.utc(2026, 9, 11)),
        isFalse,
      );

      final revoking = await repository
          .markDesktopRelayCredentialPendingRevocation(device.id);
      expect(
        revoking.relayCredentialState,
        RemoteCodingRelayCredentialState.pendingRevocation,
      );
      expect(revoking.needsNotificationRelayLifecycleRetry, isTrue);

      final cleared = await repository.clearDesktopRelayCredential(device.id);
      expect(cleared.hasNotificationRelay, isFalse);
      expect(
        await repository.loadDesktopRelayDeliverySecret(device.id),
        isNull,
      );
    },
  );

  test(
    'desktop credential install fails before writing for unknown device',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureStore = _MemorySecureStore();
      final repository = RemoteCodingRepository(
        prefs,
        secureStore: secureStore,
      );

      await expectLater(
        repository.installPendingDesktopRelayCredential(
          deviceId: 'missing-device',
          credential: RemoteCodingRelayDelegationRedemptionResponse(
            delegationId: 'delegation_123',
            deliveryHandle: 'delivery_handle_1',
            deliveryKeyId: 'delivery-key-123',
            deliverySecret: 'desktop-delivery-secret',
            expiresAt: DateTime.utc(2026, 9, 10),
          ),
        ),
        throwsStateError,
      );
      expect(secureStore.values, isEmpty);
    },
  );
}

final class _MemorySecureStore implements RemoteCodingSecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
