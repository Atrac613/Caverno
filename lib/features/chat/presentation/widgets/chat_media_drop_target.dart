import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/utils/logger.dart';
import 'composer_file_picker.dart';

class ChatMediaDropTarget extends StatefulWidget {
  const ChatMediaDropTarget({
    required this.enabled,
    required this.child,
    required this.onImageDropped,
    this.onVideoDropped,
    this.onFileDropped,
    this.videoEnabled = false,
    super.key,
  });

  final bool enabled;
  final Widget child;
  final void Function(Uint8List bytes, String mimeType, String filePath)
  onImageDropped;

  /// Handed the dropped file's path rather than its bytes: a clip is delivered
  /// by reference, so reading it here would buy nothing but a copy in memory.
  final void Function(String filePath, String mimeType)? onVideoDropped;

  /// Handed a dropped document's path, for the extensions
  /// [ComposerFilePicker.acceptsPath] takes — text formats and PDF. Like a
  /// video, it travels by reference: the composer decides whether to inline it
  /// or hand the model the path, and reading it here would prejudge that.
  final void Function(String filePath)? onFileDropped;

  /// Whether the endpoint in use accepts video. A drop is refused with the
  /// usual "not supported" notice when it does not.
  final bool videoEnabled;

  @override
  State<ChatMediaDropTarget> createState() => ChatMediaDropTargetState();
}

class ChatMediaDropTargetState extends State<ChatMediaDropTarget> {
  static const Set<String> _videoDropExtensions = {
    '.mp4',
    '.mov',
    '.webm',
    '.mkv',
    '.m4v',
    '.avi',
  };

  static const Set<String> _imageDropExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
    '.bmp',
  };

  bool _isImageDragActive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) {
        if (!_isImageDragActive) {
          setState(() => _isImageDragActive = true);
        }
      },
      onDragExited: (_) {
        if (_isImageDragActive) {
          setState(() => _isImageDragActive = false);
        }
      },
      onDragDone: (details) {
        unawaited(handleDrop(details.files));
      },
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: widget.enabled && _isImageDragActive ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: Container(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.86,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'message.drop_overlay'.tr(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @visibleForTesting
  Future<void> handleDrop(List<DropItem> items) async {
    if (_isImageDragActive && mounted) {
      setState(() => _isImageDragActive = false);
    }

    if (_videoDropAvailable) {
      final videoItem = _firstDropItem(items, _isVideoDropItem);
      final videoPath = videoItem == null
          ? null
          : _dropItemPathForImageHandling(videoItem);
      if (videoItem != null &&
          videoPath != null &&
          videoPath.trim().isNotEmpty) {
        widget.onVideoDropped!(videoPath, _videoMimeTypeForDropItem(videoItem));
        return;
      }
    }

    final imageItem = _firstDropItem(items, _isImageDropItem);
    if (imageItem == null) {
      // Documents are tried last so an image never loses to a file handler
      // that would also accept it.
      if (widget.onFileDropped != null) {
        final fileItem = _firstDropItem(items, _isFileDropItem);
        final filePath = fileItem == null
            ? null
            : _dropItemPathForImageHandling(fileItem);
        if (filePath != null && filePath.trim().isNotEmpty) {
          widget.onFileDropped!(filePath);
          return;
        }
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('message.drop_unsupported'.tr())),
      );
      return;
    }

    try {
      final bytes = await _readDropItemBytes(imageItem);
      if (!mounted) return;
      widget.onImageDropped(
        bytes,
        _mimeTypeForDropItem(imageItem),
        _dropItemPathForImageHandling(imageItem),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('message.drop_image_failed'.tr())));
      appDebugPrint('Failed to read dropped image: $e');
    }
  }

  bool get _videoDropAvailable =>
      widget.videoEnabled && widget.onVideoDropped != null;

  DropItem? _firstDropItem(
    List<DropItem> items,
    bool Function(DropItem item) matches,
  ) {
    for (final item in items) {
      if (item is DropItemDirectory) {
        continue;
      }
      if (matches(item)) {
        return item;
      }
    }
    return null;
  }

  bool _isVideoDropItem(DropItem item) {
    final mimeType = item.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('video/')) {
      return true;
    }
    final path = _dropItemPathForImageHandling(item).toLowerCase();
    return _videoDropExtensions.any((extension) => path.endsWith(extension));
  }

  String _videoMimeTypeForDropItem(DropItem item) {
    final mimeType = item.mimeType;
    if (mimeType != null && mimeType.toLowerCase().startsWith('video/')) {
      return mimeType;
    }
    final path = _dropItemPathForImageHandling(item).toLowerCase();
    if (path.endsWith('.mov')) return 'video/quicktime';
    if (path.endsWith('.webm')) return 'video/webm';
    if (path.endsWith('.mkv')) return 'video/x-matroska';
    if (path.endsWith('.avi')) return 'video/x-msvideo';
    return 'video/mp4';
  }

  bool _isFileDropItem(DropItem item) =>
      ComposerFilePicker.acceptsPath(_dropItemPathForImageHandling(item));

  bool _isImageDropItem(DropItem item) {
    final mimeType = item.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('image/')) {
      return true;
    }

    final path = _dropItemPathForImageHandling(item).toLowerCase();
    return _imageDropExtensions.any((extension) => path.endsWith(extension));
  }

  Future<Uint8List> _readDropItemBytes(DropItem item) async {
    final bookmark = item.extraAppleBookmark;
    final shouldStartSecurityScope =
        Platform.isMacOS && bookmark != null && bookmark.isNotEmpty;
    var securityScopeStarted = false;

    try {
      if (shouldStartSecurityScope) {
        securityScopeStarted = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
      }
      return item.readAsBytes();
    } finally {
      if (securityScopeStarted && bookmark != null) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  String _dropItemPathForImageHandling(DropItem item) {
    if (item.path.trim().isNotEmpty) {
      return item.path;
    }
    return item.name;
  }

  String _mimeTypeForDropItem(DropItem item) {
    final mimeType = item.mimeType;
    if (mimeType != null && mimeType.toLowerCase().startsWith('image/')) {
      return mimeType;
    }

    final path = _dropItemPathForImageHandling(item).toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.heic')) return 'image/heic';
    if (path.endsWith('.heif')) return 'image/heif';
    if (path.endsWith('.tif') || path.endsWith('.tiff')) return 'image/tiff';
    if (path.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
  }
}
