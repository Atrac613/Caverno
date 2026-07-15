import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../application/runtime/caverno_execution_runtime.dart';
import '../../application/runtime/caverno_runtime_event.dart';
import '../../application/runtime/caverno_runtime_ports.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import 'coding_projects_notifier.dart';
import 'conversations_notifier.dart';
import 'mcp_tool_provider.dart';

final cavernoRuntimeSurfaceProvider = Provider<CavernoRuntimeSurface>(
  (ref) => CavernoRuntimeSurface.flutterGui,
);

final cavernoRuntimeFrontendDiagnosticsProvider = Provider<Map<String, String>>(
  (ref) => const <String, String>{},
);

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
      return CavernoRuntimeSettingsSnapshot(
        mode: settings.assistantMode.name,
        model: settings.model,
        baseUrl: settings.baseUrl,
        workspace: project?.rootPath,
        frontendDiagnostics: frontendDiagnostics,
      );
    });
  },
);

final cavernoRuntimeRepositoryPortProvider =
    Provider<CavernoRuntimeRepositoryPort>(
      (ref) => _CallbackRuntimeRepositoryPort(
        conversationId: () =>
            ref.read(conversationsNotifierProvider).currentConversation?.id,
      ),
    );

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
  const _CallbackRuntimeRepositoryPort({required this.conversationId});

  final String? Function() conversationId;

  @override
  String? get currentConversationId => conversationId();

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {}
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
