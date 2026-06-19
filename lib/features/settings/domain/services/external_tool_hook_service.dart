import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/login_shell_environment.dart';
import '../../../../core/utils/logger.dart';
import '../entities/app_settings.dart';

final externalToolHookServiceProvider = Provider<ExternalToolHookService>((
  ref,
) {
  return const ExternalToolHookService();
});

class ExternalToolHookService {
  const ExternalToolHookService();

  static const _timeout = Duration(seconds: 15);

  Future<void> dispatch({
    required AppSettings settings,
    required String event,
    required Map<String, dynamic> payload,
  }) async {
    final hooks = settings.enabledExternalToolHooksFor(event);
    if (hooks.isEmpty) {
      return;
    }

    await Future.wait([
      for (final hook in hooks) _runHook(hook, event: event, payload: payload),
    ]);
  }

  Future<void> _runHook(
    ExternalToolHook hook, {
    required String event,
    required Map<String, dynamic> payload,
  }) async {
    Process? process;
    try {
      final env = await LoginShellEnvironment.instance.environment(
        extra: hook.normalizedEnv,
      );
      process = await Process.start(
        hook.normalizedCommand,
        hook.args,
        environment: env,
      );

      final stdoutTail = StringBuffer();
      final stderrTail = StringBuffer();
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .listen((chunk) => _appendTail(stdoutTail, chunk));
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen((chunk) => _appendTail(stderrTail, chunk));

      process.stdin.writeln(jsonEncode(payload));
      await process.stdin.close();

      final exitCode = await process.exitCode.timeout(_timeout);
      await stdoutSub.cancel();
      await stderrSub.cancel();

      if (exitCode != 0) {
        appLog(
          '[ExternalToolHook] Hook $event exited with $exitCode: '
          '${stderrTail.toString().trim()}',
        );
      }
    } on TimeoutException {
      appLog('[ExternalToolHook] Hook $event timed out: ${hook.command}');
      process?.kill();
    } catch (error, stackTrace) {
      appLog('[ExternalToolHook] Hook $event failed: $error');
      appLog('[ExternalToolHook] $stackTrace');
      process?.kill();
    }
  }

  void _appendTail(StringBuffer buffer, String chunk) {
    buffer.write(chunk);
    const maxLength = 4000;
    final text = buffer.toString();
    if (text.length <= maxLength) {
      return;
    }
    buffer
      ..clear()
      ..write(text.substring(text.length - maxLength));
  }
}
