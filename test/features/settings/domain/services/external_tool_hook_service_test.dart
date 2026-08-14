import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/executable_settings_quarantine_service.dart';
import 'package:caverno/features/settings/domain/services/external_tool_hook_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quarantined imported hooks never start a process', () async {
    var processStarts = 0;
    final service = ExternalToolHookService(
      processStarter: (command, args, environment) {
        processStarts += 1;
        throw StateError('A quarantined hook must not start');
      },
    );
    final settings = const ExecutableSettingsQuarantineService()
        .quarantineImportedSettings(
          AppSettings.defaults().copyWith(
            externalToolHooksEnabled: true,
            externalToolHooks: const [
              ExternalToolHook(
                id: 'unreviewed',
                enabled: true,
                event: 'Stop',
                command: 'unreviewed-hook',
              ),
            ],
          ),
        )
        .copyWith(externalToolHooksEnabled: true);

    await service.dispatch(
      settings: settings,
      event: 'Stop',
      payload: const {'event': 'Stop'},
    );

    expect(processStarts, 0);
  });

  test('expired imported hook reviews never start a process', () async {
    var processStarts = 0;
    final service = ExternalToolHookService(
      processStarter: (command, args, environment) {
        processStarts += 1;
        throw StateError('An expired hook must not start');
      },
    );
    final settings = AppSettings.defaults().copyWith(
      externalToolHooksEnabled: true,
      externalToolHooks: [
        ExternalToolHook(
          id: 'expired',
          enabled: true,
          event: 'Stop',
          command: 'expired-hook',
          sourceId: 'external:test',
          reviewedAt: DateTime.now().subtract(const Duration(days: 31)),
        ),
      ],
    );

    await service.dispatch(
      settings: settings,
      event: 'Stop',
      payload: const {'event': 'Stop'},
    );

    expect(processStarts, 0);
  });
}
