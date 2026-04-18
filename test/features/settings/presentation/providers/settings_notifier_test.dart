import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

void main() {
  test('new MCP servers start pending and editing a trusted server resets trust', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(settingsNotifierProvider.notifier);

    await notifier.addMcpServer();
    var settings = container.read(settingsNotifierProvider);
    final index = settings.configuredMcpServers.length - 1;

    expect(
      settings.configuredMcpServers[index].trustState,
      McpServerTrustState.pending,
    );

    await notifier.updateMcpServerUrl(index, 'http://localhost:8099');
    await notifier.updateMcpServerTrustState(
      index,
      McpServerTrustState.trusted,
    );

    settings = container.read(settingsNotifierProvider);
    expect(settings.configuredMcpServers[index].isTrusted, isTrue);
    expect(
      settings.enabledMcpServers.any(
        (server) => server.normalizedUrl == 'http://localhost:8099',
      ),
      isTrue,
    );

    await notifier.updateMcpServerUrl(index, 'http://localhost:8100');
    settings = container.read(settingsNotifierProvider);
    expect(
      settings.configuredMcpServers[index].trustState,
      McpServerTrustState.pending,
    );
    expect(
      settings.enabledMcpServers.any(
        (server) => server.normalizedUrl == 'http://localhost:8100',
      ),
      isFalse,
    );
  });

  test('bulk MCP server updates invalidate trust when identity changes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(settingsNotifierProvider.notifier);

    await notifier.updateMcpServers([
      const McpServerConfig(
        url: 'http://localhost:8081',
        enabled: true,
        trustState: McpServerTrustState.trusted,
      ),
    ]);

    var settings = container.read(settingsNotifierProvider);
    expect(settings.configuredMcpServers.single.isTrusted, isTrue);

    await notifier.updateMcpServers([
      settings.configuredMcpServers.single.copyWith(url: 'http://localhost:8082'),
    ]);

    settings = container.read(settingsNotifierProvider);
    expect(
      settings.configuredMcpServers.single.trustState,
      McpServerTrustState.pending,
    );
    expect(settings.enabledMcpServers, isEmpty);
  });
}
