import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import '../domain/remote_coding_transport_policy.dart';

/// Self-signed TLS identity for pinned Remote Coding WSS.
final class RemoteCodingTlsIdentity {
  const RemoteCodingTlsIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.certificatePin,
  });

  static const String _commonName = 'caverno-remote-coding';
  static const String _identityJsonVersion = '1';

  final String certificatePem;
  final String privateKeyPem;
  final String certificatePin;

  SecurityContext get securityContext {
    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(utf8.encode(certificatePem));
    context.usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return context;
  }

  Map<String, String> toJson() => {
    'version': _identityJsonVersion,
    'certificatePem': certificatePem,
    'privateKeyPem': privateKeyPem,
    'certificatePin': certificatePin,
  };

  factory RemoteCodingTlsIdentity.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as String?)?.trim() ?? '';
    final certificatePem = (json['certificatePem'] as String?)?.trim() ?? '';
    final privateKeyPem = (json['privateKeyPem'] as String?)?.trim() ?? '';
    final certificatePin = (json['certificatePin'] as String?)?.trim() ?? '';
    if (version != _identityJsonVersion ||
        certificatePem.isEmpty ||
        privateKeyPem.isEmpty ||
        certificatePin.isEmpty) {
      throw const FormatException('Remote Coding TLS identity is incomplete.');
    }
    final identity = RemoteCodingTlsIdentity(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      certificatePin: certificatePin,
    );
    try {
      identity.validate();
    } on FormatException {
      rethrow;
    } on TlsException {
      throw const FormatException(
        'Remote Coding TLS certificate and private key do not match.',
      );
    }
    return identity;
  }

  /// Verifies that the persisted certificate, key, and pin remain consistent.
  void validate() {
    final certificateDer = _decodePem('CERTIFICATE', certificatePem);
    final actualPin = RemoteCodingTransportPolicy.pinForDer(certificateDer);
    if (actualPin != certificatePin.trim().toLowerCase()) {
      throw const FormatException(
        'Remote Coding TLS certificate pin does not match the certificate.',
      );
    }
    securityContext;
  }

  static RemoteCodingTlsIdentity generate({DateTime? now}) {
    final pair = _generateRsaKeyPair();
    final privateKey = pair.privateKey as RSAPrivateKey;
    final publicKey = pair.publicKey as RSAPublicKey;
    final issuedAt = now ?? DateTime.now().toUtc();
    final tbs = _tbsCertificate(
      publicKey: publicKey,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 825)),
    );
    final tbsBytes = tbs.encode();
    final signature = _signSha256Rsa(tbsBytes, privateKey);
    final certificate = ASN1Sequence(
      elements: [
        tbs,
        _sha256WithRsaAlgorithm(),
        ASN1BitString(stringValues: signature),
      ],
    );
    final certificateDer = certificate.encode();
    final privateKeyDer = _pkcs1PrivateKey(privateKey).encode();
    return RemoteCodingTlsIdentity(
      certificatePem: _pem('CERTIFICATE', certificateDer),
      privateKeyPem: _pem('RSA PRIVATE KEY', privateKeyDer),
      certificatePin: RemoteCodingTransportPolicy.pinForDer(certificateDer),
    );
  }
}

AsymmetricKeyPair<PublicKey, PrivateKey> _generateRsaKeyPair() {
  final random = FortunaRandom();
  final seed = Uint8List.fromList(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  random.seed(KeyParameter(seed));
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        random,
      ),
    );
  return generator.generateKeyPair();
}

ASN1Sequence _tbsCertificate({
  required RSAPublicKey publicKey,
  required DateTime issuedAt,
  required DateTime expiresAt,
}) {
  final serial = ASN1Integer(
    BigInt.from(DateTime.now().microsecondsSinceEpoch & 0x7fffffff),
  );
  final name = _commonName();
  final version = ASN1Integer(BigInt.from(2));
  final wrappedVersion = ASN1Object(tag: 0xa0)..valueBytes = version.encode();
  return ASN1Sequence(
    elements: [
      wrappedVersion,
      serial,
      _sha256WithRsaAlgorithm(),
      name,
      ASN1Sequence(
        elements: [
          ASN1UtcTime(issuedAt.toUtc()),
          ASN1UtcTime(expiresAt.toUtc()),
        ],
      ),
      name,
      _subjectPublicKeyInfo(publicKey),
    ],
  );
}

ASN1Sequence _commonName() {
  return ASN1Sequence(
    elements: [
      ASN1Set(
        elements: [
          ASN1Sequence(
            elements: [
              ASN1ObjectIdentifier.fromIdentifierString('2.5.4.3'),
              ASN1UTF8String(
                utf8StringValue: RemoteCodingTlsIdentity._commonName,
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

ASN1Sequence _sha256WithRsaAlgorithm() {
  return ASN1Sequence(
    elements: [
      ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'),
      ASN1Null(),
    ],
  );
}

ASN1Sequence _rsaEncryptionAlgorithm() {
  return ASN1Sequence(
    elements: [
      ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'),
      ASN1Null(),
    ],
  );
}

ASN1Sequence _subjectPublicKeyInfo(RSAPublicKey publicKey) {
  final rsaPublicKey = ASN1Sequence(
    elements: [ASN1Integer(publicKey.modulus), ASN1Integer(publicKey.exponent)],
  );
  return ASN1Sequence(
    elements: [
      _rsaEncryptionAlgorithm(),
      ASN1BitString(stringValues: rsaPublicKey.encode()),
    ],
  );
}

ASN1Sequence _pkcs1PrivateKey(RSAPrivateKey key) {
  final p = key.p!;
  final q = key.q!;
  final d = key.privateExponent!;
  final exponent1 = d % (p - BigInt.one);
  final exponent2 = d % (q - BigInt.one);
  final coefficient = q.modInverse(p);
  return ASN1Sequence(
    elements: [
      ASN1Integer(BigInt.zero),
      ASN1Integer(key.modulus),
      ASN1Integer(key.publicExponent),
      ASN1Integer(d),
      ASN1Integer(p),
      ASN1Integer(q),
      ASN1Integer(exponent1),
      ASN1Integer(exponent2),
      ASN1Integer(coefficient),
    ],
  );
}

Uint8List _signSha256Rsa(Uint8List tbs, RSAPrivateKey privateKey) {
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  return signer.generateSignature(tbs).bytes;
}

String _pem(String type, List<int> der) {
  final body = base64.encode(der);
  final lines = <String>[];
  for (var i = 0; i < body.length; i += 64) {
    final end = i + 64 > body.length ? body.length : i + 64;
    lines.add(body.substring(i, end));
  }
  return '-----BEGIN $type-----\n${lines.join('\n')}\n-----END $type-----\n';
}

Uint8List _decodePem(String type, String pem) {
  final normalized = pem.trim();
  final begin = '-----BEGIN $type-----';
  final end = '-----END $type-----';
  if (!normalized.startsWith(begin) || !normalized.endsWith(end)) {
    throw FormatException('Remote Coding TLS $type PEM is invalid.');
  }
  final body = normalized
      .substring(begin.length, normalized.length - end.length)
      .replaceAll(RegExp(r'\s'), '');
  if (body.isEmpty) {
    throw FormatException('Remote Coding TLS $type PEM is empty.');
  }
  try {
    return base64.decode(body);
  } on FormatException {
    throw FormatException('Remote Coding TLS $type PEM is invalid.');
  }
}
