import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../application/roadmap_snapshot_service.dart';

/// Chooses a project's roadmap file. Completes with a project-relative path,
/// an empty string for the defaults, or null when cancelled. A path outside
/// the project is refused here, as [containedPath] refuses it when read.
class RoadmapPathDialog extends StatefulWidget {
  const RoadmapPathDialog({
    super.key,
    required this.projectRoot,
    required this.initialPath,
  });

  final String projectRoot;
  final String initialPath;

  @override
  State<RoadmapPathDialog> createState() => _RoadmapPathDialogState();
}

class _RoadmapPathDialogState extends State<RoadmapPathDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialPath,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final path = _controller.text.trim();
    if (path.isNotEmpty && containedPath(widget.projectRoot, path) == null) {
      setState(() => _error = 'project_dashboard.roadmap_path_invalid'.tr());
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('project_dashboard.roadmap_path'.tr()),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('roadmap-path-field'),
          controller: _controller,
          decoration: InputDecoration(
            hintText: 'docs/roadmap.md',
            helperText: 'project_dashboard.roadmap_path_help'.tr(),
            helperMaxLines: 3,
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey('roadmap-path-save'),
          onPressed: _save,
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
