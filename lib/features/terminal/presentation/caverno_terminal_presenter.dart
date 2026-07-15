import 'dart:convert';

import '../../chat/application/runtime/caverno_runtime_event.dart';
import '../application/caverno_cli_contract.dart';
import 'caverno_cli_redactor.dart';

abstract interface class CavernoTerminalOutputPort {
  void writeStdout(String value);

  void writeStderr(String value);
}

final class CavernoTerminalPresenter {
  CavernoTerminalPresenter({
    required this.outputMode,
    required this.output,
    CavernoCliRedactor? redactor,
  }) : redactor = redactor ?? CavernoCliRedactor();

  final CavernoCliOutputMode outputMode;
  final CavernoTerminalOutputPort output;
  final CavernoCliRedactor redactor;
  bool _assistantDeltaSeen = false;
  bool _assistantLineOpen = false;

  void present(CavernoRuntimeEvent event) {
    if (outputMode == CavernoCliOutputMode.json) {
      final safe = redactor.redactJson(event.toJson());
      output.writeStdout('${jsonEncode(safe)}\n');
      return;
    }

    switch (event) {
      case CavernoRuntimeRunStarted():
        final workspace = event.workspace == null
            ? ''
            : '; workspace=${redactor.redact(event.workspace!)}';
        output.writeStderr(
          'Caverno ${event.mode}; model=${redactor.redact(event.model)}; '
          'endpoint=${redactor.redact(event.baseUrl)}$workspace\n',
        );
        if (event.frontendDiagnostics.isNotEmpty) {
          final diagnostics = event.frontendDiagnostics.entries
              .map((entry) => '${entry.key}=${redactor.redact(entry.value)}')
              .join('; ');
          output.writeStderr('Runtime: $diagnostics\n');
        }
      case CavernoRuntimeAssistantDelta():
        _assistantDeltaSeen = true;
        _assistantLineOpen = !event.delta.endsWith('\n');
        output.writeStdout(redactor.redact(event.delta));
      case CavernoRuntimeToolLifecycle():
        if (event.state == CavernoRuntimeToolLifecycleState.queued) {
          return;
        }
        final status = event.resultStatus == null
            ? event.state.name
            : '${event.state.name}:${event.resultStatus}';
        output.writeStderr(
          '[tool] ${redactor.redact(event.toolName)} $status\n',
        );
      case CavernoRuntimeApprovalRequired():
        output.writeStderr(
          '[approval] ${redactor.redact(event.request.capability)} '
          '(${event.request.risk.name}): '
          '${redactor.redact(event.request.summary)}\n',
        );
      case CavernoRuntimeQuestionRequired():
        output.writeStderr(
          '[question] ${redactor.redact(event.request.prompt)}\n',
        );
      case CavernoRuntimeWorkflowTransition():
        final task = event.taskId == null
            ? ''
            : ' task=${redactor.redact(event.taskId!)}';
        final status = event.taskStatus == null
            ? ''
            : ' status=${redactor.redact(event.taskStatus!)}';
        output.writeStderr(
          '[workflow] ${redactor.redact(event.stage)}$task$status\n',
        );
      case CavernoRuntimeUsage():
        output.writeStderr(
          '[usage] prompt=${event.promptTokens} '
          'completion=${event.completionTokens} total=${event.totalTokens}\n',
        );
      case CavernoRuntimeRunCompleted():
        if (!_assistantDeltaSeen && event.content.isNotEmpty) {
          output.writeStdout(redactor.redact(event.content));
          _assistantLineOpen = !event.content.endsWith('\n');
        }
        if (_assistantLineOpen) {
          output.writeStdout('\n');
          _assistantLineOpen = false;
        }
      case CavernoRuntimeRunFailed():
        if (_assistantLineOpen) {
          output.writeStdout('\n');
          _assistantLineOpen = false;
        }
        output.writeStderr(
          'Caverno failed (${redactor.redact(event.code)}): '
          '${redactor.redact(event.message)}\n',
        );
    }
  }
}
