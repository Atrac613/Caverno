import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/lan_endpoint_discovery.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../settings/data/model_remote_datasource.dart';
import '../../../settings/presentation/providers/mesh_endpoint_provider.dart';
import '../providers/onboarding_notifier.dart';
import 'onboarding_scaffold.dart';

/// Finds the LLM the user is going to talk to.
///
/// Order is deliberate and widens only on demand: loopback (instant, covers
/// LM Studio / Ollama / llama.cpp on this machine) -> LAN sweep (seconds of
/// traffic, so it takes a tap) -> manual entry with a connection test.
class OnboardingConnectStep extends ConsumerStatefulWidget {
  const OnboardingConnectStep({super.key});

  @override
  ConsumerState<OnboardingConnectStep> createState() =>
      _OnboardingConnectStepState();
}

class _OnboardingConnectStepState extends ConsumerState<OnboardingConnectStep> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  bool _testing = false;
  String? _testError;

  @override
  void initState() {
    super.initState();
    final state = ref.read(onboardingNotifierProvider);
    _baseUrlController.text = state.manualBaseUrl;
    _apiKeyController.text = state.manualApiKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(loopbackDetectionProvider.notifier).detect();
    });
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testError = null;
    });
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    try {
      final models = await ModelRemoteDataSource(
        baseUrl: baseUrl,
        apiKey: apiKey.isEmpty ? null : apiKey,
      ).listModelIds();
      if (!mounted) return;
      ref
          .read(onboardingNotifierProvider.notifier)
          .markManualVerified(models: models);
      setState(() => _testing = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testError = 'onboarding.test_failed'.tr(args: [error.toString()]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final state = ref.watch(onboardingNotifierProvider);
    final detection = ref.watch(loopbackDetectionProvider);
    final lanScan = ref.watch(meshDiscoveryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OnboardingHeading(
          title: 'onboarding.step_connect_title'.tr(),
          subtitle: 'onboarding.step_connect_body'.tr(),
        ),
        SizedBox(height: space.xxl),
        if (state.isManual)
          _ManualForm(
            baseUrlController: _baseUrlController,
            apiKeyController: _apiKeyController,
            testing: _testing,
            errorText: _testError,
            verified: state.manualVerified,
            onChanged: () {
              setState(() => _testError = null);
              ref
                  .read(onboardingNotifierProvider.notifier)
                  .updateManualConnection(
                    baseUrl: _baseUrlController.text,
                    apiKey: _apiKeyController.text,
                  );
            },
            onTest: _testing ? null : _testConnection,
            onBackToDetection: () => ref
                .read(onboardingNotifierProvider.notifier)
                .useDetectedEntry(),
          )
        else
          _DetectionPanel(
            detection: detection,
            lanScan: lanScan,
            selected: state.endpoint,
            onSelect: (endpoint) => ref
                .read(onboardingNotifierProvider.notifier)
                .selectEndpoint(endpoint),
            onRescan: () => ref
                .read(loopbackDetectionProvider.notifier)
                .detect(force: true),
            onScanLan: () => ref.read(meshDiscoveryProvider.notifier).scan(),
            onManual: () =>
                ref.read(onboardingNotifierProvider.notifier).useManualEntry(),
          ),
      ],
    );
  }
}

class _DetectionPanel extends StatelessWidget {
  const _DetectionPanel({
    required this.detection,
    required this.lanScan,
    required this.selected,
    required this.onSelect,
    required this.onRescan,
    required this.onScanLan,
    required this.onManual,
  });

  final AsyncValue<List<DiscoveredEndpoint>> detection;
  final AsyncValue<List<DiscoveredEndpoint>> lanScan;
  final DiscoveredEndpoint? selected;
  final ValueChanged<DiscoveredEndpoint> onSelect;
  final VoidCallback onRescan;
  final VoidCallback onScanLan;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final space = context.space;

    if (detection.isLoading) {
      return Column(
        children: [
          const CircularProgressIndicator(),
          SizedBox(height: space.lg),
          Text('onboarding.detecting'.tr(), style: theme.textTheme.bodyMedium),
        ],
      );
    }

    // LAN results are additive: a host found by the sweep is shown alongside
    // whatever loopback already answered, deduped by base URL.
    final endpoints = <String, DiscoveredEndpoint>{};
    for (final endpoint in [
      ...?detection.asData?.value,
      ...?lanScan.asData?.value,
    ]) {
      endpoints.putIfAbsent(endpoint.baseUrl, () => endpoint);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (endpoints.isEmpty)
          Text(
            'onboarding.detected_none'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final endpoint in endpoints.values) ...[
            _EndpointCard(
              endpoint: endpoint,
              selected: selected?.baseUrl == endpoint.baseUrl,
              onTap: () => onSelect(endpoint),
            ),
            SizedBox(height: space.lg),
          ],
        SizedBox(height: space.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: space.lg,
          runSpacing: space.md,
          children: [
            TextButton.icon(
              key: const ValueKey('onboarding-rescan'),
              onPressed: onRescan,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text('onboarding.rescan'.tr()),
            ),
            TextButton.icon(
              key: const ValueKey('onboarding-scan-lan'),
              onPressed: lanScan.isLoading ? null : onScanLan,
              icon: lanScan.isLoading
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lan_outlined, size: 16),
              label: Text('onboarding.scan_lan'.tr()),
            ),
            TextButton.icon(
              key: const ValueKey('onboarding-manual'),
              onPressed: onManual,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text('onboarding.manual_entry'.tr()),
            ),
          ],
        ),
      ],
    );
  }
}

class _EndpointCard extends StatelessWidget {
  const _EndpointCard({
    required this.endpoint,
    required this.selected,
    required this.onTap,
  });

  final DiscoveredEndpoint endpoint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return OnboardingChoiceCard(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.dns_outlined, color: colorScheme.primary),
          SizedBox(width: context.space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(endpoint.serverHint, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'onboarding.endpoint_summary'.tr(
                    namedArgs: {
                      'url': endpoint.baseUrl,
                      'models': '${endpoint.modelIds.length}',
                      'ms': endpoint.responseMs.toStringAsFixed(0),
                    },
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, size: 18, color: colorScheme.primary),
        ],
      ),
    );
  }
}

class _ManualForm extends StatelessWidget {
  const _ManualForm({
    required this.baseUrlController,
    required this.apiKeyController,
    required this.testing,
    required this.errorText,
    required this.verified,
    required this.onChanged,
    required this.onTest,
    required this.onBackToDetection,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final bool testing;
  final String? errorText;
  final bool verified;
  final VoidCallback onChanged;
  final VoidCallback? onTest;
  final VoidCallback onBackToDetection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final space = context.space;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('onboarding-manual-base-url'),
          controller: baseUrlController,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: 'onboarding.base_url'.tr(),
            hintText: 'http://localhost:1234/v1',
          ),
        ),
        SizedBox(height: space.lg),
        TextField(
          key: const ValueKey('onboarding-manual-api-key'),
          controller: apiKeyController,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(labelText: 'onboarding.api_key'.tr()),
        ),
        SizedBox(height: space.lg),
        Row(
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('onboarding-test-connection'),
              onPressed: onTest,
              icon: testing
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_outlined, size: 16),
              label: Text('onboarding.test_connection'.tr()),
            ),
            SizedBox(width: space.lg),
            if (verified)
              Expanded(
                child: Text(
                  'onboarding.test_ok'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
        if (errorText != null) ...[
          SizedBox(height: space.lg),
          Text(
            errorText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        SizedBox(height: space.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBackToDetection,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text('onboarding.back_to_detection'.tr()),
          ),
        ),
      ],
    );
  }
}
