import 'dart:async';

import 'package:super_clipboard/super_clipboard.dart';

import '../../../../core/utils/logger.dart';
import 'composer_file_picker.dart';

/// Serializes composer file prepares so Send can wait for an in-flight drop.
class ComposerFilePrepareGate {
  Future<void>? _inFlight;
  int _epoch = 0;

  Future<void> wait() async {
    final pending = _inFlight;
    if (pending != null) await pending;
  }

  Future<void> enqueue(Future<void> Function(int epoch) work) {
    final epoch = ++_epoch;
    final future = work(epoch);
    _inFlight = future;
    return future;
  }

  bool isCurrent(int epoch) => epoch == _epoch;
}

/// Reads a PDF from the clipboard. `null` means the clipboard had no PDF.
Future<bool?> pasteClipboardPdf({
  required DataReader reader,
  required ComposerFilePicker picker,
  required void Function(ComposerFileChoice choice) apply,
}) async {
  if (!reader.canProvide(Formats.pdf)) return null;

  final completer = Completer<bool>();
  void finish(bool consumed) {
    if (!completer.isCompleted) completer.complete(consumed);
  }

  final progress = reader.getFile(
    Formats.pdf,
    (file) async {
      try {
        final choice = await picker.fromBytes(
          bytes: await file.readAll(),
          originalName: file.fileName ?? 'clipboard.pdf',
        );
        apply(choice);
        finish(choice.file != null);
      } catch (e) {
        appDebugPrint('Failed to read clipboard PDF: $e');
        finish(false);
      }
    },
    onError: (error) {
      appDebugPrint('Failed to read clipboard PDF: $error');
      finish(false);
    },
  );
  if (progress == null) return false;
  return completer.future;
}
