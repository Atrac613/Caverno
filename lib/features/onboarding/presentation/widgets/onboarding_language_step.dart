import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import 'onboarding_scaffold.dart';

/// Language options, in the same vocabulary `settings.language` persists.
/// Labels reuse the settings page's keys rather than duplicating the wording.
const List<({String value, String labelKey})> onboardingLanguageOptions = [
  (value: 'system', labelKey: 'settings.language_system'),
  (value: 'ja', labelKey: 'settings.language_ja'),
  (value: 'en', labelKey: 'settings.language_en'),
];

class OnboardingLanguageStep extends StatelessWidget {
  const OnboardingLanguageStep({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final space = context.space;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OnboardingHeading(
          title: 'onboarding.step_language_title'.tr(),
          subtitle: 'onboarding.step_language_body'.tr(),
        ),
        SizedBox(height: space.xxl),
        for (final option in onboardingLanguageOptions) ...[
          OnboardingChoiceCard(
            key: ValueKey('onboarding-language-${option.value}'),
            selected: selected == option.value,
            onTap: () => onSelect(option.value),
            child: Row(
              children: [
                Expanded(child: Text(option.labelKey.tr())),
                if (selected == option.value)
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
          SizedBox(height: space.lg),
        ],
      ],
    );
  }
}
