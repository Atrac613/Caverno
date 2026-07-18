import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ComputerUseDebugImageSnapshot {
  const ComputerUseDebugImageSnapshot({
    required this.title,
    required this.base64,
    required this.width,
    required this.height,
    required this.mimeType,
  });

  final String title;
  final String base64;
  final int width;
  final int height;
  final String mimeType;
}

class ComputerUseDebugImagePoint {
  const ComputerUseDebugImagePoint(this.x, this.y);

  final double x;
  final double y;
}

class ComputerUseDebugImagePreview extends StatefulWidget {
  const ComputerUseDebugImagePreview({
    super.key,
    required this.snapshot,
    required this.active,
    required this.tapAreaKey,
    required this.onPointSelected,
  });

  final ComputerUseDebugImageSnapshot snapshot;
  final bool active;
  final Key tapAreaKey;
  final ValueChanged<ComputerUseDebugImagePoint>? onPointSelected;

  @override
  State<ComputerUseDebugImagePreview> createState() =>
      _ComputerUseDebugImagePreviewState();
}

class _ComputerUseDebugImagePreviewState
    extends State<ComputerUseDebugImagePreview> {
  final _transformationController = TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeBytes();
    if (bytes == null) {
      return const Text('Failed to decode image payload.');
    }
    final aspectRatio = widget.snapshot.width > 0 && widget.snapshot.height > 0
        ? widget.snapshot.width / widget.snapshot.height
        : 16 / 9;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.snapshot.title} (${widget.snapshot.width}x${widget.snapshot.height}, ${widget.snapshot.mimeType})',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).dividerColor,
                width: 2,
              ),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      key: widget.tapAreaKey,
                      behavior: HitTestBehavior.opaque,
                      onTapDown: widget.onPointSelected == null
                          ? null
                          : (details) => _handleTap(
                              details.localPosition,
                              constraints.biggest,
                            ),
                      child: InteractiveViewer(
                        transformationController: _transformationController,
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) => Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Failed to decode image: $error'),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleTap(Offset viewportPosition, Size viewportSize) {
    if (viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        widget.snapshot.width <= 0 ||
        widget.snapshot.height <= 0) {
      return;
    }

    final scenePosition = _transformationController.toScene(viewportPosition);
    final x = scenePosition.dx.clamp(0, viewportSize.width).toDouble();
    final y = scenePosition.dy.clamp(0, viewportSize.height).toDouble();
    widget.onPointSelected?.call(
      ComputerUseDebugImagePoint(
        x / viewportSize.width * widget.snapshot.width,
        y / viewportSize.height * widget.snapshot.height,
      ),
    );
  }

  Uint8List? _decodeBytes() {
    try {
      return base64Decode(widget.snapshot.base64);
    } catch (_) {
      return null;
    }
  }
}
