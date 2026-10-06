import '../../data/datasources/local_shell_tools.dart';
import '../entities/tool_call_info.dart';
import 'local_command_tool_contract.dart';

/// The arguments of a release call reduced to what decides what runs, so two
/// spellings of one execution share an approval and a dispatch record.
Map<String, dynamic> productionReleaseCanonicalArguments(
  ToolCallInfo toolCall,
  Map<String, dynamic> source,
) {
  final arguments = <String, dynamic>{...source};
  final command = arguments['command'];
  if (command is String) {
    arguments['command'] = LocalShellTools.normalizeCommand(command);
  }
  final workingDirectory = arguments['working_directory'];
  final effectiveDirectory =
      workingDirectory is String && workingDirectory.trim().isNotEmpty
      ? workingDirectory
      : arguments['cwd'];
  if (effectiveDirectory is String) {
    arguments['working_directory'] = effectiveDirectory.trim();
  }
  // The source alias adds no semantics after path resolution.
  arguments.remove('cwd');
  // process_start always runs in the background, so an omitted flag and an
  // explicit `true` are one execution. Keying on the raw argument made the
  // harness's own retry instruction (which spells `background=true`) miss
  // an approval recorded for a call that omitted it.
  arguments['background'] =
      toolCall.name.trim().toLowerCase() == 'process_start' ||
      argumentIsTruthy(arguments['background']);
  // `label` only names the background job in the UI, and the model rewords
  // it on every retry; `reason` is narration. Neither changes what runs.
  // Session 99bdd62c (2026-09-23) spent nine refused retries on an approved
  // release whose only difference was a reworded label.
  return arguments
    ..remove('reason')
    ..remove('label');
}
