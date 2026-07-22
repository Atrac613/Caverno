import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:ui' as ui;

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../../../core/services/attachment_storage_service.dart';
import '../../../../core/services/macos_main_app_permissions_service.dart';
import '../../../../core/services/voice_providers.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/conversation_goal.dart';
import 'conversation_goal_status_presentation.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../slash_commands/slash_command.dart';
import 'message_input_slash_suggestion_state.dart';
import 'voice_mode_overlay.dart';

class MessageInputImageAttachment {
  const MessageInputImageAttachment({
    required this.id,
    required this.bytes,
    required this.mimeType,
    required this.filePath,
  });

  final int id;
  final Uint8List bytes;
  final String mimeType;
  final String filePath;
}

typedef WorktreeSessionSendHandler = FutureOr<String> Function(String prompt);

enum MessageInputWorktreeMode { local, newWorktree }

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
    this.showChatApprovalMode = false,
    this.composerPrefillText,
    this.composerPrefillVersion = 0,
    this.droppedImageAttachment,
    this.codingGoal,
    this.onCodingGoalEdit,
    this.onCodingGoalMarkComplete,
    this.onCodingGoalMarkBlocked,
    this.onCodingGoalReactivate,
    this.onCodingGoalClear,
    this.goalAutoContinueCount = 0,
    this.goalAutoContinueBudget = 0,
    this.goalAutoContinueNotice,
    this.onWorktreeSessionSend,
    this.slashCommands = const <SlashCommandDefinition>[],
    this.onSlashCommand,
    this.isFloating = false,
  });

  final void Function(
    String message,
    String? imageBase64,
    String? imageMimeType,
    String? originalImagePath,
    String? originalImageMimeType,
  )
  onSend;
  final VoidCallback onCancel;
  final bool isLoading;
  final AssistantMode assistantMode;
  final ValueChanged<AssistantMode>? onAssistantModeSelected;
  final String inputHintKey;
  final bool isCodingWorkspace;

  /// Whether to show the chat-mode permission selector (built-in browser
  /// automation). Independent from [isCodingWorkspace], which shows the coding
  /// approval selector instead.
  final bool showChatApprovalMode;
  final String? composerPrefillText;
  final int composerPrefillVersion;
  final MessageInputImageAttachment? droppedImageAttachment;
  final ConversationGoal? codingGoal;
  final VoidCallback? onCodingGoalEdit;
  final VoidCallback? onCodingGoalMarkComplete;
  final VoidCallback? onCodingGoalMarkBlocked;
  final VoidCallback? onCodingGoalReactivate;
  final VoidCallback? onCodingGoalClear;
  final int goalAutoContinueCount;
  final int goalAutoContinueBudget;
  final String? goalAutoContinueNotice;
  final WorktreeSessionSendHandler? onWorktreeSessionSend;
  final List<SlashCommandDefinition> slashCommands;
  final SlashCommandHandler? onSlashCommand;
  final bool isFloating;

  @override
  ConsumerState<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends ConsumerState<MessageInput> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  final _imagePicker = ImagePicker();

  Uint8List? _selectedImageBytes;
  String? _selectedImageMimeType;
  String? _selectedOriginalImagePath;
  String? _selectedOriginalImageMimeType;
  String? _selectedFileName;
  String? _selectedFileContent;
  int? _selectedFileSize;
  // Set instead of [_selectedFileContent] for large attachments: the file is
  // copied to a durable path and referenced by path rather than inlined.
  String? _selectedFileDurablePath;
  bool _isRecording = false;
  bool _hasText = false;
  int? _handledDroppedImageAttachmentId;
  MessageInputSlashSuggestionState _slashSuggestionState =
      MessageInputSlashSuggestionState.empty;
  MessageInputWorktreeMode _worktreeMode = MessageInputWorktreeMode.local;

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

        final slashCommandResult = _handleSlashCommandKey(event);
        if (slashCommandResult == KeyEventResult.handled) {
          return slashCommandResult;
        }

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
    _handleDroppedImageAttachment();
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
    _handleDroppedImageAttachment();

    if (!identical(widget.slashCommands, oldWidget.slashCommands)) {
      _refreshSlashSuggestions();
    }

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

  void _handleDroppedImageAttachment() {
    final attachment = widget.droppedImageAttachment;
    if (attachment == null ||
        attachment.id == _handledDroppedImageAttachmentId) {
      return;
    }

    _handledDroppedImageAttachmentId = attachment.id;
    unawaited(_attachDroppedImage(attachment));
  }

  Future<void> _attachDroppedImage(
    MessageInputImageAttachment attachment,
  ) async {
    try {
      final prepared = await _prepareImageAttachmentForSend(
        originalBytes: attachment.bytes,
        mimeType: attachment.mimeType,
        filePath: attachment.filePath,
      );
      if (!mounted || _handledDroppedImageAttachmentId != attachment.id) {
        return;
      }

      setState(() {
        _selectedImageBytes = prepared.bytes;
        _selectedImageMimeType = prepared.mimeType;
        _selectedOriginalImagePath = prepared.originalPath;
        _selectedOriginalImageMimeType = prepared.originalMimeType;
      });
      _refreshSlashSuggestions();
      _focusNode.requestFocus();
    } catch (e) {
      debugPrint('Failed to attach dropped image: $e');
    }
  }

  /// Track non-whitespace input so the trailing button can switch modes.
  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    final nextSlashSuggestionState = _slashSuggestionState.refresh(
      text: _controller.text,
      commandsEnabled: _slashCommandsEnabled,
      hasAttachment: _hasAttachment,
      commands: widget.slashCommands,
    );
    if (hasText != _hasText ||
        !identical(nextSlashSuggestionState, _slashSuggestionState)) {
      setState(() {
        _hasText = hasText;
        _slashSuggestionState = nextSlashSuggestionState;
      });
    }
  }

  bool get _slashCommandsEnabled {
    return widget.slashCommands.isNotEmpty && widget.onSlashCommand != null;
  }

  bool get _hasAttachment {
    return _selectedImageBytes != null ||
        _selectedFileContent != null ||
        _selectedFileDurablePath != null;
  }

  bool get _worktreeControlsEnabled {
    return widget.isCodingWorkspace && widget.onWorktreeSessionSend != null;
  }

  bool get _shouldSendWorktreeSession {
    return _worktreeControlsEnabled &&
        _worktreeMode == MessageInputWorktreeMode.newWorktree;
  }

  void _refreshSlashSuggestions() {
    final nextSlashSuggestionState = _slashSuggestionState.refresh(
      text: _controller.text,
      commandsEnabled: _slashCommandsEnabled,
      hasAttachment: _hasAttachment,
      commands: widget.slashCommands,
    );
    if (identical(nextSlashSuggestionState, _slashSuggestionState)) return;
    setState(() {
      _slashSuggestionState = nextSlashSuggestionState;
    });
  }

  KeyEventResult _handleSlashCommandKey(KeyDownEvent event) {
    if (!_slashCommandsEnabled) {
      return KeyEventResult.ignored;
    }

    final hasSuggestions = _slashSuggestionState.hasSuggestions;
    final key = event.logicalKey;

    if (hasSuggestions && key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _slashSuggestionState = _slashSuggestionState.selectNext();
      });
      return KeyEventResult.handled;
    }

    if (hasSuggestions && key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _slashSuggestionState = _slashSuggestionState.selectPrevious();
      });
      return KeyEventResult.handled;
    }

    if (hasSuggestions && key == LogicalKeyboardKey.tab) {
      _applySlashSuggestion(_slashSuggestionState.selectedSuggestion);
      return KeyEventResult.handled;
    }

    if (hasSuggestions && key == LogicalKeyboardKey.escape) {
      setState(() {
        _slashSuggestionState = _slashSuggestionState.dismiss(
          text: _controller.text,
        );
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter) {
      if (_controller.value.composing != TextRange.empty) {
        return KeyEventResult.ignored;
      }
      if (_submitSlashCommandFromComposer(allowSelectedSuggestion: true)) {
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _applySlashSuggestion(SlashCommandDefinition command) {
    final text = '/${command.name} ';
    _setComposerText(text);
    setState(() {
      _slashSuggestionState = _slashSuggestionState.applyCompletedText(text);
    });
  }

  bool _submitSlashCommandFromComposer({
    required bool allowSelectedSuggestion,
  }) {
    if (!_slashCommandsEnabled || _hasAttachment) {
      return false;
    }

    final rawInput = _controller.text.trimRight();
    final parsed = parseSlashCommandInput(rawInput);
    if (parsed == null) {
      return false;
    }

    var definition = findSlashCommand(parsed.commandName, widget.slashCommands);
    if (definition == null &&
        allowSelectedSuggestion &&
        _slashSuggestionState.hasSuggestions) {
      final selected = _slashSuggestionState.selectedSuggestion;
      if (selected.requiresArguments && parsed.args.isEmpty) {
        _applySlashSuggestion(selected);
        _showMissingSlashArgumentsFeedback(selected);
        return true;
      }
      definition = selected;
    }
    if (definition == null) {
      _showSlashCommandFeedback(
        'message.slash_unknown_command'.tr(
          namedArgs: {'command': parsed.commandName},
        ),
      );
      _dismissSlashSuggestions();
      return true;
    }

    if (definition.requiresArguments && parsed.args.isEmpty) {
      _showMissingSlashArgumentsFeedback(definition);
      _dismissSlashSuggestions();
      return true;
    }

    if (!definition.acceptsArguments && parsed.args.isNotEmpty) {
      _showSlashCommandFeedback(
        'message.slash_unexpected_arguments'.tr(
          namedArgs: {'command': definition.name},
        ),
      );
      _dismissSlashSuggestions();
      return true;
    }

    unawaited(
      _executeSlashCommand(
        SlashCommandInvocation(
          definition: definition,
          rawInput: rawInput,
          commandName: parsed.commandName,
          args: parsed.args,
        ),
      ),
    );
    return true;
  }

  void _showMissingSlashArgumentsFeedback(SlashCommandDefinition definition) {
    _showSlashCommandFeedback(
      'message.slash_missing_arguments'.tr(
        namedArgs: {'command': definition.name, 'usage': definition.usage},
      ),
    );
  }

  Future<void> _executeSlashCommand(SlashCommandInvocation invocation) async {
    final handler = widget.onSlashCommand;
    if (handler == null) return;

    try {
      final result = await handler(invocation);
      if (!mounted) return;

      if (result.feedbackMessage != null) {
        _showSlashCommandFeedback(result.feedbackMessage!);
      }
      final promptToSend = result.promptToSend?.trim();
      if (promptToSend != null) {
        if (promptToSend.isEmpty) {
          _showSlashCommandFeedback('message.slash_command_failed'.tr());
          _dismissSlashSuggestions();
          _focusNode.requestFocus();
          return;
        }
        widget.onSend(promptToSend, null, null, null, null);
        _pushToHistory(invocation.rawInput.trim());
        _controller.clear();
        _clearImage();
        _clearFile();
        _focusNode.requestFocus();
        return;
      }
      if (result.clearInput) {
        _pushToHistory(invocation.rawInput.trim());
        _controller.clear();
        _clearImage();
        _clearFile();
      } else {
        _dismissSlashSuggestions();
      }
      _focusNode.requestFocus();
    } catch (e) {
      debugPrint('Failed to execute slash command: $e');
      if (!mounted) return;
      _showSlashCommandFeedback('message.slash_command_failed'.tr());
      _dismissSlashSuggestions();
      _focusNode.requestFocus();
    }
  }

  void _dismissSlashSuggestions() {
    final nextSlashSuggestionState = _slashSuggestionState.dismiss();
    if (identical(nextSlashSuggestionState, _slashSuggestionState)) return;
    setState(() {
      _slashSuggestionState = nextSlashSuggestionState;
    });
  }

  void _showSlashCommandFeedback(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      );

      if (pickedFile != null) {
        final rawBytes = await pickedFile.readAsBytes();
        final rawMimeType = pickedFile.mimeType ?? 'image/jpeg';
        final prepared = await _prepareImageAttachmentForSend(
          originalBytes: rawBytes,
          mimeType: rawMimeType,
          filePath: pickedFile.name.isNotEmpty
              ? pickedFile.name
              : pickedFile.path,
        );

        setState(() {
          _selectedImageBytes = prepared.bytes;
          _selectedImageMimeType = prepared.mimeType;
          _selectedOriginalImagePath = prepared.originalPath;
          _selectedOriginalImageMimeType = prepared.originalMimeType;
        });
        _refreshSlashSuggestions();
      }
    } catch (e) {
      debugPrint('Failed to pick image: $e');
    }
  }

  Future<
    ({
      Uint8List bytes,
      String mimeType,
      String? originalPath,
      String originalMimeType,
    })
  >
  _prepareImageAttachmentForSend({
    required Uint8List originalBytes,
    required String mimeType,
    required String filePath,
  }) async {
    final originalPath = await _persistOriginalImageAttachment(
      bytes: originalBytes,
      mimeType: mimeType,
      filePath: filePath,
    );
    final resized = await _resizeImageIfNeeded(
      originalBytes,
      mimeType: mimeType,
    );
    final normalized = await _normalizeImageForUpload(
      bytes: resized.bytes,
      mimeType: resized.mimeType,
      filePath: filePath,
    );
    return (
      bytes: normalized.bytes,
      mimeType: normalized.mimeType,
      originalPath: originalPath,
      originalMimeType: mimeType,
    );
  }

  Future<String?> _persistOriginalImageAttachment({
    required Uint8List bytes,
    required String mimeType,
    required String filePath,
  }) async {
    try {
      return await AttachmentStorageService.persistBytes(
        bytes: bytes,
        originalName: _attachmentOriginalName(filePath, mimeType),
      );
    } catch (e) {
      debugPrint('Failed to persist original image attachment: $e');
      return null;
    }
  }

  String _attachmentOriginalName(String filePath, String mimeType) {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty) {
      return 'image${_extensionForMimeType(mimeType)}';
    }
    final name = trimmed.split(RegExp(r'[\\/]')).last;
    if (name.trim().isEmpty) {
      return 'image${_extensionForMimeType(mimeType)}';
    }
    if (name.contains('.')) {
      return name;
    }
    return '$name${_extensionForMimeType(mimeType)}';
  }

  String _extensionForMimeType(String mimeType) {
    switch (mimeType.toLowerCase()) {
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
      _selectedOriginalImagePath = null;
      _selectedOriginalImageMimeType = null;
    });
    _refreshSlashSuggestions();
  }

  /// Files at or below this size are inlined into the message text (the
  /// original behavior). Larger files are copied to a durable path and
  /// referenced by path so the model can analyze them with the file tools
  /// without bloating the message or the context window.
  static const int _inlineFileMaxBytes = 256 * 1024;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'csv', 'txt', 'json', 'md', //
          'log', 'jsonl', 'ndjson', 'tsv', 'xml', 'yaml', 'yml',
        ],
        // Fetch the path (available on mobile too) instead of loading the whole
        // file into memory — large files must never be read fully here.
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final size = picked.size;
      final sourcePath = picked.path;

      if (size <= _inlineFileMaxBytes) {
        // Small text file: keep the existing inline behavior.
        final bytes =
            picked.bytes ??
            (sourcePath != null ? await File(sourcePath).readAsBytes() : null);
        if (bytes == null) {
          _showFileError();
          return;
        }
        final content = utf8.decode(bytes, allowMalformed: false);
        if (!mounted) return;
        setState(() {
          _selectedFileName = picked.name;
          _selectedFileContent = content;
          _selectedFileDurablePath = null;
          _selectedFileSize = bytes.length;
        });
        _refreshSlashSuggestions();
        return;
      }

      // Large file: copy to a durable location and reference it by path. The
      // model analyzes it on disk via inspect_file / search_files / read_file.
      if (sourcePath == null) {
        _showFileError();
        return;
      }
      final durablePath = await AttachmentStorageService.persist(
        sourcePath: sourcePath,
        originalName: picked.name,
      );
      if (!mounted) return;
      setState(() {
        _selectedFileName = picked.name;
        _selectedFileContent = null;
        _selectedFileDurablePath = durablePath;
        _selectedFileSize = size;
      });
      _refreshSlashSuggestions();
    } on FormatException {
      _showFileError();
    } catch (e) {
      debugPrint('Failed to pick file: $e');
      _showFileError();
    }
  }

  void _showFileError() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('message.file_read_error'.tr())));
  }

  void _clearFile() {
    setState(() {
      _selectedFileName = null;
      _selectedFileContent = null;
      _selectedFileSize = null;
      _selectedFileDurablePath = null;
    });
    _refreshSlashSuggestions();
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
            final prepared = await _prepareImageAttachmentForSend(
              originalBytes: bytes,
              mimeType: mimeType,
              filePath: 'clipboard.$ext',
            );
            if (mounted) {
              setState(() {
                _selectedImageBytes = prepared.bytes;
                _selectedImageMimeType = prepared.mimeType;
                _selectedOriginalImagePath = prepared.originalPath;
                _selectedOriginalImageMimeType = prepared.originalMimeType;
              });
              _refreshSlashSuggestions();
            }
            completer.complete(true);
          } catch (e) {
            debugPrint('Failed to read clipboard image: $e');
            await _surfaceMacOSScreenRecordingHintIfNeeded();
            completer.complete(false);
          }
        });
        return completer.future;
      }
    }

    return false;
  }

  /// On macOS, super_clipboard / super_native_extensions reads of image
  /// clipboard data go through CoreGraphics window APIs that require
  /// Screen Recording. When the user has revoked that grant, the read
  /// fails silently. Detect the case and surface a recovery snackbar
  /// instead of leaving the paste failure invisible.
  Future<void> _surfaceMacOSScreenRecordingHintIfNeeded() async {
    if (!Platform.isMacOS) return;
    final granted = await MacosMainAppPermissions.isScreenCaptureGranted();
    if (granted) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: const Text(
          'Image paste requires Screen Recording for Caverno. '
          'Grant it in System Settings to enable clipboard images.',
        ),
        action: SnackBarAction(
          label: 'Open Settings',
          onPressed: MacosMainAppPermissions.openScreenRecordingSettings,
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _handleContentInserted(KeyboardInsertedContent content) async {
    if (!content.hasData) return;
    final mimeType = content.mimeType;
    if (!mimeType.startsWith('image/')) return;

    try {
      final bytes = content.data!;
      final ext = mimeType.split('/').last;
      final prepared = await _prepareImageAttachmentForSend(
        originalBytes: bytes,
        mimeType: mimeType,
        filePath: 'inserted.$ext',
      );
      if (mounted) {
        setState(() {
          _selectedImageBytes = prepared.bytes;
          _selectedImageMimeType = prepared.mimeType;
          _selectedOriginalImagePath = prepared.originalPath;
          _selectedOriginalImageMimeType = prepared.originalMimeType;
        });
        _refreshSlashSuggestions();
      }
    } catch (e) {
      debugPrint('Failed to handle inserted content: $e');
    }
  }

  Future<({Uint8List bytes, String mimeType})> _resizeImageIfNeeded(
    Uint8List bytes, {
    required String mimeType,
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
        return (bytes: bytes, mimeType: mimeType);
      }

      // Re-decode with target size to resize
      image.dispose();
      image = null;
      codec.dispose();
      codec = null;

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

      if (byteData == null) return (bytes: bytes, mimeType: mimeType);
      return (bytes: byteData.buffer.asUint8List(), mimeType: 'image/png');
    } catch (e) {
      debugPrint('Failed to resize image: $e');
      return (bytes: bytes, mimeType: mimeType);
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
    unawaited(_handleSendAsync());
  }

  Future<void> _handleSendAsync() async {
    final text = _controller.text.trim();
    if (text.isEmpty &&
        _selectedImageBytes == null &&
        _selectedFileContent == null &&
        _selectedFileDurablePath == null) {
      return;
    }

    if (!_hasAttachment &&
        _submitSlashCommandFromComposer(allowSelectedSuggestion: true)) {
      return;
    }

    // Embed small file content inline; reference large files by durable path.
    String finalText = text;
    if (_selectedFileContent != null) {
      final fileBlock = '[File: $_selectedFileName]\n$_selectedFileContent';
      finalText = text.isEmpty ? fileBlock : '$fileBlock\n\n$text';
    } else if (_selectedFileDurablePath != null) {
      final human = _formattedFileSize(_selectedFileSize ?? 0);
      final ref =
          '[Attached file: $_selectedFileDurablePath ($human)]\n'
          'This file is large and is available on disk at the path above. '
          'Use inspect_file first, then search_files / read_file with offset '
          'and limit. Do not try to read it all at once.';
      finalText = text.isEmpty ? ref : '$ref\n\n$text';
    }

    if (_shouldSendWorktreeSession) {
      if (_selectedImageBytes != null) {
        _showSlashCommandFeedback('message.worktree_image_unavailable'.tr());
        _focusNode.requestFocus();
        return;
      }
      await _sendWorktreeSession(finalText, historyText: text);
      return;
    }

    String? imageBase64;
    if (_selectedImageBytes != null) {
      imageBase64 = base64Encode(_selectedImageBytes!);
    }

    widget.onSend(
      finalText,
      imageBase64,
      _selectedImageMimeType,
      _selectedOriginalImagePath,
      _selectedOriginalImageMimeType,
    );
    _pushToHistory(text);
    _controller.clear();
    _clearImage();
    _clearFile();
    _focusNode.requestFocus();
  }

  Future<void> _sendWorktreeSession(
    String prompt, {
    required String historyText,
  }) async {
    final handler = widget.onWorktreeSessionSend;
    if (handler == null) {
      _showSlashCommandFeedback('chat.slash_agent_unavailable'.tr());
      _focusNode.requestFocus();
      return;
    }

    try {
      final branch = (await handler(prompt)).trim();
      if (!mounted) return;
      _showSlashCommandFeedback(
        'message.worktree_session_started'.tr(
          namedArgs: {
            'branch': branch.isEmpty
                ? 'message.worktree_session_branch_unknown'.tr()
                : branch,
          },
        ),
      );
      _pushToHistory(historyText);
      _controller.clear();
      _clearImage();
      _clearFile();
      _focusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      _showSlashCommandFeedback(
        'message.worktree_session_failed'.tr(namedArgs: {'error': '$e'}),
      );
      _focusNode.requestFocus();
    }
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

  String _reasoningEffortLabel(ReasoningEffortPreference value) {
    return switch (value) {
      ReasoningEffortPreference.automatic =>
        'settings.reasoning_effort_automatic'.tr(),
      ReasoningEffortPreference.low => 'settings.reasoning_effort_low'.tr(),
      ReasoningEffortPreference.medium =>
        'settings.reasoning_effort_medium'.tr(),
      ReasoningEffortPreference.high => 'settings.reasoning_effort_high'.tr(),
    };
  }

  String _codingApprovalModeLabel(ToolApprovalMode mode) {
    return switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.coding_approval_default'.tr(),
      ToolApprovalMode.autoReview =>
        'settings.coding_approval_auto_review'.tr(),
      ToolApprovalMode.fullAccess =>
        'settings.coding_approval_full_access'.tr(),
    };
  }

  String _codingApprovalModeDescription(ToolApprovalMode mode) {
    return switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.coding_approval_default_desc'.tr(),
      ToolApprovalMode.autoReview =>
        'settings.coding_approval_auto_review_desc'.tr(),
      ToolApprovalMode.fullAccess =>
        'settings.coding_approval_full_access_desc'.tr(),
    };
  }

  String _chatApprovalModeLabel(ToolApprovalMode mode) {
    return switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.chat_approval_default'.tr(),
      ToolApprovalMode.autoReview => 'settings.chat_approval_auto_review'.tr(),
      ToolApprovalMode.fullAccess => 'settings.chat_approval_full_access'.tr(),
    };
  }

  String _chatApprovalModeDescription(ToolApprovalMode mode) {
    return switch (mode) {
      ToolApprovalMode.defaultPermissions =>
        'settings.chat_approval_default_desc'.tr(),
      ToolApprovalMode.autoReview =>
        'settings.chat_approval_auto_review_desc'.tr(),
      ToolApprovalMode.fullAccess =>
        'settings.chat_approval_full_access_desc'.tr(),
    };
  }

  String _worktreeModeLabel(MessageInputWorktreeMode mode) {
    return switch (mode) {
      MessageInputWorktreeMode.local => 'message.worktree_mode_local'.tr(),
      MessageInputWorktreeMode.newWorktree => 'message.worktree_mode_new'.tr(),
    };
  }

  String _worktreeModeDescription(MessageInputWorktreeMode mode) {
    return switch (mode) {
      MessageInputWorktreeMode.local => 'message.worktree_mode_local_desc'.tr(),
      MessageInputWorktreeMode.newWorktree =>
        'message.worktree_mode_new_desc'.tr(),
    };
  }

  IconData _worktreeModeIcon(MessageInputWorktreeMode mode) {
    return switch (mode) {
      MessageInputWorktreeMode.local => Icons.computer_outlined,
      MessageInputWorktreeMode.newWorktree => Icons.account_tree_outlined,
    };
  }

  Widget _buildWorktreeModeSelector(BuildContext context, ThemeData theme) {
    final enabled = !widget.isLoading && _worktreeControlsEnabled;
    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: PopupMenuButton<MessageInputWorktreeMode>(
        enabled: enabled,
        tooltip: 'message.worktree_mode_tooltip'.tr(
          namedArgs: {'value': _worktreeModeLabel(_worktreeMode)},
        ),
        padding: EdgeInsets.zero,
        onSelected: (value) {
          setState(() {
            _worktreeMode = value;
          });
        },
        itemBuilder: (context) => [
          PopupMenuItem<MessageInputWorktreeMode>(
            enabled: false,
            child: Text(
              'message.worktree_start_in'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final value in MessageInputWorktreeMode.values)
            CheckedPopupMenuItem<MessageInputWorktreeMode>(
              height: 64,
              value: value,
              checked: _worktreeMode == value,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_worktreeModeIcon(value)),
                title: Text(_worktreeModeLabel(value)),
                subtitle: Text(_worktreeModeDescription(value)),
              ),
            ),
        ],
        child: _buildComposerControlChip(
          theme: theme,
          icon: _worktreeModeIcon(_worktreeMode),
          label: _worktreeModeLabel(_worktreeMode),
          key: const ValueKey('worktree-mode-selector'),
        ),
      ),
    );
  }

  Widget _buildComposerControlChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    Key? key,
    bool showChevron = true,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelLarge),
          if (showChevron) ...[
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 18),
          ],
        ],
      ),
    );
  }

  Widget _buildSlashCommandSuggestions(BuildContext context, ThemeData theme) {
    final suggestions = _slashSuggestionState.suggestions;
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const ValueKey('slash-command-suggestions'),
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final command = suggestions[index];
          final selected = index == _slashSuggestionState.selectedIndex;
          return Material(
            color: selected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            child: InkWell(
              key: ValueKey('slash-command-suggestion-${command.name}'),
              onTap: () {
                setState(() {
                  _slashSuggestionState = _slashSuggestionState.selectIndex(
                    index,
                  );
                });
                _submitSlashCommandFromComposer(allowSelectedSuggestion: true);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 148,
                      child: Text(
                        command.usage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        command.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _goalStatusLabel(ConversationGoalStatus status) =>
      ConversationGoalStatusPresentation.labelKey(status).tr();

  Color _goalStatusColor(ThemeData theme, ConversationGoalStatus status) =>
      ConversationGoalStatusPresentation.color(theme.colorScheme, status);

  IconData _goalStatusIcon(ConversationGoalStatus status) =>
      ConversationGoalStatusPresentation.icon(status);

  String _goalBudgetLabel(ConversationGoal goal) {
    final parts = <String>[];
    if (goal.hasTokenBudget) {
      parts.add(
        'chat.goal_token_budget_label'.tr(
          namedArgs: {
            'used': _formatGoalTokenCount(goal.tokenUsage),
            'total': _formatGoalTokenCount(goal.tokenBudget),
          },
        ),
      );
    }
    if (goal.hasTurnBudget) {
      parts.add(
        'chat.goal_turn_budget_label'.tr(
          namedArgs: {
            'used': goal.turnsUsed.toString(),
            'total': goal.turnBudget.toString(),
          },
        ),
      );
    }
    return parts.join('  ');
  }

  String _formatGoalTokenCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }

  void _handleGoalMenuAction(_GoalMenuAction action) {
    switch (action) {
      case _GoalMenuAction.complete:
        widget.onCodingGoalMarkComplete?.call();
      case _GoalMenuAction.block:
        widget.onCodingGoalMarkBlocked?.call();
      case _GoalMenuAction.reactivate:
        widget.onCodingGoalReactivate?.call();
      case _GoalMenuAction.clear:
        widget.onCodingGoalClear?.call();
    }
  }

  Widget _buildCodingGoalStrip(BuildContext context, ThemeData theme) {
    final goal = widget.codingGoal;
    final hasGoal = goal?.hasObjective ?? false;
    if (!hasGoal) {
      return const SizedBox.shrink();
    }
    final activeGoal = goal!;
    final status = activeGoal.status;
    final isPaused = !activeGoal.enabled;
    final statusColor = isPaused
        ? theme.colorScheme.onSurfaceVariant
        : _goalStatusColor(theme, status);
    final statusLabel = isPaused
        ? 'chat.slash_goal_status_paused'.tr(
            namedArgs: {'status': _goalStatusLabel(status)},
          )
        : _goalStatusLabel(status);
    final objective = activeGoal.normalizedObjective!;
    final budgetLabel = _goalBudgetLabel(activeGoal);
    final effectiveAutoContinueBudget = widget.goalAutoContinueBudget > 0
        ? widget.goalAutoContinueBudget
        : activeGoal.hasTurnBudget
        ? activeGoal.turnBudget
        : kGoalAutoContinueDefaultTurnBudget;
    final effectiveAutoContinueCount = widget.goalAutoContinueCount > 0
        ? widget.goalAutoContinueCount
        : activeGoal.turnsUsed;
    final autoContinueLabel = activeGoal.autoContinue
        ? 'chat.goal_auto_continue_running'.tr(
            namedArgs: {
              'count': effectiveAutoContinueCount.toString(),
              'total': effectiveAutoContinueBudget.toString(),
            },
          )
        : '';
    final notice = widget.goalAutoContinueNotice?.trim();
    final controlsEnabled = !widget.isLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, size: 18, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'chat.goal_title'.tr(),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPaused
                              ? Icons.pause_circle_outline
                              : _goalStatusIcon(status),
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    if (autoContinueLabel.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.repeat_outlined,
                            size: 14,
                            color: theme.colorScheme.secondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            autoContinueLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  objective,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (budgetLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    budgetLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: activeGoal.budgetExceeded
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (notice != null && notice.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    notice.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.onCodingGoalEdit != null)
            IconButton(
              key: const ValueKey('coding-goal-edit-button'),
              tooltip: 'chat.goal_edit'.tr(),
              icon: const Icon(Icons.edit_outlined),
              onPressed: controlsEnabled ? widget.onCodingGoalEdit : null,
            ),
          PopupMenuButton<_GoalMenuAction>(
            enabled: controlsEnabled,
            tooltip: 'chat.goal_title'.tr(),
            icon: const Icon(Icons.more_horiz),
            onSelected: _handleGoalMenuAction,
            itemBuilder: (context) => [
              if (status == ConversationGoalStatus.active) ...[
                PopupMenuItem<_GoalMenuAction>(
                  value: _GoalMenuAction.complete,
                  enabled: widget.onCodingGoalMarkComplete != null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text('chat.goal_mark_complete'.tr()),
                  ),
                ),
                PopupMenuItem<_GoalMenuAction>(
                  value: _GoalMenuAction.block,
                  enabled: widget.onCodingGoalMarkBlocked != null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.block_outlined),
                    title: Text('chat.goal_mark_blocked'.tr()),
                  ),
                ),
              ],
              if (status != ConversationGoalStatus.active)
                PopupMenuItem<_GoalMenuAction>(
                  value: _GoalMenuAction.reactivate,
                  enabled: widget.onCodingGoalReactivate != null,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_arrow_outlined),
                    title: Text('chat.goal_reactivate'.tr()),
                  ),
                ),
              PopupMenuItem<_GoalMenuAction>(
                value: _GoalMenuAction.clear,
                enabled: widget.onCodingGoalClear != null,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.close),
                  title: Text('common.clear'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsNotifierProvider);
    final settingsNotifier = ref.read(settingsNotifierProvider.notifier);
    final assistantMode = widget.assistantMode;
    final reasoningEffort = settings.reasoningEffort;
    final codingApprovalMode = settings.codingApprovalMode;
    final chatApprovalMode = settings.chatApprovalMode;
    final canSend =
        _hasText ||
        _selectedImageBytes != null ||
        _selectedFileContent != null ||
        _selectedFileDurablePath != null;

    // The composer is a rounded surface card with alert-sized corners; the
    // inner TextField stays flat (filled: false). The recording state tints
    // the card as a transient affordance.
    final composerColor = _isRecording
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
        : theme.colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.all(8),
      // Flat input area: no background fill and no top divider border.
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
                child: Tooltip(
                  message: _selectedFileDurablePath != null
                      ? 'message.attached_as_path'.tr()
                      : '',
                  child: Chip(
                    avatar: Icon(
                      _selectedFileDurablePath != null
                          ? Icons.link
                          : Icons.description,
                      size: 18,
                    ),
                    label: Text(
                      '$_selectedFileName '
                      '(${_formattedFileSize(_selectedFileSize ?? 0)})',
                      overflow: TextOverflow.ellipsis,
                    ),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: _clearFile,
                  ),
                ),
              ),
            if (_slashSuggestionState.hasSuggestions)
              _buildSlashCommandSuggestions(context, theme),
            // Composer container: full-width TextField on top,
            // action row on the bottom — both inside one rounded surface.
            Container(
              decoration: BoxDecoration(
                color: composerColor,
                borderRadius: BorderRadius.circular(context.radii.lg),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isCodingWorkspace &&
                      (widget.codingGoal?.hasObjective ?? false))
                    _buildCodingGoalStrip(context, theme),
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
                        enabled: true,
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
                          // Flat input: no fill (override the global filled
                          // inputDecorationTheme), no border, no focus border.
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        onTapOutside: (_) => _focusNode.unfocus(),
                      ),
                    ),
                  ),
                  // Row 2: action bar
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.isCodingWorkspace) ...[
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
                                        checked:
                                            assistantMode ==
                                            AssistantMode.general,
                                        child: Text(
                                          _assistantModeLabel(
                                            AssistantMode.general,
                                          ),
                                        ),
                                      ),
                                      CheckedPopupMenuItem<AssistantMode>(
                                        value: AssistantMode.coding,
                                        checked:
                                            assistantMode ==
                                            AssistantMode.coding,
                                        child: Text(
                                          _assistantModeLabel(
                                            AssistantMode.coding,
                                          ),
                                        ),
                                      ),
                                      CheckedPopupMenuItem<AssistantMode>(
                                        value: AssistantMode.plan,
                                        checked:
                                            assistantMode == AssistantMode.plan,
                                        child: Text(
                                          _assistantModeLabel(
                                            AssistantMode.plan,
                                          ),
                                        ),
                                      ),
                                    ],
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
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
                                          const Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Opacity(
                                  opacity: widget.isLoading ? 0.6 : 1.0,
                                  child: PopupMenuButton<ToolApprovalMode>(
                                    enabled: !widget.isLoading,
                                    tooltip: 'message.permission_mode_tooltip'
                                        .tr(
                                          namedArgs: {
                                            'value': _codingApprovalModeLabel(
                                              codingApprovalMode,
                                            ),
                                          },
                                        ),
                                    padding: EdgeInsets.zero,
                                    onSelected: (value) {
                                      settingsNotifier.updateCodingApprovalMode(
                                        value,
                                      );
                                    },
                                    itemBuilder: (context) => ToolApprovalMode
                                        .values
                                        .map(
                                          (value) =>
                                              CheckedPopupMenuItem<
                                                ToolApprovalMode
                                              >(
                                                height: 72,
                                                value: value,
                                                checked:
                                                    codingApprovalMode == value,
                                                child: ListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  leading: const Icon(
                                                    Icons.shield_outlined,
                                                  ),
                                                  title: Text(
                                                    _codingApprovalModeLabel(
                                                      value,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    _codingApprovalModeDescription(
                                                      value,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                        )
                                        .toList(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.shield_outlined,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _codingApprovalModeLabel(
                                              codingApprovalMode,
                                            ),
                                            style: theme.textTheme.labelLarge,
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_worktreeControlsEnabled) ...[
                                  _buildWorktreeModeSelector(context, theme),
                                  if (_worktreeMode ==
                                      MessageInputWorktreeMode.newWorktree) ...[
                                    const SizedBox(width: 8),
                                    _buildComposerControlChip(
                                      theme: theme,
                                      icon: Icons.call_split_outlined,
                                      label: 'main',
                                      key: const ValueKey(
                                        'worktree-base-branch-chip',
                                      ),
                                      showChevron: false,
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                ],
                              ],
                              if (widget.showChatApprovalMode) ...[
                                Opacity(
                                  opacity: widget.isLoading ? 0.6 : 1.0,
                                  child: PopupMenuButton<ToolApprovalMode>(
                                    enabled: !widget.isLoading,
                                    tooltip: 'message.permission_mode_tooltip'
                                        .tr(
                                          namedArgs: {
                                            'value': _chatApprovalModeLabel(
                                              chatApprovalMode,
                                            ),
                                          },
                                        ),
                                    padding: EdgeInsets.zero,
                                    onSelected: (value) {
                                      settingsNotifier.updateChatApprovalMode(
                                        value,
                                      );
                                    },
                                    itemBuilder: (context) => ToolApprovalMode
                                        .values
                                        .map(
                                          (value) =>
                                              CheckedPopupMenuItem<
                                                ToolApprovalMode
                                              >(
                                                height: 72,
                                                value: value,
                                                checked:
                                                    chatApprovalMode == value,
                                                child: ListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  leading: const Icon(
                                                    Icons.shield_outlined,
                                                  ),
                                                  title: Text(
                                                    _chatApprovalModeLabel(
                                                      value,
                                                    ),
                                                  ),
                                                  subtitle: Text(
                                                    _chatApprovalModeDescription(
                                                      value,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                        )
                                        .toList(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.shield_outlined,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _chatApprovalModeLabel(
                                              chatApprovalMode,
                                            ),
                                            style: theme.textTheme.labelLarge,
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Opacity(
                                opacity: widget.isLoading ? 0.6 : 1.0,
                                child:
                                    PopupMenuButton<ReasoningEffortPreference>(
                                      enabled: !widget.isLoading,
                                      tooltip:
                                          'message.reasoning_effort_tooltip'.tr(
                                            namedArgs: {
                                              'value': _reasoningEffortLabel(
                                                reasoningEffort,
                                              ),
                                            },
                                          ),
                                      icon: const Icon(
                                        Icons.psychology_alt_outlined,
                                      ),
                                      onSelected: (value) {
                                        settingsNotifier.updateReasoningEffort(
                                          value,
                                        );
                                      },
                                      itemBuilder: (context) =>
                                          ReasoningEffortPreference.values
                                              .map(
                                                (value) =>
                                                    CheckedPopupMenuItem<
                                                      ReasoningEffortPreference
                                                    >(
                                                      value: value,
                                                      checked:
                                                          reasoningEffort ==
                                                          value,
                                                      child: Text(
                                                        _reasoningEffortLabel(
                                                          value,
                                                        ),
                                                      ),
                                                    ),
                                              )
                                              .toList(),
                                    ),
                              ),
                              const SizedBox(width: 4),
                              // Attachments menu (image / file)
                              PopupMenuButton<_AttachmentAction>(
                                tooltip: 'message.attachments'.tr(),
                                icon: const Icon(Icons.add),
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
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                      // - when content is present: Send, even while streaming
                      // - while streaming: Cancel (stop)
                      // - otherwise: Voice mode overlay
                      if (canSend)
                        IconButton(
                          onPressed: _handleSend,
                          icon: const Icon(Icons.send),
                          tooltip: 'message.send'.tr(),
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                          ),
                        ),
                      if (canSend && widget.isLoading) const SizedBox(width: 4),
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
                      else if (!canSend)
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

enum _GoalMenuAction { complete, block, reactivate, clear }
