import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/local_diagnostics_exporter.dart';
import '../../../../core/services/macos_computer_use_service.dart';
import '../../../../core/services/macos_computer_use_setup.dart';
import '../providers/settings_notifier.dart';
import '../widgets/qr_export_dialog.dart';
import 'computer_use_debug_page.dart';
import 'debug_settings_page.dart';
import 'general_settings_page.dart';
import 'chat_settings_page.dart';
import 'voice_settings_page.dart';
import 'tools_settings_page.dart';
import 'qr_scanner_page.dart';

enum _SettingsAction { reset, import, export, importQr, exportQr }

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _resetToDefaults(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.reset_title'.tr()),
        content: Text('settings.reset_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('common.reset'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(settingsNotifierProvider.notifier).resetToDefaults();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('settings.reset_done'.tr())));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
        actions: [
          PopupMenuButton<_SettingsAction>(
            onSelected: (action) {
              switch (action) {
                case _SettingsAction.reset:
                  _resetToDefaults(context, ref);
                  break;
                case _SettingsAction.import:
                  _importSettings(context, ref);
                  break;
                case _SettingsAction.export:
                  _exportSettings(context, ref);
                  break;
                case _SettingsAction.importQr:
                  _importFromQr(context, ref);
                  break;
                case _SettingsAction.exportQr:
                  _exportToQr(context, ref);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _SettingsAction.import,
                child: Row(
                  children: [
                    const Icon(Icons.upload_file_outlined),
                    const SizedBox(width: 12),
                    Text('settings.import_settings'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _SettingsAction.export,
                child: Row(
                  children: [
                    const Icon(Icons.file_download_outlined),
                    const SizedBox(width: 12),
                    Text('settings.export_settings'.tr()),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _SettingsAction.importQr,
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner),
                    const SizedBox(width: 12),
                    Text('settings.import_qr'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _SettingsAction.exportQr,
                child: Row(
                  children: [
                    const Icon(Icons.qr_code),
                    const SizedBox(width: 12),
                    Text('settings.export_qr'.tr()),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _SettingsAction.reset,
                child: Row(
                  children: [
                    const Icon(Icons.restore, color: Colors.red),
                    const SizedBox(width: 12),
                    Text(
                      'settings.reset_to_default'.tr(),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        children: [
          const _ComputerUseOnboardingCard(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text('settings.menu_general'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GeneralSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: Text('settings.menu_chat'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.mic_outlined),
            title: Text('settings.menu_voice'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VoiceSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.build_outlined),
            title: Text('settings.menu_tools'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ToolsSettingsPage()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text('settings.menu_debug'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebugSettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importSettings(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.import_settings'.tr()),
        content: Text('settings.import_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('settings.import_settings'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await ref
            .read(settingsNotifierProvider.notifier)
            .importSettings();
        if (success && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('settings.import_done'.tr())));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('settings.import_error'.tr(args: [e.toString()])),
            ),
          );
        }
      }
    }
  }

  Future<void> _exportSettings(BuildContext context, WidgetRef ref) async {
    try {
      final path = await ref
          .read(settingsNotifierProvider.notifier)
          .exportSettings();
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('settings.export_done'.tr(args: [path]))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('settings.export_error'.tr(args: [e.toString()])),
          ),
        );
      }
    }
  }

  Future<void> _importFromQr(BuildContext context, WidgetRef ref) async {
    // Scan first, then ask for confirmation
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerPage()));

    if (result == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('settings.import_qr'.tr()),
        content: Text('settings.qr_import_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('settings.import_settings'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(settingsNotifierProvider.notifier).importFromQr(result);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('settings.import_done'.tr())));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('settings.import_error'.tr(args: [e.toString()])),
            ),
          );
        }
      }
    }
  }

  Future<void> _exportToQr(BuildContext context, WidgetRef ref) async {
    final data = ref.read(settingsNotifierProvider.notifier).exportToQr();
    showDialog(
      context: context,
      builder: (context) => QrExportDialog(data: data),
    );
  }
}

class _ComputerUseOnboardingCard extends ConsumerStatefulWidget {
  const _ComputerUseOnboardingCard();

  @override
  ConsumerState<_ComputerUseOnboardingCard> createState() =>
      _ComputerUseOnboardingCardState();
}

class _ComputerUseOnboardingCardState
    extends ConsumerState<_ComputerUseOnboardingCard>
    with WidgetsBindingObserver {
  bool _isLoading = false;
  Map<String, dynamic>? _helperStatus;
  Map<String, dynamic>? _permissions;
  Map<String, dynamic>? _lastStopResult;
  Map<String, dynamic>? _lastPermissionSettingsResult;
  String? _lastDiagnosticExportPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(macosComputerUseServiceProvider);
    if (!service.isAvailable) {
      return const SizedBox.shrink();
    }

    final checklist = _setupChecklist(service.permissionBackendInfo);
    final ready = checklist.isReady;
    final onboardingVerification = _onboardingVerification();
    final verificationOk = onboardingVerification?['ok'] == true;
    final verificationRan = onboardingVerification != null;
    final helperWorkActive = _helperWorkActive() == true;
    final hasPermissionSnapshot = _permissions != null || _helperStatus != null;
    final showAccessibilityCta =
        hasPermissionSnapshot &&
        _permissionValue('accessibilityGranted') != true;
    final showScreenRecordingCta =
        hasPermissionSnapshot &&
        _permissionValue('screenCaptureGranted') != true;
    final helperReady =
        _permissionValue('helperReachable') == true ||
        (_permissionValue('helperInstalled') == true &&
            _permissionValue('helperRunning') == true);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ready
                      ? Icons.verified_user_outlined
                      : Icons.ads_click_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ready ? 'Computer Use Ready' : 'Enable Computer Use',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        checklist.subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh computer-use status',
                  onPressed: _isLoading ? null : _refresh,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(label: 'Helper', value: helperReady),
                _StatusChip(
                  label: 'Accessibility',
                  value: _permissionValue('accessibilityGranted') == true,
                ),
                _StatusChip(
                  label: 'Screen & System Audio',
                  value: _permissionValue('screenCaptureGranted') == true,
                ),
                _StatusChip(
                  label: MacosComputerUseIpc.current.preferredTransport,
                  value: MacosComputerUseIpc.current.xpcReady,
                  trueText: 'XPC ready',
                  falseText: 'DNC bridge',
                ),
                _StatusChip(
                  label: 'Verify',
                  value: verificationOk,
                  trueText: 'Passed',
                  falseText: verificationRan ? 'Needs attention' : 'Not run',
                ),
                _StatusChip(
                  label: 'Helper Work',
                  value: !helperWorkActive,
                  trueText: 'Idle',
                  falseText: 'Active',
                ),
              ],
            ),
            if (onboardingVerification != null) ...[
              const SizedBox(height: 8),
              _VerificationSummary(verification: onboardingVerification),
            ],
            if (showAccessibilityCta || showScreenRecordingCta) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (showAccessibilityCta)
                    OutlinedButton.icon(
                      key: const ValueKey(
                        'computer-use-settings-open-accessibility',
                      ),
                      onPressed: _isLoading
                          ? null
                          : () => _openPermissionSettings('accessibility'),
                      icon: const Icon(Icons.accessibility_new_outlined),
                      label: const Text('Open Accessibility Settings'),
                    ),
                  if (showScreenRecordingCta)
                    OutlinedButton.icon(
                      key: const ValueKey(
                        'computer-use-settings-open-screen-recording',
                      ),
                      onPressed: _isLoading
                          ? null
                          : () => _openPermissionSettings('screen_recording'),
                      icon: const Icon(Icons.screenshot_monitor_outlined),
                      label: const Text('Open Screen Recording Settings'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _isLoading ? null : _launchHelper,
                  icon: const Icon(Icons.rocket_launch_outlined),
                  label: Text(
                    ready ? 'Open Computer Use' : 'Enable Computer Use',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openSmokeTest,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Open Smoke Test'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('computer-use-settings-stop-helper-work'),
                  onPressed: _isLoading ? null : _stopHelperWork,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Helper Work'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('computer-use-settings-copy-diagnostics'),
                  onPressed: _copyDiagnostics,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy Diagnostics'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey(
                    'computer-use-settings-export-diagnostics',
                  ),
                  onPressed: _exportDiagnostics,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export Diagnostics'),
                ),
              ],
            ),
            if (_lastStopResult != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last stop: ${_resultSummary(_lastStopResult!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_lastPermissionSettingsResult != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last permission action: ${_permissionActionSummary(_lastPermissionSettingsResult!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_lastDiagnosticExportPath != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last export: $_lastDiagnosticExportPath',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _launchHelper() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final helper = _decodeMap(await service.launchHelper());
      if (!mounted) {
        return;
      }
      setState(() {
        if (helper != null) {
          _helperStatus = {...?_helperStatus, ...helper};
        }
      });
      await _refresh(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        await _refresh(force: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _stopHelperWork() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final result = _decodeMap(await service.stopHelperWork());
      if (!mounted) {
        return;
      }
      setState(() {
        _lastStopResult = result ?? {'ok': false, 'error': 'Invalid response'};
      });
      await _refresh(force: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openPermissionSettings(String section) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final result = _decodeMap(
        await service.openSystemSettings(section: section),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastPermissionSettingsResult =
            result ??
            {'ok': false, 'section': section, 'error': 'Invalid response'};
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        await _refresh(force: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refresh({bool force = false}) async {
    if (_isLoading && !force) {
      return;
    }
    setState(() => _isLoading = true);
    try {
      final service = ref.read(macosComputerUseServiceProvider);
      final nextHelperStatus = <String, dynamic>{...?_helperStatus};
      for (final raw in [
        await service.getHelperStatus(),
        await service.pingHelper(),
      ]) {
        final decoded = _decodeMap(raw);
        if (decoded != null) {
          nextHelperStatus.addAll(decoded);
        }
      }
      final nextPermissions = _decodeMap(await service.getPermissions());
      if (!mounted) {
        return;
      }
      setState(() {
        _helperStatus = nextHelperStatus;
        if (nextPermissions != null) {
          _permissions = nextPermissions;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openSmokeTest() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ComputerUseDebugPage()),
    ).then((_) {
      if (mounted) {
        _refresh();
      }
    });
  }

  Future<void> _copyDiagnostics() async {
    final diagnostics = _diagnosticsJson();
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Computer-use diagnostics copied.')),
    );
  }

  Future<void> _exportDiagnostics() async {
    try {
      final diagnostics = _diagnosticsJson();
      final path = await exportLocalDiagnostics(
        filePrefix: 'caverno-computer-use-onboarding',
        contents: diagnostics,
      );
      if (!mounted) {
        return;
      }
      setState(() => _lastDiagnosticExportPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Computer-use diagnostics exported to $path')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _lastDiagnosticExportPath = 'Failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export diagnostics: $error')),
      );
    }
  }

  String _diagnosticsJson() {
    return const JsonEncoder.withIndent('  ').convert(_diagnosticsMap());
  }

  Map<String, dynamic> _diagnosticsMap() {
    return MacosComputerUseOnboardingDiagnostics(
      generatedAt: DateTime.now(),
      setupChecklist: _setupChecklist(
        ref.read(macosComputerUseServiceProvider).permissionBackendInfo,
      ),
      onboardingSmokeChecklist: _onboardingSmokeChecklist(),
      onboardingVerification: _onboardingVerification(),
      helperStatus: _helperStatus,
      permissions: _permissions,
      helperIpcProtocol: MacosComputerUseIpc.current.toJson(),
      lastAction: _lastActionLabel(),
      lastResult: {
        'helperStatus': _helperStatus,
        'permissions': _permissions,
        'onboardingVerification': _onboardingVerification(),
        'lastStopResult': _lastStopResult,
        'lastPermissionSettingsResult': _lastPermissionSettingsResult,
      },
      lastDiagnosticExportPath: _lastDiagnosticExportPath,
    ).toJson();
  }

  List<Map<String, dynamic>> _onboardingSmokeChecklist() {
    return [
      {
        'id': 'launch_helper',
        'label': 'Launch Caverno Computer Use',
        'complete':
            _permissionValue('helperInstalled') == true &&
            _permissionValue('helperRunning') == true,
      },
      {
        'id': 'verify_helper_ipc',
        'label': 'Verify helper IPC reachability',
        'complete': _permissionValue('helperReachable') == true,
      },
      {
        'id': 'grant_accessibility',
        'label': 'Grant Accessibility to Caverno Computer Use',
        'complete': _permissionValue('accessibilityGranted') == true,
      },
      {
        'id': 'grant_screen_recording',
        'label':
            'Grant Screen & System Audio Recording to Caverno Computer Use',
        'complete': _permissionValue('screenCaptureGranted') == true,
      },
    ];
  }

  MacosComputerUseSetupChecklist _setupChecklist(
    MacosComputerUseBackendInfo backend,
  ) {
    final snapshot = <String, dynamic>{};
    if (_permissions != null) {
      snapshot.addAll(_permissions!);
    }
    if (_helperStatus != null) {
      snapshot.addAll(_helperStatus!);
    }
    return MacosComputerUseSetupChecklist(
      backend: backend,
      permissions: snapshot.isEmpty
          ? null
          : MacosComputerUsePermissionSnapshot.fromMap(snapshot),
    );
  }

  bool? _permissionValue(String key) {
    final permissions = _permissions;
    final helperStatus = _helperStatus;
    final value = permissions?[key] ?? helperStatus?[key];
    return value is bool ? value : null;
  }

  bool? _helperWorkActive() {
    final value =
        _helperStatus?['audioRecordingActive'] ??
        _permissions?['audioRecordingActive'];
    return value is bool ? value : null;
  }

  Map<String, dynamic>? _onboardingVerification() {
    final value =
        _helperStatus?['onboardingVerification'] ??
        _permissions?['onboardingVerification'];
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String _resultSummary(Map<String, dynamic> result) {
    final ok = result['ok'] == true;
    final code = result['code'];
    final error = result['error'];
    if (ok) {
      final stoppedAudioRecording = result['stoppedAudioRecording'];
      final cancelledInputEvents = result['cancelledInputEvents'];
      return 'ok, audio stopped: $stoppedAudioRecording, input cancelled: $cancelledInputEvents';
    }
    if (code != null || error != null) {
      return '${code ?? 'failed'}: ${error ?? 'Unknown error'}';
    }
    return ok ? 'ok' : 'failed';
  }

  String _permissionActionSummary(Map<String, dynamic> result) {
    final section = result['section'] ?? 'unknown';
    final ok = result['ok'] == true;
    final error = result['error'];
    if (ok) {
      return 'opened $section';
    }
    return 'failed to open $section${error == null ? '' : ': $error'}';
  }

  String _lastActionLabel() {
    if (_lastStopResult != null) {
      return 'Settings stop helper work';
    }
    if (_lastPermissionSettingsResult != null) {
      return 'Settings open permission pane';
    }
    return 'Settings onboarding status';
  }

  Map<String, dynamic>? _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    this.trueText = 'Ready',
    this.falseText = 'Missing',
  });

  final String label;
  final bool value;
  final String trueText;
  final String falseText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = value ? colorScheme.primary : colorScheme.outline;
    return Chip(
      avatar: Icon(
        value ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        size: 18,
        color: color,
      ),
      label: Text('$label: ${value ? trueText : falseText}'),
    );
  }
}

class _VerificationSummary extends StatelessWidget {
  const _VerificationSummary({required this.verification});

  final Map<String, dynamic> verification;

  @override
  Widget build(BuildContext context) {
    final generatedAt = verification['generatedAt'];
    final steps = verification['steps'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          generatedAt is String
              ? 'Last Verify: ${verification['summary'] ?? generatedAt}'
              : 'Last Verify: ${verification['summary'] ?? 'Unknown'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (steps is List) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final step in steps)
                if (step is Map)
                  _StatusChip(
                    label: '${step['label'] ?? step['id'] ?? 'Step'}',
                    value: step['ok'] == true,
                    trueText: 'Done',
                    falseText: '${step['status'] ?? 'Failed'}',
                  ),
            ],
          ),
        ],
      ],
    );
  }
}
