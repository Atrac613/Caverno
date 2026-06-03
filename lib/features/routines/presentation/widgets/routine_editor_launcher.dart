import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/routine.dart';
import '../providers/routines_notifier.dart';
import 'routine_editor_sheet.dart';

/// Opens the routine editor sheet and persists the result.
///
/// Shared by the routines home view and the workspace drawer so the create /
/// edit flow stays in one place. Returns the id of the created routine when a
/// new routine is added, otherwise `null`.
Future<String?> showRoutineEditor(
  BuildContext context,
  WidgetRef ref, {
  Routine? routine,
}) async {
  final result = await showModalBottomSheet<RoutineEditorResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => RoutineEditorSheet(initialRoutine: routine),
  );

  if (result == null) {
    return null;
  }

  final notifier = ref.read(routinesNotifierProvider.notifier);
  if (routine == null) {
    final before = ref
        .read(routinesNotifierProvider)
        .routines
        .map((item) => item.id)
        .toSet();
    await notifier.createRoutine(
      name: result.name,
      prompt: result.prompt,
      intervalValue: result.intervalValue,
      intervalUnit: result.intervalUnit,
      scheduleMode: result.scheduleMode,
      timeOfDayMinutes: result.timeOfDayMinutes,
      enabled: result.enabled,
      notifyOnCompletion: result.notifyOnCompletion,
      toolsEnabled: result.toolsEnabled,
      completionAction: result.completionAction,
      googleChatRule: result.googleChatRule,
      workspaceDirectory: result.workspaceDirectory,
      allowWorkspaceWrites: result.allowWorkspaceWrites,
    );
    final created = ref
        .read(routinesNotifierProvider)
        .routines
        .firstWhere(
          (item) => !before.contains(item.id),
          orElse: () => ref.read(routinesNotifierProvider).routines.first,
        );
    return created.id;
  }

  await notifier.updateRoutine(
    routineId: routine.id,
    name: result.name,
    prompt: result.prompt,
    intervalValue: result.intervalValue,
    intervalUnit: result.intervalUnit,
    scheduleMode: result.scheduleMode,
    timeOfDayMinutes: result.timeOfDayMinutes,
    enabled: result.enabled,
    notifyOnCompletion: result.notifyOnCompletion,
    toolsEnabled: result.toolsEnabled,
    completionAction: result.completionAction,
    googleChatRule: result.googleChatRule,
    workspaceDirectory: result.workspaceDirectory,
    allowWorkspaceWrites: result.allowWorkspaceWrites,
  );
  return null;
}
