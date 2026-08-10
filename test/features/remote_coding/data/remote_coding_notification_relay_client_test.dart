import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_client.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 10, 16);
  late _FakeRelayTransport transport;
  late HttpRemoteCodingNotificationRelayClient client;

  setUp(() {
    transport = _FakeRelayTransport();
    client = HttpRemoteCodingNotificationRelayClient(
      endpoint: RemoteCodingNotificationRelayEndpoint.parse(
        'https://relay.example.test',
      ),
      transport: transport,
      clock: () => now,
      nonceFactory: () => 'nonce_12345678',
    );
  });

  test('relay endpoint accepts only a bare HTTPS origin', () {
    expect(
      RemoteCodingNotificationRelayEndpoint.parse(
        'https://relay.example.test:8443/',
      ).origin.toString(),
      'https://relay.example.test:8443',
    );
    for (final invalid in <String>[
      'http://relay.example.test',
      'https://user@relay.example.test',
      'https://relay.example.test/base',
      'https://relay.example.test?target=other',
      'not-a-url',
    ]) {
      expect(
        () => RemoteCodingNotificationRelayEndpoint.parse(invalid),
        throwsFormatException,
        reason: invalid,
      );
    }
  });

  test(
    'registration uses App Check and returns no delivery credential',
    () async {
      transport.enqueueJson({
        'schemaVersion': 2,
        'deliveryHandle': 'delivery_handle_1',
        'managementKeyId': 'management-key-1',
        'managementSecret': 'management-secret',
        'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
      });

      final response = await client.register(
        request: RemoteCodingRelayRegistrationRequest(
          installationId: 'installation_123',
          platform: RemoteCodingRelayPlatform.ios,
          fcmRegistrationToken: 'fcm-token',
          requestedAt: now,
        ),
        appCheckToken: 'app-check-token',
      );

      final sent = transport.singleRequest;
      expect(
        sent.uri.toString(),
        'https://relay.example.test/v2/registrations',
      );
      expect(
        sent.headers[RemoteCodingNotificationRelayContract.appCheckHeader],
        'app-check-token',
      );
      expect(
        sent.headers,
        isNot(contains(RemoteCodingNotificationRelayContract.signatureHeader)),
      );
      expect(response.managementSecret, 'management-secret');
      expect(response.toJson(), isNot(contains('deliverySecret')));
    },
  );

  test('delegation creation signs only the digest-bearing request', () async {
    final digest = List.filled(64, 'a').join();
    transport.enqueueJson({
      'schemaVersion': 2,
      'delegationId': 'delegation_123',
      'challengeId': 'challenge_123',
      'targetDeviceId': 'device_123',
      'expiresAt': now.add(const Duration(minutes: 5)).toIso8601String(),
    });

    await client.createDelegation(
      deliveryHandle: 'delivery_handle_1',
      managementKeyId: 'management-key-1',
      managementSecret: 'management-secret',
      request: RemoteCodingRelayDelegationCreationRequest(
        challengeId: 'challenge_123',
        challengeDigest: digest,
        targetDeviceId: 'device_123',
        requestedAt: now,
      ),
    );

    final sent = transport.singleRequest;
    expect(sent.uri.path, '/v2/registrations/delivery_handle_1/delegations');
    expect(jsonDecode(sent.body), isNot(contains('challengeSecret')));
    expect(
      _verifySigned(
        sent,
        secret: 'management-secret',
        scope: RemoteCodingRelayCredentialScope.management,
        now: now,
      ),
      isNull,
    );
  });

  test('desktop redeems directly and activation uses the new key', () async {
    final challengeSecret = List.filled(43, 's').join();
    transport.enqueueJson({
      'schemaVersion': 2,
      'delegationId': 'delegation_123',
      'deliveryHandle': 'delivery_handle_1',
      'deliveryKeyId': 'delivery-key-123',
      'deliverySecret': 'desktop-delivery-secret',
      'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
    });
    transport.enqueueEmpty();

    final credential = await client.redeemDelegation(
      delegationId: 'delegation_123',
      request: RemoteCodingRelayDelegationRedemptionRequest(
        challengeId: 'challenge_123',
        challengeSecret: challengeSecret,
        targetDeviceId: 'device_123',
        idempotencyKey: 'idempotency_123',
        requestedAt: now,
      ),
    );
    await client.activateDelegation(
      deliveryHandle: credential.deliveryHandle,
      delegationId: credential.delegationId,
      deliveryKeyId: credential.deliveryKeyId,
      deliverySecret: credential.deliverySecret,
      request: RemoteCodingRelayDelegationActivationRequest(
        deliveryKeyId: credential.deliveryKeyId,
        activatedAt: now,
      ),
    );

    final redemption = transport.requests[0];
    expect(redemption.uri.path, '/v2/delegations/delegation_123/redeem');
    expect(
      redemption.headers,
      isNot(contains(RemoteCodingNotificationRelayContract.signatureHeader)),
    );
    expect(jsonDecode(redemption.body)['challengeSecret'], challengeSecret);

    final activation = transport.requests[1];
    expect(
      activation.uri.path,
      '/v2/registrations/delivery_handle_1/delegations/delegation_123/activate',
    );
    expect(
      _verifySigned(
        activation,
        secret: 'desktop-delivery-secret',
        scope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
      ),
      isNull,
    );
  });

  test(
    'rejected responses do not expose identifiers or request secrets',
    () async {
      transport.enqueue(
        const RemoteCodingRelayHttpResponse(
          statusCode: 401,
          body: '{"error":"delivery_handle_1 desktop-delivery-secret"}',
        ),
      );

      Object? error;
      try {
        await client.revokeDeliveryCredential(
          deliveryHandle: 'delivery_handle_1',
          deliveryKeyId: 'delivery-key-123',
          deliverySecret: 'desktop-delivery-secret',
          request: RemoteCodingRelayDeliveryCredentialRevocationRequest(
            requestedAt: now,
          ),
        );
      } catch (caught) {
        error = caught;
      }

      expect(error, isA<RemoteCodingRelayClientException>());
      final message = error.toString();
      expect(message, contains('rejected (401)'));
      expect(message, isNot(contains('delivery_handle_1')));
      expect(message, isNot(contains('desktop-delivery-secret')));
    },
  );
}

RemoteCodingRelayVerificationFailure? _verifySigned(
  _CapturedRelayRequest request, {
  required String secret,
  required RemoteCodingRelayCredentialScope scope,
  required DateTime now,
}) {
  return RemoteCodingRelayRequestVerifier(
    replayGuard: RemoteCodingRelayReplayGuard(),
  ).verify(
    method: request.method,
    path: request.uri.path,
    body: request.body,
    headers: request.headers,
    secret: secret,
    credentialScope: scope,
    requiredScope: scope,
    now: now,
  );
}

final class _CapturedRelayRequest {
  const _CapturedRelayRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

final class _FakeRelayTransport implements RemoteCodingRelayHttpTransport {
  final List<RemoteCodingRelayHttpResponse> _responses = [];
  final List<_CapturedRelayRequest> requests = [];

  _CapturedRelayRequest get singleRequest => requests.single;

  void enqueueJson(Map<String, dynamic> value) {
    enqueue(
      RemoteCodingRelayHttpResponse(statusCode: 200, body: jsonEncode(value)),
    );
  }

  void enqueueEmpty() {
    enqueue(const RemoteCodingRelayHttpResponse(statusCode: 204, body: ''));
  }

  void enqueue(RemoteCodingRelayHttpResponse response) {
    _responses.add(response);
  }

  @override
  Future<RemoteCodingRelayHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    requests.add(
      _CapturedRelayRequest(
        method: method,
        uri: uri,
        headers: Map<String, String>.from(headers),
        body: body,
      ),
    );
    if (_responses.isEmpty) {
      throw StateError('No fake relay response was queued.');
    }
    return _responses.removeAt(0);
  }
}
