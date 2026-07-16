import 'dart:async';

import '../../chat/application/runtime/caverno_runtime_event.dart';
import '../presentation/caverno_cli_redactor.dart';
import '../presentation/caverno_terminal_presenter.dart';
import 'caverno_cli_arguments.dart';
import 'caverno_cli_contract.dart';
import 'caverno_cli_input.dart';
import 'caverno_cli_runtime_port.dart';
import 'caverno_terminal_interaction_controller.dart';

final class CavernoCliApplication {
  CavernoCliApplication({
    required this.input,
    required this.output,
    required this.runtime,
    this.cancellationSignals = const Stream<void>.empty(),
    CavernoCliPromptResolver promptResolver = const CavernoCliPromptResolver(),
    CavernoCliRedactor? redactor,
    DateTime Function()? now,
  }) : _promptResolver = promptResolver,
       _redactor = redactor ?? CavernoCliRedactor(),
       _now = now ?? DateTime.now;

  final CavernoCliInputPort input;
  final CavernoTerminalOutputPort output;
  final CavernoCliRuntimePort runtime;
  final Stream<void> cancellationSignals;
  final CavernoCliPromptResolver _promptResolver;
  final CavernoCliRedactor _redactor;
  final DateTime Function() _now;

  Future<int> run(CavernoCliInvocation invocation) async {
    final presenter = CavernoTerminalPresenter(
      outputMode: invocation.outputMode,
      output: output,
      redactor: _redactor,
    );
    final diagnostics = _OutputDiagnostics(output);
    final terminal = Completer<CavernoRuntimeTerminalEvent>();
    var lastSequence = 0;
    var interactionTail = Future<void>.value();
    late final CavernoTerminalInteractionController interactions;
    StreamSubscription<CavernoRuntimeEvent>? eventSubscription;
    StreamSubscription<void>? cancellationSubscription;

    void acceptEvent(CavernoRuntimeEvent event) {
      if (event.sequence <= lastSequence) {
        return;
      }
      lastSequence = event.sequence;
      presenter.present(event);
      interactionTail = interactionTail.then((_) => interactions.handle(event));
      interactionTail = interactionTail.catchError((Object error) async {
        if (!terminal.isCompleted) {
          await runtime.terminate(
            code: 'terminal_interaction_failed',
            message: error.toString(),
            exitCode: CavernoCliExitCode.blocked,
          );
        }
      });
      if (event is CavernoRuntimeTerminalEvent && !terminal.isCompleted) {
        terminal.complete(event);
      }
    }

    void completeLocally(CavernoCliFailure failure) {
      if (terminal.isCompleted) {
        return;
      }
      final event = CavernoRuntimeRunFailed(
        sequence: ++lastSequence,
        timestamp: _now().toUtc(),
        turnId: 'cli',
        code: failure.code,
        message: failure.message,
        exitCode: failure.exitCode,
      );
      presenter.present(event);
      terminal.complete(event);
    }

    interactions = CavernoTerminalInteractionController(
      input: input,
      output: output,
      decisions: runtime,
      interactive: input.isTerminal && !invocation.isJson,
    );

    try {
      final prompt = await _promptResolver.resolve(
        invocation: invocation,
        input: input,
        diagnostics: diagnostics,
      );
      await runtime.prepare(invocation);
      eventSubscription = runtime.events.listen(
        acceptEvent,
        onError: (Object error) {
          completeLocally(
            CavernoCliFailure(
              code: 'runtime_event_stream_failed',
              message: error.toString(),
              exitCode: CavernoCliExitCode.blocked,
            ),
          );
        },
      );
      cancellationSubscription = cancellationSignals.listen((_) {
        if (terminal.isCompleted) {
          return;
        }
        unawaited(
          runtime.cancel().then((_) {
            if (!terminal.isCompleted) {
              completeLocally(
                const CavernoCliFailure(
                  code: 'cancelled',
                  message: 'Execution was cancelled by the user.',
                  exitCode: CavernoCliExitCode.cancelled,
                ),
              );
            }
          }),
        );
      });
      unawaited(
        runtime.start(invocation: invocation, prompt: prompt).catchError((
          Object error,
        ) {
          final failure = error is CavernoCliFailure
              ? error
              : CavernoCliFailure(
                  code: 'service_unavailable',
                  message: error.toString(),
                  exitCode: CavernoCliExitCode.unavailable,
                );
          completeLocally(failure);
        }),
      );

      final result = await terminal.future;
      await interactionTail;
      return switch (result) {
        CavernoRuntimeRunCompleted() => CavernoCliExitCode.success,
        CavernoRuntimeRunFailed(:final exitCode) => exitCode,
      };
    } on CavernoCliFailure catch (failure) {
      completeLocally(failure);
      return failure.exitCode;
    } on Object catch (error) {
      final failure = CavernoCliFailure(
        code: 'cli_failed',
        message: error.toString(),
        exitCode: CavernoCliExitCode.blocked,
      );
      completeLocally(failure);
      return failure.exitCode;
    } finally {
      await cancellationSubscription?.cancel();
      await eventSubscription?.cancel();
      await runtime.close();
    }
  }
}

final class _OutputDiagnostics implements CavernoCliDiagnosticPort {
  const _OutputDiagnostics(this.output);

  final CavernoTerminalOutputPort output;

  @override
  void writeDiagnostic(String value) {
    output.writeStderr(value);
  }
}
