import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/logger.dart';

/// What happened when the person asked to see an attachment.
enum AttachmentOpenResult {
  opened,

  /// The retention sweep, or the person, removed the copy this message kept.
  missing,

  /// The platform refused, or there is no application registered for it.
  failed,
}

/// Hands a stored attachment to whatever the platform uses to view it.
///
/// The app cannot render a PDF page itself — the extractor is text-only, and a
/// renderer would mean a PDFium binary on five platforms — so the document is
/// shown by the viewer the person already has: Preview on macOS, the default
/// handler on Windows and Linux, and the share sheet on a phone, which is the
/// only route to another app there.
Future<AttachmentOpenResult> openAttachmentWithPlatformViewer({
  required String path,
  String? mimeType,
}) async {
  if (path.trim().isEmpty) return AttachmentOpenResult.missing;
  if (!File(path).existsSync()) return AttachmentOpenResult.missing;

  try {
    if (Platform.isIOS || Platform.isAndroid) {
      final result = await SharePlus.instance.share(
        ShareParams(files: [XFile(path, mimeType: mimeType)]),
      );
      // A dismissed sheet is not a failure: the person looked and backed out.
      return result.status == ShareResultStatus.unavailable
          ? AttachmentOpenResult.failed
          : AttachmentOpenResult.opened;
    }
    final launched = await launchUrl(Uri.file(path));
    return launched ? AttachmentOpenResult.opened : AttachmentOpenResult.failed;
  } catch (error) {
    appLog('[MessageAttachmentIo] Failed to open $path: $error');
    return AttachmentOpenResult.failed;
  }
}
