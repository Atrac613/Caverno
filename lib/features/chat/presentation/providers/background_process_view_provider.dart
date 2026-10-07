import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/background_process_monitor_snapshot.dart';
import '../../data/datasources/background_process_tools.dart';
import 'mcp_tool_provider.dart';

/// How often the sidebar re-reads the job registry while it is on screen.
const Duration backgroundProcessViewPollInterval = Duration(seconds: 1);

/// Background jobs of one conversation, refreshed while something watches.
///
/// Polled rather than pushed: the registry has no change stream, and output
/// arrives continuously, so a push per chunk would rebuild far more often
/// than a once-a-second read. Auto-dispose stops the timer when the sidebar
/// tab is closed.
final conversationBackgroundProcessesProvider = StreamProvider.autoDispose
    .family<List<BackgroundProcessMonitorSnapshot>, String>((
      ref,
      conversationId,
    ) {
      final tools = ref.watch(backgroundProcessToolsProvider);
      final controller =
          StreamController<List<BackgroundProcessMonitorSnapshot>>();
      void emit() {
        if (!controller.isClosed) {
          controller.add(tools.conversationJobs(conversationId));
        }
      }

      emit();
      final timer = Timer.periodic(
        backgroundProcessViewPollInterval,
        (_) => emit(),
      );
      ref.onDispose(() {
        timer.cancel();
        unawaited(controller.close());
      });
      return controller.stream;
    });
