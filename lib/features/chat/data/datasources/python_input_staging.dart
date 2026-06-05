import 'dart:convert';
import 'dart:io';

import '../../../../core/utils/logger.dart';

/// A staged working directory plus the attachment files placed inside it for a
/// `run_python_script` job.
class StagedPythonInputs {
  const StagedPythonInputs({
    required this.workingDirectory,
    required this.inputs,
  });

  final String workingDirectory;

  /// Each entry: `{name, path, mime}` — the shape the worker expects.
  final List<Map<String, dynamic>> inputs;
}

/// Stages chat attachments onto disk so a generated Python script can reach
/// them via the injected `caverno.inputs` helper.
class PythonInputStaging {
  PythonInputStaging._();

  /// Creates a fresh per-run working directory and, when the triggering
  /// message carried an image, writes it there as `attachment_0.<ext>`.
  static Future<StagedPythonInputs> stage({
    String? imageBase64,
    String? imageMimeType,
  }) async {
    final runDir = await Directory.systemTemp.createTemp('caverno_python_');
    final inputs = <Map<String, dynamic>>[];

    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(imageBase64);
        final name = 'attachment_0${_extensionForMime(imageMimeType)}';
        final file = File('${runDir.path}/$name');
        await file.writeAsBytes(bytes);
        inputs.add({'name': name, 'path': file.path, 'mime': imageMimeType});
      } catch (error) {
        appLog('[python] failed to stage attachment: $error');
      }
    }

    return StagedPythonInputs(workingDirectory: runDir.path, inputs: inputs);
  }

  static String _extensionForMime(String? mime) {
    switch (mime) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/gif':
        return '.gif';
      case 'image/webp':
        return '.webp';
      case 'image/heic':
        return '.heic';
      case 'image/heif':
        return '.heif';
      case 'image/bmp':
        return '.bmp';
      case 'image/tiff':
        return '.tiff';
      default:
        return '';
    }
  }
}
