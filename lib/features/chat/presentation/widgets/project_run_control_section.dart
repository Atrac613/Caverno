import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/flutter_run_provider.dart';
import 'flutter_run_control_section.dart';
import 'html_preview_control_section.dart';

/// The run control a coding project supports, chosen for it.
///
/// A project offers at most one: `htmlPreviewSupportedProvider` already
/// returns false wherever `flutterRunSupportedProvider` is true, so the two
/// never overlap and the page has no decision left to make. Keeping the choice
/// here means the companion panel asks one question -- is there a runner --
/// instead of watching both families and branching between two widgets.
class ProjectRunControlSection extends ConsumerWidget {
  const ProjectRunControlSection({
    super.key,
    required this.projectRoot,
    required this.threadId,
  });

  final String projectRoot;
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(flutterRunSupportedProvider(projectRoot))) {
      return FlutterRunControlSection(
        projectRoot: projectRoot,
        threadId: threadId,
      );
    }
    return HtmlPreviewControlSection(projectRoot: projectRoot);
  }
}
