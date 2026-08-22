import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../data/encrypted_settings_export_codec.dart';

Future<String?> showSettingsEncryptionPassphraseDialog(
  BuildContext context, {
  required bool confirmPassphrase,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SettingsEncryptionPassphraseDialog(
      confirmPassphrase: confirmPassphrase,
    ),
  );
}

final class _SettingsEncryptionPassphraseDialog extends StatefulWidget {
  const _SettingsEncryptionPassphraseDialog({required this.confirmPassphrase});

  final bool confirmPassphrase;

  @override
  State<_SettingsEncryptionPassphraseDialog> createState() =>
      _SettingsEncryptionPassphraseDialogState();
}

final class _SettingsEncryptionPassphraseDialogState
    extends State<_SettingsEncryptionPassphraseDialog> {
  final _passphraseController = TextEditingController();
  final _confirmationController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.confirmPassphrase
            ? 'settings.encrypted_export_settings'.tr()
            : 'settings.encrypted_import_title'.tr(),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.confirmPassphrase
                  ? 'settings.encrypted_export_warning'.tr()
                  : 'settings.encrypted_import_prompt'.tr(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passphraseController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
              textInputAction: widget.confirmPassphrase
                  ? TextInputAction.next
                  : TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'settings.encryption_passphrase'.tr(),
              ),
            ),
            if (widget.confirmPassphrase) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirmationController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'settings.encryption_confirm_passphrase'.tr(),
                ),
              ),
            ],
            if (_validationError != null) ...[
              const SizedBox(height: 12),
              Text(
                _validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.confirmPassphrase
                ? 'settings.export_encrypted'.tr()
                : 'settings.import_settings'.tr(),
          ),
        ),
      ],
    );
  }

  void _submit() {
    final passphrase = _passphraseController.text;
    try {
      EncryptedSettingsExportCodec.validatePassphrase(passphrase);
    } on FormatException {
      setState(() {
        _validationError = 'settings.encryption_passphrase_requirement'.tr();
      });
      return;
    }
    if (widget.confirmPassphrase &&
        passphrase != _confirmationController.text) {
      setState(() {
        _validationError = 'settings.encryption_passphrase_mismatch'.tr();
      });
      return;
    }
    Navigator.of(context).pop(passphrase);
  }
}
