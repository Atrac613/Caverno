import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a strict versioned command object', () {
    final raw = jsonEncode({
      'version': remoteCodingProtocolVersion,
      'type': 'sendMessage',
      'id': 'request-1',
      'payload': {'content': 'Fix the failing test'},
    });

    final message = RemoteCodingProtocolMessage.decode(raw);

    expect(message.type, 'sendMessage');
    expect(message.id, 'request-1');
    expect(message.payload['content'], 'Fix the failing test');
  });

  test('rejects unsupported protocol versions', () {
    // Both directions, against the current version rather than a literal: the
    // check is an exact match, so a newer peer must be refused as loudly as an
    // older one. A version-1 client decoding a version-2 approval would render
    // an unknown kind as `file` (SA-26), which is why the refusal is the
    // feature and not a limitation to relax.
    for (final version in <int>[
      remoteCodingProtocolVersion - 1,
      remoteCodingProtocolVersion + 1,
    ]) {
      final raw = jsonEncode({
        'version': version,
        'type': 'requestSnapshot',
        'payload': <String, dynamic>{},
      });

      expect(
        () => RemoteCodingProtocolMessage.decode(raw),
        throwsA(isA<FormatException>()),
        reason: 'version $version must not decode',
      );
    }
  });

  test('client command allowlist does not include project creation', () {
    expect(
      RemoteCodingProtocol.allowedClientCommands,
      unorderedEquals(<String>{
        'auth',
        'selectProject',
        'selectConversation',
        'createThread',
        'sendMessage',
        'cancelStreaming',
        'resolveApproval',
        'resolveQuestion',
        'requestSnapshot',
        'relayDelegationReady',
      }),
    );
    expect(
      RemoteCodingProtocol.allowedClientCommands,
      isNot(contains('addProject')),
    );
    expect(
      RemoteCodingProtocol.allowedClientCommands,
      isNot(contains('removeProject')),
    );
    expect(
      RemoteCodingProtocol.allowedClientCommands,
      isNot(contains('updateSettings')),
    );
    expect(
      RemoteCodingProtocol.allowedClientCommands,
      isNot(contains('addMcpServer')),
    );
    expect(
      RemoteCodingProtocol.allowedClientCommands,
      isNot(contains('removeMcpServer')),
    );
  });

  test('server event allowlist includes terminal run delivery', () {
    expect(RemoteCodingProtocol.allowedServerEvents, contains('runTerminal'));
    expect(RemoteCodingProtocol.allowedServerEvents, contains('authChallenge'));
  });
}
