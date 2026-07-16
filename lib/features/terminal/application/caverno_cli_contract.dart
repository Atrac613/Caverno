enum CavernoCliCommand { chat, coding, plan }

enum CavernoCliConversationCommand { list, show, resume }

enum CavernoCliUtilityCommand { doctor }

enum CavernoCliOutputMode { human, json }

enum CavernoCliInvocationAction {
  run,
  conversationList,
  conversationShow,
  conversationResume,
  doctor,
  help,
  version,
}

abstract final class CavernoCliExitCode {
  static const success = 0;
  static const blocked = 2;
  static const usage = 64;
  static const input = 65;
  static const unavailable = 69;
  static const persistence = 74;
  static const temporary = 75;
  static const approval = 77;
  static const cancelled = 130;
}

final class CavernoCliFailure implements Exception {
  const CavernoCliFailure({
    required this.code,
    required this.message,
    required this.exitCode,
  });

  final String code;
  final String message;
  final int exitCode;

  @override
  String toString() => message;
}
