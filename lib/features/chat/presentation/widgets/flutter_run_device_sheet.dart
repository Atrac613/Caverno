import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/flutter_run_device.dart';

/// Device picker for `flutter run`, shaped like the ask-user-question sheet so
/// a choice the app asks for always arrives the same way.
///
/// Only shown when the choice is real: a single device starts without asking.
class FlutterRunDeviceSheet extends StatelessWidget {
  const FlutterRunDeviceSheet({super.key, required this.devices});

  final List<FlutterRunDevice> devices;

  static Future<FlutterRunDevice?> show(
    BuildContext context,
    List<FlutterRunDevice> devices,
  ) {
    return showModalBottomSheet<FlutterRunDevice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FlutterRunDeviceSheet(devices: devices),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'chat.flutter_run_pick_device'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: devices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (itemContext, index) {
                  final device = devices[index];
                  return _DeviceRow(
                    device: device,
                    onSelected: device.isSupported
                        ? () => Navigator.of(itemContext).pop(device)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onSelected});

  final FlutterRunDevice device;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      device.id,
      ?device.sdk,
      if (!device.isSupported) 'chat.flutter_run_device_unsupported'.tr(),
    ].join(' • ');

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: onSelected == null ? 0.3 : 1,
      ),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('flutter-run-device-${device.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                device.isEmulator
                    ? Icons.phone_iphone_outlined
                    : Icons.desktop_windows_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
