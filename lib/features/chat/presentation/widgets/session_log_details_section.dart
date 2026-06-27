import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/session_log_details_provider.dart';

class SessionLogDetailsEntry {
  const SessionLogDetailsEntry({
    this.request,
    this.label,
    this.unavailableValue,
    this.icon = Icons.receipt_long_outlined,
  });

  final SessionLogDetailsRequest? request;
  final String? label;
  final String? unavailableValue;
  final IconData icon;
}

class SessionLogDetailsSection extends ConsumerWidget {
  const SessionLogDetailsSection({
    super.key,
    this.title,
    required this.entries,
  });

  final String? title;
  final List<SessionLogDetailsEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final requests = entries
        .map((entry) => entry.request)
        .whereType<SessionLogDetailsRequest>()
        .toList(growable: false);
    final firstRequest = requests.firstOrNull;
    final firstDetailsAsync = firstRequest == null
        ? null
        : ref.watch(sessionLogDetailsProvider(firstRequest));
    final isLoggingDisabled = firstDetailsAsync?.maybeWhen(
      data: (details) => !details.loggingEnabled,
      orElse: () => false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title ?? 'chat.companion_session_log'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: requests.isEmpty
                  ? null
                  : () {
                      for (final request in requests) {
                        ref.invalidate(sessionLogDetailsProvider(request));
                      }
                    },
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'chat.companion_session_log_refresh'.tr(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (isLoggingDisabled == true)
          _SessionLogEmptyText('chat.companion_session_log_disabled'.tr())
        else if (entries.isEmpty)
          _SessionLogEmptyText('chat.companion_session_log_missing'.tr())
        else
          for (var index = 0; index < entries.length; index++) ...[
            _SessionLogEntryView(entry: entries[index]),
            if (index != entries.length - 1) const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _SessionLogEntryView extends ConsumerWidget {
  const _SessionLogEntryView({required this.entry});

  final SessionLogDetailsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = entry.request;
    if (request == null) {
      return _SessionLogInfoRow(
        icon: entry.icon,
        label: entry.label ?? 'chat.companion_session_log'.tr(),
        value:
            entry.unavailableValue ?? 'chat.companion_session_log_missing'.tr(),
        dense: true,
      );
    }

    final detailsAsync = ref.watch(sessionLogDetailsProvider(request));
    return detailsAsync.when(
      loading: () =>
          _SessionLogEmptyText('chat.companion_session_log_loading'.tr()),
      error: (error, stackTrace) => _SessionLogEmptyText(error.toString()),
      data: (details) {
        if (!details.loggingEnabled) {
          return _SessionLogEmptyText(
            'chat.companion_session_log_disabled'.tr(),
          );
        }
        final status = details.exists
            ? details.formattedSize
            : 'chat.companion_session_log_missing'.tr();
        final label = entry.label ?? details.fileName;
        final value = entry.label == null
            ? status
            : '${details.fileName} - $status';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SessionLogInfoRow(
              icon: entry.icon,
              label: label,
              value: value,
              dense: true,
            ),
            const SizedBox(height: 10),
            _SessionLogPathRow(details: details),
          ],
        );
      },
    );
  }
}

class _SessionLogPathRow extends StatelessWidget {
  const _SessionLogPathRow({required this.details});

  final SessionLogFileDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            Icons.folder_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'chat.companion_session_log_path'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                details.path,
                maxLines: 3,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => unawaited(_copyPath(context, details.path)),
          icon: const Icon(Icons.copy_rounded, size: 18),
          tooltip: 'chat.companion_session_log_copy_path'.tr(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Future<void> _copyPath(BuildContext context, String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('chat.companion_session_log_copied'.tr())),
    );
  }
}

class _SessionLogInfoRow extends StatelessWidget {
  const _SessionLogInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Icon(
            icon,
            size: dense ? 16 : 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionLogEmptyText extends StatelessWidget {
  const _SessionLogEmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
