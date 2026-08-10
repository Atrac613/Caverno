import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'remote_coding_notification_relay_contract.dart';
import 'remote_coding_security.dart';

enum RemoteCodingRelayVerificationFailure {
  missingAuthentication,
  timestampOutsideWindow,
  wrongCredentialScope,
  invalidSignature,
  eventTimestampOutsideWindow,
  replayedNonce,
  replayedEvent,
  replayCapacityExceeded,
}

final class RemoteCodingRelayAuthHeaders {
  const RemoteCodingRelayAuthHeaders({
    required this.keyId,
    required this.timestampSeconds,
    required this.nonce,
    required this.signature,
  });

  final String keyId;
  final int timestampSeconds;
  final String nonce;
  final String signature;

  Map<String, String> toMap() => <String, String>{
    RemoteCodingNotificationRelayContract.keyIdHeader: keyId,
    RemoteCodingNotificationRelayContract.timestampHeader: timestampSeconds
        .toString(),
    RemoteCodingNotificationRelayContract.nonceHeader: nonce,
    RemoteCodingNotificationRelayContract.signatureHeader: signature,
  };

  static RemoteCodingRelayAuthHeaders? tryParse(Map<String, String> headers) {
    String read(String name) {
      final normalizedName = name.toLowerCase();
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == normalizedName) {
          return entry.value.trim();
        }
      }
      return '';
    }

    final keyId = read(RemoteCodingNotificationRelayContract.keyIdHeader);
    final timestamp = int.tryParse(
      read(RemoteCodingNotificationRelayContract.timestampHeader),
    );
    final nonce = read(RemoteCodingNotificationRelayContract.nonceHeader);
    final signature = read(
      RemoteCodingNotificationRelayContract.signatureHeader,
    );
    if (keyId.isEmpty ||
        timestamp == null ||
        nonce.isEmpty ||
        signature.isEmpty) {
      return null;
    }
    return RemoteCodingRelayAuthHeaders(
      keyId: keyId,
      timestampSeconds: timestamp,
      nonce: nonce,
      signature: signature,
    );
  }
}

final class RemoteCodingRelayRequestSigner {
  const RemoteCodingRelayRequestSigner._();

  static RemoteCodingRelayAuthHeaders sign({
    required String method,
    required String path,
    required String body,
    required String keyId,
    required String secret,
    required DateTime signedAt,
    required String nonce,
  }) {
    final timestampSeconds = signedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    final canonical = canonicalRequest(
      method: method,
      path: path,
      body: body,
      keyId: keyId,
      timestampSeconds: timestampSeconds,
      nonce: nonce,
    );
    final signature = base64UrlEncode(
      Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(canonical)).bytes,
    ).replaceAll('=', '');
    return RemoteCodingRelayAuthHeaders(
      keyId: keyId,
      timestampSeconds: timestampSeconds,
      nonce: nonce,
      signature: signature,
    );
  }

  static String canonicalRequest({
    required String method,
    required String path,
    required String body,
    required String keyId,
    required int timestampSeconds,
    required String nonce,
  }) {
    final bodyDigest = sha256.convert(utf8.encode(body)).toString();
    return <String>[
      'caverno-relay-v1',
      method.trim().toUpperCase(),
      path.trim(),
      keyId.trim(),
      timestampSeconds.toString(),
      nonce.trim(),
      bodyDigest,
    ].join('\n');
  }
}

/// Bounded in-memory replay ledger used by tests and single-instance relays.
/// Production multi-instance relays must back the same atomic contract with a
/// shared durable store.
final class RemoteCodingRelayReplayGuard {
  RemoteCodingRelayReplayGuard({
    this.retention = const Duration(minutes: 20),
    this.maxEntries = 4096,
  }) : assert(maxEntries > 0);

  final Duration retention;
  final int maxEntries;
  final LinkedHashMap<String, DateTime> _nonces = LinkedHashMap();
  final LinkedHashMap<String, DateTime> _events = LinkedHashMap();

  RemoteCodingRelayVerificationFailure? accept({
    required String keyId,
    required String nonce,
    required DateTime now,
    String? eventId,
  }) {
    _purge(now);
    final nonceKey = '$keyId:$nonce';
    if (_nonces.containsKey(nonceKey)) {
      return RemoteCodingRelayVerificationFailure.replayedNonce;
    }
    final normalizedEventId = eventId?.trim() ?? '';
    if (normalizedEventId.isNotEmpty &&
        _events.containsKey(normalizedEventId)) {
      return RemoteCodingRelayVerificationFailure.replayedEvent;
    }
    if (_nonces.length >= maxEntries ||
        (normalizedEventId.isNotEmpty && _events.length >= maxEntries)) {
      return RemoteCodingRelayVerificationFailure.replayCapacityExceeded;
    }
    _nonces[nonceKey] = now.toUtc();
    if (normalizedEventId.isNotEmpty) {
      _events[normalizedEventId] = now.toUtc();
    }
    return null;
  }

  void _purge(DateTime now) {
    final cutoff = now.toUtc().subtract(retention);
    _nonces.removeWhere((_, recordedAt) => recordedAt.isBefore(cutoff));
    _events.removeWhere((_, recordedAt) => recordedAt.isBefore(cutoff));
  }
}

final class RemoteCodingRelayRequestVerifier {
  RemoteCodingRelayRequestVerifier({
    required this.replayGuard,
    this.maximumClockSkew = const Duration(minutes: 5),
    this.maximumEventAge = const Duration(minutes: 15),
  });

  final RemoteCodingRelayReplayGuard replayGuard;
  final Duration maximumClockSkew;
  final Duration maximumEventAge;

  RemoteCodingRelayVerificationFailure? verify({
    required String method,
    required String path,
    required String body,
    required Map<String, String> headers,
    required String secret,
    required RemoteCodingRelayCredentialScope credentialScope,
    required RemoteCodingRelayCredentialScope requiredScope,
    required DateTime now,
    String? eventId,
    DateTime? eventTimestamp,
  }) {
    final auth = RemoteCodingRelayAuthHeaders.tryParse(headers);
    if (auth == null) {
      return RemoteCodingRelayVerificationFailure.missingAuthentication;
    }
    final signedAt = DateTime.fromMillisecondsSinceEpoch(
      auth.timestampSeconds * 1000,
      isUtc: true,
    );
    final clockDifference = now.toUtc().difference(signedAt).abs();
    if (clockDifference > maximumClockSkew) {
      return RemoteCodingRelayVerificationFailure.timestampOutsideWindow;
    }
    if (credentialScope != requiredScope) {
      return RemoteCodingRelayVerificationFailure.wrongCredentialScope;
    }
    final expected = RemoteCodingRelayRequestSigner.sign(
      method: method,
      path: path,
      body: body,
      keyId: auth.keyId,
      secret: secret,
      signedAt: signedAt,
      nonce: auth.nonce,
    );
    if (!RemoteCodingSecurity.constantTimeEquals(
      auth.signature,
      expected.signature,
    )) {
      return RemoteCodingRelayVerificationFailure.invalidSignature;
    }
    if (eventTimestamp != null) {
      final normalizedEventTimestamp = eventTimestamp.toUtc();
      if (normalizedEventTimestamp.isAfter(now.toUtc().add(maximumClockSkew)) ||
          normalizedEventTimestamp.isBefore(
            now.toUtc().subtract(maximumEventAge),
          )) {
        return RemoteCodingRelayVerificationFailure.eventTimestampOutsideWindow;
      }
    }
    return replayGuard.accept(
      keyId: auth.keyId,
      nonce: auth.nonce,
      now: now,
      eventId: eventId,
    );
  }
}
