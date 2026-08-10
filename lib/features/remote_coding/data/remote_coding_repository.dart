import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/presentation/providers/settings_notifier.dart';
import '../domain/remote_coding_models.dart';
import 'remote_coding_notification_relay_contract.dart';
import 'remote_coding_secure_store.dart';

final remoteCodingRepositoryProvider = Provider<RemoteCodingRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return RemoteCodingRepository(prefs);
});

class RemoteCodingRepository {
  RemoteCodingRepository(this._prefs, {RemoteCodingSecureStore? secureStore})
    : _secureStore = secureStore ?? const FlutterRemoteCodingSecureStore();

  static const _serverSettingsKey = 'remote_coding_server_settings';
  static const _mobileHostKey = 'remote_coding_mobile_host';
  static const _mobileTokenPrefix = 'caverno.remote_coding.token.';
  static const _mobileRelayMetadataKey =
      'remote_coding_mobile_notification_relay';
  static const _mobileRelayInstallationIdKey =
      'remote_coding_mobile_notification_installation_id';
  static const _mobileRelayNotificationsEnabledKey =
      'remote_coding_mobile_notifications_enabled';
  static const _mobileRelayManagementSecretKey =
      'caverno.remote_coding.relay.mobile.management_secret';
  static const _legacyMobileRelayDeliverySecretKey =
      'caverno.remote_coding.relay.mobile.delivery_secret';
  static const _desktopRelayDeliverySecretPrefix =
      'caverno.remote_coding.relay.desktop.delivery_secret.';

  final SharedPreferences _prefs;
  final RemoteCodingSecureStore _secureStore;

  RemoteCodingServerSettings loadServerSettings() {
    final raw = _prefs.getString(_serverSettingsKey);
    if (raw == null || raw.isEmpty) {
      return const RemoteCodingServerSettings();
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return RemoteCodingServerSettings.fromJson(decoded);
    } catch (_) {
      return const RemoteCodingServerSettings();
    }
  }

  Future<void> saveServerSettings(RemoteCodingServerSettings settings) async {
    final saved = await _prefs.setString(
      _serverSettingsKey,
      jsonEncode(settings.toJson()),
    );
    if (!saved) {
      throw StateError('Remote coding server settings could not be saved.');
    }
  }

  RemoteCodingHost? loadMobileHost() {
    final raw = _prefs.getString(_mobileHostKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final host = RemoteCodingHost.fromJson(decoded);
      return host.host.isEmpty || host.id.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMobileHost(RemoteCodingHost host, String token) async {
    await _prefs.setString(_mobileHostKey, jsonEncode(host.toJson()));
    await _secureStore.write(key: _tokenKey(host.id), value: token);
  }

  Future<String?> loadMobileHostToken(String hostId) {
    return _secureStore.read(key: _tokenKey(hostId));
  }

  Future<void> clearMobileHost() async {
    final host = loadMobileHost();
    await _prefs.remove(_mobileHostKey);
    if (host != null) {
      await _secureStore.delete(key: _tokenKey(host.id));
    }
  }

  Future<void> saveMobileRelayRegistration(
    RemoteCodingRelayRegistrationResponse registration,
  ) async {
    final metadata = RemoteCodingRelayRegistrationMetadata.fromJson(
      registration.metadata.toJson(),
    );
    if (registration.managementSecret.trim().isEmpty) {
      throw const FormatException(
        'Relay management credential must not be empty.',
      );
    }
    final previousManagementSecret = await _secureStore.read(
      key: _mobileRelayManagementSecretKey,
    );
    try {
      await _secureStore.write(
        key: _mobileRelayManagementSecretKey,
        value: registration.managementSecret,
      );
      final saved = await _prefs.setString(
        _mobileRelayMetadataKey,
        jsonEncode(metadata.toJson()),
      );
      if (!saved) {
        throw StateError('Relay registration metadata could not be saved.');
      }
    } catch (_) {
      await _restoreSecret(
        key: _mobileRelayManagementSecretKey,
        value: previousManagementSecret,
      );
      rethrow;
    }
  }

  Future<RemoteCodingRelayRegistrationResponse?>
  loadMobileRelayRegistration() async {
    final raw = _prefs.getString(_mobileRelayMetadataKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final metadata = RemoteCodingRelayRegistrationMetadata.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final managementSecret = await _secureStore.read(
        key: _mobileRelayManagementSecretKey,
      );
      if (managementSecret == null || managementSecret.trim().isEmpty) {
        return null;
      }
      return RemoteCodingRelayRegistrationResponse(
        deliveryHandle: metadata.deliveryHandle,
        managementKeyId: metadata.managementKeyId,
        managementSecret: managementSecret,
        expiresAt: metadata.expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearMobileRelayRegistration() async {
    await _secureStore.delete(key: _mobileRelayManagementSecretKey);
    await _secureStore.delete(key: _legacyMobileRelayDeliverySecretKey);
    await _prefs.remove(_mobileRelayMetadataKey);
  }

  Future<String> loadOrCreateMobileRelayInstallationId(
    String Function() idFactory,
  ) async {
    final existing = _prefs.getString(_mobileRelayInstallationIdKey)?.trim();
    if (_isValidOpaqueIdentifier(existing)) {
      return existing!;
    }
    final created = idFactory().trim();
    if (!_isValidOpaqueIdentifier(created)) {
      throw const FormatException('Notification installation ID is invalid.');
    }
    final saved = await _prefs.setString(
      _mobileRelayInstallationIdKey,
      created,
    );
    if (!saved) {
      throw StateError('Notification installation ID could not be saved.');
    }
    return created;
  }

  bool loadMobileRelayNotificationsEnabled() {
    return _prefs.getBool(_mobileRelayNotificationsEnabledKey) ?? false;
  }

  Future<void> saveMobileRelayNotificationsEnabled(bool enabled) async {
    final saved = await _prefs.setBool(
      _mobileRelayNotificationsEnabledKey,
      enabled,
    );
    if (!saved) {
      throw StateError('Mobile notification preference could not be saved.');
    }
  }

  Future<void> saveDesktopRelayDeliverySecret({
    required String deviceId,
    required String deliverySecret,
  }) {
    if (deliverySecret.trim().isEmpty) {
      throw const FormatException(
        'Relay delivery credential must not be empty.',
      );
    }
    return _secureStore.write(
      key: _desktopRelayDeliverySecretKey(deviceId),
      value: deliverySecret,
    );
  }

  Future<String?> loadDesktopRelayDeliverySecret(String deviceId) {
    return _secureStore.read(key: _desktopRelayDeliverySecretKey(deviceId));
  }

  Future<void> deleteDesktopRelayDeliverySecret(String deviceId) {
    return _secureStore.delete(key: _desktopRelayDeliverySecretKey(deviceId));
  }

  Future<RemoteCodingPairedDevice> installPendingDesktopRelayCredential({
    required String deviceId,
    required RemoteCodingRelayDelegationRedemptionResponse credential,
  }) async {
    final settings = loadServerSettings();
    final device = _requirePairedDevice(settings, deviceId);
    final previousSecret = await loadDesktopRelayDeliverySecret(deviceId);
    final updatedDevice = device.copyWith(
      relayDeliveryHandle: credential.deliveryHandle,
      relayDeliveryKeyId: credential.deliveryKeyId,
      relayDelegationId: credential.delegationId,
      relayCredentialExpiresAt: credential.expiresAt,
      relayCredentialState: RemoteCodingRelayCredentialState.pendingActivation,
    );
    await saveDesktopRelayDeliverySecret(
      deviceId: deviceId,
      deliverySecret: credential.deliverySecret,
    );
    try {
      await saveServerSettings(_replacePairedDevice(settings, updatedDevice));
    } catch (_) {
      await _restoreSecret(
        key: _desktopRelayDeliverySecretKey(deviceId),
        value: previousSecret,
      );
      rethrow;
    }
    return updatedDevice;
  }

  Future<RemoteCodingPairedDevice> markDesktopRelayCredentialActive({
    required String deviceId,
    required String deliveryKeyId,
  }) async {
    final settings = loadServerSettings();
    final device = _requirePairedDevice(settings, deviceId);
    if (!device.hasNotificationRelay ||
        device.relayDeliveryKeyId != deliveryKeyId) {
      throw StateError('Desktop relay credential does not match the device.');
    }
    final updatedDevice = device.copyWith(
      relayCredentialState: RemoteCodingRelayCredentialState.active,
    );
    await saveServerSettings(_replacePairedDevice(settings, updatedDevice));
    return updatedDevice;
  }

  Future<RemoteCodingPairedDevice> markDesktopRelayCredentialPendingRevocation(
    String deviceId,
  ) async {
    final settings = loadServerSettings();
    final device = _requirePairedDevice(settings, deviceId);
    if (!device.hasNotificationRelay) {
      throw StateError('Desktop relay credential is not configured.');
    }
    final updatedDevice = device.copyWith(
      relayCredentialState: RemoteCodingRelayCredentialState.pendingRevocation,
    );
    await saveServerSettings(_replacePairedDevice(settings, updatedDevice));
    return updatedDevice;
  }

  Future<RemoteCodingPairedDevice> clearDesktopRelayCredential(
    String deviceId,
  ) async {
    final settings = loadServerSettings();
    final device = _requirePairedDevice(settings, deviceId);
    final previousSecret = await loadDesktopRelayDeliverySecret(deviceId);
    await deleteDesktopRelayDeliverySecret(deviceId);
    final updatedDevice = device.withoutNotificationRelay();
    try {
      await saveServerSettings(_replacePairedDevice(settings, updatedDevice));
    } catch (_) {
      await _restoreSecret(
        key: _desktopRelayDeliverySecretKey(deviceId),
        value: previousSecret,
      );
      rethrow;
    }
    return updatedDevice;
  }

  String _tokenKey(String hostId) => '$_mobileTokenPrefix$hostId';

  String _desktopRelayDeliverySecretKey(String deviceId) {
    final normalized = deviceId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(normalized)) {
      throw const FormatException('Remote coding device ID is invalid.');
    }
    return '$_desktopRelayDeliverySecretPrefix$normalized';
  }

  bool _isValidOpaqueIdentifier(String? value) {
    return value != null && RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(value);
  }

  RemoteCodingPairedDevice _requirePairedDevice(
    RemoteCodingServerSettings settings,
    String deviceId,
  ) {
    return settings.pairedDevices.firstWhere(
      (device) => device.id == deviceId,
      orElse: () => throw StateError('Remote coding device was not found.'),
    );
  }

  RemoteCodingServerSettings _replacePairedDevice(
    RemoteCodingServerSettings settings,
    RemoteCodingPairedDevice updatedDevice,
  ) {
    return settings.copyWith(
      pairedDevices: [
        for (final device in settings.pairedDevices)
          if (device.id == updatedDevice.id) updatedDevice else device,
      ],
    );
  }

  Future<void> _restoreSecret({required String key, required String? value}) {
    if (value == null) {
      return _secureStore.delete(key: key);
    }
    return _secureStore.write(key: key, value: value);
  }
}
