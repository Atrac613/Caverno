import 'package:caverno/features/remote_coding/data/remote_coding_notification_payload.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registration request round-trips the FCM token for relay-only use', () {
    final request = RemoteCodingRelayRegistrationRequest(
      installationId: 'installation-1',
      platform: RemoteCodingRelayPlatform.ios,
      fcmRegistrationToken: 'fcm-registration-token',
      requestedAt: DateTime.utc(2026, 8, 10, 15),
    );

    final decoded = RemoteCodingRelayRegistrationRequest.fromJson(
      request.toJson(),
    );

    expect(decoded.installationId, request.installationId);
    expect(decoded.platform, RemoteCodingRelayPlatform.ios);
    expect(decoded.fcmRegistrationToken, request.fcmRegistrationToken);
    expect(decoded.requestedAt, request.requestedAt);
  });

  test('registration contract requires App Check authentication', () {
    expect(
      RemoteCodingNotificationRelayContract.hasAppCheckAuthentication(const {
        'X-Firebase-AppCheck': 'app-check-token',
      }),
      isTrue,
    );
    expect(
      RemoteCodingNotificationRelayContract.hasAppCheckAuthentication(
        const <String, String>{},
      ),
      isFalse,
    );
  });

  test('registration response returns only the management credential', () {
    final response = RemoteCodingRelayRegistrationResponse(
      deliveryHandle: 'delivery_handle_1',
      managementKeyId: 'management-key-1',
      managementSecret: 'management-secret',
      expiresAt: DateTime.utc(2026, 9, 10),
    );

    final decoded = RemoteCodingRelayRegistrationResponse.fromJson(
      response.toJson(),
    );

    expect(decoded.deliveryHandle, response.deliveryHandle);
    expect(decoded.managementKeyId, response.managementKeyId);
    expect(decoded.managementSecret, response.managementSecret);
    expect(decoded.expiresAt, response.expiresAt);
    expect(response.toJson(), isNot(contains('deliveryKeyId')));
    expect(response.toJson(), isNot(contains('deliverySecret')));
    expect(response.metadata.toJson(), isNot(contains('managementSecret')));
    expect(response.metadata.toJson(), isNot(contains('deliverySecret')));
  });

  test('delegation contract keeps the QR secret out of creation', () {
    final creation = RemoteCodingRelayDelegationCreationRequest(
      challengeId: 'challenge_123',
      challengeDigest: List.filled(64, 'a').join(),
      targetDeviceId: 'device_123',
      requestedAt: DateTime.utc(2026, 8, 10, 15),
    );
    final decodedCreation = RemoteCodingRelayDelegationCreationRequest.fromJson(
      creation.toJson(),
    );

    expect(decodedCreation.challengeDigest, creation.challengeDigest);
    expect(creation.toJson(), isNot(contains('challengeSecret')));

    final redemption = RemoteCodingRelayDelegationRedemptionRequest(
      challengeId: 'challenge_123',
      challengeSecret: List.filled(43, 'b').join(),
      targetDeviceId: 'device_123',
      idempotencyKey: 'idempotency_123',
      requestedAt: DateTime.utc(2026, 8, 10, 15, 1),
    );
    final decodedRedemption =
        RemoteCodingRelayDelegationRedemptionRequest.fromJson(
          redemption.toJson(),
        );

    expect(decodedRedemption.challengeSecret, redemption.challengeSecret);
    expect(decodedRedemption.idempotencyKey, redemption.idempotencyKey);
  });

  test('delegation paths are versioned and validate opaque IDs', () {
    expect(
      RemoteCodingNotificationRelayContract.delegationCreationPath(
        'handle_123',
      ),
      '/v2/registrations/handle_123/delegations',
    );
    expect(
      RemoteCodingNotificationRelayContract.delegationRedemptionPath(
        'delegation_123',
      ),
      '/v2/delegations/delegation_123/redeem',
    );
    expect(
      RemoteCodingNotificationRelayContract.delegationActivationPath(
        'handle_123',
        'delegation_123',
      ),
      '/v2/registrations/handle_123/delegations/delegation_123/activate',
    );
    expect(
      RemoteCodingNotificationRelayContract.deliveryCredentialRevocationPath(
        'handle_123',
        'delivery-key-123',
      ),
      '/v2/registrations/handle_123/delivery-credentials/delivery-key-123',
    );
    expect(
      () => RemoteCodingNotificationRelayContract.delegationRedemptionPath(
        '../secret',
      ),
      throwsFormatException,
    );
  });

  test('redemption response carries the desktop-only delivery credential', () {
    final response = RemoteCodingRelayDelegationRedemptionResponse(
      delegationId: 'delegation_123',
      deliveryHandle: 'delivery_handle_1',
      deliveryKeyId: 'delivery-key-123',
      deliverySecret: 'desktop-delivery-secret',
      expiresAt: DateTime.utc(2026, 9, 10),
    );

    final decoded = RemoteCodingRelayDelegationRedemptionResponse.fromJson(
      response.toJson(),
    );

    expect(decoded.toJson(), response.toJson());
  });

  test('delivery request reuses the privacy-safe notification allowlist', () {
    final request = RemoteCodingRelayDeliveryRequest(
      notification: RemoteCodingNotificationPayload(
        eventId: 'event-1',
        turnId: 'gen-1',
        conversationId: 'conversation-1',
        outcome: RemoteCodingNotificationOutcome.completed,
        title: 'Remote coding completed',
        body: 'Open Caverno to review the result.',
        completedAt: DateTime.utc(2026, 8, 10, 15, 30),
      ),
    );

    final decoded = RemoteCodingRelayDeliveryRequest.fromJson(request.toJson());

    expect(decoded.notification.eventId, 'event-1');
    expect(
      decoded.notification.outcome,
      RemoteCodingNotificationOutcome.completed,
    );
    expect(
      (request.toJson()['notification'] as Map<String, String>).keys,
      isNot(anyOf(contains('prompt'), contains('content'), contains('tool'))),
    );
  });

  test('relay paths accept only opaque URL-safe delivery handles', () {
    expect(
      RemoteCodingNotificationRelayContract.deliveryPath('handle_123'),
      '/v2/registrations/handle_123/deliveries',
    );
    expect(
      () => RemoteCodingNotificationRelayContract.deliveryPath('../secret'),
      throwsFormatException,
    );
  });

  test('contract parsers reject unsupported versions and missing secrets', () {
    expect(
      () => RemoteCodingRelayTokenRotationRequest.fromJson({
        'schemaVersion': 1,
        'fcmRegistrationToken': 'token',
      }),
      throwsFormatException,
    );
    expect(
      () => RemoteCodingRelayRegistrationResponse.fromJson({
        'schemaVersion': 2,
        'deliveryHandle': 'delivery_handle_1',
      }),
      throwsFormatException,
    );
  });
}
