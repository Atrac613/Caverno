import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/logger.dart';

/// Where a saved video ended up, for the message shown afterwards.
enum MessageVideoSaveOutcome {
  /// Written to a location the person chose.
  saved,

  /// Handed to the OS share sheet; where it went is between them and the OS.
  shared,

  /// The person backed out of the dialog.
  cancelled,
}

/// Saving and sharing for the message video viewer.
///
/// Tests inject fakes; production uses a save dialog on desktop and the share
/// sheet on mobile. Both take a path rather than bytes: a video is up to ten
/// megabytes, and there is no reason to hold it in memory to hand it to a
/// dialog that is going to write it to disk anyway.
class MessageVideoIo {
  const MessageVideoIo({this.saveFile, this.shareFile, this.isMobile});

  final Future<String?> Function({
    required String sourcePath,
    required String fileName,
    String? dialogTitle,
  })?
  saveFile;
  final Future<bool> Function({
    required String sourcePath,
    required String mimeType,
  })?
  shareFile;
  final bool Function()? isMobile;

  bool get _mobile => (isMobile ?? defaultIsMobile)();

  Future<MessageVideoSaveOutcome> save({
    required String sourcePath,
    required String fileName,
    required String mimeType,
    String? dialogTitle,
  }) async {
    if (_mobile) {
      final shared = await (shareFile ?? shareVideoWithSystemSheet)(
        sourcePath: sourcePath,
        mimeType: mimeType,
      );
      return shared
          ? MessageVideoSaveOutcome.shared
          : MessageVideoSaveOutcome.cancelled;
    }
    final saved = await (saveFile ?? saveVideoWithFilePicker)(
      sourcePath: sourcePath,
      fileName: fileName,
      dialogTitle: dialogTitle,
    );
    return saved == null || saved.trim().isEmpty
        ? MessageVideoSaveOutcome.cancelled
        : MessageVideoSaveOutcome.saved;
  }
}

bool defaultIsMobile() => Platform.isIOS || Platform.isAndroid;

/// Asks for a destination, then copies the file there.
///
/// Deliberately not `FilePicker.saveFile(bytes: ...)`: passing bytes would mean
/// reading the whole video into memory first, and on desktop the dialog hands
/// back a path we can copy to directly.
Future<String?> saveVideoWithFilePicker({
  required String sourcePath,
  required String fileName,
  String? dialogTitle,
}) async {
  final extension = videoExtensionForName(fileName);
  final destination = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
  );
  if (destination == null || destination.trim().isEmpty) return null;
  await File(sourcePath).copy(destination);
  return destination;
}

Future<bool> shareVideoWithSystemSheet({
  required String sourcePath,
  required String mimeType,
}) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(sourcePath, mimeType: mimeType)]),
    );
    return result.status == ShareResultStatus.success;
  } catch (error) {
    appLog('[MessageVideoIo] Share failed: $error');
    return false;
  }
}

/// The extension a save dialog should offer, taken from the file name.
String videoExtensionForName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return 'mp4';
  return fileName.substring(dot + 1).toLowerCase();
}
