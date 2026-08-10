import 'remote_coding_notification_payload.dart';

enum RemoteCodingRelayPlatform { ios, android }

enum RemoteCodingRelayCredentialScope { management, delivery }

extension RemoteCodingRelayPlatformWireName on RemoteCodingRelayPlatform {
  String get wireName => switch (this) {
    RemoteCodingRelayPlatform.ios => 'ios',
    RemoteCodingRelayPlatform.android => 'android',
  };
}

/// Versioned HTTPS contract shared by Caverno clients and the notification
/// relay. Provider credentials and FCM registration tokens never cross the
/// desktop delivery boundary.
final class RemoteCodingNotificationRelayContract {
  RemoteCodingNotificationRelayContract._();

  static const int schemaVersion = 2;
  static const String registrationMethod = 'POST';
  static const String rotationMethod = 'PUT';
  static const String revocationMethod = 'DELETE';
  static const String deliveryMethod = 'POST';
  static const String delegationCreationMethod = 'POST';
  static const String delegationRedemptionMethod = 'POST';
  static const String delegationActivationMethod = 'POST';
  static const String deliveryCredentialRevocationMethod = 'DELETE';
  static const String registrationPath = '/v2/registrations';
  static const String delegationPath = '/v2/delegations';

  static const String appCheckHeader = 'X-Firebase-AppCheck';
  static const String keyIdHeader = 'X-Caverno-Relay-Key-Id';
  static const String timestampHeader = 'X-Caverno-Relay-Timestamp';
  static const String nonceHeader = 'X-Caverno-Relay-Nonce';
  static const String signatureHeader = 'X-Caverno-Relay-Signature';

  static String rotationPath(String deliveryHandle) =>
      '${_registrationResourcePath(deliveryHandle)}/token';

  static String revocationPath(String deliveryHandle) =>
      _registrationResourcePath(deliveryHandle);

  static String deliveryPath(String deliveryHandle) =>
      '${_registrationResourcePath(deliveryHandle)}/deliveries';

  static String delegationCreationPath(String deliveryHandle) =>
      '${_registrationResourcePath(deliveryHandle)}/delegations';

  static String delegationRedemptionPath(String delegationId) =>
      '$delegationPath/${_opaqueIdentifier(delegationId, 'delegation ID')}/redeem';

  static String delegationActivationPath(
    String deliveryHandle,
    String delegationId,
  ) =>
      '${delegationCreationPath(deliveryHandle)}/${_opaqueIdentifier(delegationId, 'delegation ID')}/activate';

  static String deliveryCredentialRevocationPath(
    String deliveryHandle,
    String deliveryKeyId,
  ) =>
      '${_registrationResourcePath(deliveryHandle)}/delivery-credentials/${_opaqueIdentifier(deliveryKeyId, 'delivery key ID')}';

  static bool hasAppCheckAuthentication(Map<String, String> headers) =>
      _headerValue(headers, appCheckHeader).isNotEmpty;

  static String _registrationResourcePath(String deliveryHandle) {
    return '$registrationPath/${_opaqueIdentifier(deliveryHandle, 'delivery handle')}';
  }

  static String _opaqueIdentifier(String value, String label) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{8,256}$').hasMatch(normalized)) {
      throw FormatException('Relay $label is invalid.');
    }
    return normalized;
  }

  static String _headerValue(Map<String, String> headers, String name) {
    final normalizedName = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == normalizedName) {
        return entry.value.trim();
      }
    }
    return '';
  }
}

final class RemoteCodingRelayRegistrationRequest {
  const RemoteCodingRelayRegistrationRequest({
    required this.installationId,
    required this.platform,
    required this.fcmRegistrationToken,
    required this.requestedAt,
  });

  final String installationId;
  final RemoteCodingRelayPlatform platform;
  final String fcmRegistrationToken;
  final DateTime requestedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'installationId': installationId,
    'platform': platform.wireName,
    'fcmRegistrationToken': fcmRegistrationToken,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayRegistrationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    final platformName = _requiredString(json, 'platform');
    final requestedAt = DateTime.tryParse(_requiredString(json, 'requestedAt'));
    if (requestedAt == null) {
      throw const FormatException('Relay registration timestamp is invalid.');
    }
    return RemoteCodingRelayRegistrationRequest(
      installationId: _requiredString(json, 'installationId'),
      platform: switch (platformName) {
        'ios' => RemoteCodingRelayPlatform.ios,
        'android' => RemoteCodingRelayPlatform.android,
        _ => throw FormatException(
          'Unsupported relay registration platform: $platformName',
        ),
      },
      fcmRegistrationToken: _requiredString(json, 'fcmRegistrationToken'),
      requestedAt: requestedAt.toUtc(),
    );
  }
}

/// Registration response returned only to the mobile client over HTTPS.
///
/// Version 2 deliberately returns only a management credential. A scoped
/// desktop delivery credential is created later by one-time delegation and is
/// never available to the mobile application or plaintext LAN WebSocket.
final class RemoteCodingRelayRegistrationResponse {
  const RemoteCodingRelayRegistrationResponse({
    required this.deliveryHandle,
    required this.managementKeyId,
    required this.managementSecret,
    required this.expiresAt,
  });

  final String deliveryHandle;
  final String managementKeyId;
  final String managementSecret;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'deliveryHandle': deliveryHandle,
    'managementKeyId': managementKeyId,
    'managementSecret': managementSecret,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayRegistrationResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    final expiresAt = DateTime.tryParse(_requiredString(json, 'expiresAt'));
    if (expiresAt == null) {
      throw const FormatException('Relay credential expiry is invalid.');
    }
    return RemoteCodingRelayRegistrationResponse(
      deliveryHandle: _requiredString(json, 'deliveryHandle'),
      managementKeyId: _requiredString(json, 'managementKeyId'),
      managementSecret: _requiredString(json, 'managementSecret'),
      expiresAt: expiresAt.toUtc(),
    );
  }

  RemoteCodingRelayRegistrationMetadata get metadata =>
      RemoteCodingRelayRegistrationMetadata(
        deliveryHandle: deliveryHandle,
        managementKeyId: managementKeyId,
        expiresAt: expiresAt,
      );
}

/// Non-secret registration state that can be stored outside secure storage.
final class RemoteCodingRelayRegistrationMetadata {
  const RemoteCodingRelayRegistrationMetadata({
    required this.deliveryHandle,
    required this.managementKeyId,
    required this.expiresAt,
  });

  final String deliveryHandle;
  final String managementKeyId;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'deliveryHandle': deliveryHandle,
    'managementKeyId': managementKeyId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayRegistrationMetadata.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    final deliveryHandle = _requiredString(json, 'deliveryHandle');
    RemoteCodingNotificationRelayContract.deliveryPath(deliveryHandle);
    final expiresAt = DateTime.tryParse(_requiredString(json, 'expiresAt'));
    if (expiresAt == null) {
      throw const FormatException('Relay credential expiry is invalid.');
    }
    return RemoteCodingRelayRegistrationMetadata(
      deliveryHandle: deliveryHandle,
      managementKeyId: _requiredString(json, 'managementKeyId'),
      expiresAt: expiresAt.toUtc(),
    );
  }
}

/// Management-authorized request that binds a short-lived QR challenge to one
/// already-paired desktop device. Only the digest crosses the mobile-to-relay
/// boundary; the challenge secret remains out-of-band in the QR flow.
final class RemoteCodingRelayDelegationCreationRequest {
  const RemoteCodingRelayDelegationCreationRequest({
    required this.challengeId,
    required this.challengeDigest,
    required this.targetDeviceId,
    required this.requestedAt,
  });

  final String challengeId;
  final String challengeDigest;
  final String targetDeviceId;
  final DateTime requestedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'challengeId': challengeId,
    'challengeDigest': challengeDigest,
    'targetDeviceId': targetDeviceId,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayDelegationCreationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return RemoteCodingRelayDelegationCreationRequest(
      challengeId: _requiredOpaqueIdentifier(json, 'challengeId'),
      challengeDigest: _requiredSha256Digest(json, 'challengeDigest'),
      targetDeviceId: _requiredOpaqueIdentifier(json, 'targetDeviceId'),
      requestedAt: _requiredTimestamp(json, 'requestedAt'),
    );
  }
}

final class RemoteCodingRelayDelegationCreationResponse {
  const RemoteCodingRelayDelegationCreationResponse({
    required this.delegationId,
    required this.challengeId,
    required this.targetDeviceId,
    required this.expiresAt,
  });

  final String delegationId;
  final String challengeId;
  final String targetDeviceId;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'delegationId': delegationId,
    'challengeId': challengeId,
    'targetDeviceId': targetDeviceId,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayDelegationCreationResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return RemoteCodingRelayDelegationCreationResponse(
      delegationId: _requiredOpaqueIdentifier(json, 'delegationId'),
      challengeId: _requiredOpaqueIdentifier(json, 'challengeId'),
      targetDeviceId: _requiredOpaqueIdentifier(json, 'targetDeviceId'),
      expiresAt: _requiredTimestamp(json, 'expiresAt'),
    );
  }
}

/// One-time desktop redemption request sent directly to the configured HTTPS
/// relay. This body must never be logged because it carries the QR secret.
final class RemoteCodingRelayDelegationRedemptionRequest {
  const RemoteCodingRelayDelegationRedemptionRequest({
    required this.challengeId,
    required this.challengeSecret,
    required this.targetDeviceId,
    required this.idempotencyKey,
    required this.requestedAt,
  });

  final String challengeId;
  final String challengeSecret;
  final String targetDeviceId;
  final String idempotencyKey;
  final DateTime requestedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'challengeId': challengeId,
    'challengeSecret': challengeSecret,
    'targetDeviceId': targetDeviceId,
    'idempotencyKey': idempotencyKey,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayDelegationRedemptionRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return RemoteCodingRelayDelegationRedemptionRequest(
      challengeId: _requiredOpaqueIdentifier(json, 'challengeId'),
      challengeSecret: _requiredChallengeSecret(json, 'challengeSecret'),
      targetDeviceId: _requiredOpaqueIdentifier(json, 'targetDeviceId'),
      idempotencyKey: _requiredOpaqueIdentifier(json, 'idempotencyKey'),
      requestedAt: _requiredTimestamp(json, 'requestedAt'),
    );
  }
}

/// Scoped delivery credential returned only to desktop over relay HTTPS.
final class RemoteCodingRelayDelegationRedemptionResponse {
  const RemoteCodingRelayDelegationRedemptionResponse({
    required this.delegationId,
    required this.deliveryHandle,
    required this.deliveryKeyId,
    required this.deliverySecret,
    required this.expiresAt,
  });

  final String delegationId;
  final String deliveryHandle;
  final String deliveryKeyId;
  final String deliverySecret;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'delegationId': delegationId,
    'deliveryHandle': deliveryHandle,
    'deliveryKeyId': deliveryKeyId,
    'deliverySecret': deliverySecret,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayDelegationRedemptionResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return RemoteCodingRelayDelegationRedemptionResponse(
      delegationId: _requiredOpaqueIdentifier(json, 'delegationId'),
      deliveryHandle: _requiredOpaqueIdentifier(json, 'deliveryHandle'),
      deliveryKeyId: _requiredOpaqueIdentifier(json, 'deliveryKeyId'),
      deliverySecret: _requiredString(json, 'deliverySecret'),
      expiresAt: _requiredTimestamp(json, 'expiresAt'),
    );
  }
}

final class RemoteCodingRelayDelegationActivationRequest {
  const RemoteCodingRelayDelegationActivationRequest({
    required this.deliveryKeyId,
    required this.activatedAt,
  });

  final String deliveryKeyId;
  final DateTime activatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'deliveryKeyId': deliveryKeyId,
    'activatedAt': activatedAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayDelegationActivationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return RemoteCodingRelayDelegationActivationRequest(
      deliveryKeyId: _requiredOpaqueIdentifier(json, 'deliveryKeyId'),
      activatedAt: _requiredTimestamp(json, 'activatedAt'),
    );
  }
}

final class RemoteCodingRelayDeliveryCredentialRevocationRequest {
  const RemoteCodingRelayDeliveryCredentialRevocationRequest({
    required this.requestedAt,
  });

  final DateTime requestedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
  };

  factory RemoteCodingRelayDeliveryCredentialRevocationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return RemoteCodingRelayDeliveryCredentialRevocationRequest(
      requestedAt: _requiredTimestamp(json, 'requestedAt'),
    );
  }
}

final class RemoteCodingRelayTokenRotationRequest {
  const RemoteCodingRelayTokenRotationRequest({
    required this.fcmRegistrationToken,
  });

  final String fcmRegistrationToken;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'fcmRegistrationToken': fcmRegistrationToken,
  };

  factory RemoteCodingRelayTokenRotationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return RemoteCodingRelayTokenRotationRequest(
      fcmRegistrationToken: _requiredString(json, 'fcmRegistrationToken'),
    );
  }
}

final class RemoteCodingRelayRevocationRequest {
  const RemoteCodingRelayRevocationRequest();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
  };

  factory RemoteCodingRelayRevocationRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    _requireSchemaVersion(json);
    return const RemoteCodingRelayRevocationRequest();
  }
}

final class RemoteCodingRelayDeliveryRequest {
  const RemoteCodingRelayDeliveryRequest({required this.notification});

  final RemoteCodingNotificationPayload notification;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': RemoteCodingNotificationRelayContract.schemaVersion,
    'notification': notification.toFcmData(),
  };

  factory RemoteCodingRelayDeliveryRequest.fromJson(Map<String, dynamic> json) {
    _requireSchemaVersion(json);
    final notification = json['notification'];
    if (notification is! Map) {
      throw const FormatException('Relay notification payload is required.');
    }
    return RemoteCodingRelayDeliveryRequest(
      notification: RemoteCodingNotificationPayload.fromFcmData(
        Map<String, dynamic>.from(notification),
      ),
    );
  }
}

void _requireSchemaVersion(Map<String, dynamic> json) {
  final version = (json['schemaVersion'] as num?)?.toInt();
  if (version != RemoteCodingNotificationRelayContract.schemaVersion) {
    throw FormatException('Unsupported relay contract version: $version');
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('Relay contract field "$key" is required.');
  }
  return value;
}

String _requiredOpaqueIdentifier(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^[A-Za-z0-9_-]{8,256}$').hasMatch(value)) {
    throw FormatException('Relay contract field "$key" is invalid.');
  }
  return value;
}

String _requiredSha256Digest(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key).toLowerCase();
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw FormatException('Relay contract field "$key" is invalid.');
  }
  return value;
}

String _requiredChallengeSecret(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  if (!RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(value)) {
    throw FormatException('Relay contract field "$key" is invalid.');
  }
  return value;
}

DateTime _requiredTimestamp(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(_requiredString(json, key));
  if (value == null) {
    throw FormatException('Relay contract field "$key" is invalid.');
  }
  return value.toUtc();
}
