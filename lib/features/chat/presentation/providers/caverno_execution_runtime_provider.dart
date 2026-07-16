import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../application/runtime/caverno_execution_runtime.dart';
import '../../application/runtime/caverno_execution_lease.dart';
import '../../application/runtime/caverno_runtime_event.dart';
import '../../application/runtime/caverno_runtime_ports.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import 'coding_projects_notifier.dart';
import 'chat_notifier.dart';
import 'conversations_notifier.dart';
import 'mcp_tool_provider.dart';

final cavernoRuntimeSurfaceProvider = Provider<CavernoRuntimeSurface>(
  (ref) => CavernoRuntimeSurface.flutterGui,
);

final cavernoRuntimeFrontendDiagnosticsProvider = Provider<Map<String, String>>(
  (ref) => const <String, String>{},
);

/// Production frontends override this with the directory containing the
/// authoritative SQLite database. Null keeps isolated provider tests lock-free.
final cavernoRuntimeDataRootProvider = Provider<Directory?>((ref) => null);

final cavernoRuntimeSettingsPortProvider = Provider<CavernoRuntimeSettingsPort>(
  (ref) {
    final frontendDiagnostics = ref.watch(
      cavernoRuntimeFrontendDiagnosticsProvider,
    );
    return _CallbackRuntimeSettingsPort(() {
      final settings = ref.read(settingsNotifierProvider);
      final project = settings.assistantMode == AssistantMode.general
          ? null
          : ref.read(codingProjectsNotifierProvider).selectedProject;
      final conversation = ref
          .read(conversationsNotifierProvider)
          .currentConversation;
      final worktree = conversation?.normalizedWorktreePath ?? '';
      return CavernoRuntimeSettingsSnapshot(
        mode: settings.assistantMode.name,
        model: settings.model,
        baseUrl: settings.baseUrl,
        workspace: worktree.isNotEmpty ? worktree : project?.rootPath,
        frontendDiagnostics: frontendDiagnostics,
      );
    });
  },
);

final cavernoRuntimeRepositoryPortProvider =
    Provider<CavernoRuntimeRepositoryPort>((ref) {
      final refreshAuthoritativeStore =
          ref.watch(cavernoRuntimeDataRootProvider) != null;
      return _CallbackRuntimeRepositoryPort(
        conversationId: () =>
            ref.read(conversationsNotifierProvider).currentConversation?.id,
        refreshConversation: (conversationId) {
          if (!refreshAuthoritativeStore) {
            return Future<bool>.value(true);
          }
          return ref
              .read(conversationsNotifierProvider.notifier)
              .refreshConversationForExecution(conversationId);
        },
        flushPendingPersistence: () =>
            ref.read(chatNotifierProvider.notifier).flushPendingPersistence(),
      );
    });

final cavernoRuntimeOwnershipPortProvider =
    Provider<CavernoRuntimeOwnershipPort>((ref) {
      final dataRoot = ref.watch(cavernoRuntimeDataRootProvider);
      if (dataRoot == null) {
        return const _NoopRuntimeOwnershipPort();
      }
      final surface = ref.watch(cavernoRuntimeSurfaceProvider);
      return _ExecutionLeaseRuntimeOwnershipPort(
        CavernoExecutionLeaseService(
          dataRoot: dataRoot,
          frontend: surface.name,
        ),
      );
    });

final cavernoRuntimeLlmPortProvider = Provider<CavernoRuntimeLlmPort>((ref) {
  return _CallbackRuntimeLlmPort(
    () => ref.read(settingsNotifierProvider).llmProvider.name,
  );
});

final cavernoRuntimeToolPortProvider = Provider<CavernoRuntimeToolPort>((ref) {
  return _CallbackRuntimeToolPort(() {
    final definitions = ref
        .read(mcpToolServiceProvider)
        ?.getOpenAiToolDefinitions();
    if (definitions == null) {
      return const <String>[];
    }
    final names =
        definitions
            .map((definition) {
              final function = definition['function'];
              if (function is! Map) {
                return null;
              }
              return function['name']?.toString().trim();
            })
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    return names;
  });
});

final cavernoRuntimeApprovalPortProvider = Provider<CavernoRuntimeApprovalPort>(
  (ref) => const _FrontendStateRuntimeApprovalPort(),
);

final cavernoRuntimeLogPortProvider = Provider<CavernoRuntimeLogPort>(
  (ref) => const _AppRuntimeLogPort(),
);

final cavernoRuntimeLifecyclePortProvider =
    Provider<CavernoRuntimeLifecyclePort>(
      (ref) => const _ExistingChatRuntimeLifecyclePort(),
    );

final cavernoRuntimeCompositionProvider = Provider<CavernoRuntimeComposition>((
  ref,
) {
  return CavernoRuntimeComposition(
    surface: ref.watch(cavernoRuntimeSurfaceProvider),
    settings: ref.watch(cavernoRuntimeSettingsPortProvider),
    repository: ref.watch(cavernoRuntimeRepositoryPortProvider),
    ownership: ref.watch(cavernoRuntimeOwnershipPortProvider),
    llm: ref.watch(cavernoRuntimeLlmPortProvider),
    tools: ref.watch(cavernoRuntimeToolPortProvider),
    approvals: ref.watch(cavernoRuntimeApprovalPortProvider),
    logs: ref.watch(cavernoRuntimeLogPortProvider),
    lifecycle: ref.watch(cavernoRuntimeLifecyclePortProvider),
  );
});

final cavernoExecutionRuntimeProvider = Provider<CavernoExecutionRuntime>((
  ref,
) {
  final runtime = CavernoExecutionRuntime(
    composition: ref.watch(cavernoRuntimeCompositionProvider),
  );
  ref.onDispose(() {
    unawaited(runtime.close());
  });
  return runtime;
});

final class _CallbackRuntimeSettingsPort implements CavernoRuntimeSettingsPort {
  const _CallbackRuntimeSettingsPort(this._read);

  final CavernoRuntimeSettingsSnapshot Function() _read;

  @override
  CavernoRuntimeSettingsSnapshot get current => _read();
}

final class _CallbackRuntimeRepositoryPort
    implements CavernoRuntimeRepositoryPort {
  const _CallbackRuntimeRepositoryPort({
    required this.conversationId,
    required Future<bool> Function(String conversationId) refreshConversation,
    required Future<void> Function() flushPendingPersistence,
  }) : _refreshConversation = refreshConversation,
       _flushPendingPersistence = flushPendingPersistence;

  final String? Function() conversationId;
  final Future<bool> Function(String conversationId) _refreshConversation;
  final Future<void> Function() _flushPendingPersistence;

  @override
  String? get currentConversationId => conversationId();

  @override
  Future<bool> refreshConversation(String conversationId) =>
      _refreshConversation(conversationId);

  @override
  Future<void> flushPendingPersistence() => _flushPendingPersistence();

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {}
}

final class _ExecutionLeaseRuntimeOwnershipPort
    implements CavernoRuntimeOwnershipPort {
  const _ExecutionLeaseRuntimeOwnershipPort(this._service);

  final CavernoExecutionLeaseService _service;

  @override
  Future<CavernoRuntimeOwnershipHandle> acquire(
    CavernoRuntimeOwnershipRequest request,
  ) async {
    final resources = <CavernoExecutionLeaseResource>[];
    final conversationId = request.conversationId?.trim() ?? '';
    if (conversationId.isNotEmpty) {
      resources.add(CavernoExecutionLeaseResource.conversation(conversationId));
    }
    final workspace = request.workspace?.trim() ?? '';
    if ((request.mode == AssistantMode.coding.name ||
            request.mode == AssistantMode.plan.name) &&
        workspace.isNotEmpty) {
      resources.add(CavernoExecutionLeaseResource.codingWorkspace(workspace));
    }
    if (resources.isEmpty) {
      return const _NoopRuntimeOwnershipHandle();
    }

    try {
      return _ExecutionLeaseRuntimeOwnershipHandle(_service.acquire(resources));
    } on CavernoExecutionLeaseConflict catch (conflict) {
      throw CavernoRuntimeOwnershipConflict(conflict.message);
    }
  }
}

final class _ExecutionLeaseRuntimeOwnershipHandle
    implements CavernoRuntimeOwnershipHandle {
  const _ExecutionLeaseRuntimeOwnershipHandle(this._handle);

  final CavernoExecutionLeaseHandle _handle;

  @override
  void release() => _handle.release();
}

final class _NoopRuntimeOwnershipPort implements CavernoRuntimeOwnershipPort {
  const _NoopRuntimeOwnershipPort();

  @override
  Future<CavernoRuntimeOwnershipHandle> acquire(
    CavernoRuntimeOwnershipRequest request,
  ) async => const _NoopRuntimeOwnershipHandle();
}

final class _NoopRuntimeOwnershipHandle
    implements CavernoRuntimeOwnershipHandle {
  const _NoopRuntimeOwnershipHandle();

  @override
  void release() {}
}

final class _CallbackRuntimeLlmPort implements CavernoRuntimeLlmPort {
  const _CallbackRuntimeLlmPort(this._providerName);

  final String Function() _providerName;

  @override
  String get providerName => _providerName();
}

final class _CallbackRuntimeToolPort implements CavernoRuntimeToolPort {
  const _CallbackRuntimeToolPort(this._toolNames);

  final List<String> Function() _toolNames;

  @override
  List<String> get availableToolNames => _toolNames();
}

final class _FrontendStateRuntimeApprovalPort
    implements CavernoRuntimeApprovalPort {
  const _FrontendStateRuntimeApprovalPort();

  @override
  void onApprovalRequired(CavernoRuntimeApprovalRequest request) {
    // The current Flutter adapter resolves decisions through ChatState. CLI2
    // will replace this port with a TTY or fail-closed non-interactive adapter.
  }
}

final class _AppRuntimeLogPort implements CavernoRuntimeLogPort {
  const _AppRuntimeLogPort();

  @override
  void onEvent(CavernoRuntimeEvent event) {
    if (event is CavernoRuntimeRunStarted ||
        event is CavernoRuntimeTerminalEvent) {
      appLog(
        '[ExecutionRuntime] type=${event.type}; '
        'turnId=${event.turnId}; sequence=${event.sequence}',
      );
    }
  }
}

final class _ExistingChatRuntimeLifecyclePort
    implements CavernoRuntimeLifecyclePort {
  const _ExistingChatRuntimeLifecyclePort();

  @override
  void onTurnStarted(CavernoRuntimeRunStarted event) {}

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {}
}
