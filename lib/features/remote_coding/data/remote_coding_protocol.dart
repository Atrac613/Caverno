import 'dart:convert';

/// Bumped to 2 on 2026-09-06 (SA-26).
///
/// The approval wire model changed shape: `kind` became a free-form string
/// covering all eleven [PendingApprovalKinds] rather than an enum of three,
/// and `isSimpleDecision` was added. A version-1 client decodes an unknown
/// kind as `file`, so an SSH or shell approval from a version-2 desktop would
/// be shown to it as a file edit. [RemoteCodingProtocolMessage.decode]
/// requires an exact match, which turns that into a refused connection the
/// user can see and fix instead of a misrepresented approval they cannot.
const int remoteCodingProtocolVersion = 2;

class RemoteCodingProtocolMessage {
  const RemoteCodingProtocolMessage({
    required this.type,
    required this.payload,
    this.id,
  });

  final String type;
  final String? id;
  final Map<String, dynamic> payload;

  factory RemoteCodingProtocolMessage.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Remote coding message must be a JSON object.',
      );
    }
    final version = decoded['version'];
    if (version != remoteCodingProtocolVersion) {
      throw FormatException('Unsupported remote coding version: $version');
    }
    final type = (decoded['type'] as String?)?.trim();
    if (type == null || type.isEmpty) {
      throw const FormatException('Remote coding message type is required.');
    }
    final payload = decoded['payload'];
    if (payload != null && payload is! Map<String, dynamic>) {
      throw const FormatException('Remote coding payload must be an object.');
    }
    return RemoteCodingProtocolMessage(
      type: type,
      id: (decoded['id'] as String?)?.trim(),
      payload: payload == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(payload),
    );
  }

  String encode() => jsonEncode({
    'version': remoteCodingProtocolVersion,
    'type': type,
    if (id != null && id!.isNotEmpty) 'id': id,
    'payload': payload,
  });
}

class RemoteCodingProtocol {
  RemoteCodingProtocol._();

  static const Set<String> allowedClientCommands = {
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
  };

  static const Set<String> allowedServerEvents = {
    'snapshot',
    'chatStateChanged',
    'projectsChanged',
    'conversationsChanged',
    'approvalRequested',
    'approvalResolved',
    'questionRequested',
    'questionResolved',
    'runTerminal',
    'authChallenge',
    'error',
    'disconnected',
  };

  static String encode({
    required String type,
    required Map<String, dynamic> payload,
    String? id,
  }) {
    return RemoteCodingProtocolMessage(
      type: type,
      id: id,
      payload: payload,
    ).encode();
  }

  static Map<String, dynamic> errorPayload({
    required String code,
    required String message,
  }) {
    return {'code': code, 'message': message};
  }
}
