import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/types/app_theme_preference.dart';
import 'onboarding_scaffold.dart';

class OnboardingThemeStep extends StatelessWidget {
  const OnboardingThemeStep({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final AppThemePreference selected;
  final ValueChanged<AppThemePreference> onSelect;

  @override
  Widget build(BuildContext context) {
    final space = context.space;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OnboardingHeading(title: 'onboarding.step_theme_title'.tr()),
        SizedBox(height: space.xxl),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final preference in AppThemePreference.values) ...[
              Flexible(
                child: _ThemeOption(
                  preference: preference,
                  selected: selected == preference,
                  onTap: () => onSelect(preference),
                ),
              ),
              if (preference != AppThemePreference.values.last)
                SizedBox(width: space.lg),
            ],
          ],
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.preference,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreference preference;
  final bool selected;
  final VoidCallback onTap;

  static const Map<AppThemePreference, String> _labelKeys = {
    AppThemePreference.system: 'onboarding.theme_system',
    AppThemePreference.dark: 'onboarding.theme_dark',
    AppThemePreference.light: 'onboarding.theme_light',
  };

  @override
  Widget build(BuildContext context) {
    final space = context.space;
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = switch (preference) {
      AppThemePreference.system => platformBrightness,
      AppThemePreference.dark => Brightness.dark,
      AppThemePreference.light => Brightness.light,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OnboardingChoiceCard(
          key: ValueKey('onboarding-theme-${preference.name}'),
          selected: selected,
          onTap: onTap,
          padding: EdgeInsets.all(space.md),
          child: _ThemePreview(brightness: brightness),
        ),
        SizedBox(height: space.md),
        Text(
          _labelKeys[preference]!.tr(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// A miniature of the editor chrome, painted from the real theme so the swatch
/// cannot drift away from what the app actually looks like.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final theme = brightness == Brightness.dark
        ? AppTheme.dark
        : AppTheme.light;
    final scheme = theme.colorScheme;
    final radii = context.radii;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radii.sm),
      child: SizedBox(
        width: 132,
        height: 88,
        child: Row(
          children: [
            Container(
              width: 38,
              color: scheme.surfaceContainerHigh,
              child: _Lines(color: scheme.onSurfaceVariant, count: 4),
            ),
            Expanded(
              child: Container(
                color: scheme.surfaceContainerLowest,
                child: _Lines(color: scheme.primary, count: 5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.color, required this.count});

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Container(
                height: 4,
                width: 46.0 - (i % 3) * 12,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.55 - (i % 3) * 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
