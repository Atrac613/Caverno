import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../data/project_git_status_reader.dart';

/// Stops a roadmap task from starting over uncommitted work until the user
/// confirms.
///
/// A started task commits only its own captured files, so leftover changes
/// from an earlier task stay uncommitted underneath it and the two tasks' work
/// mixes in one tree. Git is read fresh on every press: the dashboard's cached
/// status can predate the previous task's last edit. Completes with true when
/// the start may proceed. A project git cannot read is not blocked, since
/// there is nothing to compare against.
Future<bool> confirmStartOverUncommittedChanges(
  BuildContext context, {
  required String projectRoot,
  ProjectGitStatusReader reader = const ProjectGitStatusReader(),
}) async {
  final status = await reader.read(projectRoot);
  if (status == null || status.changedFiles == 0) return true;
  if (!context.mounted) return false;
  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('project_dashboard.uncommitted_title'.tr()),
      content: Text(
        'project_dashboard.uncommitted_body'.tr(
          args: ['${status.changedFiles}'],
        ),
      ),
      actions: [
        FilledButton(
          key: const ValueKey('project-start-uncommitted-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        TextButton(
          key: const ValueKey('project-start-uncommitted-proceed'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('project_dashboard.start_anyway'.tr()),
        ),
      ],
    ),
  );
  return proceed == true;
}
