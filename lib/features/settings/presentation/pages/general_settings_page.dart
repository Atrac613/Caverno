import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/apple_foundation_models_platform_client.dart';
import '../../../../core/services/google_chat_delivery_service.dart';
import '../../../../core/utils/debouncer.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/apple_foundation_models_availability_provider.dart';
import '../providers/model_list_provider.dart';
import '../providers/settings_notifier.dart';

class GeneralSettingsPage extends ConsumerStatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  ConsumerState<GeneralSettingsPage> createState() =>
      _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends ConsumerState<GeneralSettingsPage> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _maxTokensController = TextEditingController();
  final _googleChatWebhookController = TextEditingController();

  final _baseUrlDebouncer = Debouncer();
  final _apiKeyDebouncer = Debouncer();
  final _maxTokensDebouncer = Debouncer();
  final _googleChatWebhookDebouncer = Debouncer();
  bool _isSendingGoogleChatTest = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    _baseUrlController.text = settings.baseUrl;
    _apiKeyController.text = settings.apiKey;
    _maxTokensController.text = settings.maxTokens.toString();
    _googleChatWebhookController.text = settings.googleChatWebhookUrl;
  }

  @override
  void dispose() {
    _baseUrlDebouncer.dispose();
    _apiKeyDebouncer.dispose();
    _maxTokensDebouncer.dispose();
    _googleChatWebhookDebouncer.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _maxTokensController.dispose();
    _googleChatWebhookController.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
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

  Future<void> _applyNvidiaNimCloudPreset(SettingsNotifier notifier) async {
    _baseUrlController.text = ApiConstants.nvidiaNimBaseUrl;
    _maxTokensController.text = ApiConstants.defaultMaxTokens.toString();
    if (_apiKeyController.text.trim() == ApiConstants.defaultApiKey) {
      _apiKeyController.clear();
    }
    await notifier.applyNvidiaNimCloudPreset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('settings.nvidia_nim_preset_applied'.tr())),
    );
  }

  Widget _buildEndpointPresetButtons(SettingsNotifier notifier) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'settings.api_preset_label'.tr(),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('apply-nvidia-nim-preset'),
              onPressed: () => _applyNvidiaNimCloudPreset(notifier),
              icon: const Icon(Icons.cloud_outlined, size: 18),
              label: Text('settings.nvidia_nim_preset_label'.tr()),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'settings.nvidia_nim_preset_helper'.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
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
      loading: () => const SizedBox.shrink(),
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

  Widget _buildModelSelector({
    required AsyncValue<List<String>> asyncModels,
    required LlmProvider llmProvider,
    required String selectedModel,
  }) {
    if (llmProvider == LlmProvider.appleFoundationModels) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'settings.model_name'.tr(),
          border: const OutlineInputBorder(),
          helperText: 'settings.apple_model_helper'.tr(),
        ),
        child: Text(selectedModel, overflow: TextOverflow.ellipsis),
      );
    }
    return asyncModels.when(
      data: (models) {
        final options = [...models];
        if (!options.contains(selectedModel)) {
          options.insert(0, selectedModel);
        }

        return DropdownButtonFormField<String>(
          initialValue: selectedModel,
          decoration: InputDecoration(
            labelText: 'settings.model_name'.tr(),
            border: const OutlineInputBorder(),
            helperText: 'settings.model_list_helper'.tr(),
          ),
          items: options
              .map(
                (model) => DropdownMenuItem<String>(
                  value: model,
                  child: Text(model, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(settingsNotifierProvider.notifier)
                .updateModel(value.trim());
          },
        );
      },
      loading: () => InputDecorator(
        decoration: InputDecoration(
          labelText: 'settings.model_name'.tr(),
          border: const OutlineInputBorder(),
          helperText: 'settings.model_loading'.tr(),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('settings.model_loading_message'.tr())),
          ],
        ),
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: selectedModel,
            decoration: InputDecoration(
              labelText: 'settings.model_name'.tr(),
              border: const OutlineInputBorder(),
              helperText: 'settings.model_error_helper'.tr(),
            ),
            items: [
              DropdownMenuItem<String>(
                value: selectedModel,
                child: Text(selectedModel, overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              ref
                  .read(settingsNotifierProvider.notifier)
                  .updateModel(value.trim());
            },
          ),
          const SizedBox(height: 8),
          Text(
            'settings.model_error_message'.tr(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ),
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
    final baseUrl = _baseUrlController.text.trim().isEmpty
        ? ApiConstants.defaultBaseUrl
        : _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim().isEmpty
        ? ApiConstants.defaultApiKey
        : _apiKeyController.text.trim();
    final modelListConfig = ModelListConfig(baseUrl: baseUrl, apiKey: apiKey);
    final isAppleProvider =
        visibleSettings.llmProvider == LlmProvider.appleFoundationModels;
    final selectedModel = visibleSettings.effectiveModel;
    final asyncModels = isAppleProvider
        ? AsyncValue.data([selectedModel])
        : ref.watch(modelListProvider(modelListConfig));

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
                    onChanged: (provider) {
                      if (provider == null) return;
                      notifier.updateLlmProvider(provider);
                    },
                  ),
                  if (appleAvailability != null &&
                      visibleProviders.contains(
                        LlmProvider.appleFoundationModels,
                      )) ...[
                    const SizedBox(height: 8),
                    _buildProviderAvailabilityMessage(appleAvailability),
                  ],
                  const SizedBox(height: 12),
                  _buildEndpointPresetButtons(notifier),
                  const SizedBox(height: 16),
                  IgnorePointer(
                    ignoring: isAppleProvider,
                    child: AnimatedOpacity(
                      opacity: isAppleProvider ? 0.45 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: TextField(
                        controller: _baseUrlController,
                        decoration: InputDecoration(
                          labelText: 'API Base URL',
                          hintText: 'http://localhost:1234/v1',
                          border: const OutlineInputBorder(),
                          helperText: isAppleProvider
                              ? 'settings.base_url_apple_disabled_helper'.tr()
                              : 'settings.base_url_helper'.tr(),
                        ),
                        keyboardType: TextInputType.url,
                        onChanged: (_) {
                          _baseUrlDebouncer.run(() {
                            notifier.updateBaseUrl(
                              _baseUrlController.text.trim(),
                            );
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  IgnorePointer(
                    ignoring: isAppleProvider,
                    child: AnimatedOpacity(
                      opacity: isAppleProvider ? 0.45 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: TextField(
                        controller: _apiKeyController,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          hintText: 'no-key',
                          border: const OutlineInputBorder(),
                          helperText: isAppleProvider
                              ? 'settings.api_key_apple_disabled_helper'.tr()
                              : 'settings.api_key_helper'.tr(),
                        ),
                        obscureText: true,
                        onChanged: (_) {
                          _apiKeyDebouncer.run(() {
                            notifier.updateApiKey(
                              _apiKeyController.text.trim(),
                            );
                          });
                        },
                      ),
                    ),
                  ),
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
                  _buildModelSelector(
                    asyncModels: asyncModels,
                    llmProvider: visibleSettings.llmProvider,
                    selectedModel: selectedModel,
                  ),
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
                      const Text('Temperature: '),
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
