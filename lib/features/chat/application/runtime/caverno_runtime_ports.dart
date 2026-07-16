import 'caverno_runtime_event.dart';

final class CavernoRuntimeSettingsSnapshot {
  const CavernoRuntimeSettingsSnapshot({
    required this.mode,
    required this.model,
    required this.baseUrl,
    this.workspace,
    this.frontendDiagnostics = const <String, String>{},
  });

  final String mode;
  final String model;
  final String baseUrl;
  final String? workspace;
  final Map<String, String> frontendDiagnostics;
}

abstract interface class CavernoRuntimeSettingsPort {
  CavernoRuntimeSettingsSnapshot get current;
}

abstract interface class CavernoRuntimeRepositoryPort {
  String? get currentConversationId;

  Future<bool> refreshConversation(String conversationId);

  Future<void> flushPendingPersistence();

  void onTurnTerminal(CavernoRuntimeTerminalEvent event);
}

final class CavernoRuntimeOwnershipRequest {
  const CavernoRuntimeOwnershipRequest({
    required this.surface,
    required this.mode,
    required this.conversationId,
    required this.workspace,
  });

  final CavernoRuntimeSurface surface;
  final String mode;
  final String? conversationId;
  final String? workspace;
}

abstract interface class CavernoRuntimeOwnershipHandle {
  void release();
}

abstract interface class CavernoRuntimeOwnershipPort {
  Future<CavernoRuntimeOwnershipHandle> acquire(
    CavernoRuntimeOwnershipRequest request,
  );
}

final class CavernoRuntimeOwnershipConflict implements Exception {
  const CavernoRuntimeOwnershipConflict(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class CavernoRuntimeLlmPort {
  String get providerName;
}

abstract interface class CavernoRuntimeToolPort {
  List<String> get availableToolNames;
}

abstract interface class CavernoRuntimeApprovalPort {
  void onApprovalRequired(CavernoRuntimeApprovalRequest request);
}

abstract interface class CavernoRuntimeLogPort {
  void onEvent(CavernoRuntimeEvent event);
}

abstract interface class CavernoRuntimeLifecyclePort {
  void onTurnStarted(CavernoRuntimeRunStarted event);

  void onTurnTerminal(CavernoRuntimeTerminalEvent event);
}

final class CavernoRuntimeComposition {
  const CavernoRuntimeComposition({
    required this.surface,
    required this.settings,
    required this.repository,
    required this.ownership,
    required this.llm,
    required this.tools,
    required this.approvals,
    required this.logs,
    required this.lifecycle,
  });

  final CavernoRuntimeSurface surface;
  final CavernoRuntimeSettingsPort settings;
  final CavernoRuntimeRepositoryPort repository;
  final CavernoRuntimeOwnershipPort ownership;
  final CavernoRuntimeLlmPort llm;
  final CavernoRuntimeToolPort tools;
  final CavernoRuntimeApprovalPort approvals;
  final CavernoRuntimeLogPort logs;
  final CavernoRuntimeLifecyclePort lifecycle;
}
