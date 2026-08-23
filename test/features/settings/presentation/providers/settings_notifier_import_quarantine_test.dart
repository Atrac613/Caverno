import 'package:caverno/features/settings/data/settings_file_service.dart';
import 'package:caverno/features/settings/data/settings_qr_service.dart';
import 'package:caverno/features/settings/data/settings_repository.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final importCase in <String, Future<void> Function(SettingsNotifier)>{
    'JSON and onboarding': (notifier) async {
      expect(await notifier.importSettings(), isTrue);
    },
    'encrypted JSON': (notifier) async {
      expect(
        await notifier.importSettings(
          requestEncryptedPassphrase: () async => 'test-passphrase',
        ),
        isTrue,
      );
    },
    'QR': (notifier) => notifier.importFromQr('payload'),
  }.entries) {
    test(
      '${importCase.key} import persists only quarantined settings',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final imported = _executableSettings();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsFileServiceProvider.overrideWithValue(
              _FakeSettingsFileService(imported),
            ),
            settingsQrServiceProvider.overrideWithValue(
              _FakeSettingsQrService(imported),
            ),
          ],
        );
        addTearDown(container.dispose);

        await importCase.value(
          container.read(settingsNotifierProvider.notifier),
        );

        final effective = container.read(settingsNotifierProvider);
        final persisted = SettingsRepository(prefs).loadReadOnly();
        final restartedContainer = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(restartedContainer.dispose);
        final restarted = restartedContainer.read(settingsNotifierProvider);
        for (final settings in [effective, persisted, restarted]) {
          expect(settings.model, 'imported-model');
          expect(settings.mcpEnabled, isFalse);
          expect(settings.mcpServers.single.needsTrustReview, isTrue);
          expect(settings.enabledMcpServers, isEmpty);
          expect(settings.externalToolHooksEnabled, isFalse);
          expect(settings.externalToolHooks.single.enabled, isFalse);
          expect(settings.externalToolHooks.single.reviewedAt, isNull);
          expect(
            settings.codingApprovalMode,
            ToolApprovalMode.defaultPermissions,
          );
          expect(
            settings.chatApprovalMode,
            ToolApprovalMode.defaultPermissions,
          );
          expect(settings.localCommandPermissionRules, isEmpty);
          expect(settings.routineComputerUseActionAllowlist, isEmpty);
        }
      },
    );
  }

  test('hook review is exact and persists across provider rebuild', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    final notifier = container.read(settingsNotifierProvider.notifier);
    await notifier.updateSettings(
      AppSettings.defaults().copyWith(
        externalToolHooksEnabled: true,
        externalToolHooks: const [
          ExternalToolHook(
            id: 'review',
            enabled: false,
            event: 'Stop',
            command: 'reviewed-hook',
            sourceId: 'external:test',
          ),
        ],
      ),
    );
    final hook = container
        .read(settingsNotifierProvider)
        .externalToolHooks
        .single;

    final reviewed = await notifier.updateExternalToolHookReview(
      0,
      enabled: true,
      expectedApprovalIdentity: hook.approvalIdentity,
    );

    expect(reviewed, isTrue);
    expect(
      container
          .read(settingsNotifierProvider)
          .enabledExternalToolHooksFor('Stop'),
      hasLength(1),
    );
    container.dispose();

    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(
      container
          .read(settingsNotifierProvider)
          .enabledExternalToolHooksFor('Stop'),
      hasLength(1),
    );
  });

  test(
    'hook review rejects an identity changed while the sheet was open',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsNotifierProvider.notifier);
      await notifier.updateSettings(
        AppSettings.defaults().copyWith(
          externalToolHooks: const [
            ExternalToolHook(
              id: 'review',
              enabled: false,
              event: 'Stop',
              command: 'first-hook',
              sourceId: 'external:test',
            ),
          ],
        ),
      );
      final reviewedIdentity = container
          .read(settingsNotifierProvider)
          .externalToolHooks
          .single
          .approvalIdentity;
      await notifier.updateSettings(
        container
            .read(settingsNotifierProvider)
            .copyWith(
              externalToolHooks: const [
                ExternalToolHook(
                  id: 'review',
                  enabled: false,
                  event: 'Stop',
                  command: 'changed-hook',
                  sourceId: 'external:test',
                ),
              ],
            ),
      );

      final reviewed = await notifier.updateExternalToolHookReview(
        0,
        enabled: true,
        expectedApprovalIdentity: reviewedIdentity,
      );

      expect(reviewed, isFalse);
      expect(
        container
            .read(settingsNotifierProvider)
            .externalToolHooks
            .single
            .enabled,
        isFalse,
      );
    },
  );
}

AppSettings _executableSettings() {
  return AppSettings.defaults().copyWith(
    model: 'imported-model',
    mcpEnabled: true,
    mcpServers: [
      McpServerConfig(
        type: McpServerType.stdio,
        command: 'dangerous-server',
        trustState: McpServerTrustState.trusted,
        trustedAt: DateTime(2026, 8, 14),
      ),
    ],
    externalToolHooksEnabled: true,
    externalToolHooks: const [
      ExternalToolHook(
        id: 'submit',
        event: 'UserPromptSubmit',
        command: 'dangerous-hook',
      ),
    ],
    codingApprovalMode: ToolApprovalMode.fullAccess,
    chatApprovalMode: ToolApprovalMode.fullAccess,
    localCommandPermissionRules: const [
      LocalCommandPermissionRule(id: 'rule', pattern: 'dangerous-server'),
    ],
    routineComputerUseActionAllowlist: const [
      RoutineComputerUseActionAllowlistEntry(
        id: 'action',
        toolName: 'computer_click',
        targetLabelContains: 'Allow',
      ),
    ],
  );
}

class _FakeSettingsFileService extends SettingsFileService {
  _FakeSettingsFileService(this.settings);

  final AppSettings settings;

  @override
  Future<AppSettings?> importSettings() async => settings;

  @override
  Future<AppSettings?> importSettingsWithEncryptedPassphrase(
    EncryptedSettingsPassphraseProvider requestPassphrase,
  ) async {
    final passphrase = await requestPassphrase();
    return passphrase == null ? null : settings;
  }
}

class _FakeSettingsQrService extends SettingsQrService {
  _FakeSettingsQrService(this.settings);

  final AppSettings settings;

  @override
  AppSettings parseQrString(String qrString) => settings;
}
