import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Maximum byte length for QR code data (binary mode capacity).
const _kQrMaxBytes = 2953;

class QrExportDialog extends StatelessWidget {
  const QrExportDialog({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final isOversized = data.length > _kQrMaxBytes;

    return AlertDialog(
      title: Text('settings.qr_export_title'.tr()),
      content: SizedBox(
        width: 250,
        height: isOversized ? null : 250,
        child: isOversized
            ? Text(
                'settings.qr_data_too_large'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            : Center(
                child: QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  size: 250.0,
                  backgroundColor: Colors.white,
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.close'.tr()),
        ),
      ],
    );
  }
}
