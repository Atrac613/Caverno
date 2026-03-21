import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/voice_providers.dart';
import 'voice_mode_overlay.dart';

class MessageInput extends ConsumerStatefulWidget {
  const MessageInput({
    super.key,
    required this.onSend,
    required this.onCancel,
    required this.isLoading,
  });

  final void Function(
    String message,
    String? imageBase64,
    String? imageMimeType,
  )
  onSend;
  final VoidCallback onCancel;
  final bool isLoading;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _imagePicker = ImagePicker();

  Uint8List? _selectedImageBytes;
  String? _selectedImageMimeType;
  bool _isRecording = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final rawBytes = await pickedFile.readAsBytes();
        final rawMimeType = pickedFile.mimeType ?? 'image/jpeg';
        final normalized = await _normalizeImageForUpload(
          bytes: rawBytes,
          mimeType: rawMimeType,
          filePath: pickedFile.path,
        );

        setState(() {
          _selectedImageBytes = normalized.bytes;
          _selectedImageMimeType = normalized.mimeType;
        });
      }
    } catch (e) {
      debugPrint('Failed to pick image: $e');
    }
  }

  Future<({Uint8List bytes, String mimeType})> _normalizeImageForUpload({
    required Uint8List bytes,
    required String mimeType,
    required String filePath,
  }) async {
    final lowerMime = mimeType.toLowerCase();
    final lowerPath = filePath.toLowerCase();
    final isWebp = lowerMime == 'image/webp' || lowerPath.endsWith('.webp');

    if (!isWebp) {
      return (bytes: bytes, mimeType: mimeType);
    }

    ui.Codec? codec;
    ui.Image? image;

    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('WEBP conversion failed (byteData is null). Use original.');
        return (bytes: bytes, mimeType: mimeType);
      }

      return (bytes: byteData.buffer.asUint8List(), mimeType: 'image/png');
    } catch (e) {
      debugPrint('WEBP conversion failed: $e');
      return (bytes: bytes, mimeType: mimeType);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  void _clearImage() {
    setState(() {
      _selectedImageBytes = null;
      _selectedImageMimeType = null;
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedImageBytes == null) return;

    String? imageBase64;
    if (_selectedImageBytes != null) {
      imageBase64 = base64Encode(_selectedImageBytes!);
    }

    widget.onSend(text, imageBase64, _selectedImageMimeType);
    _controller.clear();
    _clearImage();
    _focusNode.requestFocus();
  }

  Future<void> _toggleRecording() async {
    final stt = ref.read(sttServiceProvider);

    try {
      if (_isRecording) {
        await stt.stopListening();
        if (!mounted) return;
        setState(() => _isRecording = false);
      } else {
        if (!mounted) return;
        setState(() => _isRecording = true);

        await stt.startListening(
          onResult: (text, isFinal) {
            if (!mounted) return;
            setState(() {
              _controller.text = text;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: text.length),
              );
            });
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _isRecording = false);
          },
        );

        if (!stt.isListening && mounted) {
          setState(() => _isRecording = false);
          if (!stt.isAvailable) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('message.stt_unavailable'.tr()),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to toggle recording: $e');
      if (!mounted) return;
      setState(() => _isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image preview
            if (_selectedImageBytes != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _selectedImageBytes!,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _clearImage,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Input row
            Row(
              children: [
                // Image picker button
                IconButton(
                  onPressed: widget.isLoading ? null : _pickImage,
                  icon: const Icon(Icons.image),
                  tooltip: 'message.attach_image'.tr(),
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // Microphone button
                IconButton(
                  onPressed: widget.isLoading ? null : _toggleRecording,
                  icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
                  tooltip: _isRecording
                      ? 'message.record_stop'.tr()
                      : 'message.record_start'.tr(),
                  style: IconButton.styleFrom(
                    foregroundColor: _isRecording
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    backgroundColor: _isRecording
                        ? theme.colorScheme.errorContainer
                        : null,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: !widget.isLoading,
                    decoration: InputDecoration(
                      hintText: _isRecording
                          ? 'message.listening'.tr()
                          : 'message.input_hint'.tr(),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: _isRecording
                          ? theme.colorScheme.errorContainer.withValues(
                              alpha: 0.3,
                            )
                          : theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.isLoading)
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.stop_circle),
                    tooltip: 'message.cancel'.tr(),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    ),
                  )
                else
                  IconButton(
                    onPressed: _handleSend,
                    icon: const Icon(Icons.send),
                    tooltip: 'message.send'.tr(),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.isLoading
                      ? null
                      : () {
                          showGeneralDialog(
                            context: context,
                            barrierColor: Colors.transparent,
                            pageBuilder: (context, anim1, anim2) =>
                                const VoiceModeOverlay(),
                          );
                        },
                  icon: const Icon(Icons.record_voice_over),
                  tooltip: 'message.voice_mode_start'.tr(),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
