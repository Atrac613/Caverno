import '../../chat/application/runtime/caverno_runtime_event.dart';
import 'caverno_cli_arguments.dart';
import 'caverno_terminal_interaction_controller.dart';

abstract interface class CavernoCliRuntimePort
    implements CavernoTerminalDecisionPort {
  Stream<CavernoRuntimeEvent> get events;

  Future<void> prepare(CavernoCliInvocation invocation);

  Future<void> start({
    required CavernoCliInvocation invocation,
    required String prompt,
  });

  Future<void> cancel();

  Future<void> close();
}
