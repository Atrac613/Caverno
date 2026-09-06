import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({
    super.key,
    this.title,
    this.hint,
    this.allowManualEntry = false,
  });

  final String? title;
  final String? hint;

  /// Offers a paste-or-type alternative to the camera.
  ///
  /// Off by default, and each call site opts in separately, because scanning a
  /// QR is a proof of proximity — the person can see the screen showing it —
  /// and typing one is not. Settings import deliberately never opts in: SA-02
  /// is about what an imported configuration can do, and this would be a
  /// second way to hand it one.
  ///
  /// The Remote Coding pairing call site opts in behind
  /// `RemoteCodingDebugPairingPolicy`, which is debug-only. See its doc for
  /// why a debug build is the whole of the allowance.
  final bool allowManualEntry;

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Returns a hand-entered code as if it had been scanned.
  ///
  /// The same string the QR encodes, so it rejoins the scan path at the
  /// caller and is parsed by the same decoder. Nothing here interprets it.
  Future<void> _enterManually() async {
    final controller = TextEditingController();
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    controller.text = clipboard?.text?.trim() ?? '';
    if (!mounted) {
      controller.dispose();
      return;
    }
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter code manually'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'Paste the pairing payload',
            helperText: 'Debug builds only. Prefilled from the clipboard.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Use code'),
          ),
        ],
      ),
    );
    controller.dispose();
    final code = entered?.trim() ?? '';
    if (code.isEmpty || !mounted || _isScanned) return;
    setState(() => _isScanned = true);
    await _controller.stop();
    if (!mounted) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'settings.qr_scan_title'.tr()),
        actions: [
          if (widget.allowManualEntry)
            IconButton(
              icon: const Icon(Icons.content_paste),
              tooltip: 'Enter code manually (debug)',
              onPressed: _enterManually,
            ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_isScanned) return;
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  setState(() => _isScanned = true);
                  _controller.stop();
                  Navigator.of(context).pop(barcode.rawValue);
                  break;
                }
              }
            },
          ),
          // Overlay
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.hint ?? 'settings.qr_scan_hint'.tr(),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
