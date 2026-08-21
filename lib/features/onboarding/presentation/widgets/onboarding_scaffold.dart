import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Measure shared by every onboarding step.
const double onboardingContentMaxWidth = 760;

/// The chrome every onboarding step shares: a centred column, a Back/Next row,
/// and the page-position dots.
///
/// Steps supply only their own content so the frame stays identical as the user
/// moves through it — the thing that makes a wizard feel like one surface
/// rather than a stack of unrelated dialogs.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.stepIndex,
    required this.stepCount,
    required this.child,
    this.onBack,
    this.onNext,
    this.nextLabel,
    this.secondary,
  });

  final int stepIndex;
  final int stepCount;
  final Widget child;

  /// Null hides the Back button (first step).
  final VoidCallback? onBack;

  /// Null disables Next, which is how a step blocks on unmet input.
  final VoidCallback? onNext;

  final String? nextLabel;

  /// Optional extra action rendered under the content, e.g. "restore backup".
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final space = context.space;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: space.xl,
                    vertical: space.xl,
                  ),
                  child: ConstrainedBox(
                    // Wide enough that a full-sentence caption sets on one
                    // line, which is the measure the reference layout uses.
                    constraints: const BoxConstraints(
                      maxWidth: onboardingContentMaxWidth,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: space.xl,
                vertical: space.lg,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: onboardingContentMaxWidth,
                ),
                child: Column(
                  children: [
                    if (secondary != null) ...[
                      secondary!,
                      SizedBox(height: space.lg),
                    ],
                    Row(
                      children: [
                        if (onBack != null)
                          TextButton(
                            key: const ValueKey('onboarding-back'),
                            onPressed: onBack,
                            child: Text('onboarding.back'.tr()),
                          ),
                        const Spacer(),
                        FilledButton.icon(
                          key: const ValueKey('onboarding-next'),
                          onPressed: onNext,
                          icon: const Icon(Icons.keyboard_return, size: 16),
                          label: Text(nextLabel ?? 'onboarding.next'.tr()),
                        ),
                      ],
                    ),
                    SizedBox(height: space.xl),
                    _StepDots(index: stepIndex, count: stepCount),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == index ? colorScheme.primary : colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }
}

/// Step heading used by every page, so titles keep one weight and rhythm.
class OnboardingHeading extends StatelessWidget {
  const OnboardingHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final space = context.space;
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          SizedBox(height: space.md),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// A selectable card used by the language, theme and endpoint steps.
class OnboardingChoiceCard extends StatelessWidget {
  const OnboardingChoiceCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radii = context.radii;
    final space = context.space;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radii.md),
      child: Ink(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(radii.md),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.all(space.lg),
          child: child,
        ),
      ),
    );
  }
}
