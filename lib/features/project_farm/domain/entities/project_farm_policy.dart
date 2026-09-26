import 'package:freezed_annotation/freezed_annotation.dart';

part 'project_farm_policy.freezed.dart';
part 'project_farm_policy.g.dart';

/// What the user allows background work to do in one project (FARM4).
///
/// Written only by the user through settings, never by a model: it is the
/// human-reviewed source invariant 2 requires for verification commands. With
/// no policy, or no allowed command, background execution is unavailable.
@freezed
abstract class ProjectFarmPolicy with _$ProjectFarmPolicy {
  const ProjectFarmPolicy._();

  const factory ProjectFarmPolicy({
    required String projectId,
    @Default(<String>[]) List<String> allowedVerificationCommands,
    @Default(1) int maxConcurrentTasks,
    required DateTime updatedAt,

    /// FARM5: the subset of [allowedVerificationCommands] the user declared as
    /// not executing project code (e.g. analyze, a format check). Only these
    /// may run unattended: a test run executes code the agent just wrote, so
    /// it keeps a person in the loop. Declared, never inferred.
    @Default(<String>[]) List<String> unattendedCommands,

    /// FARM5: whether idle-time maintenance may start runs on its own. Off
    /// until the user turns it on.
    @Default(false) bool autoRunEnabled,

    /// FARM5: unattended runs allowed per local day.
    @Default(1) int dailyRunLimit,
  }) = _ProjectFarmPolicy;

  factory ProjectFarmPolicy.fromJson(Map<String, dynamic> json) =>
      _$ProjectFarmPolicyFromJson(json);

  bool get allowsBackgroundWork => allowedVerificationCommands.isNotEmpty;

  /// The command an unattended run uses: the first one the user declared as
  /// not executing project code that is also allowed. Null when none is.
  String? get unattendedCommand {
    for (final command in unattendedCommands) {
      if (allows(command)) return normalizePolicyCommand(command);
    }
    return null;
  }

  /// Whether idle-time maintenance may start a run in this project at all.
  bool get allowsUnattendedRuns =>
      autoRunEnabled && dailyRunLimit > 0 && unattendedCommand != null;

  /// Whether [command] is one the user declared, compared exactly after
  /// collapsing whitespace.
  bool allows(String command) {
    final wanted = normalizePolicyCommand(command);
    return allowedVerificationCommands.any(
      (allowed) => normalizePolicyCommand(allowed) == wanted,
    );
  }
}

String normalizePolicyCommand(String command) =>
    command.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Characters a policy command may not contain. Stricter than the LL13 runner,
/// which accepts quotes: a declared command is a plain argv with no shell
/// syntax at all, so what the user reviewed is exactly what runs.
final RegExp _forbiddenPolicyCharacters = RegExp(
  r'''[|&;<>$`(){}"'\\\n\r*?]''',
);

/// Why [command] cannot be declared, or null when it can.
String? policyCommandProblem(String command) {
  final normalized = normalizePolicyCommand(command);
  if (normalized.isEmpty) return 'empty';
  if (_forbiddenPolicyCharacters.hasMatch(command)) return 'shell_syntax';
  return null;
}
