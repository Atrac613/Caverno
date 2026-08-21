import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../settings/presentation/providers/model_list_provider.dart';
import '../providers/onboarding_notifier.dart';
import 'onboarding_scaffold.dart';

/// Picks the default model off the endpoint chosen on the previous step.
///
/// This is the step that keeps a fresh install from opening on a model name the
/// server has never heard of. The list is normally the one the connect step
/// already read while verifying the endpoint; only an endpoint that verified
/// with an empty catalog falls through to [modelListProvider], which speaks the
/// LM Studio / llama.cpp / Ollama fallbacks.
class OnboardingModelStep extends ConsumerWidget {
  const OnboardingModelStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final space = context.space;
    final state = ref.watch(onboardingNotifierProvider);
    final known = state.availableModels;
    final models = known.isNotEmpty
        ? AsyncValue<List<String>>.data(known)
        : ref.watch(
            modelListProvider(
              ModelListConfig(
                baseUrl: state.baseUrl,
                apiKey: state.apiKey,
                selectedModelId: state.selectedModel.isEmpty
                    ? null
                    : state.selectedModel,
              ),
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OnboardingHeading(
          title: 'onboarding.step_model_title'.tr(),
          subtitle: 'onboarding.step_model_body'.tr(),
        ),
        SizedBox(height: space.xxl),
        models.when(
          loading: () => Column(
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: space.lg),
              Text(
                'onboarding.model_loading'.tr(),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          error: (error, _) => Text(
            'onboarding.model_none'.tr(args: [error.toString()]),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          data: (ids) => _ModelList(
            modelIds: ids,
            selected: state.selectedModel,
            onSelect: (id) =>
                ref.read(onboardingNotifierProvider.notifier).selectModel(id),
          ),
        ),
      ],
    );
  }
}

class _ModelList extends StatelessWidget {
  const _ModelList({
    required this.modelIds,
    required this.selected,
    required this.onSelect,
  });

  final List<String> modelIds;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final space = context.space;

    if (modelIds.isEmpty) {
      return Text(
        'onboarding.model_empty'.tr(),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: modelIds.length,
        separatorBuilder: (_, _) => SizedBox(height: space.md),
        itemBuilder: (context, index) {
          final id = modelIds[index];
          return OnboardingChoiceCard(
            key: ValueKey('onboarding-model-$id'),
            selected: selected == id,
            onTap: () => onSelect(id),
            padding: EdgeInsets.symmetric(
              horizontal: space.lg,
              vertical: space.lg,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(id, style: theme.textTheme.bodyMedium),
                ),
                if (selected == id)
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
