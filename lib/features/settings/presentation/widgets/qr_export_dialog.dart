import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrExportDialog extends StatelessWidget {
  const QrExportDialog({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('settings.qr_export_title'.tr()),
      content: SizedBox(
        width: 250,
        height: 250,
        child: Center(
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
          child: Text('common.cancel'.tr()),
        ),
      ],
    );
  }
}
