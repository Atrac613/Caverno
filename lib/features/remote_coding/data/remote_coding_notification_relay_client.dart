import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_coding_notification_relay_contract.dart';
import 'remote_coding_notification_relay_security.dart';
import 'remote_coding_security.dart';

typedef RemoteCodingRelayClock = DateTime Function();
typedef RemoteCodingRelayNonceFactory = String Function();

final class RemoteCodingNotificationRelayEndpoint {
  RemoteCodingNotificationRelayEndpoint._(this.origin);

  final Uri origin;

  factory RemoteCodingNotificationRelayEndpoint.parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Notification relay URL must be an HTTPS origin.',
      );
    }
    return RemoteCodingNotificationRelayEndpoint._(
      uri.replace(path: '', query: null, fragment: null),
    );
  }

  Uri resolvePath(String path) {
    if (!path.startsWith('/v2/')) {
      throw const FormatException('Notification relay path is invalid.');
    }
    return origin.replace(path: path);
  }
}

final class RemoteCodingRelayHttpResponse {
  const RemoteCodingRelayHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

abstract interface class RemoteCodingRelayHttpTransport {
  Future<RemoteCodingRelayHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  });
}

final class HttpRemoteCodingRelayTransport
    implements RemoteCodingRelayHttpTransport {
  HttpRemoteCodingRelayTransport({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<RemoteCodingRelayHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(headers)
      ..body = body;
    final response = await _client.send(request).timeout(timeout);
    return RemoteCodingRelayHttpResponse(
      statusCode: response.statusCode,
      body: await response.stream.bytesToString(),
    );
  }
}

enum RemoteCodingRelayClientFailure { transport, rejected, invalidResponse }

final class RemoteCodingRelayClientException implements Exception {
  const RemoteCodingRelayClientException({
    required this.operation,
    required this.failure,
    this.statusCode,
  });

  final String operation;
  final RemoteCodingRelayClientFailure failure;
  final int? statusCode;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (${statusCode!})';
    return 'Notification relay $operation failed: ${failure.name}$status';
  }
}

abstract interface class RemoteCodingNotificationRelayClient {
  Future<RemoteCodingRelayRegistrationResponse> register({
    required RemoteCodingRelayRegistrationRequest request,
    required String appCheckToken,
  });

  Future<void> rotateFcmToken({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayTokenRotationRequest request,
  });

  Future<void> revokeRegistration({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
  });

  Future<RemoteCodingRelayDelegationCreationResponse> createDelegation({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayDelegationCreationRequest request,
  });

  Future<RemoteCodingRelayDelegationRedemptionResponse> redeemDelegation({
    required String delegationId,
    required RemoteCodingRelayDelegationRedemptionRequest request,
  });

  Future<void> activateDelegation({
    required String deliveryHandle,
    required String delegationId,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDelegationActivationRequest request,
  });

  Future<void> revokeDeliveryCredential({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryCredentialRevocationRequest request,
  });

  Future<void> deliver({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryRequest request,
  });
}

final class HttpRemoteCodingNotificationRelayClient
    implements RemoteCodingNotificationRelayClient {
  HttpRemoteCodingNotificationRelayClient({
    required this.endpoint,
    RemoteCodingRelayHttpTransport? transport,
    RemoteCodingRelayClock? clock,
    RemoteCodingRelayNonceFactory? nonceFactory,
    this.timeout = const Duration(seconds: 8),
  }) : _transport = transport ?? HttpRemoteCodingRelayTransport(),
       _clock = clock ?? DateTime.now,
       _nonceFactory =
           nonceFactory ??
           (() => RemoteCodingSecurity.randomToken(byteLength: 18));

  final RemoteCodingNotificationRelayEndpoint endpoint;
  final Duration timeout;
  final RemoteCodingRelayHttpTransport _transport;
  final RemoteCodingRelayClock _clock;
  final RemoteCodingRelayNonceFactory _nonceFactory;

  @override
  Future<RemoteCodingRelayRegistrationResponse> register({
    required RemoteCodingRelayRegistrationRequest request,
    required String appCheckToken,
  }) async {
    if (appCheckToken.trim().isEmpty) {
      throw const FormatException('Firebase App Check token is required.');
    }
    final json = await _send(
      operation: 'registration',
      method: RemoteCodingNotificationRelayContract.registrationMethod,
      path: RemoteCodingNotificationRelayContract.registrationPath,
      body: request.toJson(),
      additionalHeaders: {
        RemoteCodingNotificationRelayContract.appCheckHeader: appCheckToken,
      },
      expectsResponseBody: true,
    );
    return _parse(
      operation: 'registration',
      json: json,
      parser: RemoteCodingRelayRegistrationResponse.fromJson,
    );
  }

  @override
  Future<void> rotateFcmToken({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayTokenRotationRequest request,
  }) {
    return _sendSignedVoid(
      operation: 'token rotation',
      method: RemoteCodingNotificationRelayContract.rotationMethod,
      path: RemoteCodingNotificationRelayContract.rotationPath(deliveryHandle),
      body: request.toJson(),
      keyId: managementKeyId,
      secret: managementSecret,
    );
  }

  @override
  Future<void> revokeRegistration({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
  }) {
    return _sendSignedVoid(
      operation: 'registration revocation',
      method: RemoteCodingNotificationRelayContract.revocationMethod,
      path: RemoteCodingNotificationRelayContract.revocationPath(
        deliveryHandle,
      ),
      body: const RemoteCodingRelayRevocationRequest().toJson(),
      keyId: managementKeyId,
      secret: managementSecret,
    );
  }

  @override
  Future<RemoteCodingRelayDelegationCreationResponse> createDelegation({
    required String deliveryHandle,
    required String managementKeyId,
    required String managementSecret,
    required RemoteCodingRelayDelegationCreationRequest request,
  }) async {
    final json = await _sendSigned(
      operation: 'delegation creation',
      method: RemoteCodingNotificationRelayContract.delegationCreationMethod,
      path: RemoteCodingNotificationRelayContract.delegationCreationPath(
        deliveryHandle,
      ),
      body: request.toJson(),
      keyId: managementKeyId,
      secret: managementSecret,
      expectsResponseBody: true,
    );
    return _parse(
      operation: 'delegation creation',
      json: json,
      parser: RemoteCodingRelayDelegationCreationResponse.fromJson,
    );
  }

  @override
  Future<RemoteCodingRelayDelegationRedemptionResponse> redeemDelegation({
    required String delegationId,
    required RemoteCodingRelayDelegationRedemptionRequest request,
  }) async {
    final json = await _send(
      operation: 'delegation redemption',
      method: RemoteCodingNotificationRelayContract.delegationRedemptionMethod,
      path: RemoteCodingNotificationRelayContract.delegationRedemptionPath(
        delegationId,
      ),
      body: request.toJson(),
      expectsResponseBody: true,
    );
    return _parse(
      operation: 'delegation redemption',
      json: json,
      parser: RemoteCodingRelayDelegationRedemptionResponse.fromJson,
    );
  }

  @override
  Future<void> activateDelegation({
    required String deliveryHandle,
    required String delegationId,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDelegationActivationRequest request,
  }) {
    return _sendSignedVoid(
      operation: 'delegation activation',
      method: RemoteCodingNotificationRelayContract.delegationActivationMethod,
      path: RemoteCodingNotificationRelayContract.delegationActivationPath(
        deliveryHandle,
        delegationId,
      ),
      body: request.toJson(),
      keyId: deliveryKeyId,
      secret: deliverySecret,
    );
  }

  @override
  Future<void> revokeDeliveryCredential({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryCredentialRevocationRequest request,
  }) {
    return _sendSignedVoid(
      operation: 'delivery credential revocation',
      method: RemoteCodingNotificationRelayContract
          .deliveryCredentialRevocationMethod,
      path:
          RemoteCodingNotificationRelayContract.deliveryCredentialRevocationPath(
            deliveryHandle,
            deliveryKeyId,
          ),
      body: request.toJson(),
      keyId: deliveryKeyId,
      secret: deliverySecret,
    );
  }

  @override
  Future<void> deliver({
    required String deliveryHandle,
    required String deliveryKeyId,
    required String deliverySecret,
    required RemoteCodingRelayDeliveryRequest request,
  }) {
    return _sendSignedVoid(
      operation: 'notification delivery',
      method: RemoteCodingNotificationRelayContract.deliveryMethod,
      path: RemoteCodingNotificationRelayContract.deliveryPath(deliveryHandle),
      body: request.toJson(),
      keyId: deliveryKeyId,
      secret: deliverySecret,
    );
  }

  Future<void> _sendSignedVoid({
    required String operation,
    required String method,
    required String path,
    required Map<String, dynamic> body,
    required String keyId,
    required String secret,
  }) async {
    await _sendSigned(
      operation: operation,
      method: method,
      path: path,
      body: body,
      keyId: keyId,
      secret: secret,
      expectsResponseBody: false,
    );
  }

  Future<Map<String, dynamic>?> _sendSigned({
    required String operation,
    required String method,
    required String path,
    required Map<String, dynamic> body,
    required String keyId,
    required String secret,
    required bool expectsResponseBody,
  }) {
    final encodedBody = jsonEncode(body);
    final signedHeaders = RemoteCodingRelayRequestSigner.sign(
      method: method,
      path: path,
      body: encodedBody,
      keyId: keyId,
      secret: secret,
      signedAt: _clock().toUtc(),
      nonce: _nonceFactory(),
    ).toMap();
    return _sendEncoded(
      operation: operation,
      method: method,
      path: path,
      encodedBody: encodedBody,
      additionalHeaders: signedHeaders,
      expectsResponseBody: expectsResponseBody,
    );
  }

  Future<Map<String, dynamic>?> _send({
    required String operation,
    required String method,
    required String path,
    required Map<String, dynamic> body,
    required bool expectsResponseBody,
    Map<String, String> additionalHeaders = const <String, String>{},
  }) {
    return _sendEncoded(
      operation: operation,
      method: method,
      path: path,
      encodedBody: jsonEncode(body),
      additionalHeaders: additionalHeaders,
      expectsResponseBody: expectsResponseBody,
    );
  }

  Future<Map<String, dynamic>?> _sendEncoded({
    required String operation,
    required String method,
    required String path,
    required String encodedBody,
    required Map<String, String> additionalHeaders,
    required bool expectsResponseBody,
  }) async {
    late final RemoteCodingRelayHttpResponse response;
    try {
      response = await _transport.send(
        method: method,
        uri: endpoint.resolvePath(path),
        headers: <String, String>{
          'Accept': 'application/json',
          'Content-Type': 'application/json; charset=utf-8',
          ...additionalHeaders,
        },
        body: encodedBody,
        timeout: timeout,
      );
    } catch (_) {
      throw RemoteCodingRelayClientException(
        operation: operation,
        failure: RemoteCodingRelayClientFailure.transport,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteCodingRelayClientException(
        operation: operation,
        failure: RemoteCodingRelayClientFailure.rejected,
        statusCode: response.statusCode,
      );
    }
    if (!expectsResponseBody) {
      return null;
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Relay response must be an object.');
      }
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw RemoteCodingRelayClientException(
        operation: operation,
        failure: RemoteCodingRelayClientFailure.invalidResponse,
        statusCode: response.statusCode,
      );
    }
  }

  T _parse<T>({
    required String operation,
    required Map<String, dynamic>? json,
    required T Function(Map<String, dynamic>) parser,
  }) {
    try {
      return parser(json ?? const <String, dynamic>{});
    } catch (_) {
      throw RemoteCodingRelayClientException(
        operation: operation,
        failure: RemoteCodingRelayClientFailure.invalidResponse,
      );
    }
  }
}
