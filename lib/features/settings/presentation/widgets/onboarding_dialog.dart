import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_notifier.dart';

Future<void> showOnboardingDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const OnboardingDialog(),
  );
}

class OnboardingDialog extends ConsumerStatefulWidget {
  const OnboardingDialog({super.key});

  @override
  ConsumerState<OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends ConsumerState<OnboardingDialog> {
  bool _isImporting = false;
  String? _errorText;

  Future<void> _startFresh() async {
    await ref.read(settingsNotifierProvider.notifier).completeOnboarding();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _importSettings() async {
    setState(() {
      _isImporting = true;
      _errorText = null;
    });

    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final navigator = Navigator.of(context);
      final success = await ref
          .read(settingsNotifierProvider.notifier)
          .importSettings();
      if (!mounted) {
        return;
      }
      if (success) {
        await ref.read(settingsNotifierProvider.notifier).completeOnboarding();
        navigator.pop();
        messenger?.showSnackBar(
          SnackBar(content: Text('settings.import_done'.tr())),
        );
        return;
      }
      setState(() {
        _isImporting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isImporting = false;
        _errorText = 'settings.import_error'.tr(args: [error.toString()]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      icon: Icon(
        Icons.waving_hand_outlined,
        color: colorScheme.primary,
        size: 36,
      ),
      title: Text('onboarding.title'.tr(), textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'onboarding.message'.tr(),
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _OnboardingInfoRow(
                icon: Icons.settings_input_component_outlined,
                title: 'onboarding.connect_title'.tr(),
                body: 'onboarding.connect_body'.tr(),
              ),
              const SizedBox(height: 12),
              _OnboardingInfoRow(
                icon: Icons.chat_bubble_outline,
                title: 'onboarding.chat_title'.tr(),
                body: 'onboarding.chat_body'.tr(),
              ),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.restore_page_outlined,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'onboarding.restore_title'.tr(),
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'onboarding.restore_body'.tr(),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : _startFresh,
          child: Text('onboarding.start_fresh'.tr()),
        ),
        FilledButton.icon(
          onPressed: _isImporting ? null : _importSettings,
          icon: _isImporting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file_outlined),
          label: Text('onboarding.import_settings'.tr()),
        ),
      ],
    );
  }
}

class _OnboardingInfoRow extends StatelessWidget {
  const _OnboardingInfoRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(body, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
