import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import 'onboarding_scaffold.dart';

/// First page: identity and the one escape hatch (restore a backup).
class OnboardingWelcomeStep extends StatelessWidget {
  const OnboardingWelcomeStep({
    super.key,
    required this.importing,
    required this.errorText,
    required this.onImport,
  });

  final bool importing;
  final String? errorText;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final space = context.space;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlowingMark(color: colorScheme.primary),
        SizedBox(height: space.xxl),
        OnboardingHeading(
          title: 'onboarding.title'.tr(),
          subtitle: 'onboarding.message'.tr(),
        ),
        SizedBox(height: space.xxl),
        OutlinedButton.icon(
          key: const ValueKey('onboarding-import'),
          onPressed: importing ? null : onImport,
          icon: importing
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_file_outlined, size: 16),
          label: Text('onboarding.import_settings'.tr()),
        ),
        SizedBox(height: space.md),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'onboarding.restore_body'.tr(),
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (errorText != null) ...[
          SizedBox(height: space.lg),
          Text(
            errorText!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
      ],
    );
  }
}

/// The app mark over a soft radial wash — a gradient rather than an asset, so
/// it costs nothing to ship and picks up the accent colour from the theme.
class _GlowingMark extends StatelessWidget {
  const _GlowingMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
        ),
      ),
      child: Center(
        child: Icon(Icons.hub_outlined, size: 64, color: color),
      ),
    );
  }
}
