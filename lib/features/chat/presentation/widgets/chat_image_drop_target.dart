import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ChatImageDropTarget extends StatefulWidget {
  const ChatImageDropTarget({
    required this.enabled,
    required this.child,
    required this.onImageDropped,
    super.key,
  });

  final bool enabled;
  final Widget child;
  final void Function(Uint8List bytes, String mimeType, String filePath)
  onImageDropped;

  @override
  State<ChatImageDropTarget> createState() => ChatImageDropTargetState();
}

class ChatImageDropTargetState extends State<ChatImageDropTarget> {
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
                            'message.drop_image_overlay'.tr(),
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

    final imageItem = _firstImageDropItem(items);
    if (imageItem == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('message.drop_image_unsupported'.tr())),
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
      debugPrint('Failed to read dropped image: $e');
    }
  }

  DropItem? _firstImageDropItem(List<DropItem> items) {
    for (final item in items) {
      if (item is DropItemDirectory) {
        continue;
      }
      if (_isImageDropItem(item)) {
        return item;
      }
    }
    return null;
  }

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
