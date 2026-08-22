import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/security/llm_endpoint_transport_policy.dart';
import '../../../../core/services/apple_foundation_models_platform_client.dart';
import '../../../../core/services/google_chat_delivery_service.dart';
import '../../../../core/services/lan_endpoint_discovery.dart';
import '../../../../core/services/macos_update_service.dart';
import '../../../../core/utils/debouncer.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/apple_foundation_models_availability_provider.dart';
import '../providers/mesh_endpoint_provider.dart';
import '../providers/model_capability_auto_probe_notifier.dart';
import '../providers/model_list_provider.dart';
import '../providers/settings_notifier.dart';
import '../widgets/macos_update_tile.dart';
import 'model_routing_settings_page.dart';

class GeneralSettingsPage extends ConsumerStatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  ConsumerState<GeneralSettingsPage> createState() =>
      _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends ConsumerState<GeneralSettingsPage> {
  final _maxTokensController = TextEditingController();
  final _googleChatWebhookController = TextEditingController();
  final _embeddingsModelController = TextEditingController();

  final _maxTokensDebouncer = Debouncer();
  final _googleChatWebhookDebouncer = Debouncer();
  final _embeddingsModelDebouncer = Debouncer();
  bool _isSendingGoogleChatTest = false;
  bool _hasScannedLan = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    _maxTokensController.text = settings.maxTokens.toString();
    _googleChatWebhookController.text = settings.googleChatWebhookUrl;
    _embeddingsModelController.text = settings.embeddingsModel;
  }

  @override
  void dispose() {
    _maxTokensDebouncer.dispose();
    _googleChatWebhookDebouncer.dispose();
    _embeddingsModelDebouncer.dispose();
    _maxTokensController.dispose();
    _googleChatWebhookController.dispose();
    _embeddingsModelController.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  String _modelsEndpoint(String baseUrl) {
    final trimmed = baseUrl.trim().isEmpty
        ? ApiConstants.defaultBaseUrl
        : baseUrl.trim();
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    if (normalized.endsWith('/models')) {
      return normalized;
    }
    return '$normalized/models';
  }

  String _apiKeyStatus(String apiKey) {
    final normalized = apiKey.trim();
    if (normalized.isEmpty || normalized == ApiConstants.defaultApiKey) {
      return 'settings.compatibility_api_key_placeholder'.tr();
    }
    return 'settings.compatibility_api_key_configured'.tr();
  }

  String _providerLabel(LlmProvider provider) => switch (provider) {
    LlmProvider.openAiCompatible => 'settings.llm_provider_openai'.tr(),
    LlmProvider.appleFoundationModels =>
      'settings.llm_provider_apple_foundation_models'.tr(),
  };

  String _providerDisabledReason(
    AppleFoundationModelsAvailability? availability,
  ) {
    return switch (availability?.reason) {
      'appleIntelligenceNotEnabled' =>
        'settings.llm_provider_apple_intelligence_disabled'.tr(),
      'modelNotReady' => 'settings.llm_provider_apple_model_not_ready'.tr(),
      _ => 'settings.llm_provider_unavailable'.tr(),
    };
  }

  String _providerAvailabilityStatus(
    AppleFoundationModelsAvailability availability,
  ) {
    if (availability.isAvailable) {
      return 'settings.llm_provider_available'.tr();
    }
    return _providerDisabledReason(availability);
  }

  String _providerAvailabilityMessage(
    AppleFoundationModelsAvailability availability,
  ) {
    final reason = availability.reason?.trim();
    if (reason == null || reason.isEmpty) {
      return 'settings.llm_provider_apple_status_without_reason'.tr(
        namedArgs: {'status': _providerAvailabilityStatus(availability)},
      );
    }
    return 'settings.llm_provider_apple_status_with_reason'.tr(
      namedArgs: {
        'status': _providerAvailabilityStatus(availability),
        'reason': reason,
      },
    );
  }

  Widget _buildProviderAvailabilityMessage(
    AppleFoundationModelsAvailability availability,
  ) {
    final theme = Theme.of(context);
    final color = availability.isAvailable
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          availability.isAvailable
              ? Icons.check_circle_outline
              : Icons.info_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _providerAvailabilityMessage(availability),
            softWrap: true,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  /// Registered OpenAI-compatible endpoints. Selecting one switches the primary
  /// connection (base URL / API key / model) the whole app uses.
  Widget _buildEndpointList(AppSettings settings, SettingsNotifier notifier) {
    final theme = Theme.of(context);
    final profiles = settings.usableLlmEndpoints;
    final activeId = settings.activeLlmEndpoint?.id ?? '';
    final discovery = ref.watch(meshDiscoveryProvider);
    final isScanning = discovery.isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'settings.endpoints_label'.tr(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  key: const ValueKey('settings-scan-endpoints'),
                  onPressed: isScanning
                      ? null
                      : () async {
                          setState(() => _hasScannedLan = true);
                          await ref.read(meshDiscoveryProvider.notifier).scan();
                        },
                  icon: isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find_outlined, size: 18),
                  label: Text(
                    isScanning
                        ? 'settings.endpoint_scan_scanning'.tr()
                        : 'settings.endpoint_scan'.tr(),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('settings-add-endpoint'),
                  onPressed: () => _showEndpointEditor(notifier),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('settings.endpoint_add'.tr()),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (profiles.isEmpty)
          Text(
            'settings.endpoint_empty'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: Column(
              children: [
                for (final profile in profiles) ...[
                  if (profile != profiles.first) const Divider(height: 1),
                  _buildEndpointTile(
                    profile: profile,
                    isActive: profile.id == activeId,
                    canRemove: profiles.length > 1,
                    notifier: notifier,
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'settings.endpoints_helper'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_hasScannedLan) ...[
          const SizedBox(height: 16),
          _buildDiscoveredEndpoints(discovery, settings, notifier),
        ],
      ],
    );
  }

  Widget _buildDiscoveredEndpoints(
    AsyncValue<List<DiscoveredEndpoint>> discovery,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    final theme = Theme.of(context);
    return discovery.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => Text(
        'settings.endpoint_scan_error'.tr(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
      data: (endpoints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'settings.endpoint_discovered_section'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          if (endpoints.isEmpty)
            Text(
              'settings.endpoint_scan_no_results'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final endpoint in endpoints)
              _DiscoveredEndpointTile(
                endpoint: endpoint,
                isRegistered:
                    settings.llmEndpointForBaseUrl(endpoint.baseUrl) != null,
                onRegister: () => notifier.upsertLlmEndpoint(
                  LlmEndpoint(
                    id: '',
                    label: '${endpoint.serverHint} (${endpoint.host})',
                    baseUrl: endpoint.baseUrl,
                    model: endpoint.modelIds.isEmpty
                        ? ''
                        : endpoint.modelIds.first,
                    source: LlmEndpointSource.discovered,
                  ),
                  dedupeByBaseUrl: true,
                  activate: false,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildEndpointTile({
    required LlmEndpoint profile,
    required bool isActive,
    required bool canRemove,
    required SettingsNotifier notifier,
  }) {
    final theme = Theme.of(context);
    final details = <String>[
      profile.normalizedBaseUrl,
      if (profile.normalizedModel.isNotEmpty) profile.normalizedModel,
      _apiKeyStatus(profile.apiKey),
    ];
    return Opacity(
      opacity: profile.enabled ? 1 : 0.55,
      child: ListTile(
        key: ValueKey('settings-endpoint-${profile.id}'),
        leading: Icon(
          isActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                profile.displayLabel,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (profile.source == LlmEndpointSource.discovered) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'settings.endpoint_discovered_badge'.tr(),
                child: const Icon(Icons.wifi_find_outlined, size: 16),
              ),
            ],
            const SizedBox(width: 6),
            Text(
              profile.enabled
                  ? 'settings.endpoint_enabled'.tr()
                  : 'settings.endpoint_disabled'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: profile.enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        subtitle: Text(
          details.join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => _selectEndpoint(profile, notifier),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'settings.endpoint_edit'.tr(),
              onPressed: () => _showEndpointEditor(notifier, existing: profile),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'settings.endpoint_remove'.tr(),
              onPressed: canRemove
                  ? () => notifier.removeLlmEndpoint(profile.id)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectEndpoint(
    LlmEndpoint profile,
    SettingsNotifier notifier,
  ) async {
    if (!profile.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.endpoint_disabled_selection'.tr())),
      );
      return;
    }
    await notifier.selectLlmEndpoint(profile.id);
    if (!mounted) return;
    _runModelCapabilityAutoProbe();
  }

  /// Add/edit dialog. Endpoints are OpenAI-compatible only, so it collects just
  /// a display name, a base URL, and an optional API key; the model is picked
  /// from the fetched model list once the endpoint is active.
  Future<void> _showEndpointEditor(
    SettingsNotifier notifier, {
    LlmEndpoint? existing,
  }) async {
    final edited = await showDialog<LlmEndpoint>(
      context: context,
      builder: (dialogContext) => _EndpointEditorDialog(existing: existing),
    );
    if (edited == null) return;
    await notifier.upsertLlmEndpoint(edited);
    if (!mounted) return;
    _runModelCapabilityAutoProbe();
  }

  String _providerEndpointLabel(LlmProvider provider, String baseUrl) {
    return switch (provider) {
      LlmProvider.openAiCompatible => _modelsEndpoint(baseUrl),
      LlmProvider.appleFoundationModels =>
        'settings.compatibility_apple_endpoint'.tr(),
    };
  }

  Widget _buildCompatibilityDetail({
    required IconData icon,
    required String text,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompatibilityStatus({
    required AsyncValue<List<String>> asyncModels,
    required LlmProvider llmProvider,
    required String baseUrl,
    required String apiKey,
    required String selectedModel,
  }) {
    final theme = Theme.of(context);
    final endpoint = _providerEndpointLabel(llmProvider, baseUrl);
    final isAppleProvider = llmProvider == LlmProvider.appleFoundationModels;

    return asyncModels.when(
      data: (models) {
        final modelAvailable = models.contains(selectedModel);
        final isWarning = !modelAvailable;
        final containerColor = isWarning
            ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.35);
        final iconColor = isWarning
            ? theme.colorScheme.onTertiaryContainer
            : theme.colorScheme.primary;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isWarning
                        ? Icons.warning_amber_outlined
                        : Icons.check_circle_outline,
                    size: 18,
                    color: iconColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAppleProvider
                          ? 'settings.compatibility_apple_selected'.tr()
                          : isWarning
                          ? 'settings.compatibility_model_missing_title'.tr()
                          : 'settings.compatibility_connected'.tr(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildCompatibilityDetail(
                icon: isAppleProvider
                    ? Icons.phone_iphone_outlined
                    : Icons.http_outlined,
                text: 'settings.compatibility_endpoint'.tr(
                  namedArgs: {'endpoint': endpoint},
                ),
              ),
              const SizedBox(height: 6),
              _buildCompatibilityDetail(
                icon: Icons.memory_outlined,
                text: 'settings.compatibility_model'.tr(
                  namedArgs: {'model': selectedModel},
                ),
              ),
              if (!isAppleProvider) ...[
                const SizedBox(height: 6),
                _buildCompatibilityDetail(
                  icon: Icons.key_outlined,
                  text: 'settings.compatibility_api_key'.tr(
                    namedArgs: {'status': _apiKeyStatus(apiKey)},
                  ),
                ),
              ],
              if (isWarning) ...[
                const SizedBox(height: 8),
                Text(
                  'settings.compatibility_model_missing_next'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
      // Preflight in progress. This used to render nothing, which left the
      // section blank between opening it and the model list landing.
      loading: () => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'settings.compatibility_checking'.tr(),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      error: (_, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'settings.compatibility_preflight_failed_title'.tr(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildCompatibilityDetail(
              icon: Icons.http_outlined,
              text: 'settings.compatibility_endpoint'.tr(
                namedArgs: {'endpoint': endpoint},
              ),
            ),
            const SizedBox(height: 6),
            _buildCompatibilityDetail(
              icon: Icons.memory_outlined,
              text: 'settings.compatibility_model'.tr(
                namedArgs: {'model': selectedModel},
              ),
            ),
            const SizedBox(height: 6),
            _buildCompatibilityDetail(
              icon: Icons.key_outlined,
              text: 'settings.compatibility_api_key'.tr(
                namedArgs: {'status': _apiKeyStatus(apiKey)},
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'settings.compatibility_preflight_failed_next'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _supportFailureClassification({
    required AsyncValue<List<String>> asyncModels,
    required LlmProvider llmProvider,
    required String selectedModel,
  }) {
    if (llmProvider == LlmProvider.appleFoundationModels) {
      return 'onDeviceProviderSelected';
    }
    return asyncModels.when(
      data: (models) =>
          models.contains(selectedModel) ? 'ready' : 'modelNotAvailable',
      loading: () => 'preflightPending',
      error: (_, _) => 'endpointPreflightFailed',
    );
  }

  List<String>? _loadedModels(AsyncValue<List<String>> asyncModels) {
    return asyncModels.when(
      data: (models) => models,
      loading: () => null,
      error: (_, _) => null,
    );
  }

  Map<String, dynamic> _supportSnapshotMap({
    required AppSettings settings,
    required AsyncValue<List<String>> asyncModels,
    required String baseUrl,
    required String apiKey,
  }) {
    final selectedModel = settings.effectiveModel.trim().isEmpty
        ? ApiConstants.defaultModel
        : settings.effectiveModel.trim();
    final loadedModels = _loadedModels(asyncModels);
    return {
      'schemaName': 'plan_mode_support_snapshot',
      'schemaVersion': 1,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': {
        'llmProvider': settings.llmProvider.name,
        'baseUrl': baseUrl,
        'modelsEndpoint': _providerEndpointLabel(settings.llmProvider, baseUrl),
        'model': selectedModel,
        'apiKeyStatus': _apiKeyStatus(apiKey),
        'demoMode': settings.demoMode,
        'assistantMode': settings.assistantMode.name,
        'mcpEnabled': settings.mcpEnabled,
      },
      'preflight': {
        'failureClassification': _supportFailureClassification(
          asyncModels: asyncModels,
          llmProvider: settings.llmProvider,
          selectedModel: selectedModel,
        ),
        'availableModelCount': loadedModels?.length,
        'selectedModelAvailable': loadedModels?.contains(selectedModel),
      },
      'artifactPaths': {
        'deterministicSuiteReport':
            'build/integration_test_reports/plan_mode_suite_macos_report.json',
        'liveSuiteReport':
            'build/integration_test_reports/plan_mode_live_suite_macos_report.json',
        'pingCanarySummary':
            'build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/canary_summary.json',
      },
      'troubleshooting': {
        'compatibilityDoc': 'docs/plan_mode_model_endpoint_compatibility.md',
        'releaseChecklist': 'docs/plan_mode_release_readiness_checklist.md',
        'releaseCandidateGate': 'docs/plan_mode_release_candidate_gate.md',
        'nextAction':
            'Attach this snapshot with the latest Plan Mode report artifact before classifying a failure as an app regression.',
      },
    };
  }

  String _supportSnapshotJson({
    required AppSettings settings,
    required AsyncValue<List<String>> asyncModels,
    required String baseUrl,
    required String apiKey,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      _supportSnapshotMap(
        settings: settings,
        asyncModels: asyncModels,
        baseUrl: baseUrl,
        apiKey: apiKey,
      ),
    );
  }

  Future<void> _copySupportSnapshot({
    required AppSettings settings,
    required AsyncValue<List<String>> asyncModels,
    required String baseUrl,
    required String apiKey,
  }) async {
    final snapshot = _supportSnapshotJson(
      settings: settings,
      asyncModels: asyncModels,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    await Clipboard.setData(ClipboardData(text: snapshot));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('settings.plan_mode_support_copied'.tr())),
    );
  }

  Widget _buildSupportSnapshotCard({
    required AppSettings settings,
    required AsyncValue<List<String>> asyncModels,
    required String baseUrl,
    required String apiKey,
  }) {
    final theme = Theme.of(context);
    final selectedModel = settings.effectiveModel;
    final classification = _supportFailureClassification(
      asyncModels: asyncModels,
      llmProvider: settings.llmProvider,
      selectedModel: selectedModel,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.support_agent_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'settings.plan_mode_support_title'.tr(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'settings.plan_mode_support_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'settings.plan_mode_support_classification'.tr(
              namedArgs: {'classification': classification},
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('plan-mode-copy-support-snapshot'),
              onPressed: () => _copySupportSnapshot(
                settings: settings,
                asyncModels: asyncModels,
                baseUrl: baseUrl,
                apiKey: apiKey,
              ),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text('settings.plan_mode_support_copy'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  /// Model selection lives in Model routing, not here.
  ///
  /// General settings used to own the primary model picker while every other
  /// model choice (per mode, per role) lived on the routing page, so the two
  /// halves of one decision sat on different screens. This tile keeps the
  /// primary model visible next to the connection status and hands the choice
  /// itself to the page that owns it.
  Widget _buildModelRoutingLink(String selectedModel) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      // Material keeps the tile's ink splash visible above the decoration.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: const ValueKey('settings-open-model-routing'),
          leading: Icon(
            Icons.alt_route_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text('settings.model_routing_title'.tr()),
          subtitle: Text(
            'settings.model_routing_open_desc'.tr(
              namedArgs: {'model': selectedModel},
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ModelRoutingSettingsPage(),
              ),
            );
          },
        ),
      ),
    );
  }

  /// LL5: pin embeddings to their own endpoint.
  ///
  /// Embeddings used to be the one role without this, so they always followed
  /// the primary connection: moving the primary to another provider turned a
  /// working local embedding model into a silent 404 and dropped semantic
  /// search back to lexical search with no visible failure.
  Widget _buildEmbeddingsEndpointField(AppSettings settings) {
    final endpoints = settings.enabledLlmEndpoints;
    if (endpoints.isEmpty) return const SizedBox.shrink();
    final selected = settings.embeddingsEndpointId.trim();
    final hasSelection = endpoints.any((endpoint) => endpoint.id == selected);
    return DropdownButtonFormField<String>(
      key: const ValueKey('settings-embeddings-endpoint'),
      initialValue: hasSelection ? selected : '',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'settings.embeddings_endpoint_label'.tr(),
        border: const OutlineInputBorder(),
        helperText: 'settings.embeddings_endpoint_helper'.tr(),
      ),
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: Text(
            'settings.embeddings_endpoint_follow_primary'.tr(),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final endpoint in endpoints)
          DropdownMenuItem<String>(
            value: endpoint.id,
            child: Text(endpoint.displayLabel, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: settings.enableSemanticSearch
          ? (value) {
              ref
                  .read(settingsNotifierProvider.notifier)
                  .updateEmbeddingsEndpointId(value ?? '');
            }
          : null,
    );
  }

  /// Models offered for embeddings come from the pinned endpoint, so the list
  /// can never suggest a model the embeddings requests would 404 on. Falls back
  /// to the page's primary list when embeddings follow the primary.
  AsyncValue<List<String>> _embeddingsModelOptions(
    AppSettings settings,
    AsyncValue<List<String>> primaryModels,
  ) {
    final endpoint = settings.embeddingsEndpoint;
    if (endpoint == null) return primaryModels;
    return ref.watch(
      modelListProvider(
        ModelListConfig(
          baseUrl: endpoint.normalizedBaseUrl,
          apiKey: endpoint.apiKey,
        ),
      ),
    );
  }

  /// LL5: pick the embeddings model. Prefers a dropdown populated from the
  /// endpoint's /v1/models list; while that is loading or unavailable it falls
  /// back to a free-text field so a model id can still be entered by hand.
  Widget _buildEmbeddingsModelField(
    AsyncValue<List<String>> asyncModels,
    AppSettings settings,
  ) {
    final enabled = settings.enableSemanticSearch;
    final selected = settings.embeddingsModel;
    return asyncModels.maybeWhen(
      data: (models) {
        if (models.isEmpty) return _embeddingsModelTextField(enabled);
        final options = [...models];
        if (selected.isNotEmpty && !options.contains(selected)) {
          options.insert(0, selected);
        }
        return DropdownButtonFormField<String>(
          key: const ValueKey('settings-embeddings-model'),
          initialValue: selected.isEmpty ? null : selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'settings.embeddings_model_label'.tr(),
            border: const OutlineInputBorder(),
            helperText: 'settings.embeddings_model_helper'.tr(),
          ),
          items: options
              .map(
                (model) => DropdownMenuItem<String>(
                  value: model,
                  child: Text(model, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (value) {
                  if (value == null) return;
                  _embeddingsModelController.text = value;
                  ref
                      .read(settingsNotifierProvider.notifier)
                      .updateEmbeddingsModel(value);
                }
              : null,
        );
      },
      orElse: () => _embeddingsModelTextField(enabled),
    );
  }

  Widget _embeddingsModelTextField(bool enabled) {
    return TextField(
      controller: _embeddingsModelController,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: 'settings.embeddings_model_label'.tr(),
        hintText: 'text-embedding-...',
        border: const OutlineInputBorder(),
        helperText: 'settings.embeddings_model_helper'.tr(),
      ),
      onChanged: (_) {
        _embeddingsModelDebouncer.run(() {
          ref
              .read(settingsNotifierProvider.notifier)
              .updateEmbeddingsModel(_embeddingsModelController.text);
        });
      },
    );
  }

  void _runModelCapabilityAutoProbe() {
    unawaited(
      ref
          .read(modelCapabilityAutoProbeNotifierProvider.notifier)
          .runForCurrentModel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appleFoundationModelsAvailabilityProvider, (_, next) {
      next.whenData((availability) {
        if (availability.isAvailable) return;
        final currentSettings = ref.read(settingsNotifierProvider);
        if (currentSettings.llmProvider != LlmProvider.appleFoundationModels) {
          return;
        }
        ref
            .read(settingsNotifierProvider.notifier)
            .updateLlmProvider(LlmProvider.openAiCompatible);
      });
    });

    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final appleAvailabilityAsync = ref.watch(
      appleFoundationModelsAvailabilityProvider,
    );
    final appleAvailability = appleAvailabilityAsync.maybeWhen(
      data: (availability) => availability,
      orElse: () => null,
    );
    final selectableProviders = selectableLlmProviders(
      appleFoundationModelsAvailability: appleAvailability,
    );
    final visibleProviders = visibleLlmProviders(
      appleFoundationModelsAvailability: appleAvailability,
    );
    final visibleProvider = visibleLlmProviderSelection(
      selectedProvider: settings.llmProvider,
      selectableProviders: selectableProviders,
    );
    final visibleSettings = settings.llmProvider == visibleProvider
        ? settings
        : settings.copyWith(llmProvider: visibleProvider);
    final baseUrl = visibleSettings.baseUrl.trim().isEmpty
        ? ApiConstants.defaultBaseUrl
        : visibleSettings.baseUrl.trim();
    final apiKey = visibleSettings.apiKey.trim().isEmpty
        ? ApiConstants.defaultApiKey
        : visibleSettings.apiKey.trim();
    final modelListConfig = ModelListConfig(baseUrl: baseUrl, apiKey: apiKey);
    final isAppleProvider =
        visibleSettings.llmProvider == LlmProvider.appleFoundationModels;
    final selectedModel = visibleSettings.effectiveModel;
    final asyncModels = isAppleProvider
        ? AsyncValue.data([selectedModel])
        : ref.watch(modelListProvider(modelListConfig));
    final updateService = ref.watch(macosUpdateServiceProvider);

    return Scaffold(
      appBar: AppBar(title: Text('settings.menu_general'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Demo mode toggle
          SwitchListTile(
            title: Text('settings.demo_mode'.tr()),
            subtitle: Text('settings.demo_mode_desc'.tr()),
            value: settings.demoMode,
            onChanged: (value) => notifier.updateDemoMode(value),
          ),
          const Divider(),
          const SizedBox(height: 8),
          // Server, model, and generation settings (disabled in demo mode)
          IgnorePointer(
            ignoring: settings.demoMode,
            child: AnimatedOpacity(
              opacity: settings.demoMode ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server settings section
                  _buildSectionHeader('settings.server_section'.tr()),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<LlmProvider>(
                    isExpanded: true,
                    initialValue: visibleProvider,
                    decoration: InputDecoration(
                      labelText: 'settings.llm_provider_label'.tr(),
                      border: const OutlineInputBorder(),
                      helperText: 'settings.llm_provider_helper'.tr(),
                    ),
                    items: visibleProviders
                        .map((provider) {
                          final isSelectable = isLlmProviderSelectable(
                            provider: provider,
                            appleFoundationModelsAvailability:
                                appleAvailability,
                          );
                          final label = _providerLabel(provider);
                          return DropdownMenuItem<LlmProvider>(
                            value: provider,
                            enabled: isSelectable,
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        })
                        .toList(growable: false),
                    onChanged: (provider) async {
                      if (provider == null) return;
                      await notifier.updateLlmProvider(provider);
                      if (!mounted) return;
                      _runModelCapabilityAutoProbe();
                    },
                  ),
                  if (appleAvailability != null &&
                      visibleProviders.contains(
                        LlmProvider.appleFoundationModels,
                      )) ...[
                    const SizedBox(height: 8),
                    _buildProviderAvailabilityMessage(appleAvailability),
                  ],
                  const SizedBox(height: 16),
                  IgnorePointer(
                    ignoring: isAppleProvider,
                    child: AnimatedOpacity(
                      opacity: isAppleProvider ? 0.45 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: _buildEndpointList(visibleSettings, notifier),
                    ),
                  ),
                  if (isAppleProvider) ...[
                    const SizedBox(height: 8),
                    Text(
                      'settings.base_url_apple_disabled_helper'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Model settings section
                  Row(
                    children: [
                      _buildSectionHeader('settings.model_section'.tr()),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: isAppleProvider
                            ? null
                            : () {
                                ref.invalidate(
                                  modelListProvider(modelListConfig),
                                );
                              },
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: 'settings.model_refresh'.tr(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildModelRoutingLink(selectedModel),
                  const SizedBox(height: 12),
                  _buildCompatibilityStatus(
                    asyncModels: asyncModels,
                    llmProvider: visibleSettings.llmProvider,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                    selectedModel: selectedModel,
                  ),
                  const SizedBox(height: 12),
                  _buildSupportSnapshotCard(
                    settings: visibleSettings,
                    asyncModels: asyncModels,
                    baseUrl: baseUrl,
                    apiKey: apiKey,
                  ),
                  const SizedBox(height: 24),

                  // Generation parameters section
                  _buildSectionHeader('settings.generation_section'.tr()),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Chat temperature: '),
                      Expanded(
                        child: Slider(
                          value: settings.temperature,
                          min: 0.0,
                          max: 2.0,
                          divisions: 20,
                          label: settings.temperature.toStringAsFixed(1),
                          onChanged: (value) {
                            notifier.updateTemperature(value);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(settings.temperature.toStringAsFixed(1)),
                      ),
                    ],
                  ),
                  const Text(
                    'Tool loops, coding, plans, routines, and subagents use a managed low temperature.',
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('settings-prefix-stable-tool-loop'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('settings.prefix_stable_tool_loop'.tr()),
                    subtitle: Text(
                      'settings.prefix_stable_tool_loop_desc'.tr(),
                    ),
                    value: settings.enablePrefixStableToolLoop,
                    onChanged: notifier.updateEnablePrefixStableToolLoop,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _maxTokensController,
                    decoration: InputDecoration(
                      labelText: 'Max Tokens',
                      hintText: '4096',
                      border: const OutlineInputBorder(),
                      helperText: 'settings.max_tokens_helper'.tr(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      _maxTokensDebouncer.run(() {
                        final value =
                            int.tryParse(_maxTokensController.text) ?? 4096;
                        notifier.updateMaxTokens(value);
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('settings.semantic_search_section'.tr()),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('settings-enable-semantic-search'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('settings.semantic_search'.tr()),
                    subtitle: Text('settings.semantic_search_desc'.tr()),
                    value: settings.enableSemanticSearch,
                    onChanged: notifier.updateEnableSemanticSearch,
                  ),
                  const SizedBox(height: 8),
                  _buildEmbeddingsEndpointField(settings),
                  const SizedBox(height: 8),
                  _buildEmbeddingsModelField(
                    _embeddingsModelOptions(settings, asyncModels),
                    settings,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('settings.google_chat_section'.tr()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _googleChatWebhookController,
                    decoration: InputDecoration(
                      labelText: 'settings.google_chat_webhook_label'.tr(),
                      hintText: 'https://chat.googleapis.com/v1/spaces/...',
                      border: const OutlineInputBorder(),
                      helperText: 'settings.google_chat_webhook_helper'.tr(),
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: (_) {
                      _googleChatWebhookDebouncer.run(() {
                        notifier.updateGoogleChatWebhookUrl(
                          _googleChatWebhookController.text,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _isSendingGoogleChatTest
                          ? null
                          : () => _sendGoogleChatTest(context),
                      icon: _isSendingGoogleChatTest
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text('settings.google_chat_test_button'.tr()),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Language section
          _buildSectionHeader('settings.language_section'.tr()),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: settings.language,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: 'settings.language_helper'.tr(),
            ),
            items: [
              DropdownMenuItem(
                value: 'system',
                child: Text('settings.language_system'.tr()),
              ),
              DropdownMenuItem(
                value: 'ja',
                child: Text('settings.language_ja'.tr()),
              ),
              DropdownMenuItem(
                value: 'en',
                child: Text('settings.language_en'.tr()),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                notifier.updateLanguage(value);
              }
            },
          ),
          const SizedBox(height: 16),

          // Appearance section
          _buildSectionHeader('settings.appearance_section'.tr()),
          const SizedBox(height: 8),
          DropdownButtonFormField<AppThemePreference>(
            initialValue: settings.themePreference,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: 'settings.appearance_helper'.tr(),
            ),
            items: [
              DropdownMenuItem(
                value: AppThemePreference.system,
                child: Text('onboarding.theme_system'.tr()),
              ),
              DropdownMenuItem(
                value: AppThemePreference.dark,
                child: Text('onboarding.theme_dark'.tr()),
              ),
              DropdownMenuItem(
                value: AppThemePreference.light,
                child: Text('onboarding.theme_light'.tr()),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                notifier.updateThemePreference(value);
              }
            },
          ),
          const SizedBox(height: 16),
          // App update section: macOS only, because Sparkle is the only update
          // channel Caverno ships. Other platforms update through their store.
          if (updateService.isAvailable) ...[
            const SizedBox(height: 8),
            _buildSectionHeader('settings.app_updates_section'.tr()),
            const SizedBox(height: 8),
            MacosUpdateTile(service: updateService),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Future<void> _sendGoogleChatTest(BuildContext context) async {
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final deliveryService = ref.read(googleChatDeliveryServiceProvider);
    final webhookUrl = _googleChatWebhookController.text.trim();

    if (webhookUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings.google_chat_test_missing'.tr())),
      );
      return;
    }

    setState(() {
      _isSendingGoogleChatTest = true;
    });

    await notifier.updateGoogleChatWebhookUrl(webhookUrl);
    final result = await deliveryService.sendMessage(
      webhookUrl: webhookUrl,
      text: 'settings.google_chat_test_message'.tr(),
    );

    if (!context.mounted) {
      return;
    }

    setState(() {
      _isSendingGoogleChatTest = false;
    });

    final message = result.isSuccessful
        ? 'settings.google_chat_test_success'.tr()
        : 'settings.google_chat_test_failed'.tr(
            namedArgs: {'reason': result.message},
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DiscoveredEndpointTile extends StatelessWidget {
  const _DiscoveredEndpointTile({
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
      key: ValueKey('settings-discovered-${endpoint.baseUrl}'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.dns_outlined),
      title: Text('${endpoint.serverHint} · ${endpoint.host}:${endpoint.port}'),
      subtitle: Text(
        'settings.endpoint_models_count'.tr(
          args: ['${endpoint.modelIds.length}'],
        ),
      ),
      trailing: isRegistered
          ? Text(
              'settings.endpoint_registered_badge'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : TextButton(
              key: ValueKey('settings-register-${endpoint.baseUrl}'),
              onPressed: onRegister,
              child: Text('settings.endpoint_register'.tr()),
            ),
    );
  }
}

/// Owns its text controllers so they outlive the dialog's dismiss animation.
class _EndpointEditorDialog extends StatefulWidget {
  const _EndpointEditorDialog({this.existing});

  final LlmEndpoint? existing;

  @override
  State<_EndpointEditorDialog> createState() => _EndpointEditorDialogState();
}

class _EndpointEditorDialogState extends State<_EndpointEditorDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late bool _enabled;
  late bool _videoInputEnabled;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelController = TextEditingController(
      text: existing?.normalizedLabel ?? '',
    );
    _baseUrlController = TextEditingController(
      text: existing?.normalizedBaseUrl ?? ApiConstants.defaultBaseUrl,
    );
    _apiKeyController = TextEditingController(text: existing?.apiKey ?? '');
    _modelController = TextEditingController(
      text: existing?.normalizedModel ?? '',
    );
    _enabled = existing?.enabled ?? true;
    _videoInputEnabled = existing?.videoInputEnabled ?? false;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  String? _validateBaseUrl(String? value) {
    final uri = Uri.tryParse((value ?? '').trim());
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return 'settings.endpoint_base_url_invalid'.tr();
    }
    try {
      const LlmEndpointTransportPolicy().validate(
        baseUrl: uri.toString(),
        apiKey: _apiKeyController.text.trim().isEmpty
            ? ApiConstants.defaultApiKey
            : _apiKeyController.text,
      );
    } on LlmEndpointTransportException catch (error) {
      return error.message;
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    final existing = widget.existing;
    final apiKey = _apiKeyController.text.trim();
    Navigator.of(context).pop(
      LlmEndpoint(
        id: existing?.id ?? '',
        label: _labelController.text,
        baseUrl: _baseUrlController.text,
        apiKey: apiKey.isEmpty ? ApiConstants.defaultApiKey : apiKey,
        model: _modelController.text,
        enabled: _enabled,
        videoInputEnabled: _videoInputEnabled,
        source: existing?.source ?? LlmEndpointSource.manual,
        createdAt: existing?.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'settings.endpoint_add_title'.tr()
            : 'settings.endpoint_edit_title'.tr(),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('settings-endpoint-label-field'),
              controller: _labelController,
              decoration: InputDecoration(
                labelText: 'settings.endpoint_label_field'.tr(),
                hintText: 'LM Studio',
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('settings-endpoint-base-url-field'),
              controller: _baseUrlController,
              decoration: InputDecoration(
                labelText: 'API Base URL',
                hintText: ApiConstants.defaultBaseUrl,
                border: const OutlineInputBorder(),
                helperText: 'settings.base_url_helper'.tr(),
                helperMaxLines: 2,
              ),
              keyboardType: TextInputType.url,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: _validateBaseUrl,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('settings-endpoint-api-key-field'),
              controller: _apiKeyController,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: ApiConstants.defaultApiKey,
                border: const OutlineInputBorder(),
                helperText: 'settings.api_key_helper'.tr(),
                helperMaxLines: 2,
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('settings-endpoint-model-field'),
              controller: _modelController,
              decoration: InputDecoration(
                labelText: 'settings.endpoint_model_field'.tr(),
                border: const OutlineInputBorder(),
              ),
              onFieldSubmitted: (_) => _submit(),
            ),
            SwitchListTile(
              key: const ValueKey('settings-endpoint-enabled-toggle'),
              contentPadding: EdgeInsets.zero,
              title: Text('settings.endpoint_enabled_field'.tr()),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            SwitchListTile(
              key: const ValueKey('settings-endpoint-video-input-toggle'),
              contentPadding: EdgeInsets.zero,
              title: Text('settings.endpoint_video_input_field'.tr()),
              subtitle: Text('settings.endpoint_video_input_hint'.tr()),
              value: _videoInputEnabled,
              onChanged: (value) =>
                  setState(() => _videoInputEnabled = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('settings.endpoint_cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey('settings-endpoint-save'),
          onPressed: _submit,
          child: Text('settings.endpoint_save'.tr()),
        ),
      ],
    );
  }
}
