import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_notification_payload.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_contract.dart';
import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const handle = 'delivery_handle_1';
  const keyId = 'delivery-key-1';
  const secret = 'delivery-secret';
  final now = DateTime.utc(2026, 8, 10, 16);

  String deliveryBody({DateTime? completedAt}) => jsonEncode(
    RemoteCodingRelayDeliveryRequest(
      notification: RemoteCodingNotificationPayload(
        eventId: 'event-1',
        turnId: 'gen-1',
        conversationId: 'conversation-1',
        outcome: RemoteCodingNotificationOutcome.completed,
        title: 'Remote coding completed',
        body: 'Open Caverno to review the result.',
        completedAt: completedAt ?? now,
      ),
    ).toJson(),
  );

  Map<String, String> sign({
    required String body,
    required String nonce,
    String method = RemoteCodingNotificationRelayContract.deliveryMethod,
    String? path,
    DateTime? signedAt,
    String signingSecret = secret,
    String signingKeyId = keyId,
  }) => RemoteCodingRelayRequestSigner.sign(
    method: method,
    path: path ?? RemoteCodingNotificationRelayContract.deliveryPath(handle),
    body: body,
    keyId: signingKeyId,
    secret: signingSecret,
    signedAt: signedAt ?? now,
    nonce: nonce,
  ).toMap();

  RemoteCodingRelayRequestVerifier verifier() =>
      RemoteCodingRelayRequestVerifier(
        replayGuard: RemoteCodingRelayReplayGuard(),
      );

  test('accepts a correctly signed delivery inside both time windows', () {
    final body = deliveryBody();

    final result = verifier().verify(
      method: 'POST',
      path: RemoteCodingNotificationRelayContract.deliveryPath(handle),
      body: body,
      headers: sign(body: body, nonce: 'nonce-1'),
      secret: secret,
      credentialScope: RemoteCodingRelayCredentialScope.delivery,
      requiredScope: RemoteCodingRelayCredentialScope.delivery,
      now: now,
      eventId: 'event-1',
      eventTimestamp: now,
    );

    expect(result, isNull);
  });

  test('rejects body, path, and key ID tampering', () {
    final body = deliveryBody();
    final headers = sign(body: body, nonce: 'nonce-tamper');
    final requestVerifier = verifier();

    expect(
      requestVerifier.verify(
        method: 'POST',
        path: RemoteCodingNotificationRelayContract.deliveryPath(handle),
        body: '$body ',
        headers: headers,
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
      ),
      RemoteCodingRelayVerificationFailure.invalidSignature,
    );
    expect(
      requestVerifier.verify(
        method: 'POST',
        path: RemoteCodingNotificationRelayContract.rotationPath(handle),
        body: body,
        headers: headers,
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
      ),
      RemoteCodingRelayVerificationFailure.invalidSignature,
    );
    expect(
      requestVerifier.verify(
        method: 'POST',
        path: RemoteCodingNotificationRelayContract.deliveryPath(handle),
        body: body,
        headers: {
          ...headers,
          RemoteCodingNotificationRelayContract.keyIdHeader: 'other-key',
        },
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
      ),
      RemoteCodingRelayVerificationFailure.invalidSignature,
    );
  });

  test('rejects stale signed requests and stale terminal events', () {
    final body = deliveryBody(
      completedAt: now.subtract(const Duration(minutes: 16)),
    );

    expect(
      verifier().verify(
        method: 'POST',
        path: RemoteCodingNotificationRelayContract.deliveryPath(handle),
        body: body,
        headers: sign(
          body: body,
          nonce: 'nonce-stale-request',
          signedAt: now.subtract(const Duration(minutes: 6)),
        ),
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
      ),
      RemoteCodingRelayVerificationFailure.timestampOutsideWindow,
    );
    expect(
      verifier().verify(
        method: 'POST',
        path: RemoteCodingNotificationRelayContract.deliveryPath(handle),
        body: body,
        headers: sign(body: body, nonce: 'nonce-stale-event'),
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
        eventId: 'event-1',
        eventTimestamp: now.subtract(const Duration(minutes: 16)),
      ),
      RemoteCodingRelayVerificationFailure.eventTimestampOutsideWindow,
    );
  });

  test('rejects replayed nonces and event IDs', () {
    final body = deliveryBody();
    final requestVerifier = verifier();
    final firstHeaders = sign(body: body, nonce: 'nonce-replay-1');

    expect(
      requestVerifier.verify(
        method: 'POST',
        path: RemoteCodingNotificationRelayContract.deliveryPath(handle),
        body: body,
        headers: firstHeaders,
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
        eventId: 'event-1',
        eventTimestamp: now,
      ),
      isNull,
    );
    expect(
      requestVerifier.verify(
        method: 'POST',
        path: RemoteCodingNotificationRelayContract.deliveryPath(handle),
        body: body,
        headers: firstHeaders,
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
        eventId: 'event-1',
        eventTimestamp: now,
      ),
      RemoteCodingRelayVerificationFailure.replayedNonce,
    );
    expect(
      requestVerifier.verify(
        method: 'POST',
        path: RemoteCodingNotificationRelayContract.deliveryPath(handle),
        body: body,
        headers: sign(body: body, nonce: 'nonce-replay-2'),
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.delivery,
        now: now,
        eventId: 'event-1',
        eventTimestamp: now,
      ),
      RemoteCodingRelayVerificationFailure.replayedEvent,
    );
  });

  test('rejects missing authentication headers', () {
    expect(
      verifier().verify(
        method: 'DELETE',
        path: RemoteCodingNotificationRelayContract.revocationPath(handle),
        body: '{}',
        headers: const <String, String>{},
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.management,
        requiredScope: RemoteCodingRelayCredentialScope.management,
        now: now,
      ),
      RemoteCodingRelayVerificationFailure.missingAuthentication,
    );
  });

  test('management scope authenticates rotation and revocation only', () {
    final requestVerifier = verifier();
    final rotationBody = jsonEncode(
      const RemoteCodingRelayTokenRotationRequest(
        fcmRegistrationToken: 'rotated-fcm-token',
      ).toJson(),
    );
    final rotationPath = RemoteCodingNotificationRelayContract.rotationPath(
      handle,
    );

    expect(
      requestVerifier.verify(
        method: RemoteCodingNotificationRelayContract.rotationMethod,
        path: rotationPath,
        body: rotationBody,
        headers: sign(
          method: RemoteCodingNotificationRelayContract.rotationMethod,
          path: rotationPath,
          body: rotationBody,
          nonce: 'nonce-rotate',
        ),
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.management,
        requiredScope: RemoteCodingRelayCredentialScope.management,
        now: now,
      ),
      isNull,
    );

    final revocationBody = jsonEncode(
      const RemoteCodingRelayRevocationRequest().toJson(),
    );
    final revocationPath = RemoteCodingNotificationRelayContract.revocationPath(
      handle,
    );
    expect(
      requestVerifier.verify(
        method: RemoteCodingNotificationRelayContract.revocationMethod,
        path: revocationPath,
        body: revocationBody,
        headers: sign(
          method: RemoteCodingNotificationRelayContract.revocationMethod,
          path: revocationPath,
          body: revocationBody,
          nonce: 'nonce-revoke',
        ),
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.management,
        requiredScope: RemoteCodingRelayCredentialScope.management,
        now: now,
      ),
      isNull,
    );

    expect(
      verifier().verify(
        method: RemoteCodingNotificationRelayContract.rotationMethod,
        path: rotationPath,
        body: rotationBody,
        headers: sign(
          method: RemoteCodingNotificationRelayContract.rotationMethod,
          path: rotationPath,
          body: rotationBody,
          nonce: 'nonce-wrong-scope',
        ),
        secret: secret,
        credentialScope: RemoteCodingRelayCredentialScope.delivery,
        requiredScope: RemoteCodingRelayCredentialScope.management,
        now: now,
      ),
      RemoteCodingRelayVerificationFailure.wrongCredentialScope,
    );
  });

  test('replay guard fails closed at capacity until entries expire', () {
    final guard = RemoteCodingRelayReplayGuard(maxEntries: 1);

    expect(
      guard.accept(
        keyId: keyId,
        nonce: 'nonce-capacity-1',
        eventId: 'event-capacity-1',
        now: now,
      ),
      isNull,
    );
    expect(
      guard.accept(
        keyId: keyId,
        nonce: 'nonce-capacity-2',
        eventId: 'event-capacity-2',
        now: now,
      ),
      RemoteCodingRelayVerificationFailure.replayCapacityExceeded,
    );
    expect(
      guard.accept(
        keyId: keyId,
        nonce: 'nonce-capacity-2',
        eventId: 'event-capacity-2',
        now: now.add(const Duration(minutes: 21)),
      ),
      isNull,
    );
  });
}
