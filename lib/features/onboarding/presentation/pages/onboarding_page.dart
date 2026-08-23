import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/types/app_theme_preference.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../../settings/presentation/widgets/settings_encryption_passphrase_dialog.dart';
import '../providers/onboarding_notifier.dart';
import '../widgets/onboarding_connect_step.dart';
import '../widgets/onboarding_language_step.dart';
import '../widgets/onboarding_model_step.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/onboarding_theme_step.dart';
import '../widgets/onboarding_welcome_step.dart';

/// First-run setup. Shown instead of the main window until every step is done.
///
/// Language and theme are written through immediately so the wizard itself
/// changes under the user — the choice is its own preview. The connection is
/// held in [OnboardingNotifier] and persisted only at the end, so abandoning
/// the wizard leaves no half-configured endpoint behind.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  bool _importing = false;
  bool _finishing = false;
  String? _importError;

  Future<void> _importSettings() async {
    setState(() {
      _importing = true;
      _importError = null;
    });
    try {
      final imported = await ref
          .read(settingsNotifierProvider.notifier)
          .importSettings(
            requestEncryptedPassphrase: () {
              if (!mounted) return Future<String?>.value();
              return showSettingsEncryptionPassphraseDialog(
                context,
                confirmPassphrase: false,
              );
            },
          );
      if (!mounted) return;
      setState(() => _importing = false);
      if (imported) {
        ref.read(onboardingNotifierProvider.notifier).skipToDone();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importError = 'settings.import_error'.tr(args: [error.toString()]);
      });
    }
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await ref.read(onboardingNotifierProvider.notifier).complete();
    // No navigation here: main.dart swaps `home` once onboardingCompleted flips,
    // so completion has exactly one owner.
  }

  void _advance() {
    if (_finishing) return;
    final state = ref.read(onboardingNotifierProvider);
    if (!state.canAdvance) return;
    if (state.step == OnboardingStep.done) {
      unawaited(_finish());
      return;
    }
    ref.read(onboardingNotifierProvider.notifier).next();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingNotifierProvider);
    final settings = ref.watch(settingsNotifierProvider);
    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    final steps = OnboardingStep.values;
    final index = steps.indexOf(state.step);
    final isLast = state.step == OnboardingStep.done;

    final child = switch (state.step) {
      OnboardingStep.welcome => OnboardingWelcomeStep(
        importing: _importing,
        errorText: _importError,
        onImport: _importSettings,
      ),
      OnboardingStep.language => OnboardingLanguageStep(
        selected: settings.language,
        onSelect: settingsNotifier.updateLanguage,
      ),
      OnboardingStep.theme => OnboardingThemeStep(
        selected: settings.themePreference,
        onSelect: (AppThemePreference preference) =>
            settingsNotifier.updateThemePreference(preference),
      ),
      OnboardingStep.connect => const OnboardingConnectStep(),
      OnboardingStep.model => const OnboardingModelStep(),
      OnboardingStep.done => _OnboardingDoneStep(restored: state.restored),
    };

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _advance,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _advance,
      },
      child: FocusScope(
        autofocus: true,
        child: OnboardingScaffold(
          stepIndex: index,
          stepCount: steps.length,
          onBack: (index == 0 || state.restored)
              ? null
              : ref.read(onboardingNotifierProvider.notifier).back,
          onNext: (!state.canAdvance || _finishing) ? null : _advance,
          nextLabel: isLast ? 'onboarding.finish'.tr() : null,
          child: child,
        ),
      ),
    );
  }
}

class _OnboardingDoneStep extends StatelessWidget {
  const _OnboardingDoneStep({required this.restored});

  final bool restored;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final space = context.space;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        SizedBox(height: space.xxl),
        OnboardingHeading(
          title: 'onboarding.step_done_title'.tr(),
          subtitle: restored
              ? 'onboarding.step_done_restored_body'.tr()
              : 'onboarding.step_done_body'.tr(),
        ),
      ],
    );
  }
}
