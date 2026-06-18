import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lan_endpoint_discovery.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/mesh_endpoint_provider.dart';
import '../providers/settings_notifier.dart';

/// LL8 LAN inference mesh: discover OpenAI-compatible endpoints on the local
/// network and register the ones to route across. Discovery only proposes
/// candidates; registration here is the explicit, user-confirmed step.
class MeshSettingsPage extends ConsumerWidget {
  const MeshSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final discovery = ref.watch(meshDiscoveryProvider);
    final isScanning = discovery.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text('settings.mesh_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'settings.mesh_intro'.tr(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('mesh-scan-button'),
            onPressed: isScanning
                ? null
                : () => ref.read(meshDiscoveryProvider.notifier).scan(),
            icon: isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find_outlined),
            label: Text(
              isScanning
                  ? 'settings.mesh_scanning'.tr()
                  : 'settings.mesh_scan'.tr(),
            ),
          ),
          const SizedBox(height: 24),
          _DiscoveredSection(discovery: discovery, settings: settings),
          const Divider(height: 32),
          _RegisteredSection(settings: settings),
        ],
      ),
    );
  }
}

class _DiscoveredSection extends ConsumerWidget {
  const _DiscoveredSection({required this.discovery, required this.settings});

  final AsyncValue<List<DiscoveredEndpoint>> discovery;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return discovery.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => Text(
        'settings.mesh_scan_error'.tr(),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      data: (endpoints) {
        if (endpoints.isEmpty) {
          return Text(
            'settings.mesh_no_results'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'settings.mesh_discovered_section'.tr(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final endpoint in endpoints)
              _DiscoveredTile(
                endpoint: endpoint,
                isRegistered:
                    settings.namedEndpointForBaseUrl(endpoint.baseUrl) != null,
                onRegister: () => ref
                    .read(settingsNotifierProvider.notifier)
                    .upsertNamedEndpoint(
                      NamedEndpoint(
                        id: '',
                        label: '${endpoint.serverHint} (${endpoint.host})',
                        baseUrl: endpoint.baseUrl,
                      ),
                    ),
              ),
          ],
        );
      },
    );
  }
}

class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({
    required this.endpoint,
    required this.isRegistered,
    required this.onRegister,
  });

  final DiscoveredEndpoint endpoint;
  final bool isRegistered;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.dns_outlined),
      title: Text('${endpoint.serverHint} · ${endpoint.host}:${endpoint.port}'),
      subtitle: Text(
        'settings.mesh_models_count'.tr(args: ['${endpoint.modelIds.length}']),
      ),
      trailing: isRegistered
          ? Text(
              'settings.mesh_registered_already'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : TextButton(
              onPressed: onRegister,
              child: Text('settings.mesh_register'.tr()),
            ),
    );
  }
}

class _RegisteredSection extends ConsumerWidget {
  const _RegisteredSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final endpoints = settings.namedEndpoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'settings.mesh_registered_section'.tr(),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (endpoints.isEmpty)
          Text(
            'settings.mesh_no_registered'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final endpoint in endpoints)
            ListTile(
              key: ValueKey('mesh-registered-${endpoint.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(endpoint.displayLabel),
              subtitle: Text(endpoint.normalizedBaseUrl),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: endpoint.enabled,
                    onChanged: (value) => notifier.upsertNamedEndpoint(
                      endpoint.copyWith(enabled: value),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'settings.mesh_remove'.tr(),
                    onPressed: () => notifier.removeNamedEndpoint(endpoint.id),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
