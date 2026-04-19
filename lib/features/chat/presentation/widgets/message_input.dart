import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../../../core/services/voice_providers.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import 'voice_mode_overlay.dart';

class MessageInput extends ConsumerStatefulWidget {
  const MessageInput({
    super.key,
    required this.onSend,
    required this.onCancel,
    required this.isLoading,
    required this.assistantMode,
    this.onAssistantModeSelected,
    this.inputHintKey = 'message.input_hint',
    this.isCodingWorkspace = false,
    this.composerPrefillText,
    this.composerPrefillVersion = 0,
  });

  final void Function(
    String message,
    String? imageBase64,
    String? imageMimeType,
  )
  onSend;
  final VoidCallback onCancel;
  final bool isLoading;
  final AssistantMode assistantMode;
  final ValueChanged<AssistantMode>? onAssistantModeSelected;
  final String inputHintKey;
  final bool isCodingWorkspace;
  final String? composerPrefillText;
  final int composerPrefillVersion;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  final _imagePicker = ImagePicker();

  Uint8List? _selectedImageBytes;
  String? _selectedImageMimeType;
  String? _selectedFileName;
  String? _selectedFileContent;
  int? _selectedFileSize;
  bool _isRecording = false;
  bool _hasText = false;

  // Shell-like input history. `_historyIndex == -1` means not browsing;
  // otherwise it points into `_inputHistory`. `_savedDraft` preserves the
  // user's in-progress text when they start browsing, so Down can restore it.
  // The history is persisted via SharedPreferences under `_historyPrefsKey`.
  static const int _maxHistoryEntries = 100;
  static const String _historyPrefsKey = 'message_input.history';
  final List<String> _inputHistory = [];
  int _historyIndex = -1;
  String? _savedDraft;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        // Only handle key-down to avoid double-firing.
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          return _tryRecallHistory(older: true)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return _tryRecallHistory(older: false)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (event.logicalKey != LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
        // Let Enter pass through during IME composition (e.g. Japanese).
        if (_controller.value.composing != TextRange.empty) {
          return KeyEventResult.ignored;
        }
        // Shift+Enter inserts a newline (handled by TextField).
        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }
        _handleSend();
        return KeyEventResult.handled;
      },
    );
    _controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.composerPrefillVersion == oldWidget.composerPrefillVersion) {
      return;
    }

    final nextText = widget.composerPrefillText?.trimRight() ?? '';
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    if (nextText.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
    });
  }

  /// Track whether the input has any non-whitespace text so the
  /// rightmost composer button can swap between send and voice mode.
  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  /// Navigate the input history with Up/Down arrows.
  ///
  /// Up starts browsing only when the composer is empty, to avoid hijacking
  /// caret movement inside multi-line drafts. Once browsing, both arrows stay
  /// active until the user returns to the saved draft or types something new.
  bool _tryRecallHistory({required bool older}) {
    if (_inputHistory.isEmpty) return false;

    if (older) {
      if (_historyIndex == -1) {
        if (_controller.text.isNotEmpty) return false;
        _savedDraft = _controller.text;
        _historyIndex = _inputHistory.length - 1;
      } else if (_historyIndex > 0) {
        _historyIndex -= 1;
      } else {
        // Already at oldest entry; consume the key so the caret doesn't jump.
        return true;
      }
      _setComposerText(_inputHistory[_historyIndex]);
      return true;
    }

    if (_historyIndex == -1) return false;
    if (_historyIndex < _inputHistory.length - 1) {
      _historyIndex += 1;
      _setComposerText(_inputHistory[_historyIndex]);
      return true;
    }
    // Past the newest entry — restore the draft the user was writing.
    _historyIndex = -1;
    final draft = _savedDraft ?? '';
    _savedDraft = null;
    _setComposerText(draft);
    return true;
  }

  void _setComposerText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _pushToHistory(String text) {
    if (text.isEmpty) return;
    if (_inputHistory.isNotEmpty && _inputHistory.last == text) {
      // Collapse immediate duplicates (same as bash `ignoredups`).
    } else {
      _inputHistory.add(text);
      if (_inputHistory.length > _maxHistoryEntries) {
        _inputHistory.removeAt(0);
      }
      _persistHistory();
    }
    _historyIndex = -1;
    _savedDraft = null;
  }

  void _loadHistory() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final stored = prefs.getStringList(_historyPrefsKey);
      if (stored != null && stored.isNotEmpty) {
        _inputHistory
          ..clear()
          ..addAll(stored.take(_maxHistoryEntries));
      }
    } catch (e) {
      debugPrint('Failed to load input history: $e');
    }
  }

  void _persistHistory() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      unawaited(prefs.setStringList(_historyPrefsKey, _inputHistory));
    } catch (e) {
      debugPrint('Failed to persist input history: $e');
    }
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
    final isTiff =
        lowerMime == 'image/tiff' ||
        lowerPath.endsWith('.tiff') ||
        lowerPath.endsWith('.tif');
    final isHeic =
        lowerMime == 'image/heic' ||
        lowerMime == 'image/heif' ||
        lowerPath.endsWith('.heic') ||
        lowerPath.endsWith('.heif');
    final isGif = lowerMime == 'image/gif' || lowerPath.endsWith('.gif');

    if (!isWebp && !isTiff && !isHeic && !isGif) {
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

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'json', 'md'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      if (bytes.length > 102400) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('message.file_too_large'.tr())));
        return;
      }

      final content = utf8.decode(bytes, allowMalformed: false);

      setState(() {
        _selectedFileName = file.name;
        _selectedFileContent = content;
        _selectedFileSize = bytes.length;
      });
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('message.file_read_error'.tr())));
    } catch (e) {
      debugPrint('Failed to pick file: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('message.file_read_error'.tr())));
    }
  }

  void _clearFile() {
    setState(() {
      _selectedFileName = null;
      _selectedFileContent = null;
      _selectedFileSize = null;
    });
  }

  Future<void> _handlePaste() async {
    final consumed = await _handleClipboardPaste();
    if (!consumed) {
      // Fall back to standard text paste
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipData?.text != null && clipData!.text!.isNotEmpty) {
        final sel = _controller.selection;
        final text = _controller.text;
        final start = sel.isValid ? sel.start : text.length;
        final end = sel.isValid ? sel.end : text.length;
        final before = text.substring(0, start);
        final after = text.substring(end);
        _controller.value = TextEditingValue(
          text: before + clipData.text! + after,
          selection: TextSelection.collapsed(
            offset: start + clipData.text!.length,
          ),
        );
      }
    }
  }

  Future<bool> _handleClipboardPaste() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return false;

    final reader = await clipboard.read();

    // Map formats to MIME types and file extensions
    const formatInfo = <SimpleFileFormat, (String, String)>{
      Formats.png: ('image/png', 'png'),
      Formats.jpeg: ('image/jpeg', 'jpg'),
      Formats.tiff: ('image/tiff', 'tiff'),
      Formats.gif: ('image/gif', 'gif'),
      Formats.heic: ('image/heic', 'heic'),
      Formats.heif: ('image/heif', 'heif'),
    };

    for (final entry in formatInfo.entries) {
      final format = entry.key;
      final (mimeType, ext) = entry.value;
      if (reader.canProvide(format)) {
        final completer = Completer<bool>();
        reader.getFile(format, (file) async {
          try {
            final data = await file.readAll();
            final bytes = Uint8List.fromList(data);
            final resized = await _resizeImageIfNeeded(bytes);
            final normalized = await _normalizeImageForUpload(
              bytes: resized,
              mimeType: mimeType,
              filePath: 'clipboard.$ext',
            );
            if (mounted) {
              setState(() {
                _selectedImageBytes = normalized.bytes;
                _selectedImageMimeType = normalized.mimeType;
              });
            }
            completer.complete(true);
          } catch (e) {
            debugPrint('Failed to read clipboard image: $e');
            completer.complete(false);
          }
        });
        return completer.future;
      }
    }

    return false;
  }

  Future<void> _handleContentInserted(KeyboardInsertedContent content) async {
    if (!content.hasData) return;
    final mimeType = content.mimeType;
    if (!mimeType.startsWith('image/')) return;

    try {
      final bytes = content.data!;
      final resized = await _resizeImageIfNeeded(bytes);
      final ext = mimeType.split('/').last;
      final normalized = await _normalizeImageForUpload(
        bytes: resized,
        mimeType: mimeType,
        filePath: 'inserted.$ext',
      );
      if (mounted) {
        setState(() {
          _selectedImageBytes = normalized.bytes;
          _selectedImageMimeType = normalized.mimeType;
        });
      }
    } catch (e) {
      debugPrint('Failed to handle inserted content: $e');
    }
  }

  Future<Uint8List> _resizeImageIfNeeded(
    Uint8List bytes, {
    int maxDimension = 1024,
  }) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;

      final imageWidth = image.width;
      final imageHeight = image.height;

      if (imageWidth <= maxDimension && imageHeight <= maxDimension) {
        return bytes;
      }

      // Re-decode with target size to resize
      image.dispose();
      codec.dispose();

      final targetWidth = imageWidth >= imageHeight ? maxDimension : null;
      final targetHeight = imageHeight > imageWidth ? maxDimension : null;

      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final resizedFrame = await codec.getNextFrame();
      image = resizedFrame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) return bytes;
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('Failed to resize image: $e');
      return bytes;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  String _formattedFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty &&
        _selectedImageBytes == null &&
        _selectedFileContent == null) {
      return;
    }

    String? imageBase64;
    if (_selectedImageBytes != null) {
      imageBase64 = base64Encode(_selectedImageBytes!);
    }

    // Embed file content into the message text
    String finalText = text;
    if (_selectedFileContent != null) {
      final fileBlock = '[File: $_selectedFileName]\n$_selectedFileContent';
      finalText = text.isEmpty ? fileBlock : '$fileBlock\n\n$text';
    }

    widget.onSend(finalText, imageBase64, _selectedImageMimeType);
    _pushToHistory(text);
    _controller.clear();
    _clearImage();
    _clearFile();
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
              SnackBar(content: Text('message.stt_unavailable'.tr())),
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

  String _assistantModeLabel(AssistantMode mode) {
    return switch (mode) {
      AssistantMode.general => 'settings.assistant_general'.tr(),
      AssistantMode.coding => 'settings.assistant_coding'.tr(),
      AssistantMode.plan => 'settings.assistant_plan'.tr(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assistantMode = widget.assistantMode;

    final composerColor = _isRecording
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
        : theme.colorScheme.surfaceContainerHighest;

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
            // File preview
            if (_selectedFileName != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Chip(
                  avatar: const Icon(Icons.description, size: 18),
                  label: Text(
                    '$_selectedFileName (${_formattedFileSize(_selectedFileSize!)})',
                    overflow: TextOverflow.ellipsis,
                  ),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: _clearFile,
                ),
              ),
            // Composer container: full-width TextField on top,
            // action row on the bottom — both inside one rounded surface.
            Container(
              decoration: BoxDecoration(
                color: composerColor,
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: full-width TextField
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        // On desktop, intercept Cmd/Ctrl+V to handle
                        // image paste via super_clipboard. On mobile,
                        // let the system paste handle it so iOS 16+
                        // authorization works.
                        if (!Platform.isIOS && !Platform.isAndroid)
                          PasteTextIntent: CallbackAction<PasteTextIntent>(
                            onInvoke: (_) {
                              _handlePaste();
                              return null;
                            },
                          ),
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !widget.isLoading,
                        contentInsertionConfiguration:
                            ContentInsertionConfiguration(
                              onContentInserted: _handleContentInserted,
                              allowedMimeTypes: const [
                                'image/png',
                                'image/jpeg',
                                'image/gif',
                                'image/heic',
                                'image/heif',
                                'image/tiff',
                              ],
                            ),
                        contextMenuBuilder: (context, editableTextState) {
                          final isMobile = Platform.isIOS || Platform.isAndroid;
                          final buttonItems = editableTextState
                              .contextMenuButtonItems
                              .map((item) {
                                // On desktop, override paste to use
                                // super_clipboard for image support.
                                if (!isMobile &&
                                    item.type == ContextMenuButtonType.paste) {
                                  return ContextMenuButtonItem(
                                    onPressed: () {
                                      editableTextState.hideToolbar();
                                      _handlePaste();
                                    },
                                    type: ContextMenuButtonType.paste,
                                    label: item.label,
                                  );
                                }
                                return item;
                              })
                              .toList();

                          // If no paste button exists (e.g. clipboard
                          // has only an image), inject one so the user
                          // can still paste.
                          final hasPaste = buttonItems.any(
                            (item) => item.type == ContextMenuButtonType.paste,
                          );
                          if (!hasPaste) {
                            buttonItems.add(
                              ContextMenuButtonItem(
                                onPressed: () {
                                  editableTextState.hideToolbar();
                                  _handlePaste();
                                },
                                type: ContextMenuButtonType.paste,
                              ),
                            );
                          }

                          return AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: editableTextState.contextMenuAnchors,
                            buttonItems: buttonItems,
                          );
                        },
                        decoration: InputDecoration(
                          hintText: _isRecording
                              ? 'message.listening'.tr()
                              : widget.inputHintKey.tr(),
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ),
                  // Row 2: action bar
                  Row(
                    children: [
                      Opacity(
                        opacity: widget.isLoading ? 0.6 : 1.0,
                        child: PopupMenuButton<AssistantMode>(
                          enabled: !widget.isLoading,
                          tooltip: 'message.mode_tooltip'.tr(),
                          padding: EdgeInsets.zero,
                          onSelected: widget.onAssistantModeSelected,
                          itemBuilder: (context) => [
                            CheckedPopupMenuItem<AssistantMode>(
                              value: AssistantMode.general,
                              checked: assistantMode == AssistantMode.general,
                              child: Text(
                                _assistantModeLabel(AssistantMode.general),
                              ),
                            ),
                            CheckedPopupMenuItem<AssistantMode>(
                              value: AssistantMode.coding,
                              checked: assistantMode == AssistantMode.coding,
                              child: Text(
                                _assistantModeLabel(AssistantMode.coding),
                              ),
                            ),
                            CheckedPopupMenuItem<AssistantMode>(
                              value: AssistantMode.plan,
                              enabled: widget.isCodingWorkspace,
                              checked: assistantMode == AssistantMode.plan,
                              child: Text(
                                _assistantModeLabel(AssistantMode.plan),
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _assistantModeLabel(assistantMode),
                                  style: theme.textTheme.labelLarge,
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Leftmost "+" attachments menu (image / file)
                      PopupMenuButton<_AttachmentAction>(
                        tooltip: 'message.attachments'.tr(),
                        icon: const Icon(Icons.add),
                        enabled: !widget.isLoading,
                        onSelected: (action) {
                          switch (action) {
                            case _AttachmentAction.image:
                              _pickImage();
                            case _AttachmentAction.file:
                              _pickFile();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<_AttachmentAction>(
                            value: _AttachmentAction.image,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.image),
                              title: Text('message.attach_image'.tr()),
                            ),
                          ),
                          PopupMenuItem<_AttachmentAction>(
                            value: _AttachmentAction.file,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.attach_file),
                              title: Text('message.attach_file'.tr()),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Microphone (STT)
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
                      const SizedBox(width: 4),
                      // Rightmost slot:
                      // - while streaming: Cancel (stop)
                      // - when text is empty: Voice mode overlay
                      // - when text is present: Send
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
                      else if (_hasText)
                        IconButton(
                          onPressed: _handleSend,
                          icon: const Icon(Icons.send),
                          tooltip: 'message.send'.tr(),
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                          ),
                        )
                      else
                        IconButton(
                          onPressed: () {
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
                            backgroundColor:
                                theme.colorScheme.secondaryContainer,
                            foregroundColor:
                                theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Actions available from the composer's "+" attachments menu.
enum _AttachmentAction { image, file }
