import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a strict versioned command object', () {
    final raw = jsonEncode({
      'version': 1,
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
    final raw = jsonEncode({
      'version': 2,
      'type': 'requestSnapshot',
      'payload': <String, dynamic>{},
    });

    expect(
      () => RemoteCodingProtocolMessage.decode(raw),
      throwsA(isA<FormatException>()),
    );
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
}
