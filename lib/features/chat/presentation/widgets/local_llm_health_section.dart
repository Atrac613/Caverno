import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/local_llm_health.dart';
import '../../../settings/presentation/providers/local_llm_health_provider.dart';
import '../../../settings/presentation/providers/local_model_lifecycle_provider.dart';

/// Liveness of the registered local LLM endpoints, with what each has loaded.
///
/// Lives in the companion panel because that is where a turn is watched: when
/// an answer stalls, "the server is down" and "the model I selected is not
/// loaded" are the first two things worth ruling out, and both were previously
/// only visible by opening Settings.
class LocalLlmHealthSection extends ConsumerStatefulWidget {
  const LocalLlmHealthSection({super.key});

  @override
  ConsumerState<LocalLlmHealthSection> createState() =>
      _LocalLlmHealthSectionState();
}

class _LocalLlmHealthSectionState extends ConsumerState<LocalLlmHealthSection> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Owned by the panel so it stops with it: a server that went down while
    // the panel was closed is re-checked when it opens, not continuously.
    _ticker = Timer.periodic(
      localLlmHealthRefreshInterval,
      (_) => refreshLocalLlmHealth(ref),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endpoints = ref.watch(localLlmHealthEndpointsProvider);
    if (endpoints.isEmpty) {
      return _EmptyNote(text: 'chat.local_llm_none_registered'.tr());
    }
    return Column(
      key: const ValueKey('local-llm-health-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        for (final endpoint in endpoints)
          _LocalLlmHealthTile(
            key: ValueKey(endpoint.baseUrl),
            endpoint: endpoint,
          ),
      ],
    );
  }
}

/// Invalidates every watched endpoint so one tap re-checks the whole panel.
void refreshLocalLlmHealth(WidgetRef ref) {
  for (final endpoint in ref.read(localLlmHealthEndpointsProvider)) {
    ref.invalidate(localLlmHealthProvider(endpoint));
  }
}

class _LocalLlmHealthTile extends ConsumerWidget {
  const _LocalLlmHealthTile({super.key, required this.endpoint});

  final LocalModelLifecycleEndpointConfig endpoint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(localLlmHealthProvider(endpoint));
    final snapshot = async.value;
    // A refresh keeps the previous answer on screen instead of blanking the
    // row: the old state is still the best available evidence until the new
    // check lands.
    final isChecking = async.isLoading && snapshot == null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusDot(snapshot: snapshot, isChecking: isChecking),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _title(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (endpoint.isPrimary)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      'chat.local_llm_primary'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              endpoint.baseUrl,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            _ModelLine(snapshot: snapshot, isChecking: isChecking),
          ],
        ),
      ),
    );
  }

  String _title() {
    final label = endpoint.label.trim();
    if (label.isNotEmpty) return label;
    final host = Uri.tryParse(endpoint.baseUrl)?.host ?? '';
    return host.isEmpty ? endpoint.baseUrl : host;
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.snapshot, required this.isChecking});

  final LocalLlmHealthSnapshot? snapshot;
  final bool isChecking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isChecking) {
      return SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final online = snapshot?.isOnline ?? false;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online
            ? theme.colorScheme.primary
            : theme.colorScheme.error.withValues(alpha: 0.8),
      ),
    );
  }
}

class _ModelLine extends StatelessWidget {
  const _ModelLine({required this.snapshot, required this.isChecking});

  final LocalLlmHealthSnapshot? snapshot;
  final bool isChecking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = snapshot;
    if (isChecking || current == null) {
      return _Caption(text: 'chat.local_llm_checking'.tr());
    }
    if (!current.isOnline) {
      return _Caption(
        text: current.detail?.isNotEmpty ?? false
            ? '${'chat.local_llm_offline'.tr()} — ${current.detail}'
            : 'chat.local_llm_offline'.tr(),
        color: theme.colorScheme.error,
      );
    }
    if (!current.hasModels) {
      return _Caption(text: 'chat.local_llm_no_models'.tr());
    }

    final isAdvertised =
        current.modelEvidence == LocalLlmModelEvidence.advertised;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Caption(
          text: isAdvertised
              ? 'chat.local_llm_advertised_models'.tr()
              : 'chat.local_llm_loaded_models'.tr(),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final model in current.modelIds)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(model, style: theme.textTheme.labelSmall),
              ),
          ],
        ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return _Caption(text: text);
  }
}
