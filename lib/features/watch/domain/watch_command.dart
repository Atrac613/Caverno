/// A command sent from the paired Apple Watch to the iPhone app.
///
/// The vocabulary mirrors `RemoteCodingProtocol.allowedClientCommands` so the
/// two remote surfaces stay conceptually aligned, but this is a separate type:
/// the Remote Coding protocol carries a version handshake and a device
/// principal that a WatchConnectivity peer neither has nor needs.
class WatchCommand {
  const WatchCommand({required this.type, this.id, this.payload = const {}});

  final String type;

  /// Correlation id echoed back on the reply, so the watch can match a result
  /// to the tap that caused it.
  final String? id;
  final Map<String, dynamic> payload;

  static const String sendMessage = 'sendMessage';
  static const String resolveApproval = 'resolveApproval';
  static const String resolveQuestion = 'resolveQuestion';
  static const String cancelStreaming = 'cancelStreaming';
  static const String requestSnapshot = 'requestSnapshot';
  static const String selectConversation = 'selectConversation';

  /// Commands the bridge will act on. Anything else is answered with an error
  /// rather than ignored, so a watch build that is newer than the iPhone build
  /// gets a diagnosable failure instead of silence.
  static const Set<String> allowed = {
    sendMessage,
    resolveApproval,
    resolveQuestion,
    cancelStreaming,
    requestSnapshot,
    selectConversation,
  };

  factory WatchCommand.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] as String?)?.trim() ?? '';
    if (type.isEmpty) {
      throw const FormatException('Watch command type is required.');
    }
    final payload = json['payload'];
    return WatchCommand(
      type: type,
      id: (json['id'] as String?)?.trim(),
      payload: payload is Map<String, dynamic>
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (id != null && id!.isNotEmpty) 'id': id,
    'payload': payload,
  };
}

/// Reply to a [WatchCommand]. `ok` false carries a machine-readable [code] so
/// the watch can distinguish "this approval is already gone" from "the phone
/// could not reach the model".
class WatchCommandResult {
  const WatchCommandResult({
    required this.ok,
    this.id,
    this.code = '',
    this.message = '',
  });

  const WatchCommandResult.success({String? id})
    : this(ok: true, id: id);

  const WatchCommandResult.failure({
    String? id,
    required String code,
    required String message,
  }) : this(ok: false, id: id, code: code, message: message);

  final bool ok;
  final String? id;
  final String code;
  final String message;

  Map<String, dynamic> toJson() => {
    'ok': ok,
    if (id != null && id!.isNotEmpty) 'id': id,
    if (!ok) 'code': code,
    if (!ok) 'message': message,
  };
}
