import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/logger.dart';
import 'message_image_io.dart';

const Key kMessageImageViewerKey = Key('message-image-viewer');

Future<void> showMessageImageViewer({
  required BuildContext context,
  required Uint8List previewBytes,
  String? previewMimeType,
  String? originalImagePath,
  String? originalMimeType,
  String? suggestedFileName,
  MessageImageIo io = const MessageImageIo(),
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'message.close_image_viewer'.tr(),
    barrierColor: Colors.black.withValues(alpha: 0.92),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return MessageImageViewer(
        previewBytes: previewBytes,
        previewMimeType: previewMimeType,
        originalImagePath: originalImagePath,
        originalMimeType: originalMimeType,
        suggestedFileName: suggestedFileName,
        io: io,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

class MessageImageViewer extends StatefulWidget {
  const MessageImageViewer({
    super.key,
    required this.previewBytes,
    this.previewMimeType,
    this.originalImagePath,
    this.originalMimeType,
    this.suggestedFileName,
    this.io = const MessageImageIo(),
  });

  final Uint8List previewBytes;
  final String? previewMimeType;
  final String? originalImagePath;
  final String? originalMimeType;
  final String? suggestedFileName;
  final MessageImageIo io;

  @override
  State<MessageImageViewer> createState() => _MessageImageViewerState();
}

class _MessageImageViewerState extends State<MessageImageViewer> {
  final _transformationController = TransformationController();
  late Uint8List _bytes;
  late String _mimeType;
  TapDownDetails? _doubleTapDetails;
  bool _copied = false;
  bool _busy = false;
  int _copyFeedbackToken = 0;

  @override
  void initState() {
    super.initState();
    _bytes = widget.previewBytes;
    _mimeType = _firstNonEmptyMime([
      widget.previewMimeType,
      widget.originalMimeType,
    ]);
    _loadOriginalIfNeeded();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: kMessageImageViewerKey,
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black.withValues(alpha: 0.72),
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              tooltip: 'message.close_image_viewer'.tr(),
              icon: const Icon(Icons.close),
              onPressed: _close,
            ),
            actions: [
              IconButton(
                tooltip: 'message.copy_image'.tr(),
                onPressed: _busy ? null : _copy,
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.content_copy_outlined,
                ),
              ),
              IconButton(
                tooltip: 'message.download_image'.tr(),
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.download_outlined),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onDoubleTapDown: (details) => _doubleTapDetails = details,
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1,
                  maxScale: 8,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: Image.memory(
                      _bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 48,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _loadOriginalIfNeeded() async {
    final path = widget.originalImagePath?.trim();
    if (path == null || path.isEmpty) {
      return;
    }
    try {
      final bytes = await widget.io.readOriginal(path);
      if (!mounted || bytes == null || bytes.isEmpty) {
        return;
      }
      setState(() {
        _bytes = bytes;
        _mimeType = _firstNonEmptyMime([widget.originalMimeType, _mimeType]);
      });
    } catch (error) {
      appLog('[MessageImageViewer] Failed to load original image: $error');
    }
  }

  Future<void> _copy() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.io.copy(_bytes, _mimeType);
      if (!mounted) {
        return;
      }
      final token = ++_copyFeedbackToken;
      setState(() {
        _busy = false;
        _copied = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted || token != _copyFeedbackToken) {
        return;
      }
      setState(() => _copied = false);
    } catch (error) {
      appLog('[MessageImageViewer] Copy failed: $error');
      _showSnack('message.image_copy_failed'.tr());
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _download() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final savedPath = await widget.io.save(
        bytes: _bytes,
        fileName:
            widget.suggestedFileName ??
            suggestedMessageImageFileName(
              originalImagePath: widget.originalImagePath,
              mimeType: _mimeType,
            ),
        mimeType: _mimeType,
        dialogTitle: 'message.download_image'.tr(),
      );
      if (!mounted || savedPath == null || savedPath.trim().isEmpty) {
        return;
      }
      _showSnack('message.image_saved'.tr());
    } catch (error) {
      appLog('[MessageImageViewer] Save failed: $error');
      _showSnack('message.image_save_failed'.tr());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _handleDoubleTap() {
    final details = _doubleTapDetails;
    if (details == null) {
      return;
    }
    if (!_transformationController.value.isIdentity()) {
      _transformationController.value = Matrix4.identity();
      return;
    }
    const zoom = 2.5;
    final position = details.localPosition;
    _transformationController.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (zoom - 1),
        -position.dy * (zoom - 1),
        0,
        1,
      )
      ..scaleByDouble(zoom, zoom, zoom, 1);
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _firstNonEmptyMime(List<String?> candidates) {
    for (final candidate in candidates) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return 'image/png';
  }
}
