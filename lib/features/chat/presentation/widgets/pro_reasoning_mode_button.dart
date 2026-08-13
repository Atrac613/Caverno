import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';

class ProReasoningModeButton extends ConsumerWidget {
  const ProReasoningModeButton({super.key, required this.enabled});

  static const _offValue = 'off';

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsNotifierProvider);
    final selectedValue = settings.proReasoningEnabled
        ? settings.proReasoningDepth.name
        : _offValue;
    final depthLabel = settings.proReasoningEnabled
        ? _depthLabel(settings.proReasoningDepth)
        : 'message.pro_reasoning_off'.tr();

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: PopupMenuButton<String>(
        key: const ValueKey('pro-reasoning-mode-button'),
        enabled: enabled,
        tooltip: 'message.pro_reasoning_tooltip'.tr(
          namedArgs: {'value': depthLabel},
        ),
        onSelected: (value) async {
          final notifier = ref.read(settingsNotifierProvider.notifier);
          if (value == _offValue) {
            await notifier.updateProReasoningEnabled(false);
            return;
          }
          final depth = ProReasoningDepth.values.firstWhere(
            (candidate) => candidate.name == value,
          );
          await notifier.updateProReasoningDepth(depth);
          await notifier.updateProReasoningEnabled(true);
        },
        itemBuilder: (context) => [
          CheckedPopupMenuItem<String>(
            value: _offValue,
            checked: selectedValue == _offValue,
            child: Text('message.pro_reasoning_off'.tr()),
          ),
          for (final depth in ProReasoningDepth.values)
            CheckedPopupMenuItem<String>(
              value: depth.name,
              checked: selectedValue == depth.name,
              child: Text(_depthLabel(depth)),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: settings.proReasoningEnabled
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                settings.proReasoningEnabled
                    ? 'message.pro_reasoning_active'.tr(
                        namedArgs: {'depth': depthLabel},
                      )
                    : 'message.pro_reasoning'.tr(),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  String _depthLabel(ProReasoningDepth depth) => switch (depth) {
    ProReasoningDepth.standard => 'message.pro_reasoning_standard'.tr(),
    ProReasoningDepth.deep => 'message.pro_reasoning_deep'.tr(),
    ProReasoningDepth.max => 'message.pro_reasoning_max'.tr(),
  };
}
