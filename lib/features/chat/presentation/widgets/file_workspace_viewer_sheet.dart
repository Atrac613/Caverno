import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/datasources/filesystem_tools.dart';
import '../../domain/entities/turn_diff.dart';
import '../../domain/services/file_reference_extractor.dart';

const int _maxFilePreviewBytes = 220000;

Future<void> showFileWorkspaceViewer(
  BuildContext context, {
  required String rootPath,
  required List<FileReference> references,
  String? initialPath,
  String? projectName,
}) {
  return showFileWorkspaceViewerPanel(
    context: context,
    request: FileWorkspaceViewerRequest.files(
      rootPath: rootPath,
      references: references,
      initialPath: initialPath,
      projectName: projectName,
    ),
  );
}

Future<void> showTurnDiffSheet(BuildContext context, {required TurnDiff diff}) {
  return showFileWorkspaceViewerPanel(
    context: context,
    request: FileWorkspaceViewerRequest.diff(diff: diff),
  );
}

Future<void> showFileWorkspaceViewerPanel({
  required BuildContext context,
  required FileWorkspaceViewerRequest request,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close file viewer',
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final panelWidth = screenWidth < 900
          ? screenWidth
          : (screenWidth * 0.42).clamp(420.0, 720.0).toDouble();
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 16,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: request.buildViewer(
              onClose: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class FileWorkspaceViewerRequest {
  const FileWorkspaceViewerRequest._({
    this.rootPath,
    this.references = const <FileReference>[],
    this.initialPath,
    this.projectName,
    this.diff,
  });

  factory FileWorkspaceViewerRequest.files({
    required String rootPath,
    required List<FileReference> references,
    String? initialPath,
    String? projectName,
  }) {
    return FileWorkspaceViewerRequest._(
      rootPath: rootPath,
      references: references,
      initialPath: initialPath,
      projectName: projectName,
    );
  }

  factory FileWorkspaceViewerRequest.diff({required TurnDiff diff}) {
    return FileWorkspaceViewerRequest._(diff: diff);
  }

  final String? rootPath;
  final List<FileReference> references;
  final String? initialPath;
  final String? projectName;
  final TurnDiff? diff;

  bool get isDiff => diff != null;

  Widget buildViewer({VoidCallback? onClose}) {
    final requestDiff = diff;
    if (requestDiff != null) {
      return FileWorkspaceViewerSheet.forDiff(
        diff: requestDiff,
        onClose: onClose,
      );
    }
    return FileWorkspaceViewerSheet.forFiles(
      rootPath: rootPath ?? '',
      references: references,
      initialPath: initialPath,
      projectName: projectName,
      onClose: onClose,
    );
  }
}

class TurnDiffSheet extends StatelessWidget {
  const TurnDiffSheet({super.key, required this.diff, this.onClose});

  final TurnDiff diff;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return FileWorkspaceViewerSheet.forDiff(diff: diff, onClose: onClose);
  }
}

class FileWorkspaceViewerSheet extends StatefulWidget {
  const FileWorkspaceViewerSheet._({
    required this.title,
    required List<_WorkspaceViewerItem> items,
    this.subtitle,
    this.rootPath,
    this.projectName,
    this.diff,
    this.initialPath,
    this.onClose,
  }) : _items = items;

  factory FileWorkspaceViewerSheet.forFiles({
    required String rootPath,
    required List<FileReference> references,
    String? initialPath,
    String? projectName,
    VoidCallback? onClose,
  }) {
    final items = _buildFileItems(references, initialPath);
    return FileWorkspaceViewerSheet._(
      title: 'File viewer',
      subtitle: projectName?.trim().isNotEmpty == true
          ? projectName!.trim()
          : rootPath,
      rootPath: rootPath,
      projectName: projectName,
      initialPath: initialPath,
      onClose: onClose,
      items: items,
    );
  }

  factory FileWorkspaceViewerSheet.forDiff({
    required TurnDiff diff,
    VoidCallback? onClose,
  }) {
    final title = diff.source == TurnDiffSource.git
        ? 'Uncommitted changes'
        : 'Turn changes';
    return FileWorkspaceViewerSheet._(
      title: title,
      subtitle: diff.userPromptPreview.trim().isEmpty
          ? null
          : diff.userPromptPreview.trim(),
      diff: diff,
      onClose: onClose,
      items: [
        for (final file in diff.files)
          _WorkspaceViewerItem.diff(file: file, path: file.filePath),
      ],
    );
  }

  final String title;
  final String? subtitle;
  final String? rootPath;
  final String? projectName;
  final TurnDiff? diff;
  final String? initialPath;
  final VoidCallback? onClose;
  final List<_WorkspaceViewerItem> _items;

  @override
  State<FileWorkspaceViewerSheet> createState() =>
      _FileWorkspaceViewerSheetState();

  static List<_WorkspaceViewerItem> _buildFileItems(
    List<FileReference> references,
    String? initialPath,
  ) {
    final itemsByPath = <String, _WorkspaceViewerItem>{};
    void addReference(FileReference reference) {
      final path = reference.path.trim();
      if (path.isEmpty) {
        return;
      }
      itemsByPath.putIfAbsent(
        path,
        () => _WorkspaceViewerItem.file(path: path, line: reference.line),
      );
    }

    for (final reference in references) {
      addReference(reference);
    }
    final normalizedInitialPath = initialPath?.trim();
    if (normalizedInitialPath != null && normalizedInitialPath.isNotEmpty) {
      addReference(FileReference(path: normalizedInitialPath));
    }
    return itemsByPath.values.toList(growable: false);
  }
}

class _FileWorkspaceViewerSheetState extends State<FileWorkspaceViewerSheet> {
  late _WorkspaceViewerItem? _selectedItem;
  Future<_LoadedTextFile>? _fileFuture;

  bool get _isDiffMode => widget.diff != null;

  @override
  void initState() {
    super.initState();
    _selectedItem = _initialSelectedItem();
    _refreshFileFuture();
  }

  @override
  void didUpdateWidget(covariant FileWorkspaceViewerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._items != widget._items ||
        oldWidget.rootPath != widget.rootPath ||
        oldWidget.initialPath != widget.initialPath) {
      _selectedItem = _initialSelectedItem();
      _refreshFileFuture();
    }
  }

  _WorkspaceViewerItem? _initialSelectedItem() {
    if (widget._items.isEmpty) {
      return null;
    }
    final initialPath = widget.initialPath?.trim();
    if (initialPath != null && initialPath.isNotEmpty) {
      for (final item in widget._items) {
        if (item.path == initialPath) {
          return item;
        }
      }
    }
    return widget._items.first;
  }

  void _selectItem(_WorkspaceViewerItem item) {
    setState(() {
      _selectedItem = item;
      _refreshFileFuture();
    });
  }

  void _refreshFileFuture() {
    final selectedItem = _selectedItem;
    if (selectedItem == null || selectedItem.diffFile != null) {
      _fileFuture = null;
      return;
    }
    _fileFuture = _loadTextFile(selectedItem);
  }

  Future<_LoadedTextFile> _loadTextFile(_WorkspaceViewerItem item) {
    return Future<_LoadedTextFile>.value(_loadTextFileSync(item));
  }

  _LoadedTextFile _loadTextFileSync(_WorkspaceViewerItem item) {
    final rootPath = widget.rootPath?.trim();
    if (rootPath == null || rootPath.isEmpty) {
      return _LoadedTextFile.error(
        displayPath: item.path,
        message: 'Select a coding project before opening file references.',
      );
    }

    final resolvedPath = _resolvePathWithinRoot(item.path, rootPath);
    if (resolvedPath == null) {
      return _LoadedTextFile.error(
        displayPath: item.path,
        message: 'The referenced path is outside the selected project.',
      );
    }

    final type = FileSystemEntity.typeSync(resolvedPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return _LoadedTextFile.error(
        displayPath: item.path,
        absolutePath: resolvedPath,
        message: 'File does not exist: ${item.path}',
      );
    }
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.link) {
      return _LoadedTextFile.error(
        displayPath: item.path,
        absolutePath: resolvedPath,
        message: 'Path is not a regular text file.',
      );
    }

    final file = File(resolvedPath);
    RandomAccessFile? accessFile;
    try {
      final sizeBytes = file.lengthSync();
      final readLength = sizeBytes > _maxFilePreviewBytes
          ? _maxFilePreviewBytes
          : sizeBytes;
      final bytes = Uint8List(readLength);
      accessFile = file.openSync();
      final bytesRead = accessFile.readIntoSync(bytes);
      final previewBytes = bytesRead == bytes.length
          ? bytes
          : Uint8List.sublistView(bytes, 0, bytesRead);
      if (previewBytes.contains(0)) {
        return _LoadedTextFile.error(
          displayPath: item.path,
          absolutePath: file.absolute.path,
          message:
              'File is not valid UTF-8 text. Binary files are not supported.',
        );
      }
      final truncated = sizeBytes > bytesRead;
      final content = utf8.decode(previewBytes, allowMalformed: truncated);
      final lineCount = content.isEmpty ? 0 : content.split('\n').length;
      return _LoadedTextFile(
        displayPath: item.path,
        absolutePath: file.absolute.path,
        content: content,
        sizeBytes: sizeBytes,
        startLine: 1,
        lineCount: lineCount,
        totalLines: truncated ? null : lineCount,
        truncated: truncated,
        error: null,
      );
    } on FormatException {
      return _LoadedTextFile.error(
        displayPath: item.path,
        absolutePath: file.absolute.path,
        message:
            'File is not valid UTF-8 text. Binary files are not supported.',
      );
    } on FileSystemException catch (error) {
      return _LoadedTextFile.error(
        displayPath: item.path,
        absolutePath: file.absolute.path,
        message: error.toString(),
      );
    } finally {
      accessFile?.closeSync();
    }
  }

  String? _resolvePathWithinRoot(String rawPath, String rootPath) {
    final candidates = <String>[
      rawPath,
      if (rawPath.startsWith('a/') || rawPath.startsWith('b/'))
        rawPath.substring(2),
    ];

    for (final candidate in candidates) {
      final resolved = FilesystemTools.resolvePath(
        candidate,
        defaultRoot: rootPath,
      );
      if (resolved == null) {
        continue;
      }
      if (_isWithinDirectory(resolved, rootPath)) {
        return resolved;
      }
    }
    return null;
  }

  bool _isWithinDirectory(String candidatePath, String rootPath) {
    final candidate = _canonicalPath(candidatePath);
    final root = _canonicalPath(rootPath, directory: true);
    if (candidate == root) {
      return true;
    }
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    return candidate.startsWith(prefix);
  }

  String _canonicalPath(String path, {bool directory = false}) {
    try {
      return directory
          ? Directory(path).resolveSymbolicLinksSync()
          : File(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return directory
          ? Directory(path).absolute.path
          : File(path).absolute.path;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ViewerHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            summary: _summaryText(),
            onClose: widget.onClose ?? () => Navigator.of(context).maybePop(),
          ),
          const Divider(height: 1),
          Expanded(
            child: widget._items.isEmpty
                ? _buildEmptyState(theme)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 720) {
                        return _buildCompactLayout();
                      }
                      return _buildThreePaneLayout();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _summaryText() {
    final diff = widget.diff;
    if (diff == null) {
      final count = widget._items.length;
      return '$count ${count == 1 ? 'reference' : 'references'}';
    }
    if (!diff.hasChanges) {
      return diff.source == TurnDiffSource.git
          ? 'Working tree is clean'
          : 'No file changes recorded';
    }
    return diff.summaryLabel;
  }

  Widget _buildEmptyState(ThemeData theme) {
    final text = _isDiffMode
        ? (widget.diff?.source == TurnDiffSource.git
              ? 'Working tree is clean'
              : 'No file changes recorded')
        : 'No file references found.';
    return Center(
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildThreePaneLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 236,
          child: _FileListPane(
            items: widget._items,
            selectedItem: _selectedItem,
            onSelected: _selectItem,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildPreviewPane()),
        const VerticalDivider(width: 1),
        SizedBox(width: 248, child: _buildDetailsPane()),
      ],
    );
  }

  Widget _buildCompactLayout() {
    return Column(
      children: [
        SizedBox(
          height: 132,
          child: _FileListPane(
            items: widget._items,
            selectedItem: _selectedItem,
            onSelected: _selectItem,
            scrollDirection: Axis.horizontal,
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildPreviewPane()),
      ],
    );
  }

  Widget _buildPreviewPane() {
    final selectedItem = _selectedItem;
    if (selectedItem == null) {
      return const SizedBox.shrink();
    }

    final diffFile = selectedItem.diffFile;
    if (diffFile != null) {
      return _DiffPreviewPane(file: diffFile);
    }

    final fileFuture = _fileFuture;
    if (fileFuture == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<_LoadedTextFile>(
      future: fileFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _TextFilePreviewPane(
          file: snapshot.data!,
          highlightLine: selectedItem.line,
        );
      },
    );
  }

  Widget _buildDetailsPane() {
    final selectedItem = _selectedItem;
    if (selectedItem == null) {
      return const SizedBox.shrink();
    }

    final diffFile = selectedItem.diffFile;
    if (diffFile != null) {
      return _DiffDetailsPane(diff: widget.diff, file: diffFile);
    }

    final fileFuture = _fileFuture;
    if (fileFuture == null) {
      return _FileDetailsPane(
        item: selectedItem,
        rootPath: widget.rootPath,
        projectName: widget.projectName,
      );
    }
    return FutureBuilder<_LoadedTextFile>(
      future: fileFuture,
      builder: (context, snapshot) {
        return _FileDetailsPane(
          item: selectedItem,
          rootPath: widget.rootPath,
          projectName: widget.projectName,
          loadedFile: snapshot.data,
        );
      },
    );
  }
}

class _ViewerHeader extends StatelessWidget {
  const _ViewerHeader({
    required this.title,
    required this.summary,
    required this.onClose,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String summary;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
      child: Row(
        children: [
          Icon(Icons.view_sidebar_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle?.trim().isNotEmpty == true
                      ? '$summary · ${subtitle!.trim()}'
                      : summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _FileListPane extends StatelessWidget {
  const _FileListPane({
    required this.items,
    required this.selectedItem,
    required this.onSelected,
    this.scrollDirection = Axis.vertical,
  });

  final List<_WorkspaceViewerItem> items;
  final _WorkspaceViewerItem? selectedItem;
  final ValueChanged<_WorkspaceViewerItem> onSelected;
  final Axis scrollDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHorizontal = scrollDirection == Axis.horizontal;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isHorizontal)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text(
                'Files',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              scrollDirection: scrollDirection,
              padding: EdgeInsets.fromLTRB(
                isHorizontal ? 12 : 8,
                isHorizontal ? 10 : 0,
                8,
                12,
              ),
              itemCount: items.length,
              separatorBuilder: (_, _) => SizedBox(
                width: isHorizontal ? 8 : 0,
                height: isHorizontal ? 0 : 4,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _FileListTile(
                  item: item,
                  selected: item == selectedItem,
                  horizontal: isHorizontal,
                  onTap: () => onSelected(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  const _FileListTile({
    required this.item,
    required this.selected,
    required this.horizontal,
    required this.onTap,
  });

  final _WorkspaceViewerItem item;
  final bool selected;
  final bool horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diffFile = item.diffFile;
    final selectedColor = theme.colorScheme.primaryContainer.withValues(
      alpha: 0.55,
    );
    final borderColor = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.45)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.55);
    return SizedBox(
      width: horizontal ? 220 : null,
      child: Material(
        color: selected ? selectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  _iconFor(item),
                  size: 18,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (diffFile != null) ...[
                        const SizedBox(height: 4),
                        _MiniDiffStats(file: diffFile),
                      ] else if (item.line != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Line ${item.line}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(_WorkspaceViewerItem item) {
    final file = item.diffFile;
    if (file == null) {
      return Icons.description_outlined;
    }
    if (file.isDeletedFile) {
      return Icons.delete_outline;
    }
    if (file.isNewFile || file.isUntracked) {
      return Icons.note_add_outlined;
    }
    if (file.isBinary) {
      return Icons.file_present_outlined;
    }
    return Icons.difference_outlined;
  }
}

class _MiniDiffStats extends StatelessWidget {
  const _MiniDiffStats({required this.file});

  final TurnDiffFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text: '+${file.linesAdded}',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w800,
            ),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '-${file.linesRemoved}',
            style: TextStyle(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextFilePreviewPane extends StatelessWidget {
  const _TextFilePreviewPane({required this.file, this.highlightLine});

  final _LoadedTextFile file;
  final int? highlightLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (file.error != null) {
      return _PreviewMessage(
        icon: Icons.error_outline,
        title: 'Preview unavailable',
        message: file.error!,
      );
    }

    final lines = file.content.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneTitleBar(
          title: 'Preview',
          subtitle: file.displayPath,
          trailing: file.truncated ? 'truncated' : null,
        ),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final lineNumber = file.startLine + index;
                return _CodeLine(
                  lineNumber: lineNumber,
                  text: lines[index],
                  highlighted: highlightLine == lineNumber,
                );
              },
            ),
          ),
        ),
        if (file.truncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Preview is truncated. Use read_file for a narrower range.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _DiffPreviewPane extends StatelessWidget {
  const _DiffPreviewPane({required this.file});

  final TurnDiffFile file;

  @override
  Widget build(BuildContext context) {
    if (!file.hasRenderablePatch) {
      return _PreviewMessage(
        icon: Icons.info_outline,
        title: 'Diff preview unavailable',
        message: file.note.trim().isEmpty
            ? 'Diff preview is unavailable for this file.'
            : file.note.trim(),
      );
    }

    final rows = _DiffRow.parse(file.unifiedPatch);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneTitleBar(title: 'Preview', subtitle: file.filePath),
        const _DiffColumnHeader(),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: rows.length,
              itemBuilder: (context, index) => _DiffCodeLine(row: rows[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaneTitleBar extends StatelessWidget {
  const _PaneTitleBar({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Chip(
              label: Text(trailing!),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }
}

class _DiffColumnHeader extends StatelessWidget {
  const _DiffColumnHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.64,
        ),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 54, child: _HeaderLabel('Old', theme: theme)),
            SizedBox(width: 54, child: _HeaderLabel('New', theme: theme)),
            Expanded(child: _HeaderLabel('Code', theme: theme)),
          ],
        ),
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  const _CodeLine({
    required this.lineNumber,
    required this.text,
    required this.highlighted,
  });

  final int lineNumber;
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: Text(
                '$lineNumber',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                text.isEmpty ? ' ' : text,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffCodeLine extends StatelessWidget {
  const _DiffCodeLine({required this.row});

  final _DiffRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colorsFor(row.kind, theme);
    if (row.kind == _DiffRowKind.header) {
      return DecoratedBox(
        decoration: BoxDecoration(color: colors.background),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SelectableText(
            row.text,
            style: TextStyle(
              color: colors.foreground,
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: colors.background),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LineNumberCell(value: row.oldLine),
            _LineNumberCell(value: row.newLine),
            Expanded(
              child: SelectableText(
                row.text.isEmpty ? ' ' : row.text,
                style: TextStyle(
                  color: colors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _DiffLineColors _colorsFor(_DiffRowKind kind, ThemeData theme) {
    switch (kind) {
      case _DiffRowKind.addition:
        return _DiffLineColors(
          background: Colors.green.withValues(alpha: 0.10),
          foreground: Colors.green.shade800,
        );
      case _DiffRowKind.removal:
        return _DiffLineColors(
          background: theme.colorScheme.error.withValues(alpha: 0.10),
          foreground: theme.colorScheme.error,
        );
      case _DiffRowKind.header:
        return _DiffLineColors(
          background: theme.colorScheme.surfaceContainerHighest,
          foreground: theme.colorScheme.onSurfaceVariant,
        );
      case _DiffRowKind.context:
        return _DiffLineColors(
          background: null,
          foreground: theme.colorScheme.onSurface,
        );
    }
  }
}

class _LineNumberCell extends StatelessWidget {
  const _LineNumberCell({required this.value});

  final int? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 54,
      child: Text(
        value?.toString() ?? '',
        textAlign: TextAlign.right,
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

class _FileDetailsPane extends StatelessWidget {
  const _FileDetailsPane({
    required this.item,
    this.rootPath,
    this.projectName,
    this.loadedFile,
  });

  final _WorkspaceViewerItem item;
  final String? rootPath;
  final String? projectName;
  final _LoadedTextFile? loadedFile;

  @override
  Widget build(BuildContext context) {
    final file = loadedFile;
    return _DetailsPane(
      title: 'Details',
      rows: [
        if (projectName?.trim().isNotEmpty == true)
          _DetailRowData(label: 'Project', value: projectName!.trim()),
        _DetailRowData(label: 'Path', value: item.path, copyable: true),
        if (item.line != null)
          _DetailRowData(label: 'Target line', value: '${item.line}'),
        if (file?.absolutePath != null)
          _DetailRowData(
            label: 'Resolved path',
            value: file!.absolutePath!,
            copyable: true,
          ),
        if (file?.sizeBytes != null)
          _DetailRowData(label: 'Size', value: _formatBytes(file!.sizeBytes!)),
        if (file?.totalLines != null)
          _DetailRowData(label: 'Lines', value: '${file!.totalLines}'),
        if (file?.truncated == true)
          const _DetailRowData(label: 'Preview', value: 'Truncated'),
        if (rootPath?.trim().isNotEmpty == true)
          _DetailRowData(
            label: 'Root',
            value: rootPath!.trim(),
            copyable: true,
          ),
      ],
    );
  }
}

class _DiffDetailsPane extends StatelessWidget {
  const _DiffDetailsPane({required this.diff, required this.file});

  final TurnDiff? diff;
  final TurnDiffFile file;

  @override
  Widget build(BuildContext context) {
    final badges = <String>[
      if (file.isNewFile) 'new',
      if (file.isDeletedFile) 'deleted',
      if (file.isUntracked) 'untracked',
      if (file.isBinary) 'binary',
      if (file.isLargeFile) 'large',
      if (file.isTruncated) 'truncated',
    ];
    return _DetailsPane(
      title: 'Details',
      rows: [
        _DetailRowData(label: 'Path', value: file.filePath, copyable: true),
        if (badges.isNotEmpty)
          _DetailRowData(label: 'Status', value: badges.join(', ')),
        _DetailRowData(label: 'Added', value: '+${file.linesAdded}'),
        _DetailRowData(label: 'Removed', value: '-${file.linesRemoved}'),
        if (diff != null)
          _DetailRowData(
            label: 'Source',
            value: diff!.source == TurnDiffSource.git ? 'Git' : 'Tool',
          ),
        if (file.note.trim().isNotEmpty)
          _DetailRowData(label: 'Note', value: file.note.trim()),
      ],
    );
  }
}

class _DetailsPane extends StatelessWidget {
  const _DetailsPane({required this.title, required this.rows});

  final String title;
  final List<_DetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows) _DetailRow(row: row),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.row});

  final _DetailRowData row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  row.value,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ),
              if (row.copyable)
                IconButton(
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: row.value)),
                  icon: const Icon(Icons.content_copy_outlined),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 32),
              const SizedBox(height: 10),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceViewerItem {
  const _WorkspaceViewerItem._({required this.path, this.line, this.diffFile});

  factory _WorkspaceViewerItem.file({required String path, int? line}) {
    return _WorkspaceViewerItem._(path: path, line: line);
  }

  factory _WorkspaceViewerItem.diff({
    required String path,
    required TurnDiffFile file,
  }) {
    return _WorkspaceViewerItem._(path: path, diffFile: file);
  }

  final String path;
  final int? line;
  final TurnDiffFile? diffFile;
}

class _LoadedTextFile {
  const _LoadedTextFile({
    required this.displayPath,
    required this.content,
    required this.startLine,
    required this.lineCount,
    this.absolutePath,
    this.sizeBytes,
    this.totalLines,
    this.truncated = false,
    this.error,
  });

  factory _LoadedTextFile.error({
    required String displayPath,
    required String message,
    String? absolutePath,
  }) {
    return _LoadedTextFile(
      displayPath: displayPath,
      absolutePath: absolutePath,
      content: '',
      startLine: 1,
      lineCount: 0,
      error: message,
    );
  }

  final String displayPath;
  final String? absolutePath;
  final String content;
  final int? sizeBytes;
  final int startLine;
  final int lineCount;
  final int? totalLines;
  final bool truncated;
  final String? error;
}

class _DetailRowData {
  const _DetailRowData({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;
}

enum _DiffRowKind { header, context, addition, removal }

class _DiffRow {
  const _DiffRow({
    required this.kind,
    required this.text,
    this.oldLine,
    this.newLine,
  });

  final _DiffRowKind kind;
  final String text;
  final int? oldLine;
  final int? newLine;

  static final RegExp _hunkPattern = RegExp(
    r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@',
  );

  static List<_DiffRow> parse(String patch) {
    final rows = <_DiffRow>[];
    var oldLine = 0;
    var newLine = 0;
    for (final line in patch.split('\n')) {
      final hunkMatch = _hunkPattern.firstMatch(line);
      if (hunkMatch != null) {
        oldLine = int.tryParse(hunkMatch.group(1) ?? '') ?? oldLine;
        newLine = int.tryParse(hunkMatch.group(2) ?? '') ?? newLine;
        rows.add(_DiffRow(kind: _DiffRowKind.header, text: line));
        continue;
      }

      final isFileHeader =
          line.startsWith('diff --git') ||
          line.startsWith('index ') ||
          line.startsWith('---') ||
          line.startsWith('+++');
      if (isFileHeader) {
        rows.add(_DiffRow(kind: _DiffRowKind.header, text: line));
        continue;
      }

      if (line.startsWith('+')) {
        rows.add(
          _DiffRow(kind: _DiffRowKind.addition, text: line, newLine: newLine),
        );
        newLine++;
        continue;
      }
      if (line.startsWith('-')) {
        rows.add(
          _DiffRow(kind: _DiffRowKind.removal, text: line, oldLine: oldLine),
        );
        oldLine++;
        continue;
      }

      rows.add(
        _DiffRow(
          kind: _DiffRowKind.context,
          text: line,
          oldLine: oldLine > 0 ? oldLine : null,
          newLine: newLine > 0 ? newLine : null,
        ),
      );
      if (oldLine > 0) {
        oldLine++;
      }
      if (newLine > 0) {
        newLine++;
      }
    }
    return rows;
  }
}

class _DiffLineColors {
  const _DiffLineColors({required this.background, required this.foreground});

  final Color? background;
  final Color foreground;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(1)} KiB';
  }
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(1)} MiB';
}
